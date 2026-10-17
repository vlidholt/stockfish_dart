# Options

Every Stockfish 19 option is a field of `StockfishOptions`. Fields left
`null` keep their current value. `setOptions` only sends the values that
changed, applying `NumaPolicy`, `Threads` and `Hash` first.

| Field | UCI option | Range / default |
|---|---|---|
| `threads` | `Threads` | 1 – max(1024, 4 × CPUs); 1 |
| `hashMb` | `Hash` | 1 – 33554432 MiB; 16 |
| `ponder` | `Ponder` | false |
| `multiPv` | `MultiPV` | 1 – 256; 1 |
| `skillLevel` | `Skill Level` | 0 – 20; 20 |
| `moveOverhead` | `Move Overhead` | 0 – 5000 ms; 10 |
| `nodesTime` | `nodestime` | 0 – 10000; 0 |
| `chess960` | `UCI_Chess960` | false |
| `limitStrength` | `UCI_LimitStrength` | false |
| `elo` | `UCI_Elo` | 1320 – 3190; 1320 |
| `showWdl` | `UCI_ShowWDL` | false |
| `syzygyPath` | `SyzygyPath` | empty |
| `syzygyProbeDepth` | `SyzygyProbeDepth` | 1 – 100; 1 |
| `syzygy50MoveRule` | `Syzygy50MoveRule` | true |
| `syzygyProbeLimit` | `SyzygyProbeLimit` | 0 – 7; 7 |
| `evalFile` | `EvalFile` | the embedded network |
| `numaPolicy` | `NumaPolicy` | `auto` |
| `debugLogFile` | `Debug Log File` | empty (off) |
| `clearHash()` | `Clear Hash` (button) | |

Values are checked against the ranges the engine reports (`optionSpecs`)
*before* they are sent, because Stockfish silently ignores invalid values.
An invalid value throws `InvalidOptionException`.

Any option can also be set by its UCI name with `setOption(name, value)`.

## Threads and hash

More threads search faster; give the transposition table enough memory for
the time you search. A rough guide is 64–256 MiB per thread for minutes-long
analysis. The `Hash` allocation happens inside your process. If it fails (out
of memory), the call throws `EngineFatalException` and the engine restarts
with the previous size.

`NumaPolicy` controls how threads are bound to NUMA nodes on multi-socket
machines: `NumaPolicy.auto` (default), `.system`, `.hardware`, `.none` or
`NumaPolicy.custom('0-15:16-31')`.

## Tablebases

```dart
await engine.setOptions(StockfishOptions(
  syzygyPath: StockfishOptions.syzygyPathsFromList(['/tb/345', '/tb/6']),
));
```

`syzygyPathsFromList` joins directories with `;` on Windows and `:`
elsewhere. Wins and losses found in the tablebases show up as
`CentipawnScore`s near ±20000 (see `isTablebaseWin`), and `display()` shows
the WDL/DTZ probe of the current position. With `syzygy50MoveRule: false`,
positions that are winning but take more than 50 moves count as wins.

A corrupt tablebase file is reported as `EngineFatalException`. The engine
restarts; remove the file or fix `syzygyPath`.

## Chess960

```dart
await engine.setOptions(const StockfishOptions(chess960: true));
final p = Position.fromFen('bqnb1rkr/pp3ppp/3ppn2/2p5/5P2/P2P4/NPP1P1PP/BQ1BNRKR w HFhf - 2 9');
```

FENs may use X-FEN (`KQkq`) or Shredder-FEN (`HFhf`) castling rights. With
`chess960: true`, castling moves are written as the king capturing its own
rook (`e1h1`); otherwise as the usual king move (`e1g1`).

## Network file

`evalFile` loads another NNUE network. Relative names are resolved against
the directory of the native library. An invalid network makes every search
fail with `EngineCommandException` until `evalFile` points to a valid file.
`exportNet(path)` saves the current network.
