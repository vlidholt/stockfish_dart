# 03: Stockfish 19 feature coverage matrix

Taken from the `sf_19` source (`src/uci.cpp`, `src/engine.cpp`,
`src/ucioption.cpp`, `src/benchmark.cpp`). "Done" for v1 means **every row
below has a typed API, dartdoc, and at least one integration test**.
`tool/check_option_coverage.dart` enforces the options table in CI.

## 1. Standard UCI commands (GUI → engine)

| Command | Stockfish behaviour notes | Dart API |
|---|---|---|
| `uci` | Prints `id name Stockfish 19`, `id author …`, every `option …`, then `uciok` | Handshake in `Stockfish.start`; `identity`, `optionSpecs` |
| `isready` | Answers `readyok` once the UCI thread is free | `isReady()`; also used internally after every state-changing command |
| `setoption name N [value V]` | Waits for any search to finish. Unknown name → `No such option: N`. Out-of-range or invalid value is **silently ignored**. Empty string is sent as `<empty>`. | `setOptions`, `setOption`, `clearHash` |
| `ucinewgame` | Clears hash, history and thread state; can be slow with a big hash | `newGame()` |
| `position startpos [moves …]` | Invalid FEN or move → CRITICAL ERROR (upstream: `exit(1)`; our patched build: recoverable, see 01 §5) | `setPosition`, `search(position:)` |
| `position fen <fen> [moves …]` | same | same |
| `go …` (see §2) | Before searching, prints NUMA and thread-binding `info string`s | `search`, `bestMove`, `analyze` |
| `stop` | Ends search; `bestmove` follows | `stop()`, `SearchHandle.stop()` |
| `ponderhit` | Switches a ponder search to normal search | `SearchHandle.ponderHit()` |
| `quit` | Ends the UCI loop (FFI: the UCI thread is joined; process: the process exits) | `dispose()` |
| `debug`, `register` | **Not implemented by Stockfish** (prints "Unknown command") | Not exposed; documented as unsupported |

## 2. `go` parameters

| Token | Type | Dart |
|---|---|---|
| `searchmoves m1 m2 …` | moves; must come last | `search(searchMoves:)` |
| `ponder` | flag | `search(ponder: true)` |
| `wtime` / `btime` | ms | `GameClock.whiteTime` / `blackTime` |
| `winc` / `binc` | ms | `GameClock.whiteIncrement` / `blackIncrement` |
| `movestogo` | int | `GameClock.movesToGo` |
| `depth` | int | `SearchLimits.depth` |
| `nodes` | int | `SearchLimits.nodes` |
| `mate` | int (moves) | `SearchLimits.mate` |
| `movetime` | ms | `SearchLimits.moveTime` |
| `infinite` | flag | `SearchLimits.infinite()` |
| `perft` | int | `perft(depth)` (separate API; no `bestmove` is produced) |

## 3. Engine options (all 19 in Stockfish 19)

| UCI name | Type | Default | Range / values | Typed field | Notes |
|---|---|---|---|---|---|
| `Debug Log File` | string | `""` | path | `debugLogFile` | Logs all UCI I/O to a file |
| `NumaPolicy` | string | `auto` | `auto`, `system`, `hardware`, `none`, custom CPU spec | `numaPolicy` (`NumaPolicy`) | An invalid value is rejected with an `info string`, which we surface as `InvalidOptionException` |
| `Threads` | spin | 1 | 1 … max(1024, 4×HW threads) | `threads` | Echoes thread allocation as `info string` |
| `Hash` | spin | 16 | 1 … 33554432 MB (64-bit) | `hashMb` | |
| `Clear Hash` | button | | | `clearHash()` | |
| `Ponder` | check | false | | `ponder` | Tells the engine pondering is allowed (affects time use) |
| `MultiPV` | spin | 1 | 1 … 256 | `multiPv` | |
| `Skill Level` | spin | 20 | 0 … 20 | `skillLevel` / `StrengthLimit.skill` | |
| `Move Overhead` | spin | 10 | 0 … 5000 ms | `moveOverhead` | |
| `nodestime` | spin | 0 | 0 … 10000 | `nodesTime` | Nodes-as-time mode for testing |
| `UCI_Chess960` | check | false | | `chess960` | Changes castling move notation (king takes rook) |
| `UCI_LimitStrength` | check | false | | `limitStrength` / `StrengthLimit.elo` | Overrides `Skill Level` |
| `UCI_Elo` | spin | 1320 | 1320 … 3190 | `elo` | |
| `UCI_ShowWDL` | check | false | | `showWdl` | Adds `wdl W D L` to info |
| `SyzygyPath` | string | `""` | path list | `syzygyPath` / `syzygyPaths` | |
| `SyzygyProbeDepth` | spin | 1 | 1 … 100 | `syzygyProbeDepth` | |
| `Syzygy50MoveRule` | check | true | | `syzygy50MoveRule` | |
| `SyzygyProbeLimit` | spin | 7 | 0 … 7 | `syzygyProbeLimit` | |
| `EvalFile` | string | `nn-1a298aa575a0.nnue` | path | `evalFile` | The default net is embedded in the library |

> Removed in Stockfish 19: `EvalFileSmall` (the secondary net was retired
> in SFNNv16). If Q4 extends support to older versions, typed fields for
> version-specific options become nullable, and setting one that the
> running engine does not advertise throws `InvalidOptionException`.

## 4. Stockfish-specific commands

| Command | Output stream | Bracketing | Dart |
|---|---|---|---|
| `d` | stdout: ASCII board, `Fen:`, `Key:`, `Checkers:`, optional `Tablebases WDL/DTZ:` | `isready` | `display()` → `BoardDisplay` |
| `eval` | stdout: NNUE trace table + `NNUE evaluation …` + `Final evaluation …` | `isready` | `evaluate()` → `EvalTrace` |
| `flip` | none; may CRITICAL ERROR | `isready` | `flip()` |
| `bench [hash] [threads] [limit] [fenFile] [limitType]` | info lines on stdout; per-position and summary on **stderr** | `isready` + stderr wait | `bench(BenchConfig)` → `BenchResult` |
| `speedtest [threads] [hash] [seconds]` | progress and summary on **stderr** | `isready` + stderr wait | `speedtest(SpeedtestConfig)` → `SpeedtestResult` |
| `compiler` | stdout: compiler/build info | `isready` | `compilerInfo()` |
| `export_net [file]` | `info string` on success/failure | `isready` | `exportNet([path])` |
| `help` / `license` / `--help` / `--license` | stdout text | `isready` | `help()` |
| `go perft N` | stdout: `move: count` per root move, then `Nodes searched: N` | `isready` | `perft(N)` → `PerftResult` |
| `# comment` | ignored by the engine | | not exposed |

## 5. Engine → GUI output

| Output | Parsed into |
|---|---|
| `id name …` / `id author …` | `EngineIdentity(name, author, version)`, with version parsed from `Stockfish 19` / `Stockfish dev-20261017-effdc3fd` |
| `option name … type … default … min … max … var …` | `UciOptionSpec` subclasses |
| `uciok`, `readyok` | handshake / sync completions |
| `info depth seldepth multipv score {cp N\|mate N} [lowerbound\|upperbound] [wdl W D L] nodes nps hashfull tbhits time pv …` | `SearchInfo` |
| `info depth N score {mate 0\|cp 0}` (no legal moves) | `SearchInfo` + `SearchResult.terminal` |
| `info depth N currmove M currmovenumber K` | `CurrentMoveInfo` |
| `info string …` | `infoStrings`, `SearchHandle.infoStrings` |
| `info string CRITICAL ERROR: Command `X` failed. Reason: R` | `EngineCommandException(command: X, reason: R)`; engine stays usable |
| bridge `FATAL` callback (patched `exit()` sites) | `EngineFatalException`; engine reset per `RestartPolicy` |
| `info string NNUE evaluation using …` / network verification errors | `infoStrings`; a fatal net error is an `EngineStartException` |
| `bestmove M [ponder P]`, `bestmove (none)` | `SearchResult` |
| `No such option: N` | `InvalidOptionException` |
| `Unknown command: '…'` | `UnsupportedCommandException` (only reachable through `sendRaw`) |

## 6. Behaviours to document (not separate APIs)

- Scores are from the side to move. Centipawns are WDL-normalised.
  Tablebase scores show as cp ±(20000 − plies).
- `currmove` lines appear only after about 3 seconds of search.
- With `MultiPV > 1`, info lines arrive per PV index. `analyze()` aggregates them.
- Chess960 castling is written king→rook square (`e1h1`) when
  `UCI_Chess960=true`, and king two squares (`e1g1`) otherwise.
- `Ponder=true` only tells the engine it may ponder. Pondering itself is
  `go ponder` plus `ponderhit` or `stop`. The guide `doc/pondering.md` shows
  the full game-loop pattern.
- Time management: `Move Overhead` and `nodestime`; how `movestogo` and
  increments interact.
