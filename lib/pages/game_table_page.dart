import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/card_model.dart';
import '../models/player_model.dart';
import '../models/round_result.dart';
import '../models/rule_set.dart';
import '../services/rule_engine.dart';
import '../utils/app_theme.dart';
import '../widgets/action_bar.dart';
import '../widgets/hand_area.dart';
import '../widgets/player_seat.dart';
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
  final List<String> _logs = [];
  final List<FinishedSeat> _finishOrder = [];

  late List<GamePlayer> _players;
  late List<List<CardInstance>> _hands;

  CardCombo? _activeCombo;
  int? _lastPlayedSeat;
  int _currentSeat = 0;
  int _passCount = 0;
  int _round = 1;
  int _teamAScore = 0;
  int _teamBScore = 0;
  bool _aiRunning = false;
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
    _startRound(resetScores: true);
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayer = _players[_currentSeat];
    final lastPlayedBy =
        _lastPlayedSeat == null ? null : _players[_lastPlayedSeat!].name;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TableHeader(
              ruleSet: widget.ruleSet,
              round: _round,
              teamAScore: _teamAScore,
              teamBScore: _teamBScore,
              onBack: () => context.pop(),
              onRuleTap: _showRuleSheet,
              onLogTap: _showLogSheet,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 250,
                        height: 168,
                        decoration: BoxDecoration(
                          color: AppTheme.tableGreen,
                          borderRadius: BorderRadius.circular(86),
                          border: Border.all(color: const Color(0x6679D98B)),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: TableCenter(
                        activeCombo: _activeCombo,
                        lastPlayedBy: lastPlayedBy,
                        currentPlayer: currentPlayer.name,
                        passCount: _passCount,
                      ),
                    ),
                    for (var seat = 0; seat < _players.length; seat += 1)
                      Align(
                        alignment: _seatAlignment(seat),
                        child: PlayerSeat(
                          player: _players[seat],
                          isCurrent: seat == _currentSeat && _roundResult == null,
                          isAlly: _players[seat].team == _players[0].team,
                        ),
                      ),
                    Align(
                      alignment: const Alignment(0, 0.68),
                      child: _FinishOrderBar(finishOrder: _finishOrder),
                    ),
                  ],
                ),
              ),
            ),
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
        ),
      ),
    );
  }

  Alignment _seatAlignment(int seat) {
    return switch (seat) {
      0 => const Alignment(0, 0.98),
      1 => const Alignment(-0.83, 0.46),
      2 => const Alignment(-0.83, -0.46),
      3 => const Alignment(0, -0.98),
      4 => const Alignment(0.83, -0.46),
      5 => const Alignment(0.83, 0.46),
      _ => Alignment.center,
    };
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
      ),
      GamePlayer(
        id: 'a1',
        name: 'A1',
        team: TeamSide.a,
        seatIndex: 1,
        cardCount: hands[1].length,
        isUser: false,
      ),
      GamePlayer(
        id: 'b1',
        name: 'B1',
        team: TeamSide.b,
        seatIndex: 2,
        cardCount: hands[2].length,
        isUser: false,
      ),
      GamePlayer(
        id: 'a2',
        name: 'A2',
        team: TeamSide.a,
        seatIndex: 3,
        cardCount: hands[3].length,
        isUser: false,
      ),
      GamePlayer(
        id: 'b2',
        name: 'B2',
        team: TeamSide.b,
        seatIndex: 4,
        cardCount: hands[4].length,
        isUser: false,
      ),
      GamePlayer(
        id: 'a3',
        name: 'A3',
        team: TeamSide.a,
        seatIndex: 5,
        cardCount: hands[5].length,
        isUser: false,
      ),
    ];
    _activeCombo = null;
    _lastPlayedSeat = null;
    _currentSeat = 0;
    _passCount = 0;
    _logs
      ..clear()
      ..add('第 $_round 局开始，规则：${widget.ruleSet.name}');
    _finishOrder.clear();
    _roundResult = null;
    if (resetScores) {
      _teamAScore = 0;
      _teamBScore = 0;
    }
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

  void _playCards(int seat, List<CardInstance> cards, CardCombo combo) {
    setState(() {
      final ids = cards.map((card) => card.id).toSet();
      _hands[seat] = _hands[seat]
          .where((card) => !ids.contains(card.id))
          .map((card) => card.copyWith(selected: false))
          .toList();
      _activeCombo = combo;
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
        _logs.add('一圈过牌，进入新一轮');
        _activeCombo = null;
        _lastPlayedSeat = null;
        _passCount = 0;
        _players = _players.map((player) {
          return player.status == PlayerStatus.passed
              ? player.copyWith(status: PlayerStatus.waiting)
              : player;
        }).toList();
      }

      _advanceTurn();
    });

    HapticFeedback.selectionClick();
    _kickAiIfNeeded();
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
    final aFinished = _finishOrder.where((seat) => seat.team == TeamSide.a).length;
    final bFinished = _finishOrder.where((seat) => seat.team == TeamSide.b).length;
    if (aFinished < 3 && bFinished < 3) {
      return;
    }

    final winner = aFinished == 3 ? TeamSide.a : TeamSide.b;
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

  void _advanceTurn() {
    if (_roundResult != null) {
      return;
    }

    var next = (_currentSeat + 1) % _players.length;
    while (_players[next].finishRank != null) {
      next = (next + 1) % _players.length;
    }
    _currentSeat = next;
    _players = _players.map((player) {
      return player.seatIndex == next
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
      await Future<void>.delayed(const Duration(milliseconds: 650));
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
  });

  final RuleSet ruleSet;
  final int round;
  final int teamAScore;
  final int teamBScore;
  final VoidCallback onBack;
  final VoidCallback onRuleTap;
  final VoidCallback onLogTap;

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
        ],
      ),
    );
  }
}

class _FinishOrderBar extends StatelessWidget {
  const _FinishOrderBar({required this.finishOrder});

  final List<FinishedSeat> finishOrder;

  @override
  Widget build(BuildContext context) {
    if (finishOrder.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '出完顺序：${finishOrder.map((seat) => seat.playerName).join('、')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
