// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import 'position.dart';

/// Whether a score is exact or only a bound (UCI `lowerbound`/`upperbound`).
enum ScoreBound {
  /// The score is exact.
  exact,

  /// The real score is at least this value (fail high).
  lowerBound,

  /// The real score is at most this value (fail low).
  upperBound,
}

/// An evaluation as reported by the engine, from the point of view of the
/// side to move.
///
/// Either a [CentipawnScore] or a [MateScore]:
///
/// ```dart
/// switch (info.score) {
///   case CentipawnScore(:final centipawns): print('$centipawns cp');
///   case MateScore(:final moves): print('mate in $moves');
///   case null: break;
/// }
/// ```
@immutable
sealed class Score implements Comparable<Score> {
  const Score({this.bound = ScoreBound.exact});

  /// Whether this is an exact score or a bound.
  final ScoreBound bound;

  /// The same score seen from the other side.
  Score get negated;

  /// The score from White's point of view, given the [sideToMove] it was
  /// reported for.
  Score fromWhitePerspective(Side sideToMove) =>
      sideToMove == Side.white ? this : negated;

  /// A number that orders scores from worst to best for the side to move:
  /// getting mated < centipawns < delivering mate.
  int get _rank;

  @override
  int compareTo(Score other) => _rank.compareTo(other._rank);

  /// Parses the part after `score` in an info line, e.g. `cp 23`,
  /// `mate -3` or `cp 15 lowerbound`. Returns null if malformed.
  static Score? tryParse(String kind, String value, [String? bound]) {
    final v = int.tryParse(value);
    if (v == null) return null;
    final b = switch (bound) {
      'lowerbound' => ScoreBound.lowerBound,
      'upperbound' => ScoreBound.upperBound,
      _ => ScoreBound.exact,
    };
    return switch (kind) {
      'cp' => CentipawnScore(v, bound: b),
      'mate' => MateScore(v, bound: b),
      _ => null,
    };
  }
}

/// A score in centipawns.
///
/// Stockfish normalises centipawns to its win-rate model: +100 means a 50%
/// chance of winning from this position, not "one pawn of material".
/// Tablebase results are reported as ±(20000 − plies to conversion).
final class CentipawnScore extends Score {
  /// Creates a score.
  const CentipawnScore(this.centipawns, {super.bound});

  /// The value in (normalised) centipawns.
  final int centipawns;

  static const _tbValue = 20000;
  static const _maxPly = 246;

  /// Whether this is a tablebase win (cp ≥ 20000 − 246).
  bool get isTablebaseWin => centipawns >= _tbValue - _maxPly;

  /// Whether this is a tablebase loss.
  bool get isTablebaseLoss => centipawns <= -(_tbValue - _maxPly);

  /// Plies to the tablebase result, for tablebase scores.
  int? get tablebasePlies => isTablebaseWin
      ? _tbValue - centipawns
      : isTablebaseLoss
      ? _tbValue + centipawns
      : null;

  /// The value in pawns.
  double get pawns => centipawns / 100;

  @override
  CentipawnScore get negated =>
      CentipawnScore(-centipawns, bound: _flip(bound));

  @override
  int get _rank => centipawns;

  @override
  bool operator ==(Object other) =>
      other is CentipawnScore &&
      other.centipawns == centipawns &&
      other.bound == bound;

  @override
  int get hashCode => Object.hash(centipawns, bound);

  @override
  String toString() =>
      'cp $centipawns${bound == ScoreBound.exact ? '' : ' ${bound.name}'}';
}

/// A forced mate.
final class MateScore extends Score {
  /// Creates a score.
  const MateScore(this.moves, {super.bound});

  /// Moves (not plies) until mate: positive when the side to move mates,
  /// negative when it gets mated, 0 when it is already checkmated.
  final int moves;

  /// Whether the side to move delivers the mate.
  bool get isWinning => moves > 0;

  @override
  MateScore get negated => MateScore(-moves, bound: _flip(bound));

  // Mate in 1 ranks highest, getting mated now ranks lowest.
  @override
  int get _rank => moves > 0 ? 1000000 - moves : -1000000 - moves;

  @override
  bool operator ==(Object other) =>
      other is MateScore && other.moves == moves && other.bound == bound;

  @override
  int get hashCode => Object.hash(moves, bound);

  @override
  String toString() =>
      'mate $moves${bound == ScoreBound.exact ? '' : ' ${bound.name}'}';
}

ScoreBound _flip(ScoreBound b) => switch (b) {
  ScoreBound.exact => ScoreBound.exact,
  ScoreBound.lowerBound => ScoreBound.upperBound,
  ScoreBound.upperBound => ScoreBound.lowerBound,
};

/// Win/draw/loss probabilities in per mille (UCI `wdl`, enabled with the
/// `UCI_ShowWDL` option), from the point of view of the side to move.
@immutable
final class Wdl {
  /// Creates a WDL triple.
  const Wdl(this.win, this.draw, this.loss);

  /// Chance of winning, per mille.
  final int win;

  /// Chance of a draw, per mille.
  final int draw;

  /// Chance of losing, per mille.
  final int loss;

  /// Expected game score between 0 and 1 (win = 1, draw = ½).
  double get expectedScore => (win + draw / 2) / 1000;

  /// The same probabilities from White's point of view.
  Wdl fromWhitePerspective(Side sideToMove) =>
      sideToMove == Side.white ? this : Wdl(loss, draw, win);

  @override
  bool operator ==(Object other) =>
      other is Wdl &&
      other.win == win &&
      other.draw == draw &&
      other.loss == loss;

  @override
  int get hashCode => Object.hash(win, draw, loss);

  @override
  String toString() => 'wdl $win $draw $loss';
}
