// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import 'score.dart';
import 'uci_move.dart';

/// One `info` line with search progress (depth, score, principal variation).
@immutable
final class SearchInfo {
  /// Creates an info record.
  const SearchInfo({
    required this.raw,
    this.depth,
    this.selDepth,
    this.multiPv,
    this.score,
    this.wdl,
    this.nodes,
    this.nps,
    this.hashFull,
    this.tbHits,
    this.time,
    this.pv = const [],
    this.extra = const {},
  });

  /// Search depth in plies (`depth`).
  final int? depth;

  /// Selective search depth (`seldepth`).
  final int? selDepth;

  /// Index of this line when `MultiPV` > 1 (1 = best line).
  final int? multiPv;

  /// Evaluation for the side to move.
  final Score? score;

  /// Win/draw/loss probabilities; only reported with `UCI_ShowWDL`.
  final Wdl? wdl;

  /// Nodes searched so far.
  final int? nodes;

  /// Nodes per second.
  final int? nps;

  /// Transposition table usage in per mille.
  final int? hashFull;

  /// Tablebase hits.
  final int? tbHits;

  /// Time searched so far.
  final Duration? time;

  /// Principal variation, starting with the best move.
  final List<UciMove> pv;

  /// Fields this parser does not know about (forward compatibility).
  final Map<String, String> extra;

  /// The original line.
  final String raw;

  /// The first move of the principal variation, if any.
  UciMove? get bestMove => pv.isEmpty ? null : pv.first;

  @override
  String toString() => raw;
}

/// An `info depth … currmove … currmovenumber …` line: the root move being
/// searched. Stockfish only reports these after about 3 seconds of search.
@immutable
final class CurrentMoveInfo {
  /// Creates the record.
  const CurrentMoveInfo({
    required this.depth,
    required this.move,
    required this.moveNumber,
    required this.raw,
  });

  /// Current depth.
  final int depth;

  /// The root move being searched.
  final UciMove move;

  /// 1-based index of [move] in the engine's move ordering.
  final int moveNumber;

  /// The original line.
  final String raw;

  @override
  String toString() => raw;
}

/// Why a position has no legal moves.
enum TerminalState {
  /// The side to move is checkmated.
  checkmate,

  /// The side to move is stalemated.
  stalemate,
}

/// The outcome of a search: the `bestmove` line plus the final info lines.
@immutable
final class SearchResult {
  /// Creates a result.
  const SearchResult({
    required this.bestMove,
    required this.ponderMove,
    required this.lines,
    required this.elapsed,
    required this.wasStopped,
    this.terminal,
  });

  /// The move the engine chose; null when the position has no legal moves
  /// (`bestmove (none)`), see [terminal].
  final UciMove? bestMove;

  /// The reply the engine expects, to ponder on.
  final UciMove? ponderMove;

  /// The last complete info line per principal variation, ordered by
  /// `multipv` (index 0 is the best line).
  final List<SearchInfo> lines;

  /// Wall-clock duration of the search, measured in Dart.
  final Duration elapsed;

  /// Whether the search ended because it was stopped rather than because a
  /// limit was reached.
  final bool wasStopped;

  /// Set when the position has no legal moves.
  final TerminalState? terminal;

  /// The best line's final info, if any.
  SearchInfo? get finalInfo => lines.isEmpty ? null : lines.first;

  /// The final score of the best line, if any.
  Score? get score => finalInfo?.score;

  @override
  String toString() =>
      'SearchResult(bestMove: $bestMove, ponder: $ponderMove, score: $score)';
}
