import 'dart:math' as math;

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
          _StackedHandScroller(
            cards: cards,
            onToggle: onToggle,
          ),
        ],
      ),
    );
  }
}

class _StackedHandScroller extends StatelessWidget {
  const _StackedHandScroller({
    required this.cards,
    required this.onToggle,
  });

  final List<CardInstance> cards;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox(
        height: 92,
        child: Center(
          child: Text(
            '手牌已出完',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    const cardWidth = 52.0;
    const cardHeight = 76.0;
    const selectedLift = 18.0;
    const minStep = 24.0;
    const preferredStep = 36.0;

    return SizedBox(
      height: cardHeight + selectedLift,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : cardWidth + preferredStep * (cards.length - 1);
          final fittedStep = cards.length <= 1
              ? preferredStep
              : (available - cardWidth) / (cards.length - 1);
          final step = math.max(minStep, math.min(preferredStep, fittedStep));
          final stackWidth = math.max(
            available,
            cardWidth + step * (cards.length - 1),
          );
          Widget positionedCard(int index) {
            final card = cards[index];
            return AnimatedPositioned(
              key: ValueKey(card.id),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              left: index * step,
              top: card.selected ? 0 : selectedLift,
              child: HandCard(
                card: card,
                onTap: () => onToggle(card.id),
                width: cardWidth,
                height: cardHeight,
                trailingMargin: 0,
                showSelectionOffset: false,
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: stackWidth,
              height: cardHeight + selectedLift,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var index = 0; index < cards.length; index += 1)
                    if (!cards[index].selected) positionedCard(index),
                  for (var index = 0; index < cards.length; index += 1)
                    if (cards[index].selected) positionedCard(index),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
