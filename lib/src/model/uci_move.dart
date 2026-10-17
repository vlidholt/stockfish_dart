// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import '../errors.dart';

final _movePattern = RegExp(r'^([a-h][1-8])([a-h][1-8])([qrbnk])?$');

/// A move in UCI long algebraic notation: `e2e4`, `e7e8q` (promotion),
/// `e1g1` (castling; `e1h1` in Chess960 mode) or `0000` (null move).
///
/// This only checks the notation, not whether the move is legal.
extension type const UciMove._(String value) {
  /// Parses [value], throwing [InvalidMoveException] if it is not UCI
  /// notation. Upper-case input is accepted and normalised.
  factory UciMove(String value) =>
      tryParse(value) ?? (throw InvalidMoveException(value));

  /// Parses [value], returning null if it is not UCI notation.
  static UciMove? tryParse(String value) {
    final v = value.trim().toLowerCase();
    if (v == '0000') return UciMove._(v);
    // 'k' promotions only exist in some variants, but Stockfish's notation
    // allows them, so accept them here as well.
    return _movePattern.hasMatch(v) ? UciMove._(v) : null;
  }

  /// The null move, `0000`.
  static const nullMove = UciMove._('0000');

  /// Origin square, e.g. `e2`. Empty for the null move.
  String get from => isNull ? '' : value.substring(0, 2);

  /// Destination square, e.g. `e4`. Empty for the null move.
  String get to => isNull ? '' : value.substring(2, 4);

  /// Promotion piece letter (`q`, `r`, `b`, `n`), or null.
  String? get promotion => value.length == 5 ? value[4] : null;

  /// Whether this is the null move `0000`.
  bool get isNull => value == '0000';
}

/// Parses a whitespace separated list of UCI moves.
List<UciMove> parseUciMoves(String text) => [
  for (final token in text.split(RegExp(r'\s+')))
    if (token.isNotEmpty) UciMove(token),
];
