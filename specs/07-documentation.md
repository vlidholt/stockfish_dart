# 07: Documentation

## 1. API docs (dartdoc)

- `analysis_options.yaml` adds `public_member_api_docs`,
  `comment_references`, `package_api_docs`, `unawaited_futures`,
  `discarded_futures`, `avoid_dynamic_calls`, plus `strict-casts`,
  `strict-inference` and `strict-raw-types`.
- Every public class and member's docs say:
  - what it does, in one sentence;
  - the **UCI command(s) it sends** (for example *"Sends `setoption name
    MultiPV value N`"*), so readers who know UCI can orient themselves;
  - defaults, ranges and units (ms, MB, per mille, centipawns);
  - which exceptions it throws;
  - an example snippet for every facade method and every typed option.
- Library-level docs on `stockfish_dart.dart` give a 30-line overview with
  links to the guides.
- `dart doc --validate-links` in CI, and the pana score must be 160/160 before 1.0.

## 2. README.md

1. One-paragraph pitch with badges (pub, CI, license).
2. Platform support table.
3. Install: `dart pub add stockfish_dart`. The first `dart run`/`dart test`/
   `dart build cli` downloads the verified library for your platform once.
   For production builds, use `dart build cli`, never `dart compile exe`.
4. A ready-to-copy Dockerfile (04 §5).
4. A 15-line quick start.
5. Feature list mapped to the API (short version of 03-uci-coverage.md).
6. Links to the guides.
7. Licensing (GPL-3) and a no-affiliation statement.

## 3. Guides (`doc/`)

| File | Topic |
|---|---|
| `getting-started.md` | `dart pub add`, first search, dispose |
| `native-library.md` | How the hook gets the library per platform, `user_defines` (offline, mirror, build from source), cache, troubleshooting `EngineLoadException` |
| `process-mode.md` | `EngineSource.process`: several engines, crash isolation, external binaries |
| `analysis.md` | `analyze()`, MultiPV, throttling, reading scores and WDL, perspective |
| `playing-games.md` | Game loop with `GameClock`, `newGame()`, `Move Overhead` |
| `pondering.md` | `Ponder` option + `go ponder` / `ponderhit` / `stop` pattern |
| `strength-limiting.md` | `Skill Level` vs `UCI_LimitStrength` + `UCI_Elo` |
| `tablebases.md` | Syzygy setup, probe depth/limit, 50-move rule, TB scores |
| `chess960.md` | `UCI_Chess960`, X-FEN, castling notation |
| `diagnostics.md` | perft, `d`, `eval`, bench, speedtest, compiler, export_net |
| `performance.md` | Threads, Hash, NumaPolicy, large pages, several engines |
| `error-handling.md` | Exception hierarchy, recoverable vs fatal errors, RestartPolicy, the one-engine-per-process rule |
| `testing.md` | Using `FakeStockfish` in your own tests |
| `docker.md` | The reference Dockerfile, warm-up layer, multi-arch buildx, `scratch` vs slim, no-network builds, CPU/memory limits |
| `distributing.md` | `dart build cli` (not `dart compile exe`), desktop bundles, GPL checklist |
| `licensing.md` | GPL-3 for server-side vs distributed use, modified-Stockfish notice, source locations |
| `upgrading-stockfish.md` | Maintainer runbook for new releases |

## 4. Examples (`example/`)

All are runnable with `dart run example/<file>.dart`, and CI runs each one
with short limits.

- `stockfish_dart_example.dart`: the README quick start (pub.dev shows this file).
- `best_move.dart`
- `analyze_multipv.dart`
- `play_self_game.dart`: engine vs engine with a clock and pondering.
- `limit_strength.dart`
- `perft.dart`
- `tablebase_probe.dart`
- `bench.dart`
- `raw_uci.dart`: `sendRaw` and the `uci.dart` codec.
- `docker/`: `Dockerfile`, `.dockerignore` and `bin/server.dart` (a minimal
  HTTP best-move service). CI builds it and runs it with `--network none`.

## 5. CHANGELOG

Keep-a-Changelog style. Each entry names the supported Stockfish version.
