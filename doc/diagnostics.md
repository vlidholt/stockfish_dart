# Diagnostics

Stockfish's non-UCI commands, with parsed results.

| Method | Command | Result |
|---|---|---|
| `perft(depth, position:)` | `go perft` | `PerftResult`: total leaf nodes and the count per root move (`divide`) |
| `display(position:)` | `d` | `BoardDisplay`: ASCII board, FEN, hash key, checkers, tablebase probe |
| `evaluate(position:)` | `eval` | `EvalTrace`: NNUE contributions per bucket, NNUE and final evaluation (White's view, pawns) |
| `flip()` | `flip` | the mirrored position, which becomes the current one |
| `bench([config, onProgress])` | `bench` | `BenchResult`: nodes (the "bench signature"), nps, time |
| `speedtest([config, onProgress])` | `speedtest` | `SpeedtestResult`: nps over a realistic game, threads, hash usage |
| `compilerInfo()` | `compiler` | `CompilerInfo`: compiler, architecture (the CPU variant), settings |
| `exportNet([path])` | `export_net` | the engine's confirmation message |
| `help()` | `help` | license notice |

```dart
final perft = await engine.perft(5, position: const Position.startpos());
print(perft.nodes); // 4865609
perft.divide.forEach((move, n) => print('$move: $n'));

final speed = await engine.speedtest(
  const SpeedtestConfig(threads: 4, hashMb: 512, duration: Duration(seconds: 30)),
  print, // progress
);
print('${speed.nodesPerSecond} nodes/s');
```

`bench` and `speedtest` change `Threads`, `Hash` and the position while they
run; the previous values are restored afterwards. Without arguments,
`speedtest` uses every hardware thread and runs for about 150 seconds.

## Raw UCI

```dart
engine.rawOutput.listen(print);      // every line the engine prints
engine.rawErrorOutput.listen(print); // stderr (bench/speedtest summaries)
engine.infoStrings.listen(print);    // `info string` payloads
final lines = await engine.sendRaw('d');
```

`sendRaw` rejects commands that change state the `Stockfish` object tracks
(`position`, `setoption`, `go`, ...) unless you pass `unsafe: true`.

To log all traffic, pass `onTraffic: print` to `Stockfish.start`, or set
`debugLogFile`.

The UCI building blocks (`EngineSession`, `UciCommand`, `parseUciLine`,
transports) are in `package:stockfish_dart/uci.dart`. Nothing there is
Stockfish-specific, so it can drive other UCI engines too.
