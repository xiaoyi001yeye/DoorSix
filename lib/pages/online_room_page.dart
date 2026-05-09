import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import '../models/online_table.dart';
import '../models/player_model.dart';
import '../services/online_table_service.dart';
import '../services/rule_engine.dart';
import '../services/server_log_store.dart';
import '../utils/app_theme.dart';
import '../utils/player_profile_settings.dart';
import '../widgets/action_bar.dart';
import '../widgets/app_update_gate.dart';
import '../widgets/card_display_settings_sheet.dart';
import '../widgets/game_table_layout.dart';
import '../widgets/hand_area.dart';
import '../widgets/player_avatar_badge.dart';
import '../widgets/server_log_sheet.dart';
import '../widgets/table_center.dart';

enum OnlineEntryMode { create, join }

class OnlineRoomPage extends StatefulWidget {
  const OnlineRoomPage({
    required this.initialMode,
    super.key,
  });

  final OnlineEntryMode initialMode;

  @override
  State<OnlineRoomPage> createState() => _OnlineRoomPageState();
}

class _OnlineRoomPageState extends State<OnlineRoomPage> {
  final DoorSixBackendClient _client = DoorSixBackendClient();
  final RuleEngine _engine = const RuleEngine();
  final TextEditingController _nicknameController =
      TextEditingController(text: '玩家');
  final TextEditingController _roomCodeController = TextEditingController();
  final List<String> _logs = [];
  final Set<String> _selectedCardIds = {};

  late OnlineEntryMode _mode;

  OnlineSession? _session;
  OnlineTableSnapshot? _snapshot;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  bool _busy = false;
  bool _connected = false;
  int _seq = 0;
  int? _turnSecondsRemaining;
  int _serverClockOffsetMs = 0;
  Timer? _turnTimer;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    unawaited(_restoreNickname());
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    unawaited(_setPortrait());
    _socketSub?.cancel();
    _socket?.close();
    _client.close();
    _nicknameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final isGameView = snapshot != null && snapshot.status != 'waiting';
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackRequest());
      },
      child: Scaffold(
        appBar: isGameView ? null : _buildRoomAppBar(),
        body: SafeArea(
          top: !isGameView,
          bottom: !isGameView,
          child: snapshot == null
              ? _buildEntry()
              : snapshot.status == 'waiting'
                  ? _buildWaiting(snapshot)
                  : _buildPlaying(snapshot),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildRoomAppBar() {
    return AppBar(
      title: const Text('联机房间'),
      leading: IconButton(
        tooltip: '返回',
        onPressed: _handleBackRequest,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        if (_session != null)
          IconButton(
            tooltip: '复制房间号',
            onPressed: _copyRoomCode,
            icon: const Icon(Icons.content_copy_rounded),
          ),
        IconButton(
          tooltip: '同步',
          onPressed: _session == null ? null : _syncState,
          icon: const Icon(Icons.sync_rounded),
        ),
        IconButton(
          tooltip: '日志 / 控制台',
          onPressed: _showCombinedLogs,
          icon: const Icon(Icons.terminal_rounded),
        ),
      ],
    );
  }

  Widget _buildEntry() {
    final profile = PlayerProfileSettingsScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SegmentedButton<OnlineEntryMode>(
          segments: const [
            ButtonSegment(
              value: OnlineEntryMode.create,
              icon: Icon(Icons.group_add_outlined),
              label: Text('创建'),
            ),
            ButtonSegment(
              value: OnlineEntryMode.join,
              icon: Icon(Icons.login_rounded),
              label: Text('加入'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.first),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _nicknameController,
          textInputAction: _mode == OnlineEntryMode.create
              ? TextInputAction.done
              : TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '昵称',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 16),
        _EntryAvatarPicker(
          selectedAvatarId: profile.avatarPresetId,
          onSelected: profile.setAvatarPresetId,
        ),
        if (_mode == OnlineEntryMode.join) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _roomCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '房间号',
              prefixIcon: Icon(Icons.tag_rounded),
              counterText: '',
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _busy ? null : _enterRoom,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _mode == OnlineEntryMode.create
                      ? Icons.add_rounded
                      : Icons.login_rounded,
                ),
          label: Text(_mode == OnlineEntryMode.create ? '创建房间' : '加入房间'),
        ),
        const SizedBox(height: 14),
        _ServerBadge(baseUrl: _client.baseUri.toString()),
      ],
    );
  }

  Widget _buildWaiting(OnlineTableSnapshot snapshot) {
    final self = _selfSeat(snapshot);
    final isOwner = _session?.self.playerId == snapshot.ownerPlayerId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _RoomStatusPanel(
          roomCode: _session!.room.roomCode,
          connected: _connected,
          status: '等待开局',
          score: snapshot.score,
        ),
        const SizedBox(height: 14),
        _SeatGrid(
          seats: snapshot.seats,
          selfPlayerId: _session!.self.playerId,
          ownerPlayerId: snapshot.ownerPlayerId,
          busy: _busy,
          onMoveToSeat: _moveToSeat,
          onKickSeat: _confirmKickSeat,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _busy || self == null ? null : () => _sendReady(!self.ready),
                icon: Icon(
                  self?.ready == true
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                label: Text(self?.ready == true ? '取消准备' : '准备'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !isOwner ? null : _startGame,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开局'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LogPanel(logs: _logs),
      ],
    );
  }

  Widget _buildPlaying(OnlineTableSnapshot snapshot) {
    final players = _playersFrom(snapshot);
    final myHand = _myHand(snapshot);
    final currentSeat = snapshot.currentTurnSeatIndex ?? 0;
    final currentPlayer = players[currentSeat];
    final lastPlayedSeat = snapshot.lastPlayedSeatIndex;
    final lastPlayedBy = lastPlayedSeat == null ? null : players[lastPlayedSeat].name;
    final selectedCards = myHand.where((card) => card.selected).toList();
    final selectedCombo = _engine.evaluate(selectedCards);
    final isMyTurn = _isMyTurn(snapshot);
    final canPlay = isMyTurn &&
        selectedCards.isNotEmpty &&
        _engine.canPlay(candidate: selectedCombo, target: snapshot.tableCombo);
    final canPass = isMyTurn && snapshot.tableCombo != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        return Column(
          children: [
            _CompactTableHeader(
              roomCode: _session!.room.roomCode,
              round: snapshot.roundNo,
              score: snapshot.score,
              connected: _connected,
              onBack: _handleBackRequest,
              onRefresh: _syncState,
              onLogs: _showCombinedLogs,
              onSettings: () => showCardDisplaySettingsSheet(context),
            ),
            if (isLandscape)
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildOnlineTableArea(
                        players: players,
                        snapshot: snapshot,
                        currentPlayer: currentPlayer,
                        currentSeat: currentSeat,
                        lastPlayedBy: lastPlayedBy,
                      ),
                    ),
                    SizedBox(
                      width: 340,
                      child: _buildOnlineHandAndActions(
                        myHand: myHand,
                        selectedCombo: selectedCombo,
                        selectedCards: selectedCards,
                        snapshot: snapshot,
                        isMyTurn: isMyTurn,
                        canPlay: canPlay,
                        canPass: canPass,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Expanded(
                child: _buildOnlineTableArea(
                  players: players,
                  snapshot: snapshot,
                  currentPlayer: currentPlayer,
                  currentSeat: currentSeat,
                  lastPlayedBy: lastPlayedBy,
                ),
              ),
              _buildOnlineHandAndActions(
                myHand: myHand,
                selectedCombo: selectedCombo,
                selectedCards: selectedCards,
                snapshot: snapshot,
                isMyTurn: isMyTurn,
                canPlay: canPlay,
                canPass: canPass,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildOnlineTableArea({
    required List<GamePlayer> players,
    required OnlineTableSnapshot snapshot,
    required GamePlayer currentPlayer,
    required int currentSeat,
    required String? lastPlayedBy,
  }) {
    return GameTableLayout(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      players: players,
      currentSeat: snapshot.status == 'playing' ? currentSeat : null,
      playedBySeat:
          snapshot.tableCombo == null ? null : snapshot.lastPlayedSeatIndex,
      selfSeat:
          _selfSeat(snapshot)?.seatIndex ?? _session?.self.seatIndex ?? 0,
      selfTeam: _selfTeam(snapshot),
      finishOrder: snapshot.finishOrder,
      countdownSecondsForSeat: (seat) {
        if (seat != currentSeat || snapshot.status != 'playing') {
          return null;
        }
        return _turnSecondsRemaining ?? snapshot.turnDurationSeconds;
      },
      centerBuilder: (context, width) {
        return TableCenter(
          width: width,
          activeCombo: snapshot.tableCombo,
          playedCards: snapshot.tableCombo?.cards ?? const <CardInstance>[],
          lastPlayedBy: lastPlayedBy,
          currentPlayer: currentPlayer.name,
          passCount: snapshot.passCount,
        );
      },
    );
  }

  Widget _buildOnlineHandAndActions({
    required List<CardInstance> myHand,
    required CardCombo selectedCombo,
    required List<CardInstance> selectedCards,
    required OnlineTableSnapshot snapshot,
    required bool isMyTurn,
    required bool canPlay,
    required bool canPass,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        HandArea(
          cards: myHand,
          combo: selectedCombo,
          canPlay: canPlay,
          onToggle: _toggleCard,
        ),
        GameActionBar(
          isUserTurn: isMyTurn,
          canPlay: canPlay,
          canPass: canPass,
          onHint: () => _hint(myHand, snapshot.tableCombo),
          onPlay: () => _playSelected(selectedCards, snapshot),
          onPass: () => _sendGameAction('pass', {
            'gameId': snapshot.gameId,
            'roundNo': snapshot.roundNo,
            'clientKnownEventSeq': snapshot.eventSeq,
          }),
          onSort: () => setState(() => _selectedCardIds.clear()),
        ),
      ],
    );
  }

  Future<void> _restoreNickname() async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString('online_nickname');
    if (nickname != null && mounted) {
      _nicknameController.text = nickname;
    }
  }

  Future<void> _enterRoom() async {
    final nickname = _nicknameController.text.trim();
    final roomCode = _roomCodeController.text.trim();
    if (nickname.isEmpty) {
      _showMessage('先填一个昵称');
      return;
    }
    if (_mode == OnlineEntryMode.join && roomCode.length != 6) {
      _showMessage('房间号需要 6 位');
      return;
    }

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('online_nickname', nickname);
      final avatarId = PlayerProfileSettingsScope.of(context).avatarPresetId;
      final session = _mode == OnlineEntryMode.create
          ? await _client.createRoom(nickname: nickname, avatarId: avatarId)
          : await _client.joinRoom(
              roomCode: roomCode,
              nickname: nickname,
              avatarId: avatarId,
            );
      _session = session;
      _logs
        ..clear()
        ..add(_mode == OnlineEntryMode.create
            ? '房间 ${session.room.roomCode} 已创建'
            : '已加入房间 ${session.room.roomCode}');
      await _connectSocket(session);
      final snapshot = await _client.snapshot(session);
      if (!mounted) {
        return;
      }
      _selectedCardIds.clear();
      _applySnapshot(snapshot);
    } on DoorSixBackendException catch (error) {
      if (error.code == 'APP_VERSION_UNSUPPORTED') {
        unawaited(AppUpdateScope.of(context).checkNow(
          manual: true,
          ignoreDismissal: true,
          source: 'unsupported_version',
        ));
      }
      _showMessage(error.message);
      if (mounted) {
        showServerLogSheet(context);
      }
    } on SocketException {
      _showMessage('连接后端失败，请检查网络');
      if (mounted) {
        showServerLogSheet(context);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _connectSocket(OnlineSession session) async {
    await _socketSub?.cancel();
    await _socket?.close();
    final socket = await _client.connect(session);
    _socket = socket;
    _connected = true;
    _socketSub = socket.listen(
      _handleSocketMessage,
      onDone: () {
        ServerLogStore.instance.warning('WS 已关闭');
        if (mounted) {
          setState(() => _connected = false);
        }
      },
      onError: (error) {
        ServerLogStore.instance.error('WS 发生错误', detail: error.toString());
        if (mounted) {
          setState(() => _connected = false);
          _showMessage('WebSocket 已断开');
        }
      },
    );
  }

  void _handleSocketMessage(dynamic message) {
    ServerLogStore.instance.info(
      'WS 收到消息',
      detail: _compactLogDetail(message.toString()),
    );
    final data = jsonDecode(message as String) as Map<String, dynamic>;
    final type = data['type'] as String? ?? 'unknown';
    final payload =
        data['payload'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    if (type == 'error') {
      _showMessage(payload['message'] as String? ?? '后端操作失败');
      return;
    }

    if (payload['tableState'] != null) {
      final snapshotPayload = Map<String, dynamic>.from(payload)
        ..['serverTime'] = data['serverTime'];
      final snapshot = OnlineTableSnapshot.fromJson(snapshotPayload);
      _applySnapshot(snapshot, logLabel: _eventLabel(type));
      if (type == 'round_settled') {
        _showMessage('本局已结算');
      }
      return;
    }

    if (type == 'player_kicked') {
      final kickedPlayerId = payload['playerId'] as String?;
      if (kickedPlayerId == _session?.self.playerId) {
        unawaited(_handleKickedFromRoom(payload));
        return;
      }
      _logs.add(_eventLabel(type));
      unawaited(_syncState());
      return;
    }

    if (type == 'seat_updated' ||
        type == 'player_joined' ||
        type == 'player_left') {
      _logs.add(_eventLabel(type));
      unawaited(_syncState());
      return;
    }

    if (type == 'player_disconnected' || type == 'player_reconnected') {
      _logs.add(_eventLabel(type));
      unawaited(_syncState());
    }
  }

  String _eventLabel(String type) {
    return switch (type) {
      'table_snapshot' => '牌桌已同步',
      'game_started' => '游戏开始',
      'seat_updated' => '座位状态更新',
      'player_joined' => '有玩家加入',
      'player_left' => '有玩家离开',
      'player_kicked' => '有玩家被移出',
      'player_passed' => '玩家过牌',
      'new_lead_started' => '新一轮开始',
      'round_settled' => '本局结算',
      _ => '收到事件：$type',
    };
  }

  Future<void> _syncState() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      final snapshot = await _client.snapshot(session);
      if (mounted) {
        _applySnapshot(snapshot);
      }
    } catch (_) {
      _sendWs('sync_state', {
        'lastEventSeq': _snapshot?.eventSeq ?? 0,
      });
    }
  }

  void _sendReady(bool ready) {
    _sendWs('ready', {'ready': ready});
  }

  void _moveToSeat(int seatIndex) {
    if (_busy) {
      return;
    }
    _sendWs('move_seat', {'seatIndex': seatIndex});
  }

  Future<void> _confirmKickSeat(OnlineSeat seat) async {
    if (_busy || !mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移出玩家?'),
          content: Text('将 ${seat.nickname} 移出房间。'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移出'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _sendWs('kick_player', {'seatIndex': seat.seatIndex});
    }
  }

  void _startGame() {
    _sendWs('start_game', const <String, Object?>{});
  }

  void _sendGameAction(String type, Map<String, Object?> payload) {
    if (_busy) {
      return;
    }
    _sendWs(type, payload);
  }

  void _sendWs(String type, Map<String, Object?> payload) {
    final session = _session;
    final socket = _socket;
    if (session == null || socket == null) {
      ServerLogStore.instance.error(
        'WS 发送失败',
        detail: '连接未建立，消息类型：$type',
      );
      return;
    }
    _seq += 1;
    final message = jsonEncode({
      'type': type,
      'requestId': 'android_${DateTime.now().millisecondsSinceEpoch}_$_seq',
      'roomId': session.room.roomId,
      'seq': _seq,
      'payload': payload,
    });
    ServerLogStore.instance.info(
      'WS 发送 $type',
      detail: _compactLogDetail(message),
    );
    socket.add(message);
  }

  void _applySnapshot(OnlineTableSnapshot snapshot, {String? logLabel}) {
    if (!mounted) {
      return;
    }
    _syncServerClock(snapshot);
    final turnSecondsRemaining = _secondsRemainingFor(snapshot);
    unawaited(_setOrientationForStatus(snapshot.status));
    setState(() {
      _snapshot = snapshot;
      _turnSecondsRemaining = turnSecondsRemaining;
      _selectedCardIds.removeWhere(
        (id) => !snapshot.myHand.any((card) => card.id == id),
      );
      if (logLabel != null) {
        _logs.add(logLabel);
      }
    });
    _restartOnlineTurnCountdown(snapshot);
  }

  Future<void> _handleKickedFromRoom(Map<String, dynamic> payload) async {
    await _socketSub?.cancel();
    await _socket?.close();
    if (!mounted) {
      return;
    }
    final message = payload['message'] as String? ?? '你已被房主移出房间';
    setState(() {
      _socket = null;
      _session = null;
      _snapshot = null;
      _connected = false;
      _selectedCardIds.clear();
      _logs
        ..clear()
        ..add(message);
    });
    _showMessage(message);
  }

  void _syncServerClock(OnlineTableSnapshot snapshot) {
    final serverTime = snapshot.serverTime;
    if (serverTime == null) {
      return;
    }
    _serverClockOffsetMs =
        serverTime - DateTime.now().millisecondsSinceEpoch;
  }

  int? _secondsRemainingFor(OnlineTableSnapshot snapshot) {
    final deadline = snapshot.turnDeadlineAt;
    if (snapshot.status != 'playing' || deadline == null) {
      return null;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch + _serverClockOffsetMs;
    final remainingMs = deadline - nowMs;
    return (remainingMs / 1000)
        .ceil()
        .clamp(0, snapshot.turnDurationSeconds)
        .toInt();
  }

  void _restartOnlineTurnCountdown(OnlineTableSnapshot snapshot) {
    _turnTimer?.cancel();
    if (_secondsRemainingFor(snapshot) == null) {
      return;
    }

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = _snapshot;
      if (!mounted || current == null || current.status != 'playing') {
        timer.cancel();
        return;
      }

      if (current.gameId != snapshot.gameId ||
          current.roundNo != snapshot.roundNo ||
          current.currentTurnSeatIndex != snapshot.currentTurnSeatIndex ||
          current.turnDeadlineAt != snapshot.turnDeadlineAt) {
        timer.cancel();
        return;
      }

      final remaining = _secondsRemainingFor(current);
      setState(() => _turnSecondsRemaining = remaining);
      if (remaining == null || remaining <= 0) {
        timer.cancel();
      }
    });
  }

  OnlineSeat? _selfSeat(OnlineTableSnapshot snapshot) {
    final selfPlayerId = _session?.self.playerId;
    if (selfPlayerId == null) {
      return null;
    }
    for (final seat in snapshot.seats) {
      if (seat?.playerId == selfPlayerId) {
        return seat;
      }
    }
    return null;
  }

  TeamSide _selfTeam(OnlineTableSnapshot snapshot) {
    return _selfSeat(snapshot)?.team ?? _session?.self.team ?? TeamSide.a;
  }

  bool _isMyTurn(OnlineTableSnapshot snapshot) {
    final self = _selfSeat(snapshot);
    return snapshot.status == 'playing' &&
        self != null &&
        snapshot.currentTurnSeatIndex == self.seatIndex;
  }

  List<CardInstance> _myHand(OnlineTableSnapshot snapshot) {
    return _engine.sortCards(snapshot.myHand).map((card) {
      return card.copyWith(selected: _selectedCardIds.contains(card.id));
    }).toList();
  }

  List<GamePlayer> _playersFrom(OnlineTableSnapshot snapshot) {
    final selfPlayerId = _session!.self.playerId;
    return List.generate(6, (index) {
      final seat = index < snapshot.seats.length ? snapshot.seats[index] : null;
      if (seat != null) {
        return seat.toGamePlayer(selfPlayerId);
      }
      return GamePlayer(
        id: 'empty_$index',
        name: '空位',
        team: index.isEven ? TeamSide.b : TeamSide.a,
        seatIndex: index,
        cardCount: 0,
        isUser: false,
        avatarId: 'stone',
      );
    });
  }

  void _toggleCard(String id) {
    if (_snapshot == null || !_isMyTurn(_snapshot!)) {
      _showMessage('还没轮到你');
      return;
    }
    setState(() {
      if (!_selectedCardIds.add(id)) {
        _selectedCardIds.remove(id);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _hint(List<CardInstance> hand, CardCombo? tableCombo) {
    final suggestion = _engine.suggest(hand, tableCombo);
    if (suggestion.isEmpty) {
      _showMessage('没有能压过上家的牌，可以过');
      return;
    }
    setState(() {
      _selectedCardIds
        ..clear()
        ..addAll(suggestion.map((card) => card.id));
    });
  }

  void _playSelected(
    List<CardInstance> selectedCards,
    OnlineTableSnapshot snapshot,
  ) {
    if (selectedCards.isEmpty) {
      return;
    }
    _sendGameAction('play_cards', {
      'gameId': snapshot.gameId,
      'roundNo': snapshot.roundNo,
      'cardIds': selectedCards.map((card) => card.id).toList(),
      'clientKnownEventSeq': snapshot.eventSeq,
    });
  }

  Future<void> _handleBackRequest() async {
    if (_snapshot?.status == 'playing') {
      final shouldLeave = await _confirmExitGame();
      if (!shouldLeave) {
        return;
      }
    }
    await _leaveAndPop();
  }

  Future<bool> _confirmExitGame() async {
    if (!mounted) {
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认退出?'),
          content: const Text('退出后本局将作废'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _leaveAndPop() async {
    final session = _session;
    if (session != null) {
      try {
        await _client.leaveRoom(session);
      } catch (_) {
        // Leaving is best-effort; closing the socket still releases the screen.
      }
    }
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _setOrientationForStatus(String status) {
    return status == 'waiting' ? _setPortrait() : _setLandscape();
  }

  Future<void> _setLandscape() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _setPortrait() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    AppTheme.setSystemUi();
  }

  void _copyRoomCode() {
    final code = _session?.room.roomCode;
    if (code == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: code));
    _showMessage('房间号已复制');
  }

  void _showCombinedLogs() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _CombinedLogSheet(
        logs: _logs,
        history: _snapshot?.actionHistory ?? const [],
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _compactLogDetail(String text) {
    final normalized = text
        .replaceAll(RegExp(r'"playerToken"\s*:\s*"[^"]+"'), '"playerToken":"***"')
        .replaceAll(RegExp(r'playerToken=[^&\s"]+'), 'playerToken=***')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 800) {
      return normalized;
    }
    return '${normalized.substring(0, 800)}...';
  }
}

class _ServerBadge extends StatelessWidget {
  const _ServerBadge({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x334CC9F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.cloud_done_outlined, color: AppTheme.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '后端：$baseUrl',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryAvatarPicker extends StatelessWidget {
  const _EntryAvatarPicker({
    required this.selectedAvatarId,
    required this.onSelected,
  });

  final String selectedAvatarId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x334CC9F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.face_retouching_natural_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  '本局头像',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PlayerAvatarSelector(
              selectedAvatarId: selectedAvatarId,
              onSelected: onSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomStatusPanel extends StatelessWidget {
  const _RoomStatusPanel({
    required this.roomCode,
    required this.connected,
    required this.status,
    required this.score,
  });

  final String roomCode;
  final bool connected;
  final String status;
  final OnlineScore score;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomCode,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$status · A ${score.teamA} : ${score.teamB} B',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            _ConnectionDot(connected: connected),
          ],
        ),
      ),
    );
  }
}

class _CompactTableHeader extends StatelessWidget {
  const _CompactTableHeader({
    required this.roomCode,
    required this.round,
    required this.score,
    required this.connected,
    required this.onBack,
    required this.onRefresh,
    required this.onLogs,
    required this.onSettings,
  });

  final String roomCode;
  final int round;
  final OnlineScore score;
  final bool connected;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onLogs;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              _ConnectionDot(connected: connected),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '房间 $roomCode · 第 $round 局 · A ${score.teamA}:${score.teamB} B',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _ToolStrip(
              onRefresh: onRefresh,
              onLogs: onLogs,
              onSettings: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.onRefresh,
    required this.onLogs,
    required this.onSettings,
  });

  final VoidCallback onRefresh;
  final VoidCallback onLogs;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3379D98B)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '刷新',
              onPressed: onRefresh,
              icon: const Icon(Icons.sync_rounded),
            ),
            IconButton(
              tooltip: '日志 / 控制台',
              onPressed: onLogs,
              icon: const Icon(Icons.terminal_rounded),
            ),
            IconButton(
              tooltip: '配置',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: connected ? '已连接' : '未连接',
      child: Icon(
        connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        color: connected ? AppTheme.success : AppTheme.danger,
      ),
    );
  }
}

class _SeatGrid extends StatelessWidget {
  const _SeatGrid({
    required this.seats,
    required this.selfPlayerId,
    required this.ownerPlayerId,
    required this.busy,
    required this.onMoveToSeat,
    required this.onKickSeat,
  });

  final List<OnlineSeat?> seats;
  final String selfPlayerId;
  final String ownerPlayerId;
  final bool busy;
  final ValueChanged<int> onMoveToSeat;
  final ValueChanged<OnlineSeat> onKickSeat;

  @override
  Widget build(BuildContext context) {
    final isOwner = selfPlayerId == ownerPlayerId;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (context, index) {
        final seat = index < seats.length ? seats[index] : null;
        final isSelf = seat?.playerId == selfPlayerId;
        final canMoveHere = seat == null && !busy;
        final canKick =
            isOwner && seat != null && !isSelf && !seat.isAi && !busy;
        return Material(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canMoveHere ? () => onMoveToSeat(index) : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelf
                      ? AppTheme.success
                      : canMoveHere
                          ? const Color(0x6679D98B)
                          : const Color(0x334CC9F0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (seat != null) ...[
                      PlayerAvatarBadge(
                        avatarId: seat.avatarId,
                        size: 28,
                        showRing: isSelf,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        seat == null
                            ? '点击入座'
                            : isSelf
                                ? '我'
                                : seat.nickname,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: seat == null
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (seat == null)
                      Icon(
                        Icons.event_seat_outlined,
                        color: canMoveHere
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        size: 18,
                      )
                    else ...[
                      Icon(
                        seat.ready
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: seat.ready
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        size: 18,
                      ),
                      if (canKick) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: '移出玩家',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => onKickSeat(seat),
                          icon: const Icon(
                            Icons.person_remove_alt_1_outlined,
                            color: AppTheme.danger,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final visibleLogs = logs.isEmpty ? const ['暂无日志'] : logs.reversed.toList();
    return SafeArea(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        itemCount: visibleLogs.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          return Text(
            visibleLogs[index],
            style: const TextStyle(color: AppTheme.textSecondary),
          );
        },
      ),
    );
  }
}

class _CombinedLogSheet extends StatelessWidget {
  const _CombinedLogSheet({
    required this.logs,
    required this.history,
  });

  final List<String> logs;
  final List<OnlineActionHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined),
                    const SizedBox(width: 8),
                    Text(
                      '日志',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: ServerLogStore.instance.clear,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('清空通信日志'),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: '牌局历史'),
                  Tab(text: '通信日志'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ActionHistoryPanel(history: history, fallbackLogs: logs),
                    _ServerLogList(store: ServerLogStore.instance),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionHistoryPanel extends StatelessWidget {
  const _ActionHistoryPanel({
    required this.history,
    required this.fallbackLogs,
  });

  final List<OnlineActionHistoryEntry> history;
  final List<String> fallbackLogs;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      final logs = fallbackLogs.isEmpty ? const ['暂无出牌记录'] : fallbackLogs;
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, index) {
          return Text(
            logs[index],
            style: const TextStyle(color: AppTheme.textSecondary),
          );
        },
      );
    }

    final entries = history.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _ActionHistoryTile(entry: entries[index]);
      },
    );
  }
}

class _ActionHistoryTile extends StatelessWidget {
  const _ActionHistoryTile({required this.entry});

  final OnlineActionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isPlay = entry.actionType == OnlineActionType.play;
    final color = isPlay ? AppTheme.success : AppTheme.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                _timeLabel(entry.createdAt),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isPlay
                  ? Icons.file_upload_outlined
                  : Icons.keyboard_tab_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (_sourceLabel != null)
                        _HistoryChip(label: _sourceLabel!),
                    ],
                  ),
                  if (isPlay && entry.cards.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.cards.map(_cardLabel).join('、'),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    return switch (entry.actionType) {
      OnlineActionType.play =>
        '${entry.playerName} 出 ${entry.comboLabel ?? '牌'}',
      OnlineActionType.pass => '${entry.playerName} 过牌',
      OnlineActionType.newLead => '一圈过牌，${entry.playerName} 获得领出权',
    };
  }

  String? get _sourceLabel {
    return switch (entry.source) {
      OnlineActionSource.ai => 'AI',
      OnlineActionSource.timeout => '托管',
      OnlineActionSource.player => null,
    };
  }

  String _timeLabel(int millisecondsSinceEpoch) {
    final time = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _cardLabel(CardInstance card) {
    if (card.suit == CardSuit.joker) {
      return card.rank.label;
    }
    return '${card.suit.label}${card.rank.label}';
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.tableDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3379D98B)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.teamGold,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ServerLogList extends StatelessWidget {
  const _ServerLogList({required this.store});

  final ServerLogStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final entries = store.entries;
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              '暂无服务器通信日志',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (entry.detail != null && entry.detail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.detail!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
