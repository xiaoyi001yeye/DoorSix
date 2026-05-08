import 'package:flutter/material.dart';
import 'package:playing_cards/playing_cards.dart' as pc;

import '../models/card_model.dart';
import '../utils/app_theme.dart';
import '../utils/card_display_settings.dart';

class HandCard extends StatelessWidget {
  const HandCard({
    required this.card,
    required this.onTap,
    this.compact = false,
    this.showSelectionOffset = true,
    this.width,
    this.height,
    this.trailingMargin,
    super.key,
  });

  final CardInstance card;
  final VoidCallback onTap;
  final bool compact;
  final bool showSelectionOffset;
  final double? width;
  final double? height;
  final double? trailingMargin;

  @override
  Widget build(BuildContext context) {
    final metrics = CardDisplaySettingsScope.of(context).metrics;
    final cardWidth = width ?? (compact ? metrics.compactWidth : metrics.width);
    final cardHeight =
        height ?? (compact ? metrics.compactHeight : metrics.height);
    const cardRadius = 5.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: cardWidth,
        height: cardHeight,
        margin: EdgeInsets.only(
          right: trailingMargin ?? (compact ? 4 : 6) * metrics.scale,
          top: showSelectionOffset && !card.selected ? 14 * metrics.scale : 0,
          bottom:
              showSelectionOffset && card.selected ? 14 * metrics.scale : 0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: [
            if (card.selected)
              BoxShadow(
                color: AppTheme.teamGold.withValues(alpha: 0.35),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        child: pc.PlayingCardView(
          card: _toPlayingCard(card),
          elevation: card.selected ? 5 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
            side: BorderSide(
              color: card.selected ? AppTheme.teamGold : Colors.black26,
              width: card.selected ? 1.5 : 0.7,
            ),
          ),
        ),
      ),
    );
  }

  pc.PlayingCard _toPlayingCard(CardInstance card) {
    return pc.PlayingCard(_toSuit(card.suit), _toValue(card.rank));
  }

  pc.Suit _toSuit(CardSuit suit) {
    return switch (suit) {
      CardSuit.spades => pc.Suit.spades,
      CardSuit.hearts => pc.Suit.hearts,
      CardSuit.diamonds => pc.Suit.diamonds,
      CardSuit.clubs => pc.Suit.clubs,
      CardSuit.joker => pc.Suit.joker,
    };
  }

  pc.CardValue _toValue(CardRank rank) {
    return switch (rank) {
      CardRank.three => pc.CardValue.three,
      CardRank.four => pc.CardValue.four,
      CardRank.five => pc.CardValue.five,
      CardRank.six => pc.CardValue.six,
      CardRank.seven => pc.CardValue.seven,
      CardRank.eight => pc.CardValue.eight,
      CardRank.nine => pc.CardValue.nine,
      CardRank.ten => pc.CardValue.ten,
      CardRank.jack => pc.CardValue.jack,
      CardRank.queen => pc.CardValue.queen,
      CardRank.king => pc.CardValue.king,
      CardRank.ace => pc.CardValue.ace,
      CardRank.two => pc.CardValue.two,
      CardRank.smallJoker => pc.CardValue.joker_1,
      CardRank.bigJoker => pc.CardValue.joker_2,
    };
  }
}
