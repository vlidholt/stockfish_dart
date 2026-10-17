# 01: Architecture

## 1. Integration model: in-process FFI (decided)

Stockfish is compiled into a **shared library** (`libstockfish.so`,
`libstockfish.dylib`, `stockfish.dll`) with a small C bridge. Dart loads it
through **build hooks / native assets** (`package:hooks` +
`package:code_assets`, stable since Dart 3.10) and calls it through
`@Native` external functions. No child process and no user-installed binary
are needed.

```
┌──────────────────────────── Dart isolate ─────────────────────────────┐
│ Stockfish (public facade)                                             │
│   ├─ OptionsController      typed + raw options, range checks         │
│   ├─ SearchController       go / stop / ponderhit, handles            │
│   ├─ DiagnosticsController  d, eval, bench, speedtest, perft, …       │
│   └─ EngineSession          state machine + command queue             │
│         │                                                             │
│ UciCodec  (UciCommand → line, line → UciEvent)                        │
│         │                                                             │
│ EngineTransport (abstract)                                            │
│   ├─ FfiTransport      @Native calls + NativeCallable.listener (default)
│   ├─ ProcessTransport  external Stockfish binary via dart:io (optional)
│   └─ FakeTransport     scripted, for tests                            │
└─────────│─────────────────────────────────────────────────────────────┘
          │ sf_send(line)            ▲ on_line(stream, line) callback
┌─────────▼──────────────────────────┴──────────────────────────────────┐
│ libstockfish (C++17, built in our GitHub Actions)                     │
│   bridge/sf_bridge.cpp                                                │
│     • owns one UCI thread running UCIEngine::loop()                   │
│     • std::cin  ← BlockingLineQueue streambuf  (fed by sf_send)       │
│     • std::cout → LineStreambuf → callback(STDOUT, line)              │
│     • std::cerr → LineStreambuf → callback(STDERR, line)              │
│     • catches StockfishFatal → callback(FATAL, reason), engine poisoned│
│   Stockfish sf_19 sources + patches/ (exit() → throw, see §5)         │
│   NNUE net nn-1a298aa575a0.nnue embedded (incbin)                     │
└───────────────────────────────────────────────────────────────────────┘
```

UCI stays the internal protocol, even in-process. The bridge only swaps
stdin/stdout for in-memory queues. This keeps the Stockfish patch set small,
so upgrades stay cheap. The whole UCI codec is shared with
`ProcessTransport`, and it can be tested from recorded transcripts.

### Consequences of FFI (documented to users)

| Topic | Consequence | Mitigation |
|---|---|---|
| **One engine per process** | Stockfish redirects the process-wide `std::cout`/`std::cin` and keeps globals (tablebases, logger, large pages). `Stockfish.start()` throws `EngineAlreadyRunningException` if an FFI engine already exists in the process (across isolates). | For several engines at once, use `ProcessTransport` with an external binary (§3), or several Dart processes. |
| **Fatal errors** | Recoverable errors are patched into C++ exceptions (§5). A remaining *invariant violation* in Stockfish (a bug) would still abort the host process. | Audit the exit sites (§5); `ProcessTransport` gives full isolation where that matters. |
| **No hard kill** | A stuck engine can't be killed like a process. | `stop` is always honoured by Stockfish. `dispose()` sends `stop`+`quit` and joins the thread with a timeout. If the timeout passes, the engine is marked leaked and the process must restart to get a new engine. |
| **Captured `std::cout`** | Other C++ code in the same process that writes to `std::cout` would land in our stream. | Lines that can't be parsed are surfaced as `TextEvent`. Documented. |
| **Memory** | `Hash` is allocated inside the host process. | Documented. `Hash` range is validated, and allocation failure is a recoverable error (§5). |
| **Build command** | Hooks run on `dart run`, `dart test` and `dart build cli`, but **not** on `dart pub get`. `dart compile exe` **refuses** packages with hooks (verified on 3.13.5). | `dart build cli` everywhere; `dart run stockfish_dart:setup` warm-up step for Docker (04 §5). |

## 2. C bridge API (`native/bridge/sf_bridge.h`)

```c
// All strings UTF-8, NUL-terminated. Thread-safe unless noted.
typedef void (*sf_line_callback)(int32_t stream /*0=out,1=err,2=fatal*/, const char* line);

SF_EXPORT int32_t     sf_api_version(void);            // bridge ABI version, checked by Dart
SF_EXPORT const char* sf_engine_info(void);            // "Stockfish 19 by the Stockfish developers…"
SF_EXPORT int32_t     sf_start(sf_line_callback cb);   // 0 ok, 1 already running, 2 init failure
SF_EXPORT int32_t     sf_send(const char* line);       // enqueue one UCI line; 0 ok, 1 not running
SF_EXPORT int32_t     sf_stop_and_join(int32_t timeout_ms); // stop+quit, join UCI thread; 0 ok, 1 timeout
SF_EXPORT int32_t     sf_is_running(void);
SF_EXPORT int32_t     sf_reset(void);                  // destroy poisoned engine, ready for sf_start
SF_EXPORT void        sf_free(const char* ptr);        // if callbacks ever hand over ownership
```

- `sf_start` runs `Attacks::init()` and `Position::init()` once per process,
  constructs `UCIEngine` (with an empty `CommandLine`), and starts the UCI
  thread. `loop()` then blocks on the queued `std::cin`.
- The callback is a Dart `NativeCallable<…>.listener`. It can be called from
  any native thread and posts to the owning isolate's event loop. The line
  buffer is copied before the callback returns, so lifetimes stay simple.
- Output buffering: `LineStreambuf` emits once per `\n`, and flushes partial
  data on `std::flush` / `sync_endl`. This matches Stockfish's `sync_cout`
  locking, so lines never interleave.
- Dart side: `lib/src/native/bindings.dart` declares `@Native` functions with
  `assetId: 'package:stockfish_dart/stockfish'`. They are hand-written,
  since the surface is about 8 functions and `ffigen` would be overkill.

## 3. Optional `ProcessTransport`

Same codec, but spawns an **external** Stockfish binary (user-supplied path,
`STOCKFISH_PATH`, or `PATH`). It's useful for:

- several engines in one Dart process;
- full crash isolation on servers;
- using a different Stockfish build (dev versions, forks).

It is selected with `Stockfish.start(engine: EngineSource.process(path))`.
The library never downloads executables for this mode (see 04). Scope: v1.0
if time allows, otherwise v1.1 (open question Q8).

## 4. Package layout

```
stockfish_dart/
├── LICENSE                         GPL-3.0 text
├── README.md / CHANGELOG.md / pubspec.yaml / analysis_options.yaml
├── bin/
│   └── setup.dart                  `dart run stockfish_dart:setup`: warm hook cache + smoke test
├── hook/
│   └── build.dart                  native-assets build hook: download + verify (see 04)
├── native/
│   ├── stockfish/                  git submodule → official-stockfish/Stockfish @ sf_19
│   ├── patches/                    *.patch applied on top (exit→throw, export hooks)
│   ├── bridge/                     sf_bridge.h / sf_bridge.cpp / line_streambuf.h
│   ├── build/                      Makefile wrapper + per-platform build scripts
│   ├── manifest.json               per-target: url, sha256, size, bridge ABI version
│   └── SOURCE.md                   where the corresponding source is (GPL §6)
├── lib/
│   ├── stockfish_dart.dart         main library
│   ├── uci.dart                    low-level UCI codec
│   ├── testing.dart                FakeStockfish for users' tests
│   └── src/
│       ├── stockfish.dart          facade
│       ├── native/                 bindings.dart, ffi_transport.dart, abi_check.dart
│       ├── process/                process_transport.dart, line_splitter.dart
│       ├── session/                engine_session.dart, engine_state.dart, restart_policy.dart
│       ├── uci/                    uci_command.dart, uci_event.dart, uci_parser.dart, info_parser.dart, option_parser.dart
│       ├── model/                  position.dart, fen.dart, uci_move.dart, score.dart, wdl.dart,
│       │                           search_info.dart, search_limits.dart, search_result.dart,
│       │                           analysis_snapshot.dart, engine_identity.dart, option_spec.dart
│       ├── options/                stockfish_options.dart, numa_policy.dart, option_names.dart
│       ├── diagnostics/            board_display.dart, eval_trace.dart, perft_result.dart,
│       │                           bench_result.dart, speedtest_result.dart, compiler_info.dart
│       └── errors.dart
├── example/   doc/   test/   tool/
└── specs/
```

`.pubignore` excludes `native/stockfish/.git`, `native/build/out/`, the
`*.nnue` source copies, and CI-only scripts. The Stockfish *source* (about
300 KB compressed) **is** published, for GPL corresponding-source compliance
(see 05).

## 5. Patch set: making Stockfish embeddable

Stockfish 19 builds with `-fno-exceptions` and has **36 `exit()`/`abort()`
call sites**. The library build enables `-fexceptions` and applies the
following patches. They live in `native/patches/` and are each kept small, so
they rebase easily onto new releases.

### 5.1 Recoverable: converted to `throw StockfishFatal(reason)`

| Site (sf_19) | Trigger | Thread | Dart surfaces as |
|---|---|---|---|
| `uci.cpp` `terminate_on_critical_error` | invalid FEN / move / `go` argument / `flip` | UCI | `EngineCommandException(command, reason)`; **engine stays usable**: the position resets to startpos and the session re-sends the last good position |
| `tt.cpp:196` | `Hash` allocation failed | UCI | `InvalidOptionException` (`Hash` too large); previous TT kept if possible, otherwise engine reset |
| `memory.h:77` `report_failed_allocation` | any large allocation failure | UCI / worker | `EngineFatalException(outOfMemory)` → engine reset |
| `misc.cpp:118` | `Debug Log File` can't be opened | UCI | `InvalidOptionException` (also pre-checked in Dart) |
| `benchmark.cpp:423` | bench FEN file can't be opened | UCI | `ArgumentError` (also pre-checked in Dart) |
| `nnue/network.cpp:188` | `EvalFile` net invalid/missing at `go` | UCI | `InvalidOptionException(EvalFile)`; embedded net restored |
| `syzygy/tbprobe.cpp:284…345, 539, 1421` | corrupt / unreadable TB file, TB hash too small | UCI (init) **or worker** (lazy mapping during search) | `TablebaseException`; on a worker the search is aborted (see 5.3) |
| `thread.cpp:65` | OS refused to create a search thread | UCI | `InvalidOptionException(Threads)` |

### 5.2 Invariant violations: left fatal

`ucioption.cpp:82` (duplicate option registration), `numa.h` (internal
NUMA mapping inconsistencies, `CPU_ALLOC` failure, a destructor check),
`memory.cpp:244/262` (failure to *free* memory). These mean a Stockfish bug or
a corrupted process. They stay as `abort()`, and the docs say so.
`tool/audit_exits.dart` greps the submodule for `exit(`/`abort(` and fails CI
if the set of sites changes, so every Stockfish upgrade gets a fresh review.

### 5.3 Exceptions on worker threads

Search workers run in `Thread::idle_loop()`. The patch wraps the work body in
`try/catch (StockfishFatal&)`. A caught error is stored in a shared
`std::exception_ptr`, `threads.stop` is set, and the main thread rethrows it
on the UCI thread after `wait_for_search_finished()`. The bridge then emits
`FATAL` and marks the engine **poisoned**. The Dart session calls
`sf_stop_and_join` + `sf_reset` + `sf_start`, then replays options and
position (per `RestartPolicy`).

### 5.4 Other patches

- `main.cpp` is excluded from the library build. The bridge supplies the
  entry point.
- `UCIEngine::loop` treats a bridge-only sentinel command
  (`__bridge_shutdown`) like `quit`, so `sf_stop_and_join` can always end the
  loop.
- `engine_info()` gets the suffix `(stockfish_dart <ver>, modified)` to meet
  GPL §5(a) ("prominent notices stating that you modified it").

## 6. UCI codec

Unchanged by the transport choice.

**Commands (Dart → engine).** A sealed `UciCommand` hierarchy, each with
`toUci()`: `Uci`, `IsReady`, `UciNewGame`, `SetOption`, `PositionCommand`,
`Go`, `Stop`, `PonderHit`, `Quit`, `Display` (`d`), `Eval`, `Flip`, `Bench`,
`Speedtest`, `Compiler`, `ExportNet`, `Help`, `Raw`. Rules:

- `setoption name <Name> value <v>`; empty strings are sent as `<empty>`;
  buttons have no `value`.
- `searchmoves` always comes last in `go`.
- Lines containing `\r`/`\n` are rejected (injection guard).

**Events (engine → Dart).** `UciParser` maps lines to a sealed `UciEvent`:
`IdEvent`, `OptionEvent`, `UciOkEvent`, `ReadyOkEvent`, `InfoEvent`,
`CurrentMoveEvent`, `InfoStringEvent`, `CriticalErrorEvent`, `BestMoveEvent`
(`(none)` allowed), `UnknownOptionEvent`, `UnknownCommandEvent`,
`PerftLineEvent`, `PerftTotalEvent`, `TextEvent`. The FFI transport adds
`FatalEvent` from callback stream 2. The info parser is tolerant: unknown keys
go to `extra`, and `pv`/`string` take the rest of the line.

## 7. Session state machine

```
           start()
  [created] ──────▶ [starting] ──uciok + readyok──▶ [idle] ◀─────────────┐
                        │                            │ go        bestmove │
                        │ init failure / timeout     ▼                    │
                    [failed]                    [searching] ──stop()──▶ [stopping]
                                                     │ FATAL
                                                     ▼
                                                 [poisoned] ──reset+restart──▶ [starting]
  any ──dispose()──▶ [disposing] ──▶ [disposed]
```

- **One FIFO command queue.** Fire-and-forget commands (`setoption`,
  `position`, `ucinewgame`, `flip`, `export_net`) are followed by `isready`,
  and the call completes at `readyok`.
- **`isready` bracketing.** Diagnostic commands (`d`, `eval`, `compiler`,
  `help`, `bench`, `speedtest`, `go perft`) run synchronously on the UCI
  thread. Everything before `readyok` belongs to the command. For `bench` and
  `speedtest`, the stderr summary is collected the same way. Both streams go
  through the same ordered callback, so no extra wait is needed in FFI mode.
- **Busy rules.** Calls needing an idle engine wait behind a finite search.
  During an `infinite`/`ponder` search they throw `EngineBusyException`,
  unless the caller passes `interrupt: true`.
- **Timeouts.** Handshake 10 s, `isready` 30 s, and an optional per-operation
  timeout. On timeout: state becomes `poisoned`, then reset.

## 8. Errors

```
StockfishException (sealed)
├── EngineLoadException            native library missing / ABI mismatch / unsupported host
├── EngineAlreadyRunningException  second FFI engine in the same process
├── EngineStartException           handshake failed
├── EngineCommandException         CRITICAL ERROR (bad FEN/move/go arg); engine still usable
├── EngineFatalException           engine poisoned (OOM, TB corruption on worker, …); .reason, .recovered
├── EngineBusyException
├── EngineDisposedException
├── EngineTimeoutException
├── InvalidOptionException         unknown / wrong type / out of range / rejected by engine
├── InvalidPositionException       Dart-side structural FEN validation
├── InvalidMoveException           not UCI long algebraic
└── TablebaseException
```

Stockfish **silently ignores** out-of-range `spin` and unknown `combo` values,
so Dart validates against the advertised `optionSpecs` before sending.

## 9. Recovery (`RestartPolicy`)

`never` | `always` (default for FFI, since restarting in-process is cheap) |
`limited(n, window)`.

After `EngineCommandException` no restart is needed. The patched Stockfish
resets to the start position, and the session re-sends the last good
position. After a `FATAL`, the session resets the engine, re-applies options
in their original order, and re-sends the last good position. `crashes` stream
reports every event.

## 10. Threading

- Stockfish's own threads (the UCI thread plus `Threads` search workers) are
  native threads, so the Dart isolate never blocks. All Dart APIs are async.
- `NativeCallable.listener` delivers lines on the isolate that called
  `start()`. That isolate owns the engine. Using it from another isolate is
  not supported (the docs explain how to proxy with ports).
- A process-wide guard (an atomic flag in the bridge, not a Dart static)
  enforces the one-engine rule across isolates.
