import 'card_model.dart';
import 'player_model.dart';
import 'round_result.dart';
import '../services/rule_engine.dart';

class OnlineSession {
  const OnlineSession({
    required this.room,
    required this.self,
    required this.playerToken,
    required this.webSocketUrl,
  });

  final OnlineRoom room;
  final OnlineSeat self;
  final String playerToken;
  final String webSocketUrl;

  factory OnlineSession.fromJson(Map<String, dynamic> json) {
    return OnlineSession(
      room: OnlineRoom.fromJson(json['room'] as Map<String, dynamic>),
      self: OnlineSeat.fromJson(json['self'] as Map<String, dynamic>),
      playerToken: json['playerToken'] as String,
      webSocketUrl: json['webSocketUrl'] as String,
    );
  }
}

class OnlineRoom {
  const OnlineRoom({
    required this.roomId,
    required this.roomCode,
    required this.ownerPlayerId,
    required this.status,
    required this.playerCount,
    required this.maxPlayers,
  });

  final String roomId;
  final String roomCode;
  final String ownerPlayerId;
  final String status;
  final int playerCount;
  final int maxPlayers;

  factory OnlineRoom.fromJson(Map<String, dynamic> json) {
    return OnlineRoom(
      roomId: json['roomId'] as String,
      roomCode: json['roomCode'] as String,
      ownerPlayerId: json['ownerPlayerId'] as String,
      status: json['status'] as String,
      playerCount: json['playerCount'] as int,
      maxPlayers: json['maxPlayers'] as int,
    );
  }
}

class OnlineSeat {
  const OnlineSeat({
    required this.seatIndex,
    required this.playerId,
    required this.nickname,
    required this.team,
    required this.isAi,
    required this.ready,
    required this.connected,
    required this.cardCount,
    this.finishRank,
  });

  final int seatIndex;
  final String playerId;
  final String nickname;
  final TeamSide team;
  final bool isAi;
  final bool ready;
  final bool connected;
  final int cardCount;
  final int? finishRank;

  factory OnlineSeat.fromJson(Map<String, dynamic> json) {
    return OnlineSeat(
      seatIndex: json['seatIndex'] as int,
      playerId: json['playerId'] as String,
      nickname: json['nickname'] as String,
      team: (json['team'] as String) == 'A' ? TeamSide.a : TeamSide.b,
      isAi: json['isAi'] as bool? ?? false,
      ready: json['ready'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      cardCount: json['cardCount'] as int? ?? 0,
      finishRank: json['finishRank'] as int?,
    );
  }

  GamePlayer toGamePlayer(String selfPlayerId) {
    final status = finishRank == null
        ? PlayerStatus.waiting
        : PlayerStatus.finished;
    return GamePlayer(
      id: playerId,
      name: isAi ? nickname : (playerId == selfPlayerId ? '我' : nickname),
      team: team,
      seatIndex: seatIndex,
      cardCount: cardCount,
      isUser: playerId == selfPlayerId,
      status: status,
      finishRank: finishRank,
    );
  }
}

class OnlineTableSnapshot {
  const OnlineTableSnapshot({
    required this.roomId,
    required this.gameId,
    required this.roundNo,
    required this.status,
    required this.ownerPlayerId,
    required this.currentTurnSeatIndex,
    required this.lastPlayedSeatIndex,
    required this.passCount,
    required this.tableCombo,
    required this.seats,
    required this.finishOrder,
    required this.score,
    required this.myHand,
    required this.eventSeq,
    required this.actionHistory,
    this.turnStartedAt,
    this.turnDeadlineAt,
    this.serverTime,
  });

  final String roomId;
  final String? gameId;
  final int roundNo;
  final String status;
  final String ownerPlayerId;
  final int? currentTurnSeatIndex;
  final int? lastPlayedSeatIndex;
  final int passCount;
  final CardCombo? tableCombo;
  final List<OnlineSeat?> seats;
  final List<FinishedSeat> finishOrder;
  final OnlineScore score;
  final List<CardInstance> myHand;
  final int eventSeq;
  final List<OnlineActionHistoryEntry> actionHistory;
  final int? turnStartedAt;
  final int? turnDeadlineAt;
  final int? serverTime;

  factory OnlineTableSnapshot.fromJson(Map<String, dynamic> json) {
    final table = json['tableState'] as Map<String, dynamic>;
    final seatsJson = table['seats'] as List<dynamic>? ?? const [];
    final finishJson = table['finishOrder'] as List<dynamic>? ?? const [];
    final historyJson = table['actionHistory'] as List<dynamic>? ?? const [];
    return OnlineTableSnapshot(
      roomId: table['roomId'] as String,
      gameId: table['gameId'] as String?,
      roundNo: table['roundNo'] as int? ?? 0,
      status: table['status'] as String,
      ownerPlayerId: table['ownerPlayerId'] as String,
      currentTurnSeatIndex: table['currentTurnSeatIndex'] as int?,
      lastPlayedSeatIndex: table['lastPlayedSeatIndex'] as int?,
      passCount: table['passCount'] as int? ?? 0,
      tableCombo: _comboFromJson(table['tableCombo']),
      seats: seatsJson.map((seat) {
        if (seat == null) {
          return null;
        }
        return OnlineSeat.fromJson(seat as Map<String, dynamic>);
      }).toList(),
      finishOrder: finishJson.map((item) {
        final data = item as Map<String, dynamic>;
        final team = (data['team'] as String) == 'A' ? TeamSide.a : TeamSide.b;
        return FinishedSeat(
          playerId: data['playerId'] as String,
          playerName: data['nickname'] as String? ?? data['playerId'] as String,
          team: team,
          rank: data['rank'] as int,
        );
      }).toList(),
      score: OnlineScore.fromJson(table['score'] as Map<String, dynamic>?),
      myHand: (json['myHand'] as List<dynamic>? ?? const [])
          .map((card) => _cardFromJson(card as Map<String, dynamic>))
          .toList(),
      eventSeq: json['eventSeq'] as int? ?? 0,
      actionHistory: historyJson
          .map((item) => OnlineActionHistoryEntry.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(growable: false),
      turnStartedAt: table['turnStartedAt'] as int?,
      turnDeadlineAt: table['turnDeadlineAt'] as int?,
      serverTime: json['serverTime'] as int?,
    );
  }
}

enum OnlineActionType {
  play,
  pass,
  newLead,
}

enum OnlineActionSource {
  player,
  ai,
  timeout,
}

class OnlineActionHistoryEntry {
  const OnlineActionHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.actionType,
    required this.source,
    required this.seatIndex,
    required this.playerId,
    required this.playerName,
    required this.team,
    required this.cards,
    this.comboLabel,
    this.finishRank,
  });

  final String id;
  final int createdAt;
  final OnlineActionType actionType;
  final OnlineActionSource source;
  final int seatIndex;
  final String playerId;
  final String playerName;
  final TeamSide team;
  final List<CardInstance> cards;
  final String? comboLabel;
  final int? finishRank;

  factory OnlineActionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OnlineActionHistoryEntry(
      id: json['id'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
      actionType: _actionTypeFromJson(json['actionType'] as String?),
      source: _actionSourceFromJson(json['source'] as String?),
      seatIndex: json['seatIndex'] as int? ?? 0,
      playerId: json['playerId'] as String? ?? '',
      playerName: (json['nickname'] as String?) ??
          (json['playerId'] as String?) ??
          '',
      team: (json['team'] as String?) == 'A' ? TeamSide.a : TeamSide.b,
      cards: (json['cards'] as List<dynamic>? ?? const [])
          .map((card) => _cardFromJson(card as Map<String, dynamic>))
          .toList(growable: false),
      comboLabel: json['comboLabel'] as String?,
      finishRank: json['finishRank'] as int?,
    );
  }
}

class OnlineScore {
  const OnlineScore({required this.teamA, required this.teamB});

  final int teamA;
  final int teamB;

  factory OnlineScore.fromJson(Map<String, dynamic>? json) {
    return OnlineScore(
      teamA: json?['teamA'] as int? ?? 0,
      teamB: json?['teamB'] as int? ?? 0,
    );
  }
}

OnlineActionType _actionTypeFromJson(String? value) {
  return switch (value) {
    'pass' => OnlineActionType.pass,
    'new_lead' => OnlineActionType.newLead,
    _ => OnlineActionType.play,
  };
}

OnlineActionSource _actionSourceFromJson(String? value) {
  return switch (value) {
    'ai' => OnlineActionSource.ai,
    'timeout' => OnlineActionSource.timeout,
    _ => OnlineActionSource.player,
  };
}

CardInstance _cardFromJson(Map<String, dynamic> json) {
  return CardInstance(
    id: json['cardId'] as String,
    deckIndex: json['deckIndex'] as int? ?? 0,
    suit: _suitFromBackend(json['suit'] as String),
    rank: _rankFromBackend(json['rank'] as String),
  );
}

CardSuit _suitFromBackend(String value) {
  return switch (value) {
    'spades' => CardSuit.spades,
    'hearts' => CardSuit.hearts,
    'diamonds' => CardSuit.diamonds,
    'clubs' => CardSuit.clubs,
    'joker' => CardSuit.joker,
    _ => CardSuit.joker,
  };
}

CardRank _rankFromBackend(String value) {
  return switch (value) {
    '3' => CardRank.three,
    '4' => CardRank.four,
    '5' => CardRank.five,
    '6' => CardRank.six,
    '7' => CardRank.seven,
    '8' => CardRank.eight,
    '9' => CardRank.nine,
    '10' => CardRank.ten,
    'J' => CardRank.jack,
    'Q' => CardRank.queen,
    'K' => CardRank.king,
    'A' => CardRank.ace,
    '2' => CardRank.two,
    'small_joker' => CardRank.smallJoker,
    'big_joker' => CardRank.bigJoker,
    _ => CardRank.three,
  };
}

CardCombo? _comboFromJson(dynamic json) {
  if (json == null) {
    return null;
  }
  final data = json as Map<String, dynamic>;
  final kind = switch (data['comboType'] as String?) {
    'single' => ComboKind.single,
    'pair' => ComboKind.pair,
    'triple' => ComboKind.triple,
    'quad' => ComboKind.quad,
    _ => ComboKind.invalid,
  };
  final strength = data['rankStrength'] as int? ?? 0;
  final cards = (data['cardIds'] as List<dynamic>? ?? const [])
      .map((cardId) => _cardFromId(cardId as String))
      .whereType<CardInstance>()
      .toList(growable: false);
  return CardCombo(
    kind: kind,
    rankStrength: strength,
    cards: cards,
    effectiveRank: _rankFromStrength(strength),
  );
}

CardInstance? _cardFromId(String id) {
  final parts = id.split('-');
  if (parts.length < 3 || !parts.first.startsWith('d')) {
    return null;
  }
  final deckIndex = int.tryParse(parts.first.substring(1)) ?? 0;
  if (parts[1] == 'small' && parts.length >= 3 && parts[2] == 'joker') {
    return CardInstance(
      id: id,
      deckIndex: deckIndex,
      suit: CardSuit.joker,
      rank: CardRank.smallJoker,
    );
  }
  if (parts[1] == 'big' && parts.length >= 3 && parts[2] == 'joker') {
    return CardInstance(
      id: id,
      deckIndex: deckIndex,
      suit: CardSuit.joker,
      rank: CardRank.bigJoker,
    );
  }
  return CardInstance(
    id: id,
    deckIndex: deckIndex,
    suit: _suitFromBackend(parts[1]),
    rank: _rankFromBackend(parts[2]),
  );
}

CardRank? _rankFromStrength(int strength) {
  for (final rank in CardRank.values) {
    if (rank.strength == strength) {
      return rank;
    }
  }
  return null;
}
