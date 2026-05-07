import 'package:flutter/material.dart';

import '../services/server_log_store.dart';
import '../utils/app_theme.dart';

void showServerLogSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _ServerLogSheet(),
  );
}

class _ServerLogSheet extends StatelessWidget {
  const _ServerLogSheet();

  @override
  Widget build(BuildContext context) {
    final store = ServerLogStore.instance;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded),
                  const SizedBox(width: 8),
                  Text(
                    '服务器通信日志',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: store.clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AnimatedBuilder(
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
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _ServerLogTile(entry: entries[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerLogTile extends StatelessWidget {
  const _ServerLogTile({required this.entry});

  final ServerLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      ServerLogLevel.info => AppTheme.teamCyan,
      ServerLogLevel.success => AppTheme.success,
      ServerLogLevel.warning => AppTheme.teamGold,
      ServerLogLevel.error => AppTheme.danger,
    };
    final icon = switch (entry.level) {
      ServerLogLevel.info => Icons.swap_horiz_rounded,
      ServerLogLevel.success => Icons.check_circle_outline_rounded,
      ServerLogLevel.warning => Icons.error_outline_rounded,
      ServerLogLevel.error => Icons.cancel_outlined,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
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
                  const SizedBox(height: 4),
                  Text(
                    _timeLabel(entry.createdAt),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
