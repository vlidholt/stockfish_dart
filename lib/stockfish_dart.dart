// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// The Stockfish 19 chess engine for Dart.
///
/// Stockfish is embedded as a native library through FFI. The package's build
/// hook downloads (and verifies) the right library for your platform the
/// first time you `dart run`, `dart test` or `dart build cli`. No Flutter and
/// no manual setup required.
///
/// ```dart
/// import 'package:stockfish_dart/stockfish_dart.dart';
///
/// Future<void> main() async {
///   final engine = await Stockfish.start();
///   final result = await engine.bestMove(
///     Position.startpos(moves: [UciMove('e2e4')]),
///     limits: const SearchLimits.depth(16),
///   );
///   print('Best reply: ${result.bestMove} (${result.score})');
///   await engine.dispose();
/// }
/// ```
///
/// Start with `Stockfish`. Positions are `Position`s, moves are `UciMove`s
/// in UCI notation, and search limits are `SearchLimits`. Every Stockfish
/// option is a field of `StockfishOptions`.
///
/// Build applications with `dart build cli`; `dart compile exe` does not
/// support packages with native assets.
library;

export 'src/diagnostics.dart';
export 'src/engine_source.dart';
export 'src/errors.dart';
export 'src/model/option_spec.dart';
export 'src/model/position.dart';
export 'src/model/score.dart';
export 'src/model/search_info.dart';
export 'src/model/search_limits.dart';
export 'src/model/uci_move.dart';
export 'src/options/stockfish_options.dart';
export 'src/search_handle.dart';
export 'src/session/engine_session.dart' show EngineState, UciTrafficEntry;
export 'src/session/restart_policy.dart';
export 'src/stockfish.dart';
export 'src/transport/engine_transport.dart';
export 'src/transport/ffi_transport.dart' show EmbeddedLibraryInfo;
