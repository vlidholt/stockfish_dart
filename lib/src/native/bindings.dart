// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// FFI bindings to the dispatcher library (native/bridge/dispatcher.cpp),
/// provided as the `package:stockfish_dart/stockfish` code asset by the build
/// hook.
@DefaultAsset('package:stockfish_dart/stockfish')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Bridge ABI version this Dart code expects (`SFD_API_VERSION`).
const expectedApiVersion = 1;

/// Output stream ids passed to the line callback.
abstract final class NativeStream {
  /// Standard output.
  static const stdout = 0;

  /// Standard error.
  static const stderr = 1;

  /// Unrecoverable engine error.
  static const fatal = 2;

  /// The UCI loop ended.
  static const exited = 3;
}

/// Return codes of the bridge functions.
abstract final class NativeResult {
  /// Success.
  static const ok = 0;

  /// An engine is already running in this process.
  static const alreadyRunning = 1;

  /// No engine is running.
  static const notRunning = 2;

  /// The operation timed out.
  static const timeout = 3;

  /// No usable engine library could be loaded.
  static const loadFailed = 4;

  /// The dispatcher has no network.
  static const noNet = 5;
}

/// Native type of the line callback.
typedef LineCallbackNative = Void Function(Int32 stream, Pointer<Utf8> line);

/// `int32_t sf_api_version(void)`.
@Native<Int32 Function()>(symbol: 'sf_api_version')
external int sfApiVersion();

/// `const char* sf_supported_variants(void)`.
@Native<Pointer<Utf8> Function()>(symbol: 'sf_supported_variants')
external Pointer<Utf8> sfSupportedVariants();

/// `int32_t sf_load(void)`.
@Native<Int32 Function()>(symbol: 'sf_load')
external int sfLoad();

/// `const char* sf_load_error(void)`.
@Native<Pointer<Utf8> Function()>(symbol: 'sf_load_error')
external Pointer<Utf8> sfLoadError();

/// `const char* sf_variant(void)`.
@Native<Pointer<Utf8> Function()>(symbol: 'sf_variant')
external Pointer<Utf8> sfVariant();

/// `uint32_t sf_net_size(void)`.
@Native<Uint32 Function()>(symbol: 'sf_net_size')
external int sfNetSize();

/// `int32_t sf_start(callback)`.
@Native<Int32 Function(Pointer<NativeFunction<LineCallbackNative>>)>(
  symbol: 'sf_start',
)
external int sfStart(Pointer<NativeFunction<LineCallbackNative>> callback);

/// `int32_t sf_send(const char* line)`.
@Native<Int32 Function(Pointer<Utf8>)>(symbol: 'sf_send')
external int sfSend(Pointer<Utf8> line);

/// `int32_t sf_state(void)`.
@Native<Int32 Function()>(symbol: 'sf_state')
external int sfState();

/// `int32_t sf_stop(int32_t timeout_ms)`. Blocks while the engine shuts down.
@Native<Int32 Function(Int32)>(symbol: 'sf_stop')
external int sfStop(int timeoutMs);

/// `void sf_free(char* line)`.
@Native<Void Function(Pointer<Utf8>)>(symbol: 'sf_free')
external void sfFree(Pointer<Utf8> line);
