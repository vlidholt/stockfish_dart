# stockfish_dart

[![native](https://github.com/vlidholt/stockfish_dart/actions/workflows/native.yml/badge.svg)](https://github.com/vlidholt/stockfish_dart/actions/workflows/native.yml)
[![ci](https://github.com/vlidholt/stockfish_dart/actions/workflows/ci.yml/badge.svg)](https://github.com/vlidholt/stockfish_dart/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

The [Stockfish 19](https://stockfishchess.org) chess engine for Dart on
**Linux, macOS and Windows**, embedded through FFI. It comes with a typed,
documented API for every UCI command and option. No Flutter required, and
no setup: the right native library for your platform and CPU is downloaded
and verified automatically when you build.

```dart
import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start();

  final result = await engine.bestMove(
    Position.startpos(moves: [UciMove('e2e4'), UciMove('e7e5')]),
    limits: const SearchLimits.depth(20),
  );
  print('${result.bestMove} ${result.score}'); // e.g. g1f3 cp 31

  await engine.dispose();
}
```

## Features

- **Embedded Stockfish 19.** It runs in-process as a native library: no
  executable to install and no child process to manage.
- **Fast on every CPU.** Each platform ships every instruction-set variant
  Stockfish supports (x86-64 from SSE2 to AVX-512 ICL; ARMv8 and ARMv8.2
  dot product). The best one is picked at runtime.
- **Robust.** Stockfish's process exits on bad input are patched into
  exceptions. An illegal move, a corrupt tablebase or an impossible hash size
  throws a typed exception, and the engine keeps working (or restarts itself
  and restores its options and position).
- **Complete API.**
  - Searches with every `go` limit, live info streams, multi-PV analysis
    snapshots, and pondering.
  - All 19 engine options as typed fields, validated before they are sent.
  - Stockfish's extra commands: `perft`, `d`, `eval`, `flip`, `bench`,
    `speedtest`, `compiler`, `export_net`.
  - Raw UCI access when you need it.
- **Server and Docker friendly.** `dart build cli` bundles the libraries next
  to your executable. The final image needs no network and no setup.
- **Testable.** `package:stockfish_dart/testing.dart` provides a scripted
  fake engine for unit tests.
- **Also drives external engines.** `EngineSource.process()` runs any
  Stockfish (or other UCI) executable instead.

## Supported platforms

| OS | Architectures |
|---|---|
| Linux (glibc ≥ 2.28) | x64, arm64 |
| macOS (≥ 10.15 Intel, ≥ 11 Apple silicon) | x64, arm64 |
| Windows 10+ | x64, arm64 |

Other platforms (for example Alpine/musl) can compile from source; see
[native library](doc/native-library.md).

## Installation

```bash
dart pub add stockfish_dart
```

That's it. The first `dart run`, `dart test` or `dart build cli` runs the
package's build hook, which downloads the libraries for your platform (about
75 MB, once) from this repository's GitHub releases and checks their SHA-256.
`dart pub get` itself never runs code, so nothing is downloaded until you
build.

> **Use `dart build cli`, not `dart compile exe`.** `dart compile exe` does
> not support packages with native assets.

## Usage

### Searching

```dart
final engine = await Stockfish.start(
  options: const StockfishOptions(threads: 4, hashMb: 256),
);

// Await the result...
final r = await engine.bestMove(position, limits: SearchLimits.moveTime(Duration(seconds: 2)));

// ...or watch the search as it runs.
final search = engine.search(position: position, limits: const SearchLimits.depth(25));
search.info.listen((i) => print('depth ${i.depth}: ${i.score} ${i.pv.join(' ')}'));
final result = await search.result;
```

`SearchLimits` covers every `go` limit: `depth`, `nodes`, `mate`,
`moveTime`, `clock` (`wtime`/`btime`/`winc`/`binc`/`movestogo`) and
`infinite`. `searchMoves` restricts the root moves.

### Analysis with several lines

```dart
await engine.setOptions(const StockfishOptions(multiPv: 3, showWdl: true));
final analysis = engine.analyze(position, throttle: const Duration(milliseconds: 250));
analysis.snapshots.listen((s) {
  for (final line in s.lines) {
    print('#${line.multiPv} d${line.depth} ${line.score} ${line.wdl} ${line.pv.take(6).join(' ')}');
  }
});
await Future<void>.delayed(const Duration(seconds: 10));
await analysis.stop();
```

### Playing a game

```dart
await engine.newGame();
final clock = GameClock(
  whiteTime: const Duration(minutes: 3),
  blackTime: const Duration(minutes: 3),
  whiteIncrement: const Duration(seconds: 2),
  blackIncrement: const Duration(seconds: 2),
);
final move = await engine.bestMove(game, limits: SearchLimits.clock(clock));
```

See [playing games](doc/playing-games.md) for pondering.

### Options

Every Stockfish option is a typed field of `StockfishOptions`. Values are
checked against the ranges the engine reports, because Stockfish silently
ignores invalid values.

```dart
await engine.setOptions(StockfishOptions(
  threads: 8,
  hashMb: 1024,
  syzygyPath: StockfishOptions.syzygyPathsFromList(['/tb/3-4-5', '/tb/6']),
));
await engine.setOptions(StockfishOptions.strength(const StrengthLimit.elo(1800)));
await engine.setOption('Move Overhead', 50); // or by UCI name
```

### Stockfish's extra commands

```dart
final perft = await engine.perft(5, position: Position.startpos()); // 4865609 nodes
final board = await engine.display();   // `d`: ASCII board, FEN, key, checkers
final eval = await engine.evaluate();   // `eval`: NNUE breakdown
final bench = await engine.bench();     // `bench` signature and speed
final speed = await engine.speedtest(); // `speedtest`
final build = await engine.compilerInfo();
await engine.exportNet('/tmp/net.nnue');
```

### Errors

All exceptions extend `StockfishException`:

```dart
try {
  await engine.setPosition(Position.startpos(moves: [UciMove('e2e5')]));
} on EngineCommandException catch (e) {
  print(e.reason); // Illegal move: e2e5. The previous position is kept.
}
```

An unrecoverable error (out of memory, corrupt tablebase) throws
`EngineFatalException`. The engine then restarts and re-applies your options
and position (configurable with `RestartPolicy`).

Only **one embedded engine** can run per process, because Stockfish uses
process-wide state. To run several engines at once, use
`Stockfish.start(engine: EngineSource.process(path: ...))` with a Stockfish
executable.

## Docker

```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
RUN dart run stockfish_dart:setup     # downloads + verifies + smoke-tests; cached layer
COPY . .
RUN dart build cli -t bin/server.dart -o build

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bundle/ /app/
ENTRYPOINT ["/app/bin/server"]
```

The final image runs without network access. Multi-architecture builds
(`docker buildx --platform linux/amd64,linux/arm64`) work unchanged. See
[Docker](doc/docker.md) and the [example server](example/docker).

## Documentation

- [Getting started](doc/getting-started.md)
- [Native library](doc/native-library.md): how the libraries are obtained;
  offline, mirror and build-from-source options
- [Docker](doc/docker.md)
- [Analysis](doc/analysis.md)
- [Playing games and pondering](doc/playing-games.md)
- [Options, strength and tablebases](doc/options.md)
- [Diagnostics](doc/diagnostics.md)
- [Errors and recovery](doc/error-handling.md)
- [Testing your code](doc/testing.md)
- [How it works](doc/architecture.md)
- [Licensing](doc/licensing.md)
- [Maintainers: building and releasing](doc/maintainers.md)

API reference: run `dart doc` or see the package page on pub.dev.

## License

stockfish_dart is free software under the **GNU General Public License v3.0
or later** (see [LICENSE](LICENSE)), the same license as Stockfish.

The native libraries contain Stockfish 19 with small modifications (listed in
[native/patches](native/patches/README.md)) and report themselves as
`Stockfish 19 (modified by stockfish_dart)`. The corresponding source is in
this repository and attached to every native release.

Running the package on your own servers does not require you to publish your
code; distributing software that includes it does. See
[licensing](doc/licensing.md). Stockfish is developed by
[the Stockfish developers](native/stockfish/AUTHORS). This project is not
affiliated with or endorsed by the Stockfish project.
