// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Infinite multi-PV analysis with live snapshots, stopped after 2 seconds.

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start(
    options: const StockfishOptions(multiPv: 3, showWdl: true, threads: 2),
  );

  // Italian Game.
  final position = Position.startpos(
    moves: parseUciMoves('e2e4 e7e5 g1f3 b8c6 f1c4'),
  );
  final analysis = engine.analyze(
    position,
    throttle: const Duration(milliseconds: 500),
  );
  analysis.snapshots.listen((snapshot) {
    print('--- depth ${snapshot.depth}, ${snapshot.nps} nodes/s');
    for (final line in snapshot.lines) {
      final white = line.score!.fromWhitePerspective(position.sideToMove);
      print('#${line.multiPv} $white ${line.wdl} ${line.pv.take(6).join(' ')}');
    }
  });

  await Future<void>.delayed(const Duration(seconds: 2));
  final result = await analysis.stop();
  print('Best: ${result.bestMove} (expecting ${result.ponderMove})');
  await engine.dispose();
}
