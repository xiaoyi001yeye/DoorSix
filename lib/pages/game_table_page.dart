import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/card_model.dart';
import '../models/player_model.dart';
import '../models/round_result.dart';
import '../models/rule_set.dart';
import '../services/rule_engine.dart';
import '../utils/app_theme.dart';
import '../utils/card_display_settings.dart';
import '../utils/game_runtime_config.dart';
import '../utils/player_profile_settings.dart';
import '../widgets/action_bar.dart';
import '../widgets/card_display_settings_sheet.dart';
import '../widgets/game_table_layout.dart';
import '../widgets/game_table_v2/game_table_shell.dart';
import '../widgets/hand_area.dart';
import '../widgets/rule_badge.dart';
import '../widgets/table_center.dart';

class GameTablePage extends StatefulWidget {
  const GameTablePage({
    required this.ruleSet,
    super.key,
  });

  final RuleSet ruleSet;

  @override
  State<GameTablePage> createState() => _GameTablePageState();
}

class _GameTablePageState extends State<GameTablePage> {
  final RuleEngine _engine = const RuleEngine();
  final math.Random _aiRandom = math.Random();
  final List<String> _logs = [];
  final List<FinishedSeat> _finishOrder = [];

  late List<GamePlayer> _players;
  late List<List<CardInstance>> _hands;

  CardCombo? _activeCombo;
  List<CardInstance> _lastPlayedCards = [];
  int? _lastPlayedSeat;
  int _currentSeat = 0;
  int _passCount = 0;
  int _round = 1;
  int _teamAScore = 0;
  int _teamBScore = 0;
  bool _aiRunning = false;
  int _turnSecondsRemaining = GameRuntimeConfig.instance.turnDurationSeconds;
  Timer? _turnTimer;
  RoundResult? _roundResult;

  List<CardInstance> get _myHand => _hands[0];
  bool get _isUserTurn => _currentSeat == 0 && _roundResult == null;

  List<CardInstance> get _selectedCards {
    return _myHand.where((card) => card.selected).toList();
  }

  CardCombo get _selectedCombo => _engine.evaluate(_selectedCards);

  bool get _canPlay {
    return _isUserTurn &&
        _selectedCards.isNotEmpty &&
        _engine.canPlay(candidate: _selectedCombo, target: _activeCombo);
  }

  bool get _canPass => _isUserTurn && _activeCombo != null;

  @override
  void initState() {
    super.initState();
    unawaited(_setLandscape());
    _startRound(resetScores: true);
    _restartTurnCountdown(notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kickAiIfNeeded());
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    unawaited(_setPortrait());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayer = _players[_currentSeat];
    final lastPlayedBy =
        _lastPlayedSeat == null ? null : _players[_lastPlayedSeat!].name;
    final useImmersiveTable =
        CardDisplaySettingsScope.of(context).tableExperience ==
            GameTableExperience.immersive;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackRequest());
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: useImmersiveTable
              ? _buildImmersiveTable(
                  currentPlayer: currentPlayer,
                  lastPlayedBy: lastPlayedBy,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape =
                        constraints.maxWidth > constraints.maxHeight;
                    return Column(
                      children: [
                        _buildHeader(),
                        if (isLandscape)
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildTableArea(
                                    currentPlayer: currentPlayer,
                                    lastPlayedBy: lastPlayedBy,
                                  ),
                                ),
                                SizedBox(
                                  width: 360,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildHandAndActions(),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          Expanded(
                            child: _buildTableArea(
                              currentPlayer: currentPlayer,
                              lastPlayedBy: lastPlayedBy,
                            ),
                          ),
                          _buildHandAndActions(),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildImmersiveTable({
    required GamePlayer currentPlayer,
    required String? lastPlayedBy,
  }) {
    final players = _playersForDisplay();
    return GameTableShell(
      state: GameTableViewModel(
        roundNo: _round,
        teamAScore: _teamAScore,
        teamBScore: _teamBScore,
        players: players,
        selfSeat: 0,
        selfTeam: players[0].team,
        currentSeat: _roundResult == null ? _currentSeat : null,
        lastPlayedSeat: _activeCombo == null ? null : _lastPlayedSeat,
        activeCombo: _activeCombo,
        playedCards: _lastPlayedCards,
        lastPlayedBy: lastPlayedBy,
        currentPlayerName: currentPlayer.name,
        passCount: _passCount,
        finishOrder: _finishOrder,
        hand: _myHand,
        selectedCombo: _selectedCombo,
        canPlay: _canPlay,
        canPass: _canPass,
        isUserTurn: _isUserTurn,
        turnSecondsRemaining:
            _roundResult == null ? _turnSecondsRemaining : null,
        onToggleCard: _toggleCard,
      ),
      actions: [
        GameActionItem(
          kind: GameActionKind.back,
          label: '返回',
          icon: Icons.arrow_back_rounded,
          placement: GameActionPlacement.topBar,
          enabled: true,
          visible: true,
          onPressed: _handleBackRequest,
        ),
        GameActionItem(
          kind: GameActionKind.rules,
          label: '规则',
          icon: Icons.help_outline_rounded,
          placement: GameActionPlacement.topBar,
          enabled: true,
          visible: true,
          onPressed: _showRuleSheet,
        ),
        GameActionItem(
          kind: GameActionKind.replay,
          label: '回放',
          icon: Icons.replay_rounded,
          placement: GameActionPlacement.topBar,
          enabled: true,
          visible: true,
          onPressed: _showLogSheet,
        ),
        GameActionItem(
          kind: GameActionKind.settings,
          label: '设置',
          icon: Icons.settings_rounded,
          placement: GameActionPlacement.topBar,
          enabled: true,
          visible: true,
          onPressed: () => showCardDisplaySettingsSheet(context),
        ),
        GameActionItem(
          kind: GameActionKind.hint,
          label: '提示',
          icon: Icons.lightbulb_outline_rounded,
          placement: GameActionPlacement.utility,
          enabled: _isUserTurn,
          visible: true,
          disabledReason: '还没轮到你',
          onPressed: _hint,
        ),
        GameActionItem(
          kind: GameActionKind.sort,
          label: '整理',
          icon: Icons.sort_rounded,
          placement: GameActionPlacement.secondary,
          enabled: true,
          visible: false,
          onPressed: _sortMine,
        ),
        GameActionItem(
          kind: GameActionKind.pass,
          label: '不出',
          icon: Icons.keyboard_tab_rounded,
          placement: GameActionPlacement.secondary,
          enabled: _canPass,
          visible: true,
          disabledReason: '新一轮不能不出',
          onPressed: _pass,
        ),
        GameActionItem(
          kind: GameActionKind.play,
          label: '出牌',
          icon: Icons.file_upload_outlined,
          placement: GameActionPlacement.primary,
          enabled: _canPlay,
          visible: true,
          disabledReason: _isUserTurn ? '请选择可出的牌' : '还没轮到你',
          onPressed: _playSelected,
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return _TableHeader(
      ruleSet: widget.ruleSet,
      round: _round,
      teamAScore: _teamAScore,
      teamBScore: _teamBScore,
      onBack: _handleBackRequest,
      onRuleTap: _showRuleSheet,
      onLogTap: _showLogSheet,
      onSettingsTap: () => showCardDisplaySettingsSheet(context),
    );
  }

  Widget _buildTableArea({
    required GamePlayer currentPlayer,
    required String? lastPlayedBy,
  }) {
    final players = _playersForDisplay();
    return GameTableLayout(
      players: players,
      currentSeat: _roundResult == null ? _currentSeat : null,
      playedBySeat: _activeCombo == null ? null : _lastPlayedSeat,
      selfTeam: players[0].team,
      finishOrder: _finishOrder,
      countdownSecondsForSeat: (seat) {
        return seat == _currentSeat ? _turnSecondsRemaining : null;
      },
      centerBuilder: (context, width) {
        return TableCenter(
          width: width,
          activeCombo: _activeCombo,
          playedCards: _lastPlayedCards,
          lastPlayedBy: lastPlayedBy,
          currentPlayer: currentPlayer.name,
          passCount: _passCount,
        );
      },
    );
  }

  List<GamePlayer> _playersForDisplay() {
    final avatarId = PlayerProfileSettingsScope.of(context).avatarPresetId;
    return _players.map((player) {
      return player.isUser ? player.copyWith(avatarId: avatarId) : player;
    }).toList(growable: false);
  }

  Widget _buildHandAndActions() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        HandArea(
          cards: _myHand,
          combo: _selectedCombo,
          canPlay: _canPlay,
          onToggle: _toggleCard,
        ),
        GameActionBar(
          isUserTurn: _isUserTurn,
          canPlay: _canPlay,
          canPass: _canPass,
          onHint: _hint,
          onPlay: _playSelected,
          onPass: _pass,
          onSort: _sortMine,
        ),
      ],
    );
  }

  void _startRound({required bool resetScores}) {
    final hands = _engine.dealHands(deckCount: widget.ruleSet.deckCount);
    _hands = hands;
    _players = [
      GamePlayer(
        id: 'me',
        name: '我',
        team: TeamSide.b,
        seatIndex: 0,
        cardCount: hands[0].length,
        isUser: true,
        avatarId: 'sun',
      ),
      GamePlayer(
        id: 'a1',
        name: 'A1',
        team: TeamSide.a,
        seatIndex: 1,
        cardCount: hands[1].length,
        isUser: false,
        avatarId: 'leaf',
      ),
      GamePlayer(
        id: 'b1',
        name: 'B1',
        team: TeamSide.b,
        seatIndex: 2,
        cardCount: hands[2].length,
        isUser: false,
        avatarId: 'wave',
      ),
      GamePlayer(
        id: 'a2',
        name: 'A2',
        team: TeamSide.a,
        seatIndex: 3,
        cardCount: hands[3].length,
        isUser: false,
        avatarId: 'crown',
      ),
      GamePlayer(
        id: 'b2',
        name: 'B2',
        team: TeamSide.b,
        seatIndex: 4,
        cardCount: hands[4].length,
        isUser: false,
        avatarId: 'stone',
      ),
      GamePlayer(
        id: 'a3',
        name: 'A3',
        team: TeamSide.a,
        seatIndex: 5,
        cardCount: hands[5].length,
        isUser: false,
        avatarId: 'spark',
      ),
    ];
    _activeCombo = null;
    _lastPlayedCards = [];
    _lastPlayedSeat = null;
    _currentSeat = _findFirstLeadSeat(hands);
    _turnSecondsRemaining = GameRuntimeConfig.instance.turnDurationSeconds;
    _passCount = 0;
    _logs
      ..clear()
      ..add('第 $_round 局开始，规则：${widget.ruleSet.name}')
      ..add('${_players[_currentSeat].name} 抓到红桃4，先出牌');
    _finishOrder.clear();
    _roundResult = null;
    if (resetScores) {
      _teamAScore = 0;
      _teamBScore = 0;
    }
  }

  int _findFirstLeadSeat(List<List<CardInstance>> hands) {
    for (var seat = 0; seat < hands.length; seat += 1) {
      final hasHeartFour = hands[seat].any((card) {
        return card.suit == CardSuit.hearts && card.rank == CardRank.four;
      });
      if (hasHeartFour) {
        return seat;
      }
    }
    return 0;
  }

  void _toggleCard(String id) {
    if (!_isUserTurn) {
      _showMessage('还没轮到你');
      return;
    }

    setState(() {
      _hands[0] = _myHand.map((card) {
        return card.id == id ? card.copyWith(selected: !card.selected) : card;
      }).toList();
    });
    HapticFeedback.selectionClick();
  }

  void _hint() {
    final suggestion = _engine.suggest(_myHand, _activeCombo);
    if (suggestion.isEmpty) {
      _showMessage('没有能压过上家的牌，可以过');
      return;
    }

    final ids = suggestion.map((card) => card.id).toSet();
    setState(() {
      _hands[0] = _myHand.map((card) {
        return card.copyWith(selected: ids.contains(card.id));
      }).toList();
    });
    HapticFeedback.selectionClick();
  }

  void _sortMine() {
    setState(() {
      _hands[0] = _engine.sortCards(
        _myHand.map((card) => card.copyWith(selected: false)).toList(),
      );
    });
  }

  void _playSelected() {
    final combo = _selectedCombo;
    if (!_engine.canPlay(candidate: combo, target: _activeCombo)) {
      _showMessage(combo.isValid ? '这手牌压不过上家' : combo.label);
      return;
    }

    _playCards(_currentSeat, _selectedCards, combo);
  }

  void _pass() {
    if (!_canPass) {
      return;
    }
    _passSeat(_currentSeat);
  }

  Future<void> _handleBackRequest() async {
    final shouldLeave = await _confirmExitGame();
    if (shouldLeave && mounted) {
      context.pop();
    }
  }

  Future<bool> _confirmExitGame() async {
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

  void _playCards(int seat, List<CardInstance> cards, CardCombo combo) {
    setState(() {
      final ids = cards.map((card) => card.id).toSet();
      _hands[seat] = _hands[seat]
          .where((card) => !ids.contains(card.id))
          .map((card) => card.copyWith(selected: false))
          .toList();
      _activeCombo = combo;
      _lastPlayedCards = cards
          .map((card) => card.copyWith(selected: false))
          .toList(growable: false);
      _lastPlayedSeat = seat;
      _passCount = 0;
      _players = _players.map((player) {
        if (player.seatIndex == seat) {
          return player.copyWith(
            cardCount: _hands[seat].length,
            status: PlayerStatus.waiting,
          );
        }
        return player.status == PlayerStatus.passed
            ? player.copyWith(status: PlayerStatus.waiting)
            : player;
      }).toList();
      _logs.add('${_players[seat].name} 出 ${combo.label}');
      _markFinishedIfNeeded(seat);
      _maybeFinishRound();
      if (_roundResult == null) {
        _advanceTurn();
      }
    });

    HapticFeedback.lightImpact();
    _restartTurnCountdown();
    _kickAiIfNeeded();
  }

  void _passSeat(int seat) {
    setState(() {
      _passCount += 1;
      _players = _players.map((player) {
        return player.seatIndex == seat
            ? player.copyWith(status: PlayerStatus.passed)
            : player;
      }).toList();
      _logs.add('${_players[seat].name} 过');

      if (_passCount >= _activePlayerCount - 1) {
        final nextLeadSeat = _leadSeatAfterAllPasses(seat);
        _logs.add('一圈过牌，进入新一轮');
        _activeCombo = null;
        _lastPlayedCards = [];
        _lastPlayedSeat = null;
        _passCount = 0;
        _players = _players.map((player) {
          return player.status == PlayerStatus.passed
              ? player.copyWith(status: PlayerStatus.waiting)
              : player;
        }).toList();
        _setCurrentSeat(nextLeadSeat);
      } else {
        _advanceTurn();
      }
    });

    HapticFeedback.selectionClick();
    _restartTurnCountdown();
    _kickAiIfNeeded();
  }

  void _restartTurnCountdown({bool notify = true}) {
    _turnTimer?.cancel();
    if (_roundResult != null || _activePlayerCount <= 1) {
      return;
    }

    void resetSeconds() {
      _turnSecondsRemaining = GameRuntimeConfig.instance.turnDurationSeconds;
    }

    if (notify && mounted) {
      setState(resetSeconds);
    } else {
      resetSeconds();
    }

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _roundResult != null) {
        timer.cancel();
        return;
      }

      if (_turnSecondsRemaining <= 1) {
        timer.cancel();
        _handleTurnTimeout();
        return;
      }

      setState(() {
        _turnSecondsRemaining -= 1;
      });
    });
  }

  void _handleTurnTimeout() {
    if (_roundResult != null) {
      return;
    }

    final seat = _currentSeat;
    _logs.add('${_players[seat].name} 超时托管');
    _autoPlaySeat(seat);
  }

  void _autoPlaySeat(int seat) {
    final suggestion = _engine.suggest(_hands[seat], _activeCombo);
    if (suggestion.isNotEmpty) {
      _playCards(seat, suggestion, _engine.evaluate(suggestion));
      return;
    }

    if (_activeCombo == null && _hands[seat].isNotEmpty) {
      final fallback = [_hands[seat].first];
      _playCards(seat, fallback, _engine.evaluate(fallback));
      return;
    }

    if (_activeCombo != null) {
      _passSeat(seat);
    }
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

  int get _activePlayerCount {
    return _players.where((player) => player.finishRank == null).length;
  }

  void _markFinishedIfNeeded(int seat) {
    if (_hands[seat].isNotEmpty || _players[seat].finishRank != null) {
      return;
    }

    final rank = _finishOrder.length + 1;
    final player = _players[seat];
    _finishOrder.add(FinishedSeat(
      playerId: player.id,
      playerName: player.name,
      team: player.team,
      rank: rank,
    ));
    _players[seat] = player.copyWith(
      cardCount: 0,
      status: PlayerStatus.finished,
      finishRank: rank,
    );
    _logs.add('${player.name} 出完，当前第 $rank 名');
  }

  void _maybeFinishRound() {
    if (_finishOrder.length < _players.length - 1) {
      return;
    }

    final gongTeam = _finishOrder.first.team;
    final lastHomeTeam = _lastHomePlayer.team;
    final winner = gongTeam == lastHomeTeam ? _opponentOf(gongTeam) : gongTeam;
    final caught = _players
        .where((player) => player.team != winner && player.finishRank == null)
        .map((player) => player.name)
        .toList();
    final delta = 3 + caught.length;

    _roundResult = RoundResult(
      winner: winner,
      finishOrder: List.unmodifiable(_finishOrder),
      caughtPlayers: caught,
      teamAScoreDelta: winner == TeamSide.a ? delta : 0,
      teamBScoreDelta: winner == TeamSide.b ? delta : 0,
    );

    if (winner == TeamSide.a) {
      _teamAScore += delta;
    } else {
      _teamBScore += delta;
    }

    scheduleMicrotask(_showRoundResult);
  }

  GamePlayer get _lastHomePlayer {
    final unfinished = _players.where((player) => player.finishRank == null);
    if (unfinished.isNotEmpty) {
      return unfinished.first;
    }

    final lastFinished = _finishOrder.last;
    return _players.firstWhere((player) => player.id == lastFinished.playerId);
  }

  TeamSide _opponentOf(TeamSide team) {
    return team == TeamSide.a ? TeamSide.b : TeamSide.a;
  }

  void _advanceTurn() {
    if (_roundResult != null) {
      return;
    }

    _setCurrentSeat(_nextActiveSeatCounterclockwiseFrom(_currentSeat));
  }

  int _leadSeatAfterAllPasses(int fallbackSeat) {
    final leadSeat = _lastPlayedSeat;
    if (leadSeat == null) {
      return _nextActiveSeatCounterclockwiseFrom(fallbackSeat);
    }

    if (_players[leadSeat].finishRank == null) {
      return leadSeat;
    }

    return _nextActiveSeatCounterclockwiseFrom(leadSeat);
  }

  int _nextActiveSeatCounterclockwiseFrom(int seat) {
    var next = (seat - 1 + _players.length) % _players.length;
    while (_players[next].finishRank != null) {
      next = (next - 1 + _players.length) % _players.length;
    }
    return next;
  }

  void _setCurrentSeat(int seat) {
    _currentSeat = seat;
    _players = _players.map((player) {
      return player.seatIndex == seat
          ? player.copyWith(status: PlayerStatus.thinking)
          : player;
    }).toList();
  }

  void _kickAiIfNeeded() {
    if (_aiRunning || _roundResult != null || _isUserTurn) {
      return;
    }
    unawaited(_runAiTurns());
  }

  Future<void> _runAiTurns() async {
    _aiRunning = true;
    while (mounted && !_isUserTurn && _roundResult == null) {
      await Future<void>.delayed(Duration(seconds: 3 + _aiRandom.nextInt(6)));
      if (!mounted || _isUserTurn || _roundResult != null) {
        break;
      }
      _takeAiTurn(_currentSeat);
    }
    _aiRunning = false;
  }

  void _takeAiTurn(int seat) {
    final target = _activeCombo;
    var suggestion = _engine.suggest(_hands[seat], target);
    if (suggestion.isEmpty && target == null && _hands[seat].isNotEmpty) {
      suggestion = [_hands[seat].first];
    }

    if (suggestion.isEmpty) {
      _passSeat(seat);
      return;
    }

    final combo = _engine.evaluate(suggestion);
    _playCards(seat, suggestion, combo);
  }

  void _showRoundResult() {
    final result = _roundResult;
    if (!mounted || result == null) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(result.winner == _players[0].team ? '本队获胜' : '本队失利'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('胜方：${result.winner.label}'),
              const SizedBox(height: 10),
              const Text('出完顺序'),
              const SizedBox(height: 6),
              for (final seat in result.finishOrder)
                Text('${seat.rank}. ${seat.playerName} (${seat.team.label})'),
              const SizedBox(height: 10),
              Text(
                result.caughtPlayers.isEmpty
                    ? '被逮：无'
                    : '被逮：${result.caughtPlayers.join('、')}',
              ),
              const SizedBox(height: 8),
              Text(
                '本局：A队 +${result.teamAScoreDelta}，B队 +${result.teamBScoreDelta}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.pop();
              },
              child: const Text('返回首页'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _round += 1;
                  _startRound(resetScores: false);
                });
                _restartTurnCountdown();
                _kickAiIfNeeded();
              },
              child: const Text('下一局'),
            ),
          ],
        );
      },
    );
  }

  void _showLogSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            return ListTile(
              dense: true,
              leading: Text('${index + 1}'),
              title: Text(_logs[index]),
            );
          },
        );
      },
    );
  }

  void _showRuleSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.ruleSet.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(widget.ruleSet.summary),
              const SizedBox(height: 16),
              Text('牌副数：${widget.ruleSet.deckCount}'),
              Text('进贡：${widget.ruleSet.enableTribute ? '开' : '关'}'),
              Text('接风：${widget.ruleSet.enableFollowLead ? '开' : '关'}'),
              Text('混牌：${widget.ruleSet.enableWildCards ? '开' : '关'}'),
            ],
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.ruleSet,
    required this.round,
    required this.teamAScore,
    required this.teamBScore,
    required this.onBack,
    required this.onRuleTap,
    required this.onLogTap,
    required this.onSettingsTap,
  });

  final RuleSet ruleSet;
  final int round;
  final int teamAScore;
  final int teamBScore;
  final VoidCallback onBack;
  final VoidCallback onRuleTap;
  final VoidCallback onLogTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '第 $round 局',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RuleBadge(ruleSet: ruleSet, onTap: onRuleTap),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'A队 $teamAScore    B队 $teamBScore',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '牌局记录',
            onPressed: onLogTap,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: '配置',
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}
