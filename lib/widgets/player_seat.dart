import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/player_model.dart';
import '../utils/app_theme.dart';

class PlayerSeat extends StatelessWidget {
  const PlayerSeat({
    required this.player,
    required this.isCurrent,
    required this.isAlly,
    this.countdownSeconds,
    super.key,
  });

  final GamePlayer player;
  final bool isCurrent;
  final bool isAlly;
  final int? countdownSeconds;

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
          color: isCurrent
              ? AppTheme.success
              : borderColor.withValues(alpha: 0.75),
          width: isCurrent ? 2 : 1.2,
        ),
        boxShadow: [
          if (isCurrent)
            BoxShadow(
              color: AppTheme.success.withValues(alpha: 0.24),
              blurRadius: 18,
              spreadRadius: 1,
            ),
        ],
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

    final seat = isCurrent && countdownSeconds != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TurnCountdownPill(seconds: countdownSeconds!),
              const SizedBox(height: 5),
              content,
            ],
          )
        : content;

    if (!isCurrent) {
      return seat;
    }

    return seat
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.04, 1.04),
          duration: 700.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _TurnCountdownPill extends StatelessWidget {
  const _TurnCountdownPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.tableDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.teamGold.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.teamGold.withValues(alpha: 0.18),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 13,
            color: AppTheme.teamCyan,
          ),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: const TextStyle(
              color: AppTheme.teamGold,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
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
