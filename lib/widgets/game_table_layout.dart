import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/player_model.dart';
import '../models/round_result.dart';
import '../utils/app_theme.dart';
import 'player_seat.dart';

typedef TableCenterBuilder = Widget Function(
  BuildContext context,
  double width,
);

class GameTableLayout extends StatelessWidget {
  const GameTableLayout({
    required this.players,
    required this.currentSeat,
    required this.selfTeam,
    required this.centerBuilder,
    this.finishOrder = const [],
    this.countdownSecondsForSeat,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 14),
    super.key,
  });

  final List<GamePlayer> players;
  final int? currentSeat;
  final TeamSide selfTeam;
  final TableCenterBuilder centerBuilder;
  final List<FinishedSeat> finishOrder;
  final int? Function(int seatIndex)? countdownSecondsForSeat;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = math.min(360.0, constraints.maxWidth * 0.62);
          final tableHeight = math.max(170.0, tableWidth * 0.58);
          final centerWidth = math.min(
            330.0,
            math.max(260.0, constraints.maxWidth * 0.42),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: tableWidth,
                  height: tableHeight,
                  child: const TableMat(),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: centerBuilder(context, centerWidth),
              ),
              for (var seat = 0; seat < players.length; seat += 1)
                Align(
                  alignment: seatAlignment(seat),
                  child: PlayerSeat(
                    player: players[seat],
                    isCurrent: currentSeat == seat,
                    isAlly: players[seat].team == selfTeam,
                    countdownSeconds: countdownSecondsForSeat?.call(seat),
                  ),
                ),
              Align(
                alignment: const Alignment(0, 0.62),
                child: FinishOrderBar(finishOrder: finishOrder),
              ),
            ],
          );
        },
      ),
    );
  }
}

Alignment seatAlignment(int seat) {
  return switch (seat) {
    0 => const Alignment(0, 0.9),
    1 => const Alignment(-0.96, 0.5),
    2 => const Alignment(-0.96, -0.5),
    3 => const Alignment(0, -0.9),
    4 => const Alignment(0.96, -0.5),
    5 => const Alignment(0.96, 0.5),
    _ => Alignment.center,
  };
}

class TableMat extends StatelessWidget {
  const TableMat({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(96),
        gradient: const RadialGradient(
          center: Alignment(0, -0.18),
          radius: 0.9,
          colors: [
            Color(0xFF1F8A68),
            AppTheme.tableGreen,
            Color(0xFF0D4037),
          ],
          stops: [0, 0.58, 1],
        ),
        border: Border.all(color: const Color(0x8859D68B), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppTheme.success.withValues(alpha: 0.14),
            blurRadius: 22,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(82),
            border: Border.all(color: const Color(0x3379D98B), width: 1),
          ),
          child: Align(
            alignment: const Alignment(0, -0.08),
            child: FractionallySizedBox(
              widthFactor: 0.54,
              heightFactor: 0.18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinishOrderBar extends StatelessWidget {
  const FinishOrderBar({required this.finishOrder, super.key});

  final List<FinishedSeat> finishOrder;

  @override
  Widget build(BuildContext context) {
    if (finishOrder.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
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
