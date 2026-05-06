import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/player_model.dart';
import '../utils/app_theme.dart';

class PlayerSeat extends StatelessWidget {
  const PlayerSeat({
    required this.player,
    required this.isCurrent,
    required this.isAlly,
    super.key,
  });

  final GamePlayer player;
  final bool isCurrent;
  final bool isAlly;

  @override
  Widget build(BuildContext context) {
    final borderColor = isAlly ? AppTheme.teamCyan : AppTheme.teamGold;
    final content = Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppTheme.success : borderColor.withValues(alpha: 0.75),
          width: isCurrent ? 2 : 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TeamDot(team: player.team),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  player.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            player.finishRank == null
                ? '余牌 ${player.cardCount}'
                : '第 ${player.finishRank} 名',
            style: TextStyle(
              color: player.finishRank == null
                  ? AppTheme.textSecondary
                  : AppTheme.success,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (player.status == PlayerStatus.passed) ...[
            const SizedBox(height: 4),
            const Text(
              '过',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );

    if (!isCurrent) {
      return content;
    }

    return content
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.04, 1.04),
          duration: 700.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _TeamDot extends StatelessWidget {
  const _TeamDot({required this.team});

  final TeamSide team;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: team == TeamSide.a ? AppTheme.teamGold : AppTheme.teamCyan,
        shape: BoxShape.circle,
      ),
    );
  }
}
