// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import '../errors.dart';
import 'uci_move.dart';

/// The side to move.
enum Side {
  /// White.
  white,

  /// Black.
  black;

  /// The other side.
  Side get opponent => this == white ? black : white;
}

/// A chess position as sent to the engine with the UCI `position` command:
/// a starting point (the standard start position or a FEN) plus the moves
/// played from there.
///
/// ```dart
/// final p = Position.startpos(moves: [UciMove('e2e4'), UciMove('c7c5')]);
/// final q = Position.fromFen('8/8/8/8/8/8/8/K1k5 w - - 0 1');
/// ```
@immutable
final class Position {
  /// The standard starting position, optionally followed by [moves].
  const Position.startpos({this.moves = const []}) : fen = null;

  const Position._(this.fen, this.moves);

  /// A position given by [fen], optionally followed by [moves].
  ///
  /// The FEN is checked for structural validity (see [validateFen]); throws
  /// [InvalidPositionException] if it is malformed. Whether the position is
  /// legal is checked by the engine.
  factory Position.fromFen(String fen, {List<UciMove> moves = const []}) {
    final normalized = fen.trim().split(RegExp(r'\s+')).join(' ');
    validateFen(normalized);
    return Position._(normalized, List.unmodifiable(moves));
  }

  /// FEN of the standard starting position.
  static const standardStartFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// The FEN this position starts from, or null for the standard start
  /// position.
  final String? fen;

  /// Moves played from [fen] (or the start position).
  final List<UciMove> moves;

  /// Whether this starts from the standard start position.
  bool get isStartpos => fen == null;

  /// The FEN of the starting point (the standard FEN for [isStartpos]).
  String get startFen => fen ?? standardStartFen;

  /// A copy with [move] appended.
  Position play(UciMove move) => playAll([move]);

  /// A copy with [moves] appended.
  Position playAll(Iterable<UciMove> moves) =>
      Position._(fen, List.unmodifiable([...this.moves, ...moves]));

  /// The side to move after [moves], derived from the FEN and move count.
  Side get sideToMove {
    final start = startFen.split(' ')[1] == 'w' ? Side.white : Side.black;
    return moves.length.isEven ? start : start.opponent;
  }

  /// The arguments of the UCI `position` command, e.g.
  /// `startpos moves e2e4` or `fen <fen> moves e2e4`.
  String toUci() {
    final base = fen == null ? 'startpos' : 'fen $fen';
    return moves.isEmpty ? base : '$base moves ${moves.join(' ')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Position &&
      other.fen == fen &&
      other.moves.length == moves.length &&
      _sameMoves(other.moves, moves);

  static bool _sameMoves(List<UciMove> a, List<UciMove> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(fen, Object.hashAll(moves));

  @override
  String toString() => 'Position(${toUci()})';
}

final _castling = RegExp(r'^(-|[KQkqA-Ha-h]{1,4})$');
final _enPassant = RegExp(r'^(-|[a-h][36])$');

/// Checks that [fen] is a structurally valid FEN (or X-FEN/Shredder-FEN for
/// Chess960) and throws [InvalidPositionException] if not.
///
/// Checked: six fields, eight ranks of eight squares, valid piece letters,
/// exactly one king per side, no pawns on the first or last rank, side to
/// move, castling and en passant syntax, and the move counters. Legality
/// (for example the side not to move being in check) is left to the engine.
void validateFen(String fen) {
  Never fail(String why) =>
      throw InvalidPositionException(fen, 'Invalid FEN "$fen": $why');

  final fields = fen.split(' ');
  if (fields.length != 6) fail('expected 6 fields, got ${fields.length}');

  final ranks = fields[0].split('/');
  if (ranks.length != 8) fail('expected 8 ranks, got ${ranks.length}');
  var whiteKings = 0, blackKings = 0;
  for (var r = 0; r < 8; r++) {
    var squares = 0;
    for (final c in ranks[r].split('')) {
      final digit = int.tryParse(c);
      if (digit != null) {
        if (digit < 1 || digit > 8) fail('invalid empty-square count "$c"');
        squares += digit;
      } else if ('pnbrqkPNBRQK'.contains(c)) {
        squares++;
        if (c == 'K') whiteKings++;
        if (c == 'k') blackKings++;
        if ((c == 'p' || c == 'P') && (r == 0 || r == 7)) {
          fail('pawn on rank ${8 - r}');
        }
      } else {
        fail('invalid piece "$c"');
      }
    }
    if (squares != 8) fail('rank ${8 - r} has $squares squares');
  }
  if (whiteKings != 1 || blackKings != 1) {
    fail('each side needs exactly one king');
  }
  if (fields[1] != 'w' && fields[1] != 'b') fail('side to move must be w or b');
  if (!_castling.hasMatch(fields[2])) {
    fail('invalid castling rights "${fields[2]}"');
  }
  if (!_enPassant.hasMatch(fields[3])) {
    fail('invalid en passant square "${fields[3]}"');
  }
  final halfmove = int.tryParse(fields[4]);
  final fullmove = int.tryParse(fields[5]);
  if (halfmove == null || halfmove < 0) fail('invalid halfmove clock');
  if (fullmove == null || fullmove < 0) fail('invalid fullmove number');
}
