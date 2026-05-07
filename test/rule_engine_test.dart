import 'dart:convert';
import 'dart:io';

import 'package:door_six/models/card_model.dart';
import 'package:door_six/models/rule_set.dart';
import 'package:door_six/services/rule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = RuleEngine();

  test('天津通用 preset follows the canonical basic rule shape', () {
    expect(RuleSet.tianjin.deckCount, 1);
    expect(RuleSet.tianjin.enableWildCards, isTrue);

    final hands = engine.dealHands(deckCount: RuleSet.tianjin.deckCount);

    expect(hands, hasLength(6));
    expect(hands.every((hand) => hand.length == 9), isTrue);
  });

  test('canonical rank order puts 3 above 2 and jokers above 3', () {
    expect(CardRank.three.strength, greaterThan(CardRank.two.strength));
    expect(CardRank.smallJoker.strength, greaterThan(CardRank.three.strength));
    expect(
      CardRank.bigJoker.strength,
      greaterThan(CardRank.smallJoker.strength),
    );
  });

  test('wild cards can complete pairs but do not change single-card rank', () {
    final pairSix = engine.evaluate([
      _card(CardSuit.hearts, CardRank.smallJoker),
      _card(CardSuit.clubs, CardRank.six),
    ]);
    final pairFive = engine.evaluate([
      _card(CardSuit.hearts, CardRank.five),
      _card(CardSuit.clubs, CardRank.five),
    ]);
    final singleSmallJoker = engine.evaluate([
      _card(CardSuit.hearts, CardRank.smallJoker),
    ]);

    expect(pairSix.kind, ComboKind.pair);
    expect(pairSix.effectiveRank, CardRank.six);
    expect(engine.canPlay(candidate: pairSix, target: pairFive), isTrue);
    expect(singleSmallJoker.effectiveRank, CardRank.smallJoker);
  });

  test('quad cannot beat a different combo kind', () {
    final quadFour = engine.evaluate([
      _card(CardSuit.spades, CardRank.four),
      _card(CardSuit.hearts, CardRank.four),
      _card(CardSuit.diamonds, CardRank.four),
      _card(CardSuit.clubs, CardRank.four),
    ]);
    final tripleAce = engine.evaluate([
      _card(CardSuit.spades, CardRank.ace),
      _card(CardSuit.hearts, CardRank.ace),
      _card(CardSuit.diamonds, CardRank.ace),
    ]);

    expect(quadFour.kind, ComboKind.quad);
    expect(engine.canPlay(candidate: quadFour, target: tripleAce), isFalse);
  });

  test('canonical JSON records the same non-ambiguous rule facts', () {
    final file = File('assets/config/rules/zha_liujia_tianjin_basic_v1.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    expect(data['id'], 'zha_liujia_tianjin_basic_v1');
    expect(data['canonicalForProject'], isTrue);
    expect(data['deck'], containsPair('standardDeckCount', 1));
    expect(data['deck'], containsPair('cardsPerPlayer', 9));
    expect(
      data['comparison'],
      containsPair('crossKindBeatingAllowed', false),
    );
    expect(
      (data['comparison'] as Map<String, dynamic>)['rankOrderHighToLow'],
      [
        'big_joker',
        'small_joker',
        '3',
        '2',
        'A',
        'K',
        'Q',
        'J',
        '10',
        '9',
        '8',
        '7',
        '6',
        '5',
        '4',
      ],
    );
  });
}

CardInstance _card(CardSuit suit, CardRank rank) {
  return CardInstance(
    id: '${suit.name}-${rank.name}',
    deckIndex: 0,
    suit: suit,
    rank: rank,
  );
}
