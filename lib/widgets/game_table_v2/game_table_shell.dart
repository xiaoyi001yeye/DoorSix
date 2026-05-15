import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/card_model.dart';
import '../../models/player_model.dart';
import '../../models/round_result.dart';
import '../../services/rule_engine.dart';
import '../../utils/card_display_settings.dart';
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
  bucketGrid,
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

const BucketGrid _debugBucketGrid = BucketGrid(columns: 100, rows: 100);
const double _handDockTopClearanceBuckets = 2.0;
const double _v2RegularHandCardHeight = 98.0;
const double _v2CompactHandCardHeight = 75.0;
const double _v2RegularHandSelectedLift = 18.0;
const double _v2CompactHandSelectedLift = 12.0;
const double _v2RemoteSeatScale = 0.5;

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
  bool _showBucketGrid = true;

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
              if (_showBucketGrid) const _BucketGridOverlay(),
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
        kind: GameActionKind.bucketGrid,
        label: _showBucketGrid ? '隐藏网格' : '显示网格',
        icon: _showBucketGrid ? Icons.grid_off : Icons.grid_on,
        placement: GameActionPlacement.topBar,
        enabled: true,
        visible: true,
        onPressed: _toggleBucketGrid,
      ),
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

  void _toggleBucketGrid() {
    setState(() {
      _showBucketGrid = !_showBucketGrid;
    });
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
    final capturedRects = <String, Rect>{};
    final entries = <_LayoutDebugEntry>[];

    for (final item in _debugKeys.entries) {
      final renderObject = item.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final offset = renderObject.localToGlobal(Offset.zero) - rootOrigin;
      capturedRects[item.key] = offset & renderObject.size;
    }

    for (final item in capturedRects.entries) {
      final parentName = _layoutDebugParentName(item.key, capturedRects);
      entries.add(
        _LayoutDebugEntry(
          name: item.key,
          rect: item.value,
          rootSize: rootSize,
          bucketGrid: _debugBucketGrid,
          parentName: parentName,
          parentRect: parentName == null ? null : capturedRects[parentName],
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

  String? _layoutDebugParentName(String name, Map<String, Rect> rects) {
    if (name != '中央出牌区' && !name.startsWith('座位')) {
      return null;
    }
    if (rects.containsKey('横屏/座位舞台')) {
      return '横屏/座位舞台';
    }
    if (rects.containsKey('竖屏/座位舞台')) {
      return '竖屏/座位舞台';
    }
    return null;
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
      'bucket grid: ${_debugBucketGrid.columns} x ${_debugBucketGrid.rows}',
      'captured: ${_formatTime(capturedAt)}',
      '',
    ];

    for (final entry in entries) {
      lines.add('[${entry.name}]');
      lines.add('bucket: ${entry.bucketSummary}');
      if (entry.parentBucketSummary != null) {
        lines.add('parent bucket: ${entry.parentBucketSummary}');
      }
      lines.add(
        'position: left ${entry.rect.left.toStringAsFixed(1)} '
        '(${_pct(entry.leftRatio)}), top '
        '${entry.rect.top.toStringAsFixed(1)} (${_pct(entry.topRatio)})',
      );
      lines.add(
        'size: ${entry.rect.width.toStringAsFixed(1)} x '
        '${entry.rect.height.toStringAsFixed(1)} '
        '(${_pct(entry.widthRatio)} x ${_pct(entry.heightRatio)})',
      );
      lines.add(
        'center: ${entry.rect.center.dx.toStringAsFixed(1)}, '
        '${entry.rect.center.dy.toStringAsFixed(1)}',
      );
      lines.add('raw: ${entry.summary}');
      lines.add('');
    }

    return lines.join('\n').trimRight();
  }
}

class _LayoutDebugEntry {
  const _LayoutDebugEntry({
    required this.name,
    required this.rect,
    required this.rootSize,
    required this.bucketGrid,
    required this.parentName,
    required this.parentRect,
  });

  final String name;
  final Rect rect;
  final Size rootSize;
  final BucketGrid bucketGrid;
  final String? parentName;
  final Rect? parentRect;

  double get widthRatio {
    return rootSize.width == 0 ? 0 : rect.width / rootSize.width;
  }

  double get heightRatio =>
      rootSize.height == 0 ? 0 : rect.height / rootSize.height;

  double get leftRatio => rootSize.width == 0 ? 0 : rect.left / rootSize.width;

  double get topRatio => rootSize.height == 0 ? 0 : rect.top / rootSize.height;

  double get bucketX => rootSize.width == 0
      ? 0
      : rect.left / rootSize.width * bucketGrid.columns;

  double get bucketY => rootSize.height == 0
      ? 0
      : rect.top / rootSize.height * bucketGrid.rows;

  double get bucketWidth => rootSize.width == 0
      ? 0
      : rect.width / rootSize.width * bucketGrid.columns;

  double get bucketHeight => rootSize.height == 0
      ? 0
      : rect.height / rootSize.height * bucketGrid.rows;

  String get bucketSummary {
    return 'grid ${bucketGrid.columns}x${bucketGrid.rows} | '
        'x=${_bucket(bucketX)}, y=${_bucket(bucketY)}, '
        'w=${_bucket(bucketWidth)}, h=${_bucket(bucketHeight)}';
  }

  String? get parentBucketSummary {
    final parent = parentRect;
    if (parent == null || parent.width == 0 || parent.height == 0) {
      return null;
    }
    final parentBucketX =
        (rect.left - parent.left) / parent.width * bucketGrid.columns;
    final parentBucketY =
        (rect.top - parent.top) / parent.height * bucketGrid.rows;
    final parentBucketWidth = rect.width / parent.width * bucketGrid.columns;
    final parentBucketHeight = rect.height / parent.height * bucketGrid.rows;
    return '$parentName grid ${bucketGrid.columns}x${bucketGrid.rows} | '
        'x=${_bucket(parentBucketX)}, y=${_bucket(parentBucketY)}, '
        'w=${_bucket(parentBucketWidth)}, '
        'h=${_bucket(parentBucketHeight)}';
  }

  String get summary {
    return [
      name,
      'bucket x=${_bucket(bucketX)}',
      'bucket y=${_bucket(bucketY)}',
      'bucket w=${_bucket(bucketWidth)}',
      'bucket h=${_bucket(bucketHeight)}',
      if (parentBucketSummary != null) 'parent bucket=$parentBucketSummary',
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
                        'bucket grid=${_debugBucketGrid.columns} x '
                            '${_debugBucketGrid.rows}',
                        'captured=${_formatTime(report.capturedAt)}',
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final entry in report.entries) ...[
                      _LayoutLogBlock(
                        title: entry.name,
                        lines: [
                          'bucket: ${entry.bucketSummary}',
                          if (entry.parentBucketSummary != null)
                            'parent bucket: ${entry.parentBucketSummary}',
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
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);
        final resolvedLayout = GameTableLayoutResolver.resolveLandscape(
          config: layoutConfig,
          parentSize: parentSize,
        );
        final compact = resolvedLayout.compact;
        final handDockRect = _handDockRectForCards(
          context: context,
          configuredRect: resolvedLayout.rectFor('hand_dock'),
          parentSize: parentSize,
          compact: compact,
        );

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
                  layoutConfig: layoutConfig,
                  forceCompact: compact,
                ),
              ),
            ),
            _PositionedLayer(
              rect: handDockRect,
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

  Rect _handDockRectForCards({
    required BuildContext context,
    required Rect configuredRect,
    required Size parentSize,
    required bool compact,
  }) {
    if (configuredRect.isEmpty ||
        !parentSize.height.isFinite ||
        parentSize.height <= 0) {
      return configuredRect;
    }

    final scale = CardDisplaySettingsScope.of(context).scale;
    final cardHeight =
        (compact ? _v2CompactHandCardHeight : _v2RegularHandCardHeight) *
            scale;
    final topClearance = parentSize.height /
        _debugBucketGrid.rows *
        _handDockTopClearanceBuckets;
    final height = cardHeight + topClearance;
    final bottom =
        configuredRect.bottom.clamp(0.0, parentSize.height).toDouble();
    final top = math.max(0.0, bottom - height);

    return Rect.fromLTWH(
      configuredRect.left,
      top,
      configuredRect.width,
      bottom - top,
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

class _BucketPositionedLayer extends StatelessWidget {
  const _BucketPositionedLayer({
    required this.parentSize,
    required this.bucketRect,
    required this.child,
  });

  final Size parentSize;
  final BucketRect bucketRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _PositionedLayer(
      rect: bucketRect.resolve(parentSize, _debugBucketGrid),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            _BucketPositionedLayer(
              parentSize: parentSize,
              bucketRect: const BucketRect(
                x: 2.0,
                y: 1.0,
                width: 96.0,
                height: 9.0,
              ),
              child: SizedBox.expand(
                key: debugKeyFor('竖屏/顶栏'),
                child: _GameTopBar(state: state, actions: actions),
              ),
            ),
            _BucketPositionedLayer(
              parentSize: parentSize,
              bucketRect: const BucketRect(
                x: 2.0,
                y: 10.8,
                width: 96.0,
                height: 58.0,
              ),
              child: SizedBox.expand(
                key: debugKeyFor('竖屏/座位舞台'),
                child: _SeatStage(state: state, debugKeyFor: debugKeyFor),
              ),
            ),
            _BucketPositionedLayer(
              parentSize: parentSize,
              bucketRect: const BucketRect(
                x: 2.0,
                y: 70.0,
                width: 96.0,
                height: 17.0,
              ),
              child: SizedBox.expand(
                key: debugKeyFor('竖屏/手牌区'),
                child: _HandDock(state: state),
              ),
            ),
            _BucketPositionedLayer(
              parentSize: parentSize,
              bucketRect: const BucketRect(
                x: 2.0,
                y: 88.2,
                width: 96.0,
                height: 10.2,
              ),
              child: SizedBox.expand(
                key: debugKeyFor('竖屏/底部操作栏'),
                child: _BottomActions(actions: actions),
              ),
            ),
          ],
        );
      },
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
        final compact =
            constraints.maxWidth < 700 || constraints.maxHeight < 78;
        final topActions = actions
            .where((action) =>
                action.visible &&
                action.placement == GameActionPlacement.topBar &&
                action.kind != GameActionKind.back)
            .toList(growable: false);
        final showActionCaptions = !compact;
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
              tone: _RoundButtonTone.blue,
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
            const SizedBox(width: 10),
            for (final action in topActions) ...[
              _RoundIconButton(
                tooltip: action.label,
                icon: action.icon,
                tone: _RoundButtonTone.light,
                caption: showActionCaptions ? action.label : null,
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
    this.layoutConfig,
    this.forceCompact = false,
  });

  final GameTableViewModel state;
  final _LayoutDebugKeyProvider debugKeyFor;
  final GameTableLayoutConfig? layoutConfig;
  final bool forceCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentSize = Size(constraints.maxWidth, constraints.maxHeight);
        final compact = layoutConfig != null
            ? forceCompact
            : forceCompact ||
                constraints.maxHeight < 170 ||
                constraints.maxWidth < 650;
        final layout = layoutConfig == null
            ? _SeatStageBucketLayout.forMode(compact)
            : _SeatStageBucketLayout.fromConfig(layoutConfig!, compact);
        final centerRect = layout.center.resolve(parentSize, _debugBucketGrid);
        final centerScale = compact
            ? math.min(centerRect.width / 196.0, centerRect.height / 48.0)
            : 1.0;
        final centerWidth = centerRect.width;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _BucketPositionedLayer(
              parentSize: parentSize,
              bucketRect: layout.center,
              child: SizedBox.expand(
                key: debugKeyFor('中央出牌区'),
                child: Center(
                  child: _CenterPlayPanel(
                    state: state,
                    width: centerWidth,
                    compact: compact,
                    compactScale: centerScale.clamp(0.55, 1.0).toDouble(),
                  ),
                ),
              ),
            ),
            for (final player in state.players)
              _BucketPlayerSeat(
                player: player,
                state: state,
                debugKeyFor: debugKeyFor,
                layout: layout,
                parentSize: parentSize,
                compact: compact,
              ),
          ],
        );
      },
    );
  }
}

class _BucketPlayerSeat extends StatelessWidget {
  const _BucketPlayerSeat({
    required this.player,
    required this.state,
    required this.debugKeyFor,
    required this.layout,
    required this.parentSize,
    required this.compact,
  });

  final GamePlayer player;
  final GameTableViewModel state;
  final _LayoutDebugKeyProvider debugKeyFor;
  final _SeatStageBucketLayout layout;
  final Size parentSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final displaySeat = _displaySeatIndex(player.seatIndex, state.selfSeat);
    final bucketRect = layout.bucketForDisplaySeat(displaySeat);
    if (bucketRect == null) {
      return const SizedBox.shrink();
    }
    final rect = bucketRect.resolve(parentSize, _debugBucketGrid);
    final compactScale = compact
        ? math
            .min(rect.width / 154.0, rect.height / 54.0)
            .clamp(0.55, 1.0)
            .toDouble()
        : 1.0;
    final seatScale = displaySeat == 0 ? 1.0 : _v2RemoteSeatScale;

    return _PositionedLayer(
      rect: rect,
      child: SizedBox.expand(
        key: debugKeyFor('座位${player.seatIndex}/显示$displaySeat'),
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Center(
            child: _PlayerSeatV2(
              player: player,
              isCurrent: state.currentSeat == player.seatIndex,
              isAlly: player.team == state.selfTeam,
              showPlayPointer:
                  !compact && state.lastPlayedSeat == player.seatIndex,
              countdownSeconds: null,
              compact: compact,
              compactScale: compactScale,
              sizeScale: seatScale,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatStageBucketLayout {
  const _SeatStageBucketLayout({
    required this.center,
    required this.seats,
  });

  factory _SeatStageBucketLayout.forMode(bool compact) {
    return compact ? compactLayout : regularLayout;
  }

  factory _SeatStageBucketLayout.fromConfig(
    GameTableLayoutConfig config,
    bool compact,
  ) {
    final fallback = _SeatStageBucketLayout.forMode(compact);
    BucketRect configuredRect(String id, BucketRect fallbackRect) {
      final layer = config.layers[id];
      if (layer == null) {
        return fallbackRect;
      }
      return compact ? layer.landscapeCompact : layer.landscapeRegular;
    }

    return _SeatStageBucketLayout(
      center: configuredRect('center_play_panel', fallback.center),
      seats: {
        for (final entry in fallback.seats.entries)
          entry.key: entry.value == null
              ? null
              : configuredRect('seat_display_${entry.key}', entry.value!),
      },
    );
  }

  static const regularLayout = _SeatStageBucketLayout(
    center: BucketRect(x: 25.0, y: 22.0, width: 50.0, height: 56.0),
    seats: {
      0: null,
      1: BucketRect(x: 0.0, y: 58.0, width: 16.0, height: 15.0),
      2: BucketRect(x: 0.0, y: 32.0, width: 16.0, height: 15.0),
      3: BucketRect(x: 34.0, y: 0.0, width: 16.0, height: 15.0),
      4: BucketRect(x: 78.0, y: 20.0, width: 16.0, height: 15.0),
      5: BucketRect(x: 78.0, y: 58.0, width: 16.0, height: 15.0),
    },
  );

  static const compactLayout = _SeatStageBucketLayout(
    center: BucketRect(x: 34.0, y: 76.0, width: 32.0, height: 24.0),
    seats: {
      0: null,
      1: BucketRect(x: 0.0, y: 76.0, width: 14.0, height: 12.0),
      2: BucketRect(x: 0.0, y: 12.0, width: 14.0, height: 12.0),
      3: BucketRect(x: 36.0, y: 0.0, width: 14.0, height: 12.0),
      4: BucketRect(x: 82.0, y: 0.0, width: 14.0, height: 12.0),
      5: BucketRect(x: 82.0, y: 76.0, width: 14.0, height: 12.0),
    },
  );

  final BucketRect center;
  final Map<int, BucketRect?> seats;

  BucketRect? bucketForDisplaySeat(int displaySeat) {
    final rect = seats[displaySeat];
    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      return null;
    }
    return rect;
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
            text: state.lastPlayedBy == null
                ? '等待首出'
                : '上手：${state.lastPlayedBy}',
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
    this.sizeScale = 1,
  });

  final GamePlayer player;
  final bool isCurrent;
  final bool isAlly;
  final bool showPlayPointer;
  final int? countdownSeconds;
  final bool compact;
  final double compactScale;
  final double sizeScale;

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
    final seat = Container(
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
    );
    final countdown = countdownSeconds;
    final showCountdown = countdown != null && isCurrent;

    final seatContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlayPointer)
          Icon(
            Icons.arrow_drop_down_rounded,
            color: const Color(0xFFD09B3A),
            size: compact ? 20 : 28,
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seat,
            if (showCountdown) ...[
              SizedBox(width: compact ? 5 : 8),
              _SmallBluePill(text: '${countdown}s'),
            ],
          ],
        ),
      ],
    );

    if (sizeScale == 1.0) {
      return seatContent;
    }

    return Transform.scale(
      scale: sizeScale,
      child: seatContent,
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
    final countdown = state.turnSecondsRemaining;
    final horizontalPadding = compact ? 14.0 : 18.0;
    final countdownReserve = countdown == null ? 0.0 : (compact ? 58.0 : 68.0);
    final statusTop = compact ? 10.0 : 14.0;
    return Container(
      clipBehavior: Clip.hardEdge,
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
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding + countdownReserve,
                0,
              ),
              child: _V2HandScroller(
                cards: state.hand,
                onToggle: state.onToggleCard,
                compact: compact,
              ),
            ),
          ),
          if (showStatus)
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              top: statusTop,
              child: Row(
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
            ),
          if (countdown != null)
            Positioned(
              right: horizontalPadding,
              top: 0,
              bottom: 0,
              child: Center(
                child: _SmallBluePill(text: '${countdown}s'),
              ),
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
      return const Center(
        child: Text(
          '手牌已出完',
          style: TextStyle(color: Color(0xFF6D6B61)),
        ),
      );
    }

    final scale = CardDisplaySettingsScope.of(context).scale;
    final cardWidth = (compact ? 52.0 : 68.0) * scale;
    final cardHeight = (compact ? 75.0 : 98.0) * scale;
    final selectedLift = (compact ? 12.0 : 18.0) * scale;
    final minStep = (compact ? 24.0 : 30.0) * scale;
    final preferredStep = (compact ? 36.0 : 48.0) * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : cardWidth + preferredStep * (cards.length - 1);
        final availableHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : cardHeight + selectedLift;
        final cardBottom = availableHeight;
        final normalTop = cardBottom - cardHeight;
        final fittedSelectedLift = math.min(
          selectedLift,
          math.max(0, normalTop),
        );
        final selectedTop = normalTop - fittedSelectedLift;
        final fittedStep = cards.length <= 1
            ? preferredStep
            : (availableWidth - cardWidth) / (cards.length - 1);
        final step = math.max(minStep, math.min(preferredStep, fittedStep));
        final stackWidth = math.max(
          availableWidth,
          cardWidth + step * (cards.length - 1),
        );

        Widget positionedCard(int index) {
          final card = cards[index];
          return AnimatedPositioned(
            key: ValueKey(card.id),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            left: index * step,
            top: card.selected ? selectedTop : normalTop,
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

        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: stackWidth,
              height: availableHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var index = 0; index < cards.length; index += 1)
                    if (!cards[index].selected) positionedCard(index),
                  for (var index = 0; index < cards.length; index += 1)
                    if (cards[index].selected) positionedCard(index),
                ],
              ),
            ),
          ),
        );
      },
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
          action.kind == GameActionKind.hint
              ? _HintActionButton(action: action)
              : _IconActionButton(action: action, size: 54),
      ],
    );
  }
}

class _HintButtonAtlas {
  const _HintButtonAtlas._();

  static const assetPath = 'assets/images/table_skin/hint_button_atlas.png';
  static const _spriteSize = Size(386, 156);
  static const _stateCenters = [
    Offset(218, 291),
    Offset(626, 291),
    Offset(1034, 291),
    Offset(218, 629),
    Offset(626, 629),
  ];

  static Rect sourceRect(int stateIndex) {
    final center = _stateCenters[stateIndex];
    return Rect.fromCenter(
      center: center,
      width: _spriteSize.width,
      height: _spriteSize.height,
    );
  }
}

class _HintActionButton extends StatefulWidget {
  const _HintActionButton({required this.action});

  final GameActionItem action;

  @override
  State<_HintActionButton> createState() => _HintActionButtonState();
}

class _HintActionButtonState extends State<_HintActionButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final enabled = action.enabled && action.onPressed != null;
    final stateIndex = !enabled
        ? 2
        : _pressed
            ? 1
            : _hovered
                ? 3
                : 0;
    final foregroundColor = enabled ? Colors.white : Colors.white70;

    return Tooltip(
      message: enabled ? action.label : action.disabledReason ?? action.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: action.label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
          onExit: enabled ? (_) => setState(() => _hovered = false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? action.onPressed : null,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              scale: _pressed ? 0.97 : 1,
              child: SizedBox(
                width: 77,
                height: 29,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: _AtlasSpriteImage(
                        assetPath: _HintButtonAtlas.assetPath,
                        sourceRect: _HintButtonAtlas.sourceRect(stateIndex),
                      ),
                    ),
                    if (!enabled)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                    Center(
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        color: foregroundColor,
                        size: 18,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (_hovered && enabled)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD35E)
                                  .withValues(alpha: 0.22),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

enum _RoundButtonTone {
  blue,
  light,
}

class _RoundButtonAtlas {
  const _RoundButtonAtlas._();

  static const assetPath =
      'assets/images/table_skin/function_round_buttons_atlas.png';
  static const _spriteSize = 238.0;
  static const _centerX = [170.0, 483.0, 796.0, 1109.0];
  static const _centerY = [210.0, 586.0];

  static Rect sourceRect({
    required _RoundButtonTone tone,
    required int stateIndex,
  }) {
    final row = tone == _RoundButtonTone.blue ? 0 : 1;
    final center = Offset(_centerX[stateIndex], _centerY[row]);
    return Rect.fromCenter(
      center: center,
      width: _spriteSize,
      height: _spriteSize,
    );
  }
}

class _AtlasSpriteImage extends StatefulWidget {
  const _AtlasSpriteImage({
    required this.assetPath,
    required this.sourceRect,
  });

  final String assetPath;
  final Rect sourceRect;

  @override
  State<_AtlasSpriteImage> createState() => _AtlasSpriteImageState();
}

class _AtlasSpriteImageState extends State<_AtlasSpriteImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(_AtlasSpriteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath != oldWidget.assetPath) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    final listener = _imageStreamListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    super.dispose();
  }

  void _resolveImage() {
    final oldListener = _imageStreamListener;
    if (oldListener != null) {
      _imageStream?.removeListener(oldListener);
    }

    final imageProvider = AssetImage(widget.assetPath);
    final stream = imageProvider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((imageInfo, synchronousCall) {
      if (!mounted) {
        return;
      }
      if (synchronousCall) {
        _image = imageInfo.image;
        return;
      }
      setState(() {
        _image = imageInfo.image;
      });
    });

    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      painter: _AtlasSpritePainter(
        image: image,
        sourceRect: widget.sourceRect,
      ),
      size: Size.infinite,
    );
  }
}

class _AtlasSpritePainter extends CustomPainter {
  const _AtlasSpritePainter({
    required this.image,
    required this.sourceRect,
  });

  final ui.Image image;
  final Rect sourceRect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      sourceRect,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_AtlasSpritePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.sourceRect != sourceRect;
  }
}

class _RoundIconButton extends StatefulWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tone = _RoundButtonTone.light,
    this.caption,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final _RoundButtonTone tone;
  final String? caption;

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  static const _buttonSize = 54.0;

  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final stateIndex = !enabled
        ? 2
        : _pressed
            ? 1
            : _hovered
                ? 3
                : 0;
    final iconColor = _iconColor(enabled);
    final iconSize = widget.tone == _RoundButtonTone.blue ? 30.0 : 28.0;
    final button = Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
          onExit: enabled ? (_) => setState(() => _hovered = false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? widget.onPressed : null,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              scale: _pressed ? 0.96 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: enabled ? 0.18 : 0.08,
                      ),
                      blurRadius: _pressed ? 5 : 10,
                      offset: Offset(0, _pressed ? 2 : 5),
                    ),
                    if (_hovered && enabled)
                      BoxShadow(
                        color: const Color(0xFFFFD35E).withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AtlasSpriteImage(
                        assetPath: _RoundButtonAtlas.assetPath,
                        sourceRect: _RoundButtonAtlas.sourceRect(
                          tone: widget.tone,
                          stateIndex: stateIndex,
                        ),
                      ),
                      if (!enabled)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      Center(
                        child: Icon(
                          widget.icon,
                          color: iconColor,
                          size: iconSize,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final caption = widget.caption;
    if (caption == null) {
      return button;
    }

    return SizedBox(
      width: 62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0C4380),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Color _iconColor(bool enabled) {
    if (!enabled) {
      return widget.tone == _RoundButtonTone.blue
          ? Colors.white70
          : const Color(0xFF6D7683);
    }
    return widget.tone == _RoundButtonTone.blue
        ? Colors.white
        : const Color(0xFF0C4380);
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

class _BucketGridOverlay extends StatelessWidget {
  const _BucketGridOverlay();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        painter: _BucketGridPainter(grid: _debugBucketGrid),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _BucketGridPainter extends CustomPainter {
  const _BucketGridPainter({required this.grid});

  final BucketGrid grid;

  static const _lineColor = Color(0x8FD6D6D6);
  static const _majorLineColor = Color(0xCC2E7D32);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final minorPaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 0.65
      ..style = PaintingStyle.stroke;
    final majorPaint = Paint()
      ..color = _majorLineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final bucketWidth = size.width / grid.columns;
    final bucketHeight = size.height / grid.rows;

    for (var column = 0; column <= grid.columns; column += 1) {
      final x = column * bucketWidth;
      _drawDashedLine(
        canvas,
        Offset(x, 0),
        Offset(x, size.height),
        column % 10 == 0 ? majorPaint : minorPaint,
      );
    }

    for (var row = 0; row <= grid.rows; row += 1) {
      final y = row * bucketHeight;
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        row % 10 == 0 ? majorPaint : minorPaint,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const dashLength = 4.0;
    const gapLength = 4.0;
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) {
      return;
    }
    final direction = delta / distance;
    var current = 0.0;
    while (current < distance) {
      final dashEnd = math.min(current + dashLength, distance);
      canvas.drawLine(
        start + direction * current,
        start + direction * dashEnd,
        paint,
      );
      current += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _BucketGridPainter oldDelegate) {
    return oldDelegate.grid.columns != grid.columns ||
        oldDelegate.grid.rows != grid.rows;
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

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _bucket(double value) => value.toStringAsFixed(1);

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
