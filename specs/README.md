# stockfish_dart: implementation plan

This directory holds the plan for `stockfish_dart`, a pure-Dart package (no
Flutter) that embeds the [Stockfish](https://stockfishchess.org) chess engine
through FFI. It runs on macOS, Windows and Linux.

> Status: **plan approved in principle (2026-10-17); Q4 and Q8 still open.**
> Nothing in `lib/` has been written yet. Target engine: **Stockfish 19**
> (tag `sf_19`, released 2026-09-05).

## As built (2026-10-17)

The implementation follows this plan with these deliberate deviations:

- **No universal binary.** Stockfish's universal build relies on executable-only
  tricks (LTO assembly rewriting, init-section renaming). Instead each target
  ships a **dispatcher** library (CPU detection, the 98 MB network, C API)
  plus one small **engine library per instruction set** (8 for x86-64, 2 for
  arm64), all bundled as code assets. The dispatcher loads the best variant
  from its own directory. See `doc/architecture.md`.
- **The network is 98.5 MB**, not 78.9 MB (an earlier size probe was wrong).
- **Toolchains:** manylinux_2_28 containers (GCC) for Linux, llvm-mingw for
  Windows x64/arm64, Apple clang for macOS (separate x64 and arm64 libraries,
  chosen by the build hook rather than fat binaries).
- **Two more Stockfish patches** were needed, both found by tests: option
  insertion order is now per `OptionsMap` (a re-created engine printed no
  options), and tablebase file handles are released before throwing. The
  Windows command-line handling and a missing `<iterator>` include are also
  patched. See `native/patches/README.md`.
- **The build hook only warns** when a package version has no prebuilt
  libraries for a target (instead of failing), so tools and fake-engine
  tests still build.
- **`ProcessTransport` shipped in 1.0** (Q8).
- **Guides** are condensed into the files listed in the README's
  Documentation section.

## Documents

| # | File | Contents |
|---|------|----------|
| 1 | [01-architecture.md](01-architecture.md) | FFI design, C bridge, Stockfish patch set, session state machine, errors |
| 2 | [02-public-api.md](02-public-api.md) | The full public Dart API with signatures and examples |
| 3 | [03-uci-coverage.md](03-uci-coverage.md) | Every Stockfish 19 command, option and output, mapped to the Dart API |
| 4 | [04-native-build-and-distribution.md](04-native-build-and-distribution.md) | GitHub Actions builds, build hook download + verify, Docker |
| 5 | [05-licensing.md](05-licensing.md) | GPL-3 duties as distributors of modified Stockfish; guidance for users |
| 6 | [06-testing-and-ci.md](06-testing-and-ci.md) | Unit, fake-engine, native and integration tests; CI matrix |
| 7 | [07-documentation.md](07-documentation.md) | Dartdoc standards, README, guides, examples |
| 8 | [08-milestones.md](08-milestones.md) | Ordered work plan with acceptance criteria and estimates |

## Goals

1. **Full coverage.** Every UCI command, all 19 engine options, and every
   Stockfish extension (`bench`, `speedtest`, `d`, `eval`, `flip`,
   `compiler`, `export_net`, `go perft`) is reachable through a typed,
   documented Dart API.
2. **Idiomatic Dart.** Uses `Future`s and `Stream`s, sealed result types,
   immutable values, and typed exceptions. Raw UCI is available but never
   required.
3. **Desktop cross-platform.** Linux x64/arm64, macOS arm64/x64, Windows
   x64/arm64.
4. **Zero manual setup, including in Docker.** The build hook downloads and
   verifies the right library automatically on the first `dart run` /
   `dart test` / `dart build cli`. A Docker image built with the reference
   Dockerfile runs with no network and no setup.
5. **Robust.** Bad input never takes down the host process. Stockfish's
   `exit()` calls for input and environment errors are patched into
   recoverable errors.
6. **Documented.** 100% dartdoc (lint-enforced), guides and runnable examples.

## Non-goals (v1)

- Web/WASM and mobile. The FFI design leaves a path to mobile later.
- A chess-rules library. Moves are UCI long-algebraic and positions are FEN.
  Validation is structural only.
- Training or tuning NNUE networks.

## Decisions

| Decision | Choice | Notes |
|---|---|---|
| Engine integration | **In-process FFI** via Dart build hooks + `@Native` | 01 §1. One engine per process. Optional `ProcessTransport` for multi-engine and isolation. |
| Robustness | **Patch Stockfish's recoverable `exit()` sites into C++ exceptions** | 36 sites audited, about 10 converted. 01 §5. |
| Library delivery | **All targets downloaded at build time by the build hook** (not on `pub get`: pub never runs hooks). Built in our GitHub Actions; SHA-256 pinned in `native/manifest.json`. | 04 §1–2. Pub package stays under 1 MB. |
| Docker | Reference multi-stage Dockerfile with a `dart run stockfish_dart:setup` warm-up layer, then `dart build cli` and `FROM scratch` | 04 §5. Must use `dart build cli`: `dart compile exe` refuses packages with hooks. |
| NNUE net | Embedded in each library (78.9 MB) | Each download is about 80 MB |
| Package name | `stockfish_dart` | |
| Validation | **Structural only** (FEN syntax, UCI move format, option ranges) | 02 §3 |
| License | **GPL-3.0-or-later**; `LICENSE` added | 05 |
| SDK | `^3.10.0` (local: 3.13.5) | Build hooks are stable from 3.10 |

## Open questions

- **Q8: `ProcessTransport` in 1.0?** It covers several engines per process
  and full crash isolation using an external Stockfish binary. Proposed:
  include it if M0–M4 land on schedule, otherwise 1.1.
- **Q4: Older Stockfish versions?** Proposed: 19 only. Since we build the
  library ourselves, users always get our pinned version.

## Major risk

Building Stockfish 19's **universal** (runtime CPU-dispatch) target as a
**shared library** is unproven. Upstream designed it for executables (LTO,
assembly section rewriting, custom net embedding). The M0 spike settles
this before any other work. Fallbacks are in 04 §3.
