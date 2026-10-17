// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// @docImport 'engine_source.dart';
/// @docImport 'session/restart_policy.dart';
/// @docImport 'stockfish.dart';
library;

/// Base class of every exception thrown by this package.
sealed class StockfishException implements Exception {
  const StockfishException(this.message);

  /// Human-readable description.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The native engine library could not be loaded.
///
/// Usually the build hook could not provide a library for this platform; see
/// the `doc/native-library.md` guide for the `user_defines` that control it.
final class EngineLoadException extends StockfishException {
  /// Creates the exception.
  const EngineLoadException(super.message);
}

/// An embedded engine is already running in this process.
///
/// Stockfish redirects the process-wide standard streams, so only one
/// embedded engine can run per process. Dispose the other instance first, or
/// use [EngineSource.process] to run several engines.
final class EngineAlreadyRunningException extends StockfishException {
  /// Creates the exception.
  const EngineAlreadyRunningException([
    super.message =
        'An embedded Stockfish engine is already running in this process.',
  ]);
}

/// The engine did not complete the UCI handshake.
final class EngineStartException extends StockfishException {
  /// Creates the exception.
  const EngineStartException(super.message);
}

/// The engine rejected a command (`info string CRITICAL ERROR`), for example
/// an invalid FEN, an illegal move or an invalid `go` argument.
///
/// The engine stays usable; its position is restored to the last position
/// that was applied successfully.
final class EngineCommandException extends StockfishException {
  /// Creates the exception.
  const EngineCommandException(this.command, this.reason)
    : super('Command `$command` failed: $reason');

  /// The UCI command that failed.
  final String command;

  /// Stockfish's explanation.
  final String reason;
}

/// The engine hit an unrecoverable error (out of memory, corrupt tablebase,
/// process exit, ...) and had to be restarted.
final class EngineFatalException extends StockfishException {
  /// Creates the exception.
  const EngineFatalException(this.reason, {this.restarted = false})
    : super(reason);

  /// What went wrong.
  final String reason;

  /// Whether the engine was restarted automatically (see [RestartPolicy]).
  final bool restarted;
}

/// The operation needs an idle engine, but an infinite or ponder search is
/// running. Stop the search first, or pass `interrupt: true`.
final class EngineBusyException extends StockfishException {
  /// Creates the exception.
  const EngineBusyException([
    super.message =
        'An infinite or ponder search is running; stop it first or pass interrupt: true.',
  ]);
}

/// The engine was used after [Stockfish.dispose].
final class EngineDisposedException extends StockfishException {
  /// Creates the exception.
  const EngineDisposedException([
    super.message = 'The engine has been disposed.',
  ]);
}

/// An operation did not finish in time.
final class EngineTimeoutException extends StockfishException {
  /// Creates the exception.
  const EngineTimeoutException(super.message);
}

/// An option name or value was rejected.
final class InvalidOptionException extends StockfishException {
  /// Creates the exception.
  const InvalidOptionException(this.name, String message) : super(message);

  /// The option's UCI name.
  final String name;
}

/// A FEN string is not structurally valid.
final class InvalidPositionException extends StockfishException {
  /// Creates the exception.
  const InvalidPositionException(this.fen, String message) : super(message);

  /// The rejected FEN.
  final String fen;
}

/// A move is not in UCI long algebraic notation.
final class InvalidMoveException extends StockfishException {
  /// Creates the exception.
  const InvalidMoveException(this.move)
    : super('"$move" is not a UCI move (expected e.g. e2e4, e7e8q or 0000).');

  /// The rejected move text.
  final String move;
}
