import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/rule_set.dart';
import '../services/online_table_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_update_gate.dart';
import '../widgets/card_display_settings_sheet.dart';
import '../widgets/server_log_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DoorSixBackendClient _backend = DoorSixBackendClient();

  ServerHealthSnapshot _serverHealth = ServerHealthSnapshot(
    status: ServerHealthStatus.checking,
    checkedAt: DateTime.now(),
  );
  bool _checkingServer = false;

  @override
  void initState() {
    super.initState();
    _checkingServer = true;
    unawaited(_loadServerHealth());
  }

  @override
  void dispose() {
    _backend.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '砸六家',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ],
                    ),
                  ),
                  _ServerTrafficLight(
                    snapshot: _serverHealth,
                    checking: _checkingServer,
                    onRefresh: _checkServer,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '服务器日志',
                    onPressed: () => showServerLogSheet(context),
                    icon: const Icon(Icons.terminal_rounded),
                  ),
                  IconButton(
                    tooltip: '设置',
                    onPressed: () => showCardDisplaySettingsSheet(
                      context,
                      onCheckUpdates: () => AppUpdateScope.of(context).checkNow(
                        manual: true,
                        ignoreDismissal: true,
                        source: 'manual',
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _HeroTablePreview(
                onTap: () => context.push('/table', extra: RuleSet.tianjin),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/rules'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('快速开始'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/table', extra: RuleSet.tianjin),
                      icon: const Icon(Icons.psychology_alt_outlined),
                      label: const Text('练习桌'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/online/create'),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('创建房间'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/online/join'),
                icon: const Icon(Icons.login_rounded),
                label: const Text('加入房间'),
              ),
              const Spacer(),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/rules'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('规则说明'),
                  ),
                  const Spacer(),
                  const _RulePill(label: '当前：天津通用'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkServer() async {
    if (_checkingServer) {
      return;
    }
    setState(() {
      _checkingServer = true;
      _serverHealth = ServerHealthSnapshot(
        status: ServerHealthStatus.checking,
        checkedAt: _serverHealth.checkedAt,
      );
    });
    await _loadServerHealth();
  }

  Future<void> _loadServerHealth() async {
    final health = await _backend.health();
    if (!mounted) {
      return;
    }
    setState(() {
      _serverHealth = health;
      _checkingServer = false;
    });
  }
}

class _ServerTrafficLight extends StatelessWidget {
  const _ServerTrafficLight({
    required this.snapshot,
    required this.checking,
    required this.onRefresh,
  });

  final ServerHealthSnapshot snapshot;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final label = switch (snapshot.status) {
      ServerHealthStatus.available => '服务器可用',
      ServerHealthStatus.busy => '服务器忙',
      ServerHealthStatus.down => '服务器死了',
      ServerHealthStatus.checking => '检测中',
    };
    final activeColor = switch (snapshot.status) {
      ServerHealthStatus.available => AppTheme.success,
      ServerHealthStatus.busy => AppTheme.teamGold,
      ServerHealthStatus.down => AppTheme.danger,
      ServerHealthStatus.checking => AppTheme.teamGold,
    };

    return Tooltip(
      message: '$label，点击刷新',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: checking ? null : onRefresh,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: activeColor.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LightDot(
                  color: AppTheme.danger,
                  active: snapshot.status == ServerHealthStatus.down,
                ),
                const SizedBox(width: 4),
                _LightDot(
                  color: AppTheme.teamGold,
                  active: snapshot.status == ServerHealthStatus.busy ||
                      snapshot.status == ServerHealthStatus.checking,
                ),
                const SizedBox(width: 4),
                _LightDot(
                  color: AppTheme.success,
                  active: snapshot.status == ServerHealthStatus.available,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LightDot extends StatelessWidget {
  const _LightDot({
    required this.color,
    required this.active,
  });

  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: active ? color : color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        boxShadow: [
          if (active)
            BoxShadow(
              color: color.withValues(alpha: 0.42),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
    );
  }
}

class _HeroTablePreview extends StatelessWidget {
  const _HeroTablePreview({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppTheme.tableDark,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x334CC9F0)),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 180,
                height: 112,
                decoration: BoxDecoration(
                  color: AppTheme.tableGreen,
                  borderRadius: BorderRadius.circular(56),
                  border: Border.all(color: const Color(0x6679D98B)),
                ),
                child: const Center(
                  child: Text(
                    '6 人牌桌',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            for (final seat in _previewSeats)
              Align(
                alignment: seat.alignment,
                child: _PreviewSeat(label: seat.label, isAlly: seat.isAlly),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSeatData {
  const _PreviewSeatData(this.alignment, this.label, this.isAlly);

  final Alignment alignment;
  final String label;
  final bool isAlly;
}

const _previewSeats = [
  _PreviewSeatData(Alignment(0, 0.86), '我', true),
  _PreviewSeatData(Alignment(-0.74, 0.44), 'A1', false),
  _PreviewSeatData(Alignment(-0.74, -0.44), 'B1', true),
  _PreviewSeatData(Alignment(0, -0.86), 'A2', false),
  _PreviewSeatData(Alignment(0.74, -0.44), 'B2', true),
  _PreviewSeatData(Alignment(0.74, 0.44), 'A3', false),
];

class _PreviewSeat extends StatelessWidget {
  const _PreviewSeat({required this.label, required this.isAlly});

  final String label;
  final bool isAlly;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAlly ? AppTheme.teamCyan : AppTheme.teamGold,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RulePill extends StatelessWidget {
  const _RulePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
