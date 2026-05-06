import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/rule_set.dart';
import '../utils/app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
                        const SizedBox(height: 6),
                        Text(
                          '天津六人两队扑克',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '设置',
                    onPressed: () => _showComingSoon(context, '设置'),
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
                      onPressed: () => _showComingSoon(context, '创建房间'),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('创建房间'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, '加入房间'),
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

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 会在牌桌原型稳定后补上')),
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
