// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Runs a short search with every engine variant this CPU supports, each in
// its own process (STOCKFISH_DART_VARIANT selects the variant).
//
//   dart run tool/smoke_variants.dart

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) return _search(args.single);

  final info = Stockfish.inspectEmbeddedLibrary();
  print('CPU supports: ${info.supportedVariants.join(', ')}');
  var failed = false;
  for (final variant in info.supportedVariants) {
    final r = await Process.run(
      Platform.resolvedExecutable,
      [...Platform.executableArguments, Platform.script.toFilePath(), variant],
      environment: {'STOCKFISH_DART_VARIANT': variant},
    );
    final out = '${r.stdout}${r.stderr}'.trim();
    if (r.exitCode == 0) {
      print('ok    $variant: $out');
    } else {
      failed = true;
      print('FAIL  $variant (exit ${r.exitCode}): $out');
    }
  }
  exit(failed ? 1 : 0);
}

Future<void> _search(String variant) async {
  final info = Stockfish.inspectEmbeddedLibrary();
  if (info.loadedVariant != variant) {
    stderr.writeln('loaded ${info.loadedVariant} (${info.loadError})');
    exit(2);
  }
  final engine = await Stockfish.start();
  final r = await engine.bestMove(
    Position.startpos(),
    limits: const SearchLimits.depth(14),
  );
  final c = await engine.compilerInfo();
  stdout.write(
    '${r.bestMove} ${r.score} '
    '${r.finalInfo?.nps} nps, ${c.architecture}',
  );
  await engine.dispose();
}
