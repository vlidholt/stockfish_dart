// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import '../model/position.dart';
import '../model/search_limits.dart';
import '../model/uci_move.dart';

/// A command sent to a UCI engine. [toUci] gives the line to send.
@immutable
sealed class UciCommand {
  const UciCommand();

  /// The command line, without a line terminator.
  String toUci();

  @override
  String toString() => toUci();
}

/// `uci`: start the handshake.
final class UciHandshakeCommand extends UciCommand {
  /// Creates the command.
  const UciHandshakeCommand();

  @override
  String toUci() => 'uci';
}

/// `isready`: wait until the engine has processed everything sent so far.
final class IsReadyCommand extends UciCommand {
  /// Creates the command.
  const IsReadyCommand();

  @override
  String toUci() => 'isready';
}

/// `ucinewgame`: the next position belongs to a new game.
final class UciNewGameCommand extends UciCommand {
  /// Creates the command.
  const UciNewGameCommand();

  @override
  String toUci() => 'ucinewgame';
}

/// `setoption name <name> [value <value>]`.
final class SetOptionCommand extends UciCommand {
  /// Creates the command. A null [value] is used for buttons.
  const SetOptionCommand(this.name, [this.value]);

  /// Option name.
  final String name;

  /// Option value; empty strings are sent as `<empty>`.
  final String? value;

  @override
  String toUci() => switch (value) {
    null => 'setoption name $name',
    '' => 'setoption name $name value <empty>',
    final v => 'setoption name $name value $v',
  };
}

/// `position startpos|fen … [moves …]`.
final class PositionCommand extends UciCommand {
  /// Creates the command.
  const PositionCommand(this.position);

  /// The position to set.
  final Position position;

  @override
  String toUci() => 'position ${position.toUci()}';
}

/// `go …`: start searching.
final class GoCommand extends UciCommand {
  /// Creates the command.
  const GoCommand({
    this.limits = const SearchLimits.infinite(),
    this.searchMoves = const [],
    this.ponder = false,
  });

  /// When to stop.
  final SearchLimits limits;

  /// Restrict the search to these root moves.
  final List<UciMove> searchMoves;

  /// Search in ponder mode (`go ponder`).
  final bool ponder;

  @override
  String toUci() => [
    'go',
    if (ponder) 'ponder',
    ...limits.toUciArguments(),
    // Must be last: Stockfish reads everything after it as moves.
    if (searchMoves.isNotEmpty) ...['searchmoves', ...searchMoves],
  ].join(' ');
}

/// `go perft <depth>`: count leaf nodes (Stockfish extension).
final class PerftCommand extends UciCommand {
  /// Creates the command.
  const PerftCommand(this.depth);

  /// Depth to count to.
  final int depth;

  @override
  String toUci() => 'go perft $depth';
}

/// `stop`: end the current search; `bestmove` follows.
final class StopCommand extends UciCommand {
  /// Creates the command.
  const StopCommand();

  @override
  String toUci() => 'stop';
}

/// `ponderhit`: the opponent played the expected move.
final class PonderHitCommand extends UciCommand {
  /// Creates the command.
  const PonderHitCommand();

  @override
  String toUci() => 'ponderhit';
}

/// `quit`: end the engine.
final class QuitCommand extends UciCommand {
  /// Creates the command.
  const QuitCommand();

  @override
  String toUci() => 'quit';
}

/// `d`: print the board (Stockfish extension).
final class DisplayCommand extends UciCommand {
  /// Creates the command.
  const DisplayCommand();

  @override
  String toUci() => 'd';
}

/// `eval`: print the static evaluation breakdown (Stockfish extension).
final class EvalCommand extends UciCommand {
  /// Creates the command.
  const EvalCommand();

  @override
  String toUci() => 'eval';
}

/// `flip`: mirror the position (Stockfish extension).
final class FlipCommand extends UciCommand {
  /// Creates the command.
  const FlipCommand();

  @override
  String toUci() => 'flip';
}

/// `compiler`: print build information (Stockfish extension).
final class CompilerCommand extends UciCommand {
  /// Creates the command.
  const CompilerCommand();

  @override
  String toUci() => 'compiler';
}

/// `export_net [file]`: save the network (Stockfish extension).
final class ExportNetCommand extends UciCommand {
  /// Creates the command.
  const ExportNetCommand([this.path]);

  /// Target file; the network's default name in the working directory if null.
  final String? path;

  @override
  String toUci() => path == null ? 'export_net' : 'export_net $path';
}

/// `help`: print the license notice (Stockfish extension).
final class HelpCommand extends UciCommand {
  /// Creates the command.
  const HelpCommand();

  @override
  String toUci() => 'help';
}

/// `bench …` (Stockfish extension).
final class BenchCommand extends UciCommand {
  /// Creates the command from its positional arguments.
  const BenchCommand(this.arguments);

  /// `[hash] [threads] [limit] [fenFile] [limitType]`.
  final List<String> arguments;

  @override
  String toUci() => ['bench', ...arguments].join(' ');
}

/// `speedtest [threads] [hash] [seconds]` (Stockfish extension).
final class SpeedtestCommand extends UciCommand {
  /// Creates the command from its positional arguments.
  const SpeedtestCommand(this.arguments);

  /// `[threads] [hash] [seconds]`.
  final List<String> arguments;

  @override
  String toUci() => ['speedtest', ...arguments].join(' ');
}

/// Any other line.
final class RawCommand extends UciCommand {
  /// Creates the command.
  const RawCommand(this.line);

  /// The line to send.
  final String line;

  @override
  String toUci() => line;
}

/// Throws [ArgumentError] if [line] contains a line break: every command
/// must be exactly one line, or text after the break would be executed as
/// another command.
void checkSingleLine(String line) {
  if (line.contains('\n') || line.contains('\r')) {
    throw ArgumentError.value(
      line,
      'line',
      'UCI commands must not contain line breaks',
    );
  }
}
