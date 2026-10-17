# 08: Milestones

Each milestone ends with green CI on all matrix hosts. Estimates assume one
developer. M0 is a **go/no-go gate**: if the shared-library build of the
universal target fails, we pick a fallback from 04 §3 before going further.

## M0: Native feasibility spike (4–6 days)

- [ ] Add `native/stockfish` submodule at `sf_19`; set up the
      `native/build/` wrapper Makefile.
- [ ] Build Stockfish as a **shared library** with `-fPIC -fexceptions`
      for `x86-64-universal` and `arm64-universal` on Linux, then macOS fat
      dylib, then Windows (MSYS2 clang) x64/arm64. Record sizes and whether
      the universal runtime dispatch and the embedded net survive.
- [ ] Minimal `sf_bridge.cpp` (stdin/stdout streambufs, UCI thread,
      callback). Run `uci` / `go depth 10` from a C harness on all 5 targets.
- [ ] Prototype the `exit()` → exception patch for `terminate_on_critical_error`
      and one worker-thread site (Syzygy). Prove the engine survives in-process.
- [ ] Minimal `hook/build.dart` with `@Native` bindings; `dart run` and
      `dart build cli` load the library on all 3 OSes.
- [ ] **Docker proof:** the hook downloads the library in a `dart:stable`
      build stage, `dart build cli` bundles it, and the binary runs on
      `FROM scratch` + `/runtime` with `--network none` (glibc-only
      dependency check), on amd64 and arm64.
- [ ] `tool/capture_fixtures.dart`: record SF19 transcripts (`uci`, MultiPV +
      WDL search, `go mate`, mated/stalemated, `currmove`, `d` ± TB, `eval`,
      `compiler`, `help`, perft divide, `bench`, short `speedtest`, CRITICAL
      ERRORs, unknown option/command) into `test/fixtures/sf19/`.

**Done when:** a written spike report (`specs/spike-report.md`) with a
go/fallback decision per target, and the size-budget verdict.

## M1: Groundwork, UCI codec and models (4 days)

- [ ] `pubspec.yaml` (SDK `^3.10.0`; deps `hooks`, `code_assets`, `crypto`,
      `meta`, `collection`, `path`; dev deps `test`, `lints`, `coverage`); strict `analysis_options.yaml`; remove the template
      `Awesome`; SPDX headers + `tool/check_headers.dart`.
- [ ] `UciCommand` hierarchy + injection guard; `UciParser`, `InfoParser`,
      `OptionSpecParser`.
- [ ] Models: `UciMove`, `Position` + FEN validator, `Score`, `Wdl`,
      `SearchInfo`, `CurrentMoveInfo`, `SearchLimits`, `GameClock`,
      `SearchResult`, `UciOptionSpec`.
- [ ] Unit + fixture-replay tests; CI skeleton (unit tests on 6 hosts).

**Done when:** every fixture line parses as expected, with ≥ 95% coverage on
`uci/` and `model/`.

## M2: Native library: production quality (6–8 days)

- [ ] Full patch set (01 §5): all recoverable sites converted, worker-thread
      exception propagation, `__bridge_shutdown`, modified-version
      `engine_info`; `native/patches/README.md`.
- [ ] `tool/audit_exits.dart` with the committed site list.
- [ ] Bridge: ABI versioning, process-wide single-engine guard,
      `sf_reset`, join with timeout.
- [ ] `native.yml`: 5 build jobs, C smoke harness, artifacts,
      `build-info.json`, release job with source tarball, manifest PR.
- [ ] `hook/build.dart`: download + verify + shared-dir cache / `library_path` /
      mirror / `build_from_source` / `allow_download`; hook tests with a local
      HTTP server.
- [ ] `bin/setup.dart` (`dart run stockfish_dart:setup`): warm-up + smoke test.

**Done when:** `native-v0.1.0` is released from CI, and a fresh machine on
each OS gets a working engine through `dart pub get` + `dart run`.

## M3: Transport, session and facade (5–6 days)

- [ ] `FfiTransport` (`NativeCallable.listener`, ABI check), `FakeTransport` /
      public `FakeStockfish`.
- [ ] `EngineSession`: state machine, FIFO queue, `isready` bracketing,
      busy rules, timeouts, recoverable vs fatal handling, `RestartPolicy`
      replay.
- [ ] Facade: `start`, `withTransport`, `identity`, `optionSpecs`,
      `dispose`, `Finalizer`, `failures`, raw streams, `sendRaw`.
- [ ] `StockfishOptions` (all 19 options), `NumaPolicy`, `StrengthLimit`,
      syzygy helpers, ordered diff-apply, validation against specs; raw
      `setOption`; `clearHash`; `newGame`; `setPosition`; `isReady`.
- [ ] Session tests (06 §3).

## M4: Search and Stockfish extensions (4–5 days)

- [ ] `search` / `SearchHandle`, `bestMove`, `analyze` / `AnalysisSnapshot`,
      ponder flow.
- [ ] `perft`, `display`, `evaluate`, `flip`, `bench`, `speedtest`,
      `compilerInfo`, `exportNet`, `help` with parsers and progress callbacks.
- [ ] Integration tests (06 §4), including recoverable-error and restart-soak
      suites, and Syzygy tests with cached 3–4-piece tables.

**Done when:** every row in 03-uci-coverage.md is ticked.

## M5: `ProcessTransport` (2 days; may slip to 1.1, see Q8)

- [ ] `ProcessTransport` (line splitting, stderr, kill, EOF self-termination),
      `EngineSource.process`, resolution (path → `STOCKFISH_PATH` → `PATH`).
- [ ] `process`-tagged integration tests.

## M6: Docs, examples and release (3–4 days)

- [ ] Dartdoc on 100% of the public API; `dart doc --validate-links`.
- [ ] README, `doc/` guides, examples (run in CI); `dart build cli` end to end.
- [ ] `example/docker/` (Dockerfile + tiny server) and the CI Docker job (06 §5 step 9).
- [ ] `publish.yml`: verify every manifest URL + hash resolves → publish via OIDC.
- [ ] pana 160/160; CHANGELOG `1.0.0`; tag `native-v1.0.0` then `v1.0.0`.

**Done when:** published to pub.dev and installable on all targets.

## Later (post-1.0, not committed)

- Android/iOS: the FFI design carries over. It needs mobile build jobs and
  hook targets, and iOS needs a static library/XCFramework.
- `dartchess` interop library (SAN PVs, full legality checks).
- `StockfishPool` across several `ProcessTransport` engines.
- WASM/web, with a transport over Stockfish's WASM build.
- Developer-ID signing/notarisation of the macOS dylib; Authenticode for Windows.

**Total:** about 28–35 working days to 1.0. FFI adds about 8–10 days over the
process-only design, mostly in M0 and M2.
