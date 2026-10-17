# How it works

```
 your Dart code
      │  Stockfish (typed API)
      ▼
 EngineSession ── command queue, isready bracketing, busy rules,
      │           error mapping, restart + replay
      ▼
 FfiTransport ── @Native calls; output arrives through a
      │          NativeCallable.listener callback
      ▼
 stockfish (dispatcher library)
   • embeds the 98 MB NNUE network once
   • detects CPU features, loads the best engine library from its own directory
   • copies output lines for Dart; C API: sf_load/sf_start/sf_send/sf_stop/...
      │
      ▼
 stockfish_<variant> (engine library, one per instruction set)
   • Stockfish 19 sources (patched, see native/patches)
   • engine bridge: runs Stockfish's own UCI loop on a dedicated thread;
     std::cin reads from a line queue, std::cout/std::cerr lines go to a callback
```

Stockfish keeps speaking UCI internally, so the C API is tiny and the
patches to Stockfish stay small. The same `EngineSession` also drives external
engines through `ProcessTransport` (`EngineSource.process`).

## Command flow

Commands are queued and run one at a time. Commands without an answer
(`setoption`, `position`, `ucinewgame`, `flip`...) are followed by `isready`.
The call completes on `readyok`, which also surfaces `CRITICAL ERROR` lines
and unknown options as exceptions. Stockfish runs its diagnostic commands
synchronously on the UCI thread, so everything printed before `readyok`
belongs to the command. That's how `d`, `eval`, `perft`, `bench` and the
other extensions are parsed without per-command terminators.

Searches hold the queue until `bestmove`. `stop` and `ponderhit` bypass the
queue. Commands issued during an infinite or ponder search throw
`EngineBusyException`, because they would otherwise wait forever.

## Errors

Upstream Stockfish exits the process on invalid input and resource failures.
The embedded build throws `CommandError` (the UCI loop reports it and
continues) or `FatalError` (the UCI thread ends and the bridge reports it)
instead. Errors on search threads go through a handler, because exceptions
can't cross threads. On a fatal error the session stops the engine, starts a
new one in the same process and re-applies options and position.

## Distribution

The native libraries are built by this repository's `native` workflow for
six targets. Linux builds run in `manylinux_2_28` containers, so they work
with glibc 2.28 and newer and link the C++ runtime statically; Windows builds
use llvm-mingw; macOS builds use Apple clang. The libraries are published as
GitHub release assets. `native/manifest.json` (shipped in the pub package)
records each file's SHA-256. The build hook downloads the files for the
target being built, verifies them, and hands them to the Dart build system
as code assets, which `dart build cli` copies into `bundle/lib/`.
