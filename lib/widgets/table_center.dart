import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/card_model.dart';
import '../services/rule_engine.dart';
import '../utils/app_theme.dart';
import 'hand_card.dart';

class TableCenter extends StatelessWidget {
  const TableCenter({
    required this.activeCombo,
    required this.lastPlayedBy,
    required this.currentPlayer,
    required this.passCount,
    this.playedCards = const [],
    super.key,
  });

  final CardCombo? activeCombo;
  final String? lastPlayedBy;
  final String currentPlayer;
  final int passCount;
  final List<CardInstance> playedCards;

  @override
  Widget build(BuildContext context) {
    final comboText = activeCombo == null ? '新一轮，可任意出牌' : activeCombo!.label;
    final byText = lastPlayedBy == null ? '等待首出' : '上手：$lastPlayedBy';

    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.tableDark,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x5579D98B)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Text(
              comboText,
              key: ValueKey(comboText),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.12, end: 0),
          ),
          const SizedBox(height: 8),
          if (activeCombo != null && playedCards.isNotEmpty) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SizedBox(
                key: ValueKey(playedCards.map((card) => card.id).join(',')),
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final card in playedCards)
                      HandCard(
                        card: card.copyWith(selected: false),
                        compact: true,
                        showSelectionOffset: false,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            byText,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前轮到：$currentPlayer',
            style: const TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (passCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '连续过牌 $passCount',
              style: const TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
