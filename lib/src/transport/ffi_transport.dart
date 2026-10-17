// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../errors.dart';
import '../native/bindings.dart' as native;
import '../uci/uci_command.dart' show checkSingleLine;
import 'engine_transport.dart';

/// Runs the embedded Stockfish library in this process (the default).
///
/// Only one embedded engine can run per process at a time.
final class FfiTransport extends EngineTransport {
  /// Creates the transport. Nothing is loaded until [start].
  FfiTransport();

  final _events = StreamController<TransportEvent>.broadcast();
  NativeCallable<native.LineCallbackNative>? _callable;
  Completer<void>? _exited;
  String _variant = '';
  bool _keepAlive = true;

  @override
  void setKeepAlive(bool keepAlive) {
    _keepAlive = keepAlive;
    _callable?.keepIsolateAlive = keepAlive;
  }

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  String get description => 'embedded Stockfish ($_variant)';

  /// The CPU variant of the loaded engine library, e.g. `x86_64_avx2`.
  String get variant => _variant;

  /// Loads the library (if needed) and reports what this CPU supports.
  ///
  /// Throws [EngineLoadException] if no usable library is available.
  static EmbeddedLibraryInfo inspect() {
    _checkLibrary();
    final rc = native.sfLoad();
    return EmbeddedLibraryInfo(
      apiVersion: native.sfApiVersion(),
      supportedVariants: native.sfSupportedVariants().toDartString().split(','),
      loadedVariant: rc == native.NativeResult.ok
          ? native.sfVariant().toDartString()
          : null,
      loadError: rc == native.NativeResult.ok
          ? null
          : native.sfLoadError().toDartString(),
      netSize: native.sfNetSize(),
    );
  }

  static void _checkLibrary() {
    final int api;
    try {
      api = native.sfApiVersion();
    } on ArgumentError catch (e) {
      throw EngineLoadException(
        'The Stockfish native library is not available for this platform or '
        'was not built. Run the program with `dart run`, `dart test` or '
        '`dart build cli` (not `dart compile exe`) so the stockfish_dart build '
        'hook can provide it. ($e)',
      );
    }
    if (api != native.expectedApiVersion) {
      throw EngineLoadException(
        'The Stockfish native library has bridge API version $api, but this '
        'version of stockfish_dart needs ${native.expectedApiVersion}. Clear '
        '.dart_tool/hooks_runner and rebuild.',
      );
    }
  }

  @override
  Future<void> start() async {
    if (_callable != null) return;
    _checkLibrary();

    final rc = native.sfLoad();
    if (rc != native.NativeResult.ok) {
      throw EngineLoadException(native.sfLoadError().toDartString());
    }
    _variant = native.sfVariant().toDartString();

    final callable = NativeCallable<native.LineCallbackNative>.listener(_onLine)
      ..keepIsolateAlive = _keepAlive;
    final started = native.sfStart(callable.nativeFunction);
    if (started != native.NativeResult.ok) {
      callable.close();
      if (started == native.NativeResult.alreadyRunning) {
        throw const EngineAlreadyRunningException();
      }
      throw EngineLoadException(
        'The embedded engine failed to start (code $started).',
      );
    }
    _callable = callable;
    _exited = Completer<void>();
  }

  void _onLine(int stream, Pointer<Utf8> pointer) {
    final String text;
    try {
      text = pointer.toDartString();
    } finally {
      native.sfFree(pointer);
    }
    if (_events.isClosed) return;
    switch (stream) {
      case native.NativeStream.stdout:
        _events.add(OutputLine(text));
      case native.NativeStream.stderr:
        _events.add(OutputLine(text, isError: true));
      case native.NativeStream.fatal:
        _events.add(FatalEvent(text));
      case native.NativeStream.exited:
        _events.add(const ExitedEvent());
        final exited = _exited;
        if (exited != null && !exited.isCompleted) exited.complete();
    }
  }

  @override
  void send(String line) {
    checkSingleLine(line);
    if (_callable == null) return;
    final pointer = line.toNativeUtf8();
    try {
      native.sfSend(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  Future<void> stop({Duration timeout = const Duration(seconds: 5)}) async {
    final callable = _callable;
    if (callable == null) return;

    final exited = _exited!;
    if (!exited.isCompleted) {
      send('stop');
      send('setoption name Debug Log File value <empty>');
      send('quit');
      try {
        await exited.future.timeout(timeout);
      } on TimeoutException {
        throw EngineTimeoutException(
          'The embedded engine did not shut down within $timeout.',
        );
      }
    }

    // The UCI loop has ended; this only joins its thread.
    final rc = native.sfStop(timeout.inMilliseconds);
    if (rc == native.NativeResult.timeout) {
      throw EngineTimeoutException(
        'The embedded engine did not shut down within $timeout.',
      );
    }
    _callable = null;
    _exited = null;
    // Let already-posted callbacks drain before closing the callable.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    callable.close();
  }
}

/// Diagnostics about the embedded native library.
final class EmbeddedLibraryInfo {
  /// Creates the info.
  const EmbeddedLibraryInfo({
    required this.apiVersion,
    required this.supportedVariants,
    required this.loadedVariant,
    required this.loadError,
    required this.netSize,
  });

  /// Bridge ABI version of the dispatcher.
  final int apiVersion;

  /// Engine variants this CPU can run, best first.
  final List<String> supportedVariants;

  /// The variant that was loaded, or null if none could be.
  final String? loadedVariant;

  /// Why loading failed, if it did.
  final String? loadError;

  /// Size of the embedded NNUE network in bytes.
  final int netSize;

  @override
  String toString() =>
      'EmbeddedLibraryInfo(variant: $loadedVariant, supported: $supportedVariants'
      '${loadError == null ? '' : ', error: $loadError'})';
}
