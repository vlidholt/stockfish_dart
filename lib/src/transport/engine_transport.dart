// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Something the engine produced.
sealed class TransportEvent {
  const TransportEvent();
}

/// A line of engine output.
final class OutputLine extends TransportEvent {
  /// Creates the event.
  const OutputLine(this.line, {this.isError = false});

  /// The line, without terminator.
  final String line;

  /// Whether it was written to standard error.
  final bool isError;

  @override
  String toString() => isError ? 'stderr: $line' : line;
}

/// The engine hit an unrecoverable error and must be restarted.
final class FatalEvent extends TransportEvent {
  /// Creates the event.
  const FatalEvent(this.reason);

  /// What went wrong.
  final String reason;

  @override
  String toString() => 'fatal: $reason';
}

/// The engine's UCI loop (or process) ended.
final class ExitedEvent extends TransportEvent {
  /// Creates the event.
  const ExitedEvent([this.exitCode]);

  /// The process exit code, if known.
  final int? exitCode;

  @override
  String toString() => 'exited: $exitCode';
}

/// A line-based connection to a UCI engine.
///
/// Implementations: the embedded engine (FFI, the default), an external
/// process, or a fake for tests. A transport may be started again after it
/// was stopped; [events] stays the same stream across restarts.
abstract class EngineTransport {
  /// Creates a transport.
  EngineTransport();

  /// Engine output and lifecycle events.
  Stream<TransportEvent> get events;

  /// A short description for error messages (e.g. `embedded x86_64_avx2`).
  String get description;

  /// Starts the engine.
  Future<void> start();

  /// Sends one command line.
  void send(String line);

  /// Ends the engine, waiting up to [timeout].
  Future<void> stop({Duration timeout = const Duration(seconds: 5)});

  /// Whether the transport should keep the Dart isolate alive. The session
  /// enables this while commands are in flight, so an idle engine that was
  /// never disposed does not prevent the program from exiting.
  void setKeepAlive(bool keepAlive) {}
}
