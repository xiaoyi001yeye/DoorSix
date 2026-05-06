enum CardSuit {
  spades,
  hearts,
  diamonds,
  clubs,
  joker,
}

enum CardRank {
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
  ace,
  two,
  smallJoker,
  bigJoker,
}

class CardInstance {
  const CardInstance({
    required this.id,
    required this.deckIndex,
    required this.suit,
    required this.rank,
    this.selected = false,
  });

  final String id;
  final int deckIndex;
  final CardSuit suit;
  final CardRank rank;
  final bool selected;

  CardInstance copyWith({bool? selected}) {
    return CardInstance(
      id: id,
      deckIndex: deckIndex,
      suit: suit,
      rank: rank,
      selected: selected ?? this.selected,
    );
  }
}

extension CardRankPresentation on CardRank {
  int get strength {
    return switch (this) {
      CardRank.three => 3,
      CardRank.four => 4,
      CardRank.five => 5,
      CardRank.six => 6,
      CardRank.seven => 7,
      CardRank.eight => 8,
      CardRank.nine => 9,
      CardRank.ten => 10,
      CardRank.jack => 11,
      CardRank.queen => 12,
      CardRank.king => 13,
      CardRank.ace => 14,
      CardRank.two => 16,
      CardRank.smallJoker => 18,
      CardRank.bigJoker => 19,
    };
  }

  String get label {
    return switch (this) {
      CardRank.three => '3',
      CardRank.four => '4',
      CardRank.five => '5',
      CardRank.six => '6',
      CardRank.seven => '7',
      CardRank.eight => '8',
      CardRank.nine => '9',
      CardRank.ten => '10',
      CardRank.jack => 'J',
      CardRank.queen => 'Q',
      CardRank.king => 'K',
      CardRank.ace => 'A',
      CardRank.two => '2',
      CardRank.smallJoker => '小王',
      CardRank.bigJoker => '大王',
    };
  }
}

extension CardSuitPresentation on CardSuit {
  String get label {
    return switch (this) {
      CardSuit.spades => '黑桃',
      CardSuit.hearts => '红桃',
      CardSuit.diamonds => '方片',
      CardSuit.clubs => '梅花',
      CardSuit.joker => '王',
    };
  }

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;
}
