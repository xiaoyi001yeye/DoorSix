import 'package:flutter/material.dart';

import '../models/player_avatar.dart';

class PlayerAvatarBadge extends StatelessWidget {
  const PlayerAvatarBadge({
    required this.avatarId,
    this.size = 32,
    this.showRing = true,
    super.key,
  });

  final String avatarId;
  final double size;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final preset = PlayerAvatarPreset.byId(avatarId);
    return Tooltip(
      message: preset.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: preset.background,
          shape: BoxShape.circle,
          border: showRing
              ? Border.all(
                  color: preset.foreground.withValues(alpha: 0.82),
                  width: 1.4,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: preset.foreground.withValues(alpha: 0.16),
              blurRadius: 10,
            ),
          ],
        ),
        child: Icon(
          preset.icon,
          size: size * 0.58,
          color: preset.foreground,
        ),
      ),
    );
  }
}

class PlayerAvatarSelector extends StatelessWidget {
  const PlayerAvatarSelector({
    required this.selectedAvatarId,
    required this.onSelected,
    super.key,
  });

  final String selectedAvatarId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in PlayerAvatarPreset.presets)
          _AvatarChoice(
            preset: preset,
            selected: preset.id == selectedAvatarId,
            onTap: () => onSelected(preset.id),
          ),
      ],
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PlayerAvatarPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: preset.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? preset.foreground.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? preset.foreground
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatarBadge(
                avatarId: preset.id,
                size: 34,
                showRing: selected,
              ),
              const SizedBox(height: 6),
              Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? preset.foreground : Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
