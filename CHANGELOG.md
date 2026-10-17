# Changelog

## 0.1.0

First release, embedding Stockfish 19 (`sf_19`).

- `Stockfish` API: typed options for all 19 engine options, positions,
  searches with every `go` limit, info streams, multi-PV analysis,
  pondering, and every Stockfish extension command (`perft`, `d`, `eval`,
  `flip`, `bench`, `speedtest`, `compiler`, `export_net`, `help`).
- Embedded engine through FFI with per-CPU variants (x86-64 SSE2 to
  AVX-512 ICL, ARMv8 and ARMv8.2 dot product) selected at runtime.
- Recoverable errors: invalid input and resource failures no longer end
  the process; automatic restart with option and position replay.
- Build hook that downloads and verifies the native libraries for Linux,
  macOS and Windows (x64 and arm64), with offline, mirror and
  build-from-source options.
- `EngineSource.process` for external UCI engines.
- `FakeStockfish` for tests, `dart run stockfish_dart:setup`, Docker example.
