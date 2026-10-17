// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Stockfish's non-UCI commands: d, eval, perft, compiler, and a short bench.

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final library = Stockfish.inspectEmbeddedLibrary();
  print('CPU variants: ${library.supportedVariants.join(', ')}');
  print('Using: ${library.loadedVariant}');

  final engine = await Stockfish.start();
  final position = Position.startpos(moves: parseUciMoves('e2e4 c7c5'));

  final board = await engine.display(position: position);
  print(board.ascii);
  print('FEN: ${board.fen}  key: ${board.key}');

  final eval = await engine.evaluate();
  print('Static evaluation (White): ${eval.finalWhite}');

  final perft = await engine.perft(4, position: const Position.startpos());
  print('perft(4) = ${perft.nodes}');

  final build = await engine.compilerInfo();
  print('Built with ${build.compiledBy} for ${build.architecture}');

  final bench = await engine.bench(const BenchConfig(limit: 8));
  print('bench: ${bench.nodes} nodes, ${bench.nodesPerSecond} nodes/s');

  await engine.dispose();
}
