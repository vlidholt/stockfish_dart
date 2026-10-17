// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start(
    options: const StockfishOptions(threads: 2, hashMb: 64),
  );
  print('Running ${engine.identity.name}');

  // A one-shot search.
  final position = Position.startpos(
    moves: [UciMove('e2e4'), UciMove('e7e5'), UciMove('g1f3')],
  );
  final result = await engine.bestMove(
    position,
    limits: const SearchLimits.depth(18),
  );
  print('Best move: ${result.bestMove}, score: ${result.score}');

  // Watch a search in progress.
  final handle = engine.search(
    position: position,
    limits: const SearchLimits.moveTime(Duration(milliseconds: 500)),
  );
  handle.info.listen((info) {
    if (info.pv.isNotEmpty) {
      print('depth ${info.depth}: ${info.score} ${info.pv.take(5).join(' ')}');
    }
  });
  await handle.result;

  await engine.dispose();
}
