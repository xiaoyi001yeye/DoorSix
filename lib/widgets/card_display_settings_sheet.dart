import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/card_display_settings.dart';
import '../utils/player_profile_settings.dart';
import 'player_avatar_badge.dart';

void showCardDisplaySettingsSheet(
  BuildContext context, {
  VoidCallback? onCheckUpdates,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) {
      return _CardDisplaySettingsSheet(onCheckUpdates: onCheckUpdates);
    },
  );
}

class _CardDisplaySettingsSheet extends StatelessWidget {
  const _CardDisplaySettingsSheet({this.onCheckUpdates});

  final VoidCallback? onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final settings = CardDisplaySettingsScope.of(context);
    final profile = PlayerProfileSettingsScope.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 44;

    return AnimatedBuilder(
      animation: Listenable.merge([settings, profile]),
      builder: (context, _) {
        final metrics = settings.metrics;
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.style_rounded, color: AppTheme.teamGold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '配置',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    Text(
                      '${metrics.percent}%',
                      style: const TextStyle(
                        color: AppTheme.teamGold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '牌面大小',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${metrics.width.toStringAsFixed(0)} x '
                      '${metrics.height.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Slider(
                  min: CardDisplaySettings.minScale,
                  max: CardDisplaySettings.maxScale,
                  value: settings.scale,
                  label: '${metrics.percent}%',
                  onChanged: settings.setScale,
                ),
                const Row(
                  children: [
                    Text(
                      '100%',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Spacer(),
                    Text(
                      '150%',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  '字体大小',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<FontSizePreset>(
                    segments: [
                      for (final preset in FontSizePreset.values)
                        ButtonSegment(
                          value: preset,
                          label: Text(preset.label),
                        ),
                    ],
                    selected: {settings.fontSizePreset},
                    onSelectionChanged: (selection) {
                      settings.setFontSizePreset(selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '头像',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                PlayerAvatarSelector(
                  selectedAvatarId: profile.avatarPresetId,
                  onSelected: profile.setAvatarPresetId,
                ),
                if (onCheckUpdates != null) ...[
                  const SizedBox(height: 22),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCheckUpdates?.call();
                      },
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('检查新版本'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
