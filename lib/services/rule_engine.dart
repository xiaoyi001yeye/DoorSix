import 'dart:math';

import '../models/card_model.dart';

enum ComboKind {
  invalid,
  single,
  pair,
  triple,
  quad,
}

class CardCombo {
  const CardCombo({
    required this.kind,
    required this.rankStrength,
    required this.cards,
    this.effectiveRank,
  });

  final ComboKind kind;
  final int rankStrength;
  final List<CardInstance> cards;
  final CardRank? effectiveRank;

  bool get isValid => kind != ComboKind.invalid;

  String get label {
    if (!isValid) {
      return '牌型不成立';
    }

    final first = effectiveRank?.label ?? cards.first.rank.label;
    return switch (kind) {
      ComboKind.invalid => '牌型不成立',
      ComboKind.single => '单张 $first',
      ComboKind.pair => '对子 $first',
      ComboKind.triple => '三张 $first',
      ComboKind.quad => '四张 $first',
    };
  }
}

class RuleEngine {
  const RuleEngine();

  List<CardInstance> createDecks({int deckCount = 1}) {
    final cards = <CardInstance>[];
    for (var deckIndex = 0; deckIndex < deckCount; deckIndex += 1) {
      for (final suit in [
        CardSuit.spades,
        CardSuit.hearts,
        CardSuit.diamonds,
        CardSuit.clubs,
      ]) {
        for (final rank in [
          CardRank.three,
          CardRank.four,
          CardRank.five,
          CardRank.six,
          CardRank.seven,
          CardRank.eight,
          CardRank.nine,
          CardRank.ten,
          CardRank.jack,
          CardRank.queen,
          CardRank.king,
          CardRank.ace,
          CardRank.two,
        ]) {
          cards.add(CardInstance(
            id: 'd$deckIndex-${suit.name}-${rank.name}',
            deckIndex: deckIndex,
            suit: suit,
            rank: rank,
          ));
        }
      }

      cards.add(CardInstance(
        id: 'd$deckIndex-small-joker',
        deckIndex: deckIndex,
        suit: CardSuit.joker,
        rank: CardRank.smallJoker,
      ));
      cards.add(CardInstance(
        id: 'd$deckIndex-big-joker',
        deckIndex: deckIndex,
        suit: CardSuit.joker,
        rank: CardRank.bigJoker,
      ));
    }
    return cards;
  }

  List<List<CardInstance>> dealHands({
    int deckCount = 1,
    int playerCount = 6,
    Random? random,
  }) {
    final deck = createDecks(deckCount: deckCount).toList();
    deck.shuffle(random ?? Random());

    final hands = List.generate(playerCount, (_) => <CardInstance>[]);
    for (var i = 0; i < deck.length; i += 1) {
      hands[i % playerCount].add(deck[i]);
    }
    return hands.map(sortCards).toList();
  }

  List<CardInstance> sortCards(List<CardInstance> cards) {
    final sorted = cards.toList();
    sorted.sort((a, b) {
      final rankCompare = a.rank.strength.compareTo(b.rank.strength);
      if (rankCompare != 0) {
        return rankCompare;
      }
      final suitCompare = a.suit.index.compareTo(b.suit.index);
      if (suitCompare != 0) {
        return suitCompare;
      }
      return a.deckIndex.compareTo(b.deckIndex);
    });
    return sorted;
  }

  CardCombo evaluate(List<CardInstance> cards) {
    final selected = cards.toList();
    if (selected.isEmpty) {
      return const CardCombo(
        kind: ComboKind.invalid,
        rankStrength: 0,
        cards: [],
      );
    }

    final effectiveRank = _effectiveRankFor(selected);
    if (effectiveRank == null) {
      return CardCombo(
        kind: ComboKind.invalid,
        rankStrength: 0,
        cards: selected,
      );
    }

    final kind = switch (selected.length) {
      1 => ComboKind.single,
      2 => ComboKind.pair,
      3 => ComboKind.triple,
      4 => ComboKind.quad,
      _ => ComboKind.invalid,
    };

    return CardCombo(
      kind: kind,
      rankStrength: effectiveRank.strength,
      cards: selected,
      effectiveRank: effectiveRank,
    );
  }

  CardRank? _effectiveRankFor(List<CardInstance> cards) {
    if (cards.length == 1) {
      return cards.first.rank;
    }

    final naturalRanks = cards
        .where((card) => !card.rank.isWild)
        .map((card) => card.rank)
        .toSet();
    if (naturalRanks.length > 1) {
      return null;
    }
    if (naturalRanks.length == 1) {
      return naturalRanks.first;
    }

    return CardRank.three;
  }

  bool canPlay({
    required CardCombo candidate,
    required CardCombo? target,
  }) {
    if (!candidate.isValid) {
      return false;
    }

    if (target == null || !target.isValid) {
      return true;
    }

    if (candidate.kind != target.kind) {
      return false;
    }

    if (candidate.cards.length != target.cards.length) {
      return false;
    }

    return candidate.rankStrength > target.rankStrength;
  }

  List<CardInstance> suggest(List<CardInstance> hand, CardCombo? target) {
    final candidates = <List<CardInstance>>[];
    final sortedHand = sortCards(hand);
    for (var size = 1; size <= min(sortedHand.length, 4); size += 1) {
      candidates.addAll(_combinations(sortedHand, size));
    }

    candidates.sort((a, b) {
      final comboA = evaluate(a);
      final comboB = evaluate(b);
      final kindCompare = comboA.kind.index.compareTo(comboB.kind.index);
      if (kindCompare != 0) {
        return kindCompare;
      }
      return comboA.rankStrength.compareTo(comboB.rankStrength);
    });

    for (final cards in candidates) {
      final combo = evaluate(cards);
      if (canPlay(candidate: combo, target: target)) {
        return cards;
      }
    }

    return [];
  }

  List<List<CardInstance>> _combinations(List<CardInstance> cards, int size) {
    final result = <List<CardInstance>>[];

    void collect(int start, List<CardInstance> current) {
      if (current.length == size) {
        result.add(current.toList());
        return;
      }

      for (var i = start; i < cards.length; i += 1) {
        current.add(cards[i]);
        collect(i + 1, current);
        current.removeLast();
      }
    }

    collect(0, []);
    return result;
  }
}
