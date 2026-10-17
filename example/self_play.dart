// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// A short game: a full-strength engine (White) against itself limited to
// ~1500 Elo (Black), each side with a 3-second clock plus increment.

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start();
  await engine.newGame();

  var game = const Position.startpos();
  var white = const Duration(seconds: 3), black = const Duration(seconds: 3);
  const increment = Duration(milliseconds: 100);

  for (var ply = 0; ply < 20; ply++) {
    final whiteToMove = game.sideToMove == Side.white;
    await engine.setOptions(
      StockfishOptions.strength(
        whiteToMove ? StrengthLimit.full : const StrengthLimit.elo(1500),
      ),
    );
    final clock = GameClock(
      whiteTime: white,
      blackTime: black,
      whiteIncrement: increment,
      blackIncrement: increment,
    );
    final watch = Stopwatch()..start();
    final result = await engine.bestMove(
      game,
      limits: SearchLimits.clock(clock),
    );
    final used = watch.elapsed;
    if (whiteToMove) {
      white = white - used + increment;
    } else {
      black = black - used + increment;
    }

    final move = result.bestMove;
    if (move == null) {
      print('Game over: ${result.terminal!.name}');
      break;
    }
    final score = result.score?.fromWhitePerspective(game.sideToMove);
    print(
      '${ply ~/ 2 + 1}${whiteToMove ? '.' : '...'} $move '
      '($score, ${used.inMilliseconds} ms)',
    );
    game = game.play(move);
  }

  print('Final position: ${(await engine.display(position: game)).fen}');
  await engine.dispose();
}
