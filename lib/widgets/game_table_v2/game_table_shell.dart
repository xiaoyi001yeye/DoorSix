import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/card_model.dart';
import '../../models/player_model.dart';
import '../../models/round_result.dart';
import '../../services/rule_engine.dart';
import 'config/game_table_layout_config.dart';
import 'config/game_table_layout_loader.dart';
import 'config/game_table_layout_resolver.dart';
import '../hand_card.dart';
import '../player_avatar_badge.dart';

enum GameActionKind {
  back,
  hint,
  sort,
  pass,
  play,
  rules,
  replay,
  refresh,
  settings,
  layoutLog,
}

enum GameActionPlacement {
  primary,
  secondary,
  utility,
  topBar,
}

class GameActionItem {
  const GameActionItem({
    required this.kind,
    required this.label,
    required this.icon,
    required this.placement,
    required this.enabled,
    required this.visible,
    this.disabledReason,
    this.onPressed,
  });

  final GameActionKind kind;
  final String label;
  final IconData icon;
  final GameActionPlacement placement;
  final bool enabled;
  final bool visible;
  final String? disabledReason;
  final VoidCallback? onPressed;
}

class GameTableViewModel {
  const GameTableViewModel({
    required this.roundNo,
    required this.teamAScore,
    required this.teamBScore,
    required this.players,
    required this.selfSeat,
    required this.selfTeam,
    required this.currentSeat,
    required this.lastPlayedSeat,
    required this.activeCombo,
    required this.playedCards,
    required this.lastPlayedBy,
    required this.currentPlayerName,
    required this.passCount,
    required this.finishOrder,
    required this.hand,
    required this.selectedCombo,
    required this.canPlay,
    required this.canPass,
    required this.isUserTurn,
    required this.onToggleCard,
    this.roomCode,
    this.connected,
    this.turnSecondsRemaining,
    this.currentTrickIndex,
    this.totalTrickCount,
  });

  final String? roomCode;
  final int roundNo;
  final int teamAScore;
  final int teamBScore;
  final bool? connected;
  final int? turnSecondsRemaining;
  final int? currentTrickIndex;
  final int? totalTrickCount;
  final List<GamePlayer> players;
  final int selfSeat;
  final TeamSide selfTeam;
  final int? currentSeat;
  final int? lastPlayedSeat;
  final CardCombo? activeCombo;
  final List<CardInstance> playedCards;
  final String? lastPlayedBy;
  final String currentPlayerName;
  final int passCount;
  final List<FinishedSeat> finishOrder;
  final List<CardInstance> hand;
  final CardCombo selectedCombo;
  final bool canPlay;
  final bool canPass;
  final bool isUserTurn;
  final ValueChanged<String> onToggleCard;
}

typedef _LayoutDebugKeyProvider = GlobalKey Function(String name);

class GameTableShell extends StatefulWidget {
  const GameTableShell({
    required this.state,
    required this.actions,
    super.key,
  });

  final GameTableViewModel state;
  final List<GameActionItem> actions;

  @override
  State<GameTableShell> createState() => _GameTableShellState();
}

class _GameTableShellState extends State<GameTableShell> {
  final _rootKey = GlobalKey(debugLabel: '牌桌根容器');
  final Map<String, GlobalKey> _debugKeys = {};
  GameTableLayoutConfig _layoutConfig = GameTableLayoutConfig.fallback;
  String? _layoutConfigError;

  GlobalKey _debugKeyFor(String name) {
    return _debugKeys.putIfAbsent(name, () => GlobalKey(debugLabel: name));
  }

  @override
  void initState() {
    super.initState();
    _loadLayoutConfig();
  }

  Future<void> _loadLayoutConfig() async {
    try {
      final config = await GameTableLayoutLoader.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _layoutConfig = config;
        _layoutConfigError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _layoutConfig = GameTableLayoutConfig.fallback;
        _layoutConfigError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        return DecoratedBox(
          key: _rootKey,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF1DFB7),
                Color(0xFFE9D4A5),
                Color(0xFFDDBF83),
              ],
            ),
          ),
          child: Stack(
            children: [
              const _InkWashBackdrop(),
              SafeArea(
                top: false,
                bottom: false,
                child: isLandscape
                    ? _LandscapeTable(
                        state: widget.state,
                        actions: _actionsWithLayoutLog(),
                        debugKeyFor: _debugKeyFor,
                        layoutConfig: _layoutConfig,
                      )
                    : _PortraitTable(
                        state: widget.state,
                        actions: _actionsWithLayoutLog(),
                        debugKeyFor: _debugKeyFor,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<GameActionItem> _actionsWithLayoutLog() {
    return [
      ...widget.actions,
      GameActionItem(
        kind: GameActionKind.layoutLog,
        label: '布局日志',
        icon: Icons.bug_report_outlined,
        placement: GameActionPlacement.topBar,
        enabled: true,
        visible: true,
        onPressed: _showLayoutLog,
      ),
    ];
  }

  void _showLayoutLog() {
    final report = _buildLayoutReport();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LayoutLogSheet(report: report),
    );
  }

  _LayoutDebugReport _buildLayoutReport() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final devicePixelRatio = mediaQuery?.devicePixelRatio ?? 1.0;
    final screenLogicalSize = mediaQuery?.size ?? Size.zero;
    final screenPhysicalSize = Size(
      screenLogicalSize.width * devicePixelRatio,
      screenLogicalSize.height * devicePixelRatio,
    );
    final rootObject = _rootKey.currentContext?.findRenderObject();
    final rootBox = rootObject is RenderBox ? rootObject : null;
    final rootSize = rootBox?.size ?? Size.zero;
    final rootOrigin = rootBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final entries = <_LayoutDebugEntry>[];

    for (final item in _debugKeys.entries) {
      final renderObject = item.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final offset = renderObject.localToGlobal(Offset.zero) - rootOrigin;
      entries.add(
        _LayoutDebugEntry(
          name: item.key,
          rect: offset & renderObject.size,
          rootSize: rootSize,
        ),
      );
    }

    return _LayoutDebugReport(
      capturedAt: DateTime.now(),
      layoutConfigId: _layoutConfig.id,
      layoutConfigError: _layoutConfigError,
      devicePixelRatio: devicePixelRatio,
      screenPhysicalSize: screenPhysicalSize,
      screenLogicalSize: screenLogicalSize,
      rootSize: rootSize,
      entries: entries,
    );
  }
}

class _LayoutDebugReport {
  const _LayoutDebugReport({
    required this.capturedAt,
    required this.layoutConfigId,
    required this.layoutConfigError,
    required this.devicePixelRatio,
    required this.screenPhysicalSize,
    required this.screenLogicalSize,
    required this.rootSize,
    required this.entries,
  });

  final DateTime capturedAt;
  final String layoutConfigId;
  final String? layoutConfigError;
  final double devicePixelRatio;
  final Size screenPhysicalSize;
  final Size screenLogicalSize;
  final Size rootSize;
  final List<_LayoutDebugEntry> entries;

  String toClipboardText() {
    final lines = <String>[
      '牌桌布局日志',
      'layout config: $layoutConfigId',
      if (layoutConfigError != null) 'layout config error: $layoutConfigError',
      'devicePixelRatio: ${devicePixelRatio.toStringAsFixed(1)}',
      'screen physical: ${screenPhysicalSize.width.toStringAsFixed(0)} x '
          '${screenPhysicalSize.height.toStringAsFixed(0)}',
      'screen logical: ${screenLogicalSize.width.toStringAsFixed(1)} x '
          '${screenLogicalSize.height.toStringAsFixed(1)}',
      'root: ${rootSize.width.toStringAsFixed(1)} x '
          '${rootSize.height.toStringAsFixed(1)}',
      'captured: ${_formatTime(capturedAt)}',
      '',
    ];

    for (final entry in entries) {
      lines
        ..add('[${entry.name}]')
        ..add(
          'position: left ${entry.rect.left.toStringAsFixed(1)} '
          '(${_pct(entry.leftRatio)}), top '
          '${entry.rect.top.toStringAsFixed(1)} (${_pct(entry.topRatio)})',
        )
        ..add(
          'size: ${entry.rect.width.toStringAsFixed(1)} x '
          '${entry.rect.height.toStringAsFixed(1)} '
          '(${_pct(entry.widthRatio)} x ${_pct(entry.heightRatio)})',
        )
        ..add(
          'center: ${entry.rect.center.dx.toStringAsFixed(1)}, '
          '${entry.rect.center.dy.toStringAsFixed(1)}',
        )
        ..add('raw: ${entry.summary}')
        ..add('');
    }

    return lines.join('\n').trimRight();
  }
}

class _LayoutDebugEntry {
  const _LayoutDebugEntry({
    required this.name,
    required this.rect,
    required this.rootSize,
  });

  final String name;
  final Rect rect;
  final Size rootSize;

  double get widthRatio {
    return rootSize.width == 0 ? 0 : rect.width / rootSize.width;
  }

  double get heightRatio =>
      rootSize.height == 0 ? 0 : rect.height / rootSize.height;

  double get leftRatio => rootSize.width == 0 ? 0 : rect.left / rootSize.width;

  double get topRatio => rootSize.height == 0 ? 0 : rect.top / rootSize.height;

  String get summary {
    return [
      name,
      'x=${rect.left.toStringAsFixed(1)} (${_pct(leftRatio)})',
      'y=${rect.top.toStringAsFixed(1)} (${_pct(topRatio)})',
      'w=${rect.width.toStringAsFixed(1)} (${_pct(widthRatio)})',
      'h=${rect.height.toStringAsFixed(1)} (${_pct(heightRatio)})',
      'cx=${rect.center.dx.toStringAsFixed(1)}',
      'cy=${rect.center.dy.toStringAsFixed(1)}',
    ].join(' | ');
  }
}

class _LayoutLogSheet extends StatelessWidget {
  const _LayoutLogSheet({required this.report});

  final _LayoutDebugReport report;

  Future<void> _copyReport(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report.toClipboardText()));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('布局日志已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootSize = report.rootSize;
    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.36,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F2DE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD2B56F),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bug_report_outlined,
                      color: Color(0xFF0C4380),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '牌桌布局日志',
                        style: TextStyle(
                          color: Color(0xFF0C4380),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyReport(context),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制'),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    _LayoutLogBlock(
                      title: '根容器',
                      lines: [
                        'layoutConfig=${report.layoutConfigId}',
                        if (report.layoutConfigError != null)
                          'layoutConfigError=${report.layoutConfigError}',
                        'devicePixelRatio='
                            '${report.devicePixelRatio.toStringAsFixed(1)}',
                        'screen physical='
                            '${report.screenPhysicalSize.width.toStringAsFixed(0)} x '
                            '${report.screenPhysicalSize.height.toStringAsFixed(0)}',
                        'screen logical='
                            '${report.screenLogicalSize.width.toStringAsFixed(1)} x '
                            '${report.screenLogicalSize.height.toStringAsFixed(1)}',
                        'size=${rootSize.width.toStringAsFixed(1)} x '
                            '${rootSize.height.toStringAsFixed(1)}',
                        'captured=${_formatTime(report.capturedAt)}',
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final entry in report.entries) ...[
                      _LayoutLogBlock(
                        title: entry.name,
                        lines: [
                          'position: left ${entry.rect.left.toStringAsFixed(1)} '
                              '(${_pct(entry.leftRatio)}), top '
                              '${entry.rect.top.toStringAsFixed(1)} '
                              '(${_pct(entry.topRatio)})',
                          'size: ${entry.rect.width.toStringAsFixed(1)} x '
                              '${entry.rect.height.toStringAsFixed(1)} '
                              '(${_pct(entry.widthRatio)} x '
                              '${_pct(entry.heightRatio)})',
                          'center: ${entry.rect.center.dx.toStringAsFixed(1)}, '
                              '${entry.rect.center.dy.toStringAsFixed(1)}',
                          'raw: ${entry.summary}',
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LayoutLogBlock extends StatelessWidget {
  const _LayoutLogBlock({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0C983)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF0C4380),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              SelectableText(
                line,
                style: const TextStyle(
                  color: Color(0xFF345B73),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeTable extends StatelessWidget {
  const _LandscapeTable({
    required this.state,
    required this.actions,
    required this.debugKeyFor,
    required this.layoutConfig,
  });

  final GameTableViewModel state;
  final List<GameActionItem> actions;
  final _LayoutDebugKeyProvider debugKeyFor;
  final GameTableLayoutConfig layoutConfig;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedLayout = GameTableLayoutResolver.resolveLandscape(
          config: layoutConfig,
          parentSize: Size(constraints.maxWidth, constraints.maxHeight),
        );
        final compact = resolvedLayout.compact;

        return Stack(
          children: [
            _PositionedLayer(
              rect: resolvedLayout.rectFor('top_bar'),
              child: KeyedSubtree(
                key: debugKeyFor('横屏/顶栏'),
                child: _GameTopBar(state: state, actions: actions),
              ),
            ),
            _PositionedLayer(
              rect: resolvedLayout.rectFor('seat_stage'),
              child: KeyedSubtree(
                key: debugKeyFor('横屏/座位舞台'),
                child: _SeatStage(
                  state: state,
                  debugKeyFor: debugKeyFor,
                  forceCompact: compact,
                ),
              ),
            ),
            _PositionedLayer(
              rect: resolvedLayout.rectFor('hand_dock'),
              child: KeyedSubtree(
                key: debugKeyFor('横屏/手牌区'),
                child: _HandDock(
                  state: state,
                  compact: compact,
                  showStatus: false,
                ),
              ),
            ),
            _PositionedLayer(
              rect: resolvedLayout.rectFor('action_column'),
              child: KeyedSubtree(
                key: debugKeyFor('横屏/右侧操作栏'),
                child: _ActionColumn(actions: actions, compact: compact),
              ),
            ),
            _PositionedLayer(
              rect: resolvedLayout.rectFor('utility_actions'),
              child: KeyedSubtree(
                key: debugKeyFor('横屏/左下辅助操作'),
                child: _UtilityActions(actions: actions),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PositionedLayer extends StatelessWidget {
  const _PositionedLayer({
    required this.rect,
    required this.child,
  });

  final Rect rect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: child,
    );
  }
}

class _PortraitTable extends StatelessWidget {
  const _PortraitTable({
    required this.state,
    required this.actions,
    required this.debugKeyFor,
  });

  final GameTableViewModel state;
  final List<GameActionItem> actions;
  final _LayoutDebugKeyProvider debugKeyFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: KeyedSubtree(
            key: debugKeyFor('竖屏/顶栏'),
            child: _GameTopBar(state: state, actions: actions),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: KeyedSubtree(
              key: debugKeyFor('竖屏/座位舞台'),
              child: _SeatStage(state: state, debugKeyFor: debugKeyFor),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: KeyedSubtree(
            key: debugKeyFor('竖屏/手牌区'),
            child: _HandDock(state: state),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: KeyedSubtree(
            key: debugKeyFor('竖屏/底部操作栏'),
            child: _BottomActions(actions: actions),
          ),
        ),
      ],
    );
  }
}

class _GameTopBar extends StatelessWidget {
  const _GameTopBar({
    required this.state,
    required this.actions,
  });

  final GameTableViewModel state;
  final List<GameActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final topActions = actions
            .where((action) =>
                action.visible &&
                action.placement == GameActionPlacement.topBar &&
                action.kind != GameActionKind.back)
            .toList(growable: false);
        final visibleTopActions = compact
            ? topActions
                .where((action) =>
                    action.kind == GameActionKind.settings ||
                    action.kind == GameActionKind.layoutLog)
                .toList(growable: false)
            : topActions;
        final roomText =
            state.roomCode == null ? '练习桌' : '房间 ${state.roomCode}';
        final connectionText = compact
            ? null
            : state.connected == null
                ? null
                : state.connected!
                    ? '良好'
                    : '断线';

        return Row(
          children: [
            _RoundIconButton(
              tooltip: '返回',
              icon: Icons.arrow_back_rounded,
              onPressed: _firstAction(GameActionKind.back)?.onPressed,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: _bluePanelDecoration(radius: 18),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        roomText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFECA8),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const _TopDivider(),
                    Text(
                      '第 ${state.roundNo} 局',
                      style: const TextStyle(
                        color: Color(0xFFFFECA8),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!compact) ...[
                      const _TopDivider(),
                      Text(
                        'A ${state.teamAScore}: ${state.teamBScore} B',
                        style: const TextStyle(
                          color: Color(0xFFFFECA8),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                    if (connectionText != null) ...[
                      const _TopDivider(),
                      Icon(
                        state.connected!
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        size: 20,
                        color: state.connected!
                            ? const Color(0xFFBEEA6B)
                            : const Color(0xFFFFA19C),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        connectionText,
                        style: TextStyle(
                          color: state.connected!
                              ? const Color(0xFFBEEA6B)
                              : const Color(0xFFFFA19C),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!compact && state.turnSecondsRemaining != null) ...[
              const SizedBox(width: 10),
              _TimerBadge(seconds: state.turnSecondsRemaining!),
            ],
            const SizedBox(width: 10),
            for (final action in visibleTopActions) ...[
              _RoundIconButton(
                tooltip: action.label,
                icon: action.icon,
                onPressed: action.enabled ? action.onPressed : null,
              ),
              const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  GameActionItem? _firstAction(GameActionKind kind) {
    for (final action in actions) {
      if (action.kind == kind) {
        return action;
      }
    }
    return null;
  }
}

class _SeatStage extends StatelessWidget {
  const _SeatStage({
    required this.state,
    required this.debugKeyFor,
    this.forceCompact = false,
  });

  final GameTableViewModel state;
  final _LayoutDebugKeyProvider debugKeyFor;
  final bool forceCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            forceCompact ||
            constraints.maxHeight < 170 ||
            constraints.maxWidth < 650;
        final centerWidth = compact
            ? 196.0
            : math.min(340.0, constraints.maxWidth * 0.36);
        if (compact) {
          return _CompactSeatStage(
            state: state,
            debugKeyFor: debugKeyFor,
            centerWidth: centerWidth,
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: KeyedSubtree(
                key: debugKeyFor('中央出牌区'),
                child: _CenterPlayPanel(
                  state: state,
                  width: centerWidth,
                ),
              ),
            ),
            for (final player in state.players)
              _MeasuredPlayerSeat(
                player: player,
                state: state,
                debugKeyFor: debugKeyFor,
                compact: false,
              ),
          ],
        );
      },
    );
  }
}

class _CompactSeatStage extends StatelessWidget {
  const _CompactSeatStage({
    required this.state,
    required this.debugKeyFor,
    required this.centerWidth,
  });

  final GameTableViewModel state;
  final _LayoutDebugKeyProvider debugKeyFor;
  final double centerWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final seatWidth = math.min(
          154.0,
          math.max(112.0, (constraints.maxWidth - 24) / 3),
        );
        final compactScale = seatWidth / 154.0;
        final seatHeight = 54.0 * compactScale;
        final centerGap = 10.0 * compactScale;
        final middleWidth = math.max(
          118.0,
          constraints.maxWidth - (seatWidth * 2) - (centerGap * 2),
        );
        final compactCenterWidth = math.min(
          centerWidth * compactScale,
          middleWidth,
        );
        final centerHeight = 48.0 * compactScale;
        final maxX = math.max(0.0, constraints.maxWidth - seatWidth);
        final maxY = math.max(0.0, constraints.maxHeight - seatHeight);
        final centerLeft = (constraints.maxWidth - compactCenterWidth) / 2;
        final centerTop =
            maxY + math.max(0.0, (seatHeight - centerHeight) / 2);

        Offset seatOffset(GamePlayer player) {
          final displaySeat =
              _displaySeatIndex(player.seatIndex, state.selfSeat);
          return switch (displaySeat) {
            1 => Offset(0, maxY),
            2 => Offset.zero,
            3 => Offset(maxX / 2, 0),
            4 => Offset(maxX, 0),
            5 => Offset(maxX, maxY),
            _ => Offset(maxX / 2, maxY),
          };
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: centerLeft,
              top: centerTop,
              child: KeyedSubtree(
                key: debugKeyFor('中央出牌区'),
                child: _CenterPlayPanel(
                  state: state,
                  width: compactCenterWidth,
                  compact: true,
                  compactScale: compactScale,
                ),
              ),
            ),
            for (final player in state.players)
              if (_displaySeatIndex(player.seatIndex, state.selfSeat) != 0)
                Positioned(
                  left: seatOffset(player).dx,
                  top: seatOffset(player).dy,
                  child: KeyedSubtree(
                    key: debugKeyFor(
                      '座位${player.seatIndex}/显示'
                      '${_displaySeatIndex(player.seatIndex, state.selfSeat)}',
                    ),
                    child: _PlayerSeatV2(
                      player: player,
                      isCurrent: state.currentSeat == player.seatIndex,
                      isAlly: player.team == state.selfTeam,
                      showPlayPointer: false,
                      compact: true,
                      compactScale: compactScale,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _MeasuredPlayerSeat extends StatelessWidget {
  const _MeasuredPlayerSeat({
    required this.player,
    required this.state,
    required this.debugKeyFor,
    required this.compact,
  });

  final GamePlayer player;
  final GameTableViewModel state;
  final _LayoutDebugKeyProvider debugKeyFor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final displaySeat = _displaySeatIndex(player.seatIndex, state.selfSeat);
    return Align(
      alignment: _seatAlignment(displaySeat),
      child: KeyedSubtree(
        key: debugKeyFor('座位${player.seatIndex}/显示$displaySeat'),
        child: _PlayerSeatV2(
          player: player,
          isCurrent: state.currentSeat == player.seatIndex,
          isAlly: player.team == state.selfTeam,
          showPlayPointer: state.lastPlayedSeat == player.seatIndex,
          countdownSeconds: state.currentSeat == player.seatIndex
              ? state.turnSecondsRemaining
              : null,
          compact: compact,
        ),
      ),
    );
  }
}

class _CenterPlayPanel extends StatelessWidget {
  const _CenterPlayPanel({
    required this.state,
    required this.width,
    this.compact = false,
    this.compactScale = 1,
  });

  final GameTableViewModel state;
  final double width;
  final bool compact;
  final double compactScale;

  @override
  Widget build(BuildContext context) {
    final playedCards = state.playedCards;
    if (compact) {
      final scale = compactScale;
      final panelHeight = 48.0 * scale;
      final cardWidth = 28.0 * scale;
      final cardHeight = 40.0 * scale;
      final sideWidth = math.max(58.0, 72.0 * scale);
      final titleFont = math.max(10.5, 12.0 * scale);
      final metaFont = math.max(9.5, 11.0 * scale);
      return Container(
        width: width,
        height: panelHeight,
        padding: EdgeInsets.symmetric(
          horizontal: 10.0 * scale,
          vertical: 4.0 * scale,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8B66D), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: playedCards.isEmpty
                    ? Center(
                        child: Text(
                          '新一轮',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF0C4380),
                            fontWeight: FontWeight.w900,
                            fontSize: titleFont,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final card in playedCards)
                              HandCard(
                                card: card.copyWith(selected: false),
                                onTap: () {},
                                width: cardWidth,
                                height: cardHeight,
                                trailingMargin: 3,
                                showSelectionOffset: false,
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            SizedBox(width: 8 * scale),
            SizedBox(
              width: sideWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.activeCombo == null
                        ? '等待首出'
                        : state.activeCombo!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF0C4380),
                      fontWeight: FontWeight.w900,
                      fontSize: titleFont,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    '轮到 ${state.currentPlayerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF345B73),
                      fontWeight: FontWeight.w800,
                      fontSize: metaFont,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8B66D), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playedCards.isEmpty)
            const SizedBox(
              height: 82,
              child: Center(
                child: Text(
                  '新一轮',
                  style: TextStyle(
                    color: Color(0xFF0C4380),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 86,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final card in playedCards)
                      HandCard(
                        card: card.copyWith(selected: false),
                        onTap: () {},
                        width: 54,
                        height: 78,
                        trailingMargin: 5,
                        showSelectionOffset: false,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          _SmallBluePill(
            text: state.lastPlayedBy == null ? '等待首出' : '上手：${state.lastPlayedBy}',
          ),
          const SizedBox(height: 10),
          Text(
            _roundText,
            style: const TextStyle(
              color: Color(0xFF0C4380),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '轮到：${state.currentPlayerName}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0C4380),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String get _roundText {
    final current = state.currentTrickIndex;
    final total = state.totalTrickCount;
    if (current == null || total == null) {
      return state.activeCombo == null ? '当前轮次' : state.activeCombo!.label;
    }
    return '当前轮次  $current/$total';
  }
}

class _PlayerSeatV2 extends StatelessWidget {
  const _PlayerSeatV2({
    required this.player,
    required this.isCurrent,
    required this.isAlly,
    required this.showPlayPointer,
    this.countdownSeconds,
    this.compact = false,
    this.compactScale = 1,
  });

  final GamePlayer player;
  final bool isCurrent;
  final bool isAlly;
  final bool showPlayPointer;
  final int? countdownSeconds;
  final bool compact;
  final double compactScale;

  @override
  Widget build(BuildContext context) {
    final borderColor = isCurrent
        ? const Color(0xFFFFDE7A)
        : isAlly
            ? const Color(0xFF4B8FD4)
            : const Color(0xFFD09B3A);
    final name = player.isUser ? '玩家' : player.name;
    final scale = compact ? compactScale : 1.0;
    final seatWidth = compact ? 154.0 * scale : 212.0;
    final seatHeight = compact ? 54.0 * scale : 76.0;
    final avatarSize = compact ? math.max(32.0, 40.0 * scale) : 58.0;
    final iconSize = compact ? math.max(16.0, 19.0 * scale) : 26.0;
    final nameFont = compact ? math.max(11.0, 14.0 * scale) : 18.0;
    final metaFont = compact ? math.max(9.0, 10.0 * scale) : 12.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (countdownSeconds != null && isCurrent) ...[
          _SmallBluePill(text: '${countdownSeconds}s'),
          SizedBox(height: compact ? 2 : 4),
        ],
        if (showPlayPointer)
          Icon(
            Icons.arrow_drop_down_rounded,
            color: const Color(0xFFD09B3A),
            size: compact ? 20 : 28,
        ),
        Container(
          width: seatWidth,
          height: seatHeight,
          padding: EdgeInsets.fromLTRB(
            compact ? 6 * scale : 8,
            compact ? 6 * scale : 8,
            compact ? 8 * scale : 12,
            compact ? 6 * scale : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(compact ? 27 : 38),
            border: Border.all(
              color: borderColor,
              width: isCurrent ? 2.2 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              PlayerAvatarBadge(
                avatarId: player.avatarId,
                size: avatarSize,
                showRing: true,
              ),
              SizedBox(width: compact ? 7 * scale : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (player.isUser) ...[
                          _DealerMark(team: player.team),
                          SizedBox(width: compact ? 3 : 4),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF0C4380),
                              fontWeight: FontWeight.w900,
                              fontSize: nameFont,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      _metaText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: player.finishRank == null
                            ? const Color(0xFF345B73)
                            : const Color(0xFF247A37),
                        fontWeight: FontWeight.w800,
                        fontSize: metaFont,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 4 * scale : 6),
              Icon(
                Icons.style_rounded,
                color: const Color(0xFF1F65B5),
                size: iconSize,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _metaText {
    if (player.finishRank != null) {
      return '第 ${player.finishRank} 名';
    }
    if (player.status == PlayerStatus.passed) {
      return '不出 · 余牌 ${player.cardCount}';
    }
    return '余牌 ${player.cardCount}';
  }
}

class _HandDock extends StatelessWidget {
  const _HandDock({
    required this.state,
    this.compact = false,
    this.showStatus = true,
  });

  final GameTableViewModel state;
  final bool compact;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final selectedCount = state.hand.where((card) => card.selected).length;
    final status = selectedCount == 0
        ? '请选择要出的牌'
        : state.selectedCombo.isValid
            ? '${state.selectedCombo.label}${state.canPlay ? '，可以出' : '，压不过上家'}'
            : state.selectedCombo.label;
    return Container(
      constraints: BoxConstraints(
        minHeight: showStatus
            ? (compact ? 112 : 130)
            : (compact ? 100 : 118),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        showStatus ? (compact ? 10 : 14) : (compact ? 8 : 10),
        compact ? 14 : 18,
        compact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(compact ? 22 : 26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStatus) ...[
            Row(
              children: [
                Text(
                  '我的手牌 ${state.hand.length}',
                  style: const TextStyle(
                    color: Color(0xFF0C4380),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedCount == 0
                          ? const Color(0xFF6D6B61)
                          : state.canPlay
                              ? const Color(0xFF247A37)
                              : const Color(0xFFC84335),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          _V2HandScroller(
            cards: state.hand,
            onToggle: state.onToggleCard,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _V2HandScroller extends StatelessWidget {
  const _V2HandScroller({
    required this.cards,
    required this.onToggle,
    this.compact = false,
  });

  final List<CardInstance> cards;
  final ValueChanged<String> onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return SizedBox(
        height: compact ? 72 : 86,
        child: const Center(
          child: Text(
            '手牌已出完',
            style: TextStyle(color: Color(0xFF6D6B61)),
          ),
        ),
      );
    }

    final cardWidth = compact ? 52.0 : 68.0;
    final cardHeight = compact ? 75.0 : 98.0;
    final selectedLift = compact ? 12.0 : 18.0;
    final minStep = compact ? 24.0 : 30.0;
    final preferredStep = compact ? 36.0 : 48.0;

    return SizedBox(
      height: cardHeight + selectedLift,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fittedStep = cards.length <= 1
              ? preferredStep
              : (constraints.maxWidth - cardWidth) / (cards.length - 1);
          final step = math.max(minStep, math.min(preferredStep, fittedStep));
          final stackWidth = math.max(
            constraints.maxWidth,
            cardWidth + step * (cards.length - 1),
          );

          Widget positionedCard(int index) {
            final card = cards[index];
            return AnimatedPositioned(
              key: ValueKey(card.id),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              left: index * step,
              top: card.selected ? 0 : selectedLift,
              child: HandCard(
                card: card,
                onTap: () => onToggle(card.id),
                width: cardWidth,
                height: cardHeight,
                trailingMargin: 0,
                showSelectionOffset: false,
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: stackWidth,
              height: cardHeight + selectedLift,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < cards.length; index += 1)
                    if (!cards[index].selected) positionedCard(index),
                  for (var index = 0; index < cards.length; index += 1)
                    if (cards[index].selected) positionedCard(index),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.actions,
    this.compact = false,
  });

  final List<GameActionItem> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final buttons = actions
        .where((action) =>
            action.visible &&
            action.kind != GameActionKind.sort &&
            (action.placement == GameActionPlacement.primary ||
                action.placement == GameActionPlacement.secondary))
        .toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < buttons.length; index += 1) ...[
          _ActionButton(action: buttons[index], compact: compact),
          if (index != buttons.length - 1) SizedBox(height: compact ? 8 : 10),
        ],
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.actions});

  final List<GameActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final buttons = actions
        .where((action) =>
            action.visible &&
            action.placement != GameActionPlacement.topBar)
        .toList(growable: false);
    return Row(
      children: [
        for (var index = 0; index < buttons.length; index += 1) ...[
          Expanded(child: _ActionButton(action: buttons[index], compact: true)),
          if (index != buttons.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _UtilityActions extends StatelessWidget {
  const _UtilityActions({required this.actions});

  final List<GameActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final utility = actions
        .where((action) =>
            action.visible && action.placement == GameActionPlacement.utility)
        .toList(growable: false);
    if (utility.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in utility)
          _IconActionButton(
            action: action,
            size: action.kind == GameActionKind.hint ? 50 : 54,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    this.compact = false,
  });

  final GameActionItem action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isPrimary = action.placement == GameActionPlacement.primary;
    return Tooltip(
      message: action.enabled ? action.label : action.disabledReason ?? action.label,
      child: FilledButton.icon(
        onPressed: action.enabled ? action.onPressed : null,
        icon: Icon(action.icon),
        label: Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(compact ? 46 : 54),
          backgroundColor: isPrimary
              ? const Color(0xFF2F8E2D)
              : const Color(0xFF2469AA),
          disabledBackgroundColor: const Color(0xFF7C827A),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isPrimary ? const Color(0xFFE8D889) : const Color(0xFFD2B56F),
              width: 1.4,
            ),
          ),
          textStyle: TextStyle(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.action,
    required this.size,
  });

  final GameActionItem action;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.enabled ? action.label : action.disabledReason ?? action.label,
      child: FilledButton(
        onPressed: action.enabled ? action.onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(size),
          backgroundColor: const Color(0xFF2469AA),
          disabledBackgroundColor: const Color(0xFF7C827A),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFD2B56F), width: 1.3),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Icon(action.icon, size: 24),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF7F0D5),
          foregroundColor: const Color(0xFF0C4380),
          disabledBackgroundColor: const Color(0xFFD8D0B7),
          disabledForegroundColor: const Color(0xFF6C6C6C),
          side: const BorderSide(color: Color(0xFFD2B56F), width: 1.4),
          minimumSize: const Size(54, 54),
        ),
      ),
    );
  }
}

class _TimerBadge extends StatelessWidget {
  const _TimerBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      width: 118,
      alignment: Alignment.center,
      decoration: _bluePanelDecoration(radius: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white, size: 21),
          const SizedBox(width: 6),
          Text(
            '${seconds.toString().padLeft(2, '0')}s',
            style: const TextStyle(
              color: Color(0xFFFFECA8),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBluePill extends StatelessWidget {
  const _SmallBluePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: _bluePanelDecoration(radius: 12),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFFFECA8),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DealerMark extends StatelessWidget {
  const _DealerMark({required this.team});

  final TeamSide team;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: team == TeamSide.a
            ? const Color(0xFFD09B3A)
            : const Color(0xFF4B8FD4),
        shape: BoxShape.circle,
      ),
      child: const Text(
        '庄',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TopDivider extends StatelessWidget {
  const _TopDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        '|',
        style: TextStyle(
          color: Color(0xFFFFECA8),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InkWashBackdrop extends StatelessWidget {
  const _InkWashBackdrop();

  static const _assetPath = 'assets/images/tianjin_table_background.png';

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_assetPath),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}

BoxDecoration _bluePanelDecoration({required double radius}) {
  return BoxDecoration(
    color: const Color(0xFF285789),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFFD2B56F), width: 1.3),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.18),
        blurRadius: 12,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

int _displaySeatIndex(int seatIndex, int selfSeat) {
  return (seatIndex - selfSeat + 6) % 6;
}

Alignment _seatAlignment(int seat) {
  return switch (seat) {
    0 => const Alignment(0, 0.90),
    1 => const Alignment(-0.92, 0.42),
    2 => const Alignment(-0.92, -0.42),
    3 => const Alignment(0, -0.84),
    4 => const Alignment(0.92, -0.42),
    5 => const Alignment(0.92, 0.42),
    _ => Alignment.center,
  };
}

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
