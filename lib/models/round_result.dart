import 'player_model.dart';

class FinishedSeat {
  const FinishedSeat({
    required this.playerId,
    required this.playerName,
    required this.team,
    required this.rank,
  });

  final String playerId;
  final String playerName;
  final TeamSide team;
  final int rank;
}

class RoundResult {
  const RoundResult({
    required this.winner,
    required this.finishOrder,
    required this.caughtPlayers,
    required this.teamAScoreDelta,
    required this.teamBScoreDelta,
  });

  final TeamSide winner;
  final List<FinishedSeat> finishOrder;
  final List<String> caughtPlayers;
  final int teamAScoreDelta;
  final int teamBScoreDelta;
}
