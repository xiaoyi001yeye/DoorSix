import 'dart:math';

import '../models/card_model.dart';

enum ComboKind {
  invalid,
  single,
  pair,
  triple,
  bomb,
  jokerPair,
}

class CardCombo {
  const CardCombo({
    required this.kind,
    required this.rankStrength,
    required this.cards,
  });

  final ComboKind kind;
  final int rankStrength;
  final List<CardInstance> cards;

  bool get isValid => kind != ComboKind.invalid;

  String get label {
    if (!isValid) {
      return '牌型不成立';
    }

    final first = cards.first.rank.label;
    return switch (kind) {
      ComboKind.invalid => '牌型不成立',
      ComboKind.single => '单张 $first',
      ComboKind.pair => '对子 $first',
      ComboKind.triple => '三张 $first',
      ComboKind.bomb => '炸弹 $first',
      ComboKind.jokerPair => '王炸',
    };
  }
}

class RuleEngine {
  const RuleEngine();

  List<CardInstance> createDecks({int deckCount = 2}) {
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
    int deckCount = 2,
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

    final uniqueRanks = selected.map((card) => card.rank).toSet();
    final onlyJokers = selected.every((card) => card.suit == CardSuit.joker);

    if (selected.length == 2 && onlyJokers) {
      return CardCombo(
        kind: ComboKind.jokerPair,
        rankStrength: 99,
        cards: selected,
      );
    }

    if (uniqueRanks.length != 1) {
      return CardCombo(
        kind: ComboKind.invalid,
        rankStrength: 0,
        cards: selected,
      );
    }

    final rank = selected.first.rank.strength;
    final kind = switch (selected.length) {
      1 => ComboKind.single,
      2 => ComboKind.pair,
      3 => ComboKind.triple,
      >= 4 => ComboKind.bomb,
      _ => ComboKind.invalid,
    };

    return CardCombo(kind: kind, rankStrength: rank, cards: selected);
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

    if (candidate.kind == ComboKind.jokerPair) {
      return target.kind != ComboKind.jokerPair;
    }

    if (candidate.kind == ComboKind.bomb && target.kind != ComboKind.bomb) {
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
    final groups = <CardRank, List<CardInstance>>{};
    for (final card in sortCards(hand)) {
      groups.putIfAbsent(card.rank, () => []).add(card);
    }

    final candidates = <List<CardInstance>>[];
    for (final group in groups.values) {
      for (var size = 1; size <= min(group.length, 4); size += 1) {
        candidates.add(group.take(size).toList());
      }
    }

    final jokers = hand.where((card) => card.suit == CardSuit.joker).toList();
    if (jokers.length >= 2) {
      candidates.add(jokers.take(2).toList());
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
}
