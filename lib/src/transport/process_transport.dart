// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import '../uci/uci_command.dart' show checkSingleLine;
import 'engine_transport.dart';

/// Runs an external UCI engine executable as a child process.
///
/// Unlike the embedded engine, several of these can run at once, and a crash
/// can never affect the host process.
final class ProcessTransport extends EngineTransport {
  /// Creates the transport for [executable].
  ProcessTransport(
    this.executable, {
    this.arguments = const [],
    this.workingDirectory,
  });

  /// Finds an executable: [path] if given, else `STOCKFISH_PATH`, else
  /// `stockfish` on the `PATH`.
  static String resolveExecutable([String? path]) {
    if (path != null) return path;
    final env = Platform.environment['STOCKFISH_PATH'];
    if (env != null && env.isNotEmpty) return env;
    final names = Platform.isWindows
        ? ['stockfish.exe', 'stockfish']
        : ['stockfish'];
    final dirs = (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    );
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final candidate = File('$dir${Platform.pathSeparator}$name');
        if (candidate.existsSync()) return candidate.path;
      }
    }
    throw const EngineLoadException(
      'No Stockfish executable found: pass a path, set STOCKFISH_PATH or put '
      'stockfish on the PATH.',
    );
  }

  /// The engine executable.
  final String executable;

  /// Command line arguments (Stockfish treats them as one-shot commands, so
  /// usually none).
  final List<String> arguments;

  /// Working directory of the process.
  final String? workingDirectory;

  final _events = StreamController<TransportEvent>.broadcast();
  Process? _process;
  Completer<void>? _exited;

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  String get description => 'process $executable';

  /// The engine's process id, while running.
  int? get pid => _process?.pid;

  @override
  Future<void> start() async {
    if (_process != null) return;
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throw EngineLoadException('Could not start $executable: ${e.message}');
    }
    _process = process;
    final exited = _exited = Completer<void>();

    final decoder = const Utf8Decoder(allowMalformed: true);
    final out = process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen((l) => _events.add(OutputLine(l)))
        .asFuture<void>();
    final err = process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen((l) => _events.add(OutputLine(l, isError: true)))
        .asFuture<void>();

    unawaited(() async {
      final code = await process.exitCode;
      await Future.wait([out, err]).catchError((_) => <void>[]);
      if (identical(_process, process)) _process = null;
      _events.add(ExitedEvent(code));
      if (!exited.isCompleted) exited.complete();
    }());
  }

  @override
  void send(String line) {
    checkSingleLine(line);
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(line);
    } on Object {
      // The process is gone; ExitedEvent reports that.
    }
  }

  @override
  Future<void> stop({Duration timeout = const Duration(seconds: 5)}) async {
    final process = _process;
    final exited = _exited;
    if (process == null || exited == null) return;
    send('stop');
    send('quit');
    try {
      await process.stdin.close();
    } on Object {
      // Already closed.
    }
    try {
      await exited.future.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await exited.future;
    }
    _process = null;
  }
}
