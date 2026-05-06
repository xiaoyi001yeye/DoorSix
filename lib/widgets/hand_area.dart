import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../services/rule_engine.dart';
import '../utils/app_theme.dart';
import 'hand_card.dart';

class HandArea extends StatelessWidget {
  const HandArea({
    required this.cards,
    required this.combo,
    required this.canPlay,
    required this.onToggle,
    super.key,
  });

  final List<CardInstance> cards;
  final CardCombo combo;
  final bool canPlay;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final selectedCount = cards.where((card) => card.selected).length;
    final status = selectedCount == 0
        ? '请选择要出的牌'
        : combo.isValid
            ? '${combo.label}${canPlay ? '，可以出' : '，压不过上家'}'
            : combo.label;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(top: BorderSide(color: Color(0x22333333))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的手牌 ${cards.length}',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selectedCount == 0
                        ? AppTheme.textSecondary
                        : canPlay
                            ? AppTheme.success
                            : AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              itemBuilder: (context, index) {
                final card = cards[index];
                return HandCard(
                  card: card,
                  onTap: () => onToggle(card.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
