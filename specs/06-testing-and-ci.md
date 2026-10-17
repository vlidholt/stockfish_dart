# 06: Testing and CI

## 1. Test layers

| Layer | Location | Needs native lib | Runs on |
|---|---|---|---|
| Unit: parsers, codec, models, validation | `test/unit/` | no | every CI job + locally |
| Session: state machine with `FakeTransport` | `test/session/` | no | every CI job |
| Fixture replay: real SF19 transcripts → parser | `test/unit/fixtures_test.dart` | no | every CI job |
| Native smoke: C harness against the bridge | `native/test/` | built in job | `native.yml` per target |
| Integration: embedded engine (FFI) | `test/integration/` (`@Tags(['integration'])`) | yes (hook) | CI platform matrix |
| Integration: `ProcessTransport` | `test/integration/process/` (`@Tags(['process'])`) | official binary | Linux + macOS + Windows x64 |
| Build hook: download / cache hit / override / mirror / hash mismatch / `allow_download: false` | `test/hook/` | local HTTP server with fake assets | every CI job |
| Docker end to end | `example/docker/` | hook download | `ubuntu-24.04` + `ubuntu-24.04-arm` |

`dart_test.yaml` defines the tags. Integration tests run whenever the hook
can supply a library. Each FFI integration test file runs in its **own test
process** (`dart test --concurrency=1` plus separate suites), because only one
embedded engine may exist per process.

## 2. Unit test inventory (non-exhaustive)

- **Info parser:** every field; `lowerbound`/`upperbound`; `wdl`; `mate 0`;
  `mate -3`; TB cp scores (±20000 − n); `currmove` lines; unknown keys go to
  `extra`; `string` swallowing the rest; extra whitespace; CRLF.
- **Option parser:** every option line from the SF19 `uci` transcript, and
  names with spaces; `combo` with `var`s; `string` default `<empty>`.
- **Command serialisation:** `go` field order with `searchmoves` last;
  `<empty>`; buttons without `value`; newline injection rejected.
- **FEN validator:** a table of about 40 valid and invalid FENs, including
  Chess960 X-FEN/Shredder castling.
- **UciMove:** promotions, null move, case handling.
- **Score:** perspective flipping, ordering (`compareTo`: mate > TB > cp).
- **Diagnostics parsers:** `d`, `eval`, `bench`, `speedtest`, `compiler`,
  perft divide, all from fixtures.
- **Manifest:** every supported `Abi` maps to exactly one asset.
- **Option coverage:** every option in the SF19 `uci` fixture maps to a
  `StockfishOptions` field (same check as `tool/check_option_coverage.dart`).

## 3. Session tests (`FakeTransport`)

- Handshake success, timeout, non-UCI binary (no `uciok`).
- `setOptions` diffing and ordering (`NumaPolicy` → `Threads` → `Hash` → rest).
- Out-of-range values rejected in Dart; `No such option` turned into an exception.
- Queueing: two `bestMove` calls are serialised; `setPosition` waits for a finite search.
- `EngineBusyException` while infinite or pondering; `interrupt: true` path.
- `stop()` when idle is a no-op; `stop()` races with a natural `bestmove`.
- Ponder flow: `go ponder` → `ponderhit` → `bestmove`; and `go ponder` →
  `stop` → `bestmove`, which is discarded per UCI convention.
- CRITICAL ERROR line → `EngineCommandException`; the session re-sends the
  last good position and the engine stays `idle`.
- `FATAL` callback mid-search → `EngineFatalException`; reset + restart
  re-applies options (in order) and the last good position; `RestartPolicy.never`
  leaves the engine `poisoned`.
- `dispose()` during a search; double `dispose()`; use after dispose.
- `analyze()` aggregation with interleaved multipv lines and depth pruning.

## 4. Integration tests (real Stockfish 19)

- Handshake: `identity.name == 'Stockfish 19'`; `optionSpecs` contains all 19 options.
- **Every option** is set to a non-default value and read back through the
  `Debug Log File` transcript or its effect (Threads → info string;
  MultiPV → multiple lines; ShowWDL → `wdl` present).
- `bestMove` at depth 10 from startpos returns a legal move.
- Mate-in-2 puzzle with `SearchLimits.mate(2)` → `MateScore(2)`.
- Checkmated position → `bestMove == null`, `terminal == checkmate`;
  stalemate likewise.
- Perft: startpos d5 = 4,865,609; Kiwipete d4 = 4,085,603; divide sums
  match the total.
- Chess960 position: castling as king-takes-rook with `chess960: true`.
- Syzygy: CI caches the 3- and 4-piece tables (about 1 MB from
  tablebase.lichess.ovh). A KQvK position gives TB scores; `d` shows
  `Tablebases WDL`.
- Pondering end to end with real clocks.
- `analyze()` with MultiPV 3 for 2 s → snapshots with 3 lines and
  increasing depth.
- Strength limit: `StrengthLimit.elo(1500)` is accepted and searches.
- Recoverable errors, each followed by a successful `bestMove` in the
  **same host process**: illegal move, malformed-but-structurally-valid FEN,
  bad `go` argument via `sendRaw(unsafe: true)`, `Hash` larger than physical
  RAM (allocation failure), unopenable `Debug Log File`, a corrupt Syzygy
  file (truncated copy) probed *during search* on a worker thread.
- `display()`, `evaluate()`, `flip()`, `compilerInfo()`, `help()`.
- `exportNet()` to a temp file → file exists and name matches `nn-*.nnue`.
- `bench(BenchConfig(limit: 6))` → nodes > 0.
- `speedtest(SpeedtestConfig(threads: 1, hashMb: 16, duration: 1s))` → nps > 0.
- One-engine rule: a second `Stockfish.start()` (also from another isolate)
  throws `EngineAlreadyRunningException`; after `dispose()` a new start works.
- Restart soak: 50 fatal → reset → restart cycles; RSS growth stays under a
  bound (catches leaks in the reset path); no stray native threads.
- `dispose()` during a deep search returns within the grace period.
- `ProcessTransport` (tag `process`): 3 external engines in parallel; the
  engine process exits when the Dart test process is SIGKILLed.
- `dart build cli` of `example/best_move.dart` → run the bundled output on
  each OS (checks that native assets are bundled and loadable).

## 5. CI (GitHub Actions)

```yaml
matrix:
  include:
    - { os: ubuntu-24.04,         arch: x64   }
    - { os: ubuntu-24.04-arm,     arch: arm64 }
    - { os: macos-15,             arch: arm64 }
    - { os: macos-15-intel,       arch: x64   }   # or whatever Intel image is still offered
    - { os: windows-2025,         arch: x64   }
    - { os: windows-11-arm,       arch: arm64 }
  sdk: [3.10.0, stable]
```

Steps:

1. `dart pub get`
2. `dart format --output=none --set-exit-if-changed .`
3. `dart analyze --fatal-infos`
4. `dart run tool/check_headers.dart`
5. `dart test` (unit + session + fixtures + hook)
6. Library source: on PRs that touch `native/`, use the artifact from the
   same run's `native.yml` jobs (`user_defines.library_path`). Otherwise let
   the hook download the released asset (cached by manifest hash).
7. `dart test --tags integration` (and `process` where applicable)
8. On ubuntu stable only: `dart doc --validate-links`, coverage via
   `package:coverage` (target ≥ 90% lines for `lib/src`), and
   `dart pub publish --dry-run` (asserts the archive is under 2 MB, so no
   binary sneaks in).
9. **Docker job:** `docker buildx build --platform linux/amd64` (and arm64 on
   the arm runner) of `example/docker/Dockerfile`. It runs the image with
   `--network none` and asserts a best move is printed. This proves the
   runtime image needs no network or setup, and that `FROM scratch` +
   `/runtime` has every library `libstockfish` needs. A second build checks
   that a source-only change does not re-download (the warm-up layer is
   cached).

`native.yml` (see 04 §3) builds and smoke-tests the libraries for all 5
targets. A nightly job rebuilds against Stockfish `master` with our patches
in **allow-failure** mode. That gives early warning of patch conflicts, new
`exit()` sites and protocol drift.

Publishing: a tag `v*` triggers `dart pub publish` through pub.dev's
automated publishing with GitHub OIDC.
