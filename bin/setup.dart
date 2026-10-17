// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// `dart run stockfish_dart:setup`
//
// Running this triggers the stockfish_dart build hook (which downloads and
// verifies the native library for this platform), then starts the engine
// and runs a short search. Use it as a warm-up step in Dockerfiles and CI,
// or to diagnose installation problems. Exits with a non-zero code on
// failure.

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main(List<String> args) async {
  try {
    final info = Stockfish.inspectEmbeddedLibrary();
    stdout.writeln(
      'stockfish_dart: CPU supports ${info.supportedVariants.join(', ')}',
    );
    if (info.loadedVariant == null) {
      stderr.writeln('stockfish_dart: ${info.loadError}');
      exit(1);
    }
    stdout.writeln(
      'stockfish_dart: using engine variant ${info.loadedVariant}',
    );

    final engine = await Stockfish.start();
    final result = await engine.bestMove(
      const Position.startpos(),
      limits: const SearchLimits.depth(10),
    );
    stdout.writeln(
      'stockfish_dart: ${engine.identity.name} works '
      '(best move ${result.bestMove}, ${result.finalInfo?.nps ?? 0} nodes/s)',
    );
    await engine.dispose();
  } on StockfishException catch (e) {
    stderr.writeln('stockfish_dart: $e');
    exit(1);
  }
}
