// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import 'transport/engine_transport.dart';
import 'transport/ffi_transport.dart';
import 'transport/process_transport.dart';

/// Which engine `Stockfish.start` runs.
@immutable
sealed class EngineSource {
  const EngineSource();

  /// The Stockfish 19 library embedded by this package (FFI). The default.
  ///
  /// Only one embedded engine can run per process at a time.
  const factory EngineSource.embedded() = EmbeddedEngineSource;

  /// An external UCI engine executable, run as a child process.
  ///
  /// [path] defaults to `STOCKFISH_PATH`, then `stockfish` on the `PATH`.
  /// Use this to run several engines at once, to isolate crashes completely,
  /// or to use a different Stockfish build.
  const factory EngineSource.process({
    String? path,
    List<String> arguments,
    String? workingDirectory,
  }) = ProcessEngineSource;

  /// Creates the transport for this source.
  EngineTransport createTransport();
}

/// See [EngineSource.embedded].
final class EmbeddedEngineSource extends EngineSource {
  /// Creates the source.
  const EmbeddedEngineSource();

  @override
  EngineTransport createTransport() => FfiTransport();

  @override
  String toString() => 'EngineSource.embedded()';
}

/// See [EngineSource.process].
final class ProcessEngineSource extends EngineSource {
  /// Creates the source.
  const ProcessEngineSource({
    this.path,
    this.arguments = const [],
    this.workingDirectory,
  });

  /// The executable, or null to search `STOCKFISH_PATH` and `PATH`.
  final String? path;

  /// Command line arguments.
  final List<String> arguments;

  /// Working directory.
  final String? workingDirectory;

  @override
  EngineTransport createTransport() => ProcessTransport(
    ProcessTransport.resolveExecutable(path),
    arguments: arguments,
    workingDirectory: workingDirectory,
  );

  @override
  String toString() => 'EngineSource.process(${path ?? ''})';
}
