enum TeamSide {
  a,
  b,
}

enum PlayerStatus {
  waiting,
  thinking,
  passed,
  finished,
  caught,
}

class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.name,
    required this.team,
    required this.seatIndex,
    required this.cardCount,
    required this.isUser,
    this.status = PlayerStatus.waiting,
    this.finishRank,
  });

  final String id;
  final String name;
  final TeamSide team;
  final int seatIndex;
  final int cardCount;
  final bool isUser;
  final PlayerStatus status;
  final int? finishRank;

  GamePlayer copyWith({
    int? cardCount,
    PlayerStatus? status,
    int? finishRank,
  }) {
    return GamePlayer(
      id: id,
      name: name,
      team: team,
      seatIndex: seatIndex,
      cardCount: cardCount ?? this.cardCount,
      isUser: isUser,
      status: status ?? this.status,
      finishRank: finishRank ?? this.finishRank,
    );
  }
}

extension TeamSidePresentation on TeamSide {
  String get label => this == TeamSide.a ? 'A队' : 'B队';
}

extension PlayerStatusPresentation on PlayerStatus {
  String get label {
    return switch (this) {
      PlayerStatus.waiting => '等待',
      PlayerStatus.thinking => '出牌中',
      PlayerStatus.passed => '过',
      PlayerStatus.finished => '已出完',
      PlayerStatus.caught => '被逮',
    };
  }
}
