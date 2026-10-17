# Getting started

## Install

```bash
dart pub add stockfish_dart
```

Requirements: Dart 3.10 or newer on Linux (glibc 2.28+), macOS or Windows,
on x64 or arm64.

## First search

```dart
import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start();
  print(engine.identity.name); // Stockfish 19 (modified by stockfish_dart)

  final result = await engine.bestMove(
    const Position.startpos(),
    limits: const SearchLimits.depth(15),
  );
  print('${result.bestMove} ${result.score}');

  await engine.dispose();
}
```

Run it with `dart run`. The first run prints `Running build hooks...` while
the native library is downloaded (about 80 MB, once per project). Later runs
use the cached copy.

To check an installation, run the bundled setup command. It loads the
library, reports which CPU variant is used and runs a short search:

```bash
dart run stockfish_dart:setup
```

## Core concepts

- **`Stockfish`** is the engine. Create it with `Stockfish.start()`, and
  always call `dispose()` when you're done. Calls run one at a time, in the
  order you make them.
- **`Position`** is what the engine analyses: `Position.startpos()` or
  `Position.fromFen(...)`, plus the moves played since (`moves:`, `play`,
  `playAll`).
- **`UciMove`** is a move in UCI long algebraic notation (`e2e4`, `e7e8q`,
  `e1g1`). This package has no chess-rules engine; use a library such as
  `package:dartchess` to convert from SAN or to generate legal moves.
- **`SearchLimits`** says when a search stops: depth, nodes, mate, move time,
  game clock, or infinite.
- **`SearchResult`** holds the best move, the move to ponder on, and the final
  info lines (score, PV, WDL...).
- **`StockfishOptions`** holds the engine options (threads, hash, MultiPV,
  skill...).

Scores are from the point of view of the **side to move**. Use
`score.fromWhitePerspective(position.sideToMove)` for White's view.

## Building an application

```bash
dart build cli -t bin/my_app.dart -o build
./build/bundle/bin/my_app
```

`dart build cli` puts the native libraries in `build/bundle/lib/`. Ship the
whole `bundle` directory. `dart compile exe` cannot be used with packages
that have native assets.

## Next steps

- [Analysis](analysis.md): live search info and multi-PV.
- [Playing games](playing-games.md): clocks and pondering.
- [Options](options.md): threads, hash, strength, tablebases, Chess960.
- [Docker](docker.md): deploying to servers.
