# Modifications to Stockfish

`native/stockfish/` contains the source of
[Stockfish 19](https://github.com/official-stockfish/Stockfish/tree/sf_19)
(tag `sf_19`, released 2026-09-05), licensed under the GNU GPL v3 or later.
It was imported unmodified (commit `960e583` of this repository) and then
changed by stockfish_dart as listed below. `stockfish_dart.patch` holds the
complete diff against the upstream release.

The modified engine identifies itself as
`Stockfish 19 (modified by stockfish_dart)`.

| Date | File(s) | Change | Why |
|---|---|---|---|
| 2026-10-17 | `src/fatal_error.h` (new), `src/misc.h` | `CommandError` and `FatalError` exceptions, `asyncFatalHandler` hook | Replace process exits when embedded as a library |
| 2026-10-17 | `src/uci.cpp` | `terminate_on_critical_error` throws; the UCI loop catches `CommandError`, prints the usual `info string CRITICAL ERROR` line and resets to the start position | Invalid FEN/moves/arguments must not end the host process |
| 2026-10-17 | `src/memory.h`, `src/tt.cpp`, `src/thread.cpp` | Allocation and thread-creation failures throw `FatalError` | Recoverable by restarting the engine |
| 2026-10-17 | `src/misc.cpp`, `src/benchmark.cpp`, `src/nnue/network.cpp` | Unopenable debug log / bench file and invalid networks throw `CommandError` | Same |
| 2026-10-17 | `src/syzygy/tbprobe.cpp` | Tablebase errors throw `FatalError`, after releasing file handles and mappings | Same |
| 2026-10-17 | `src/thread.cpp` | Errors in jobs on search threads are passed to `asyncFatalHandler` | Exceptions can't cross threads |
| 2026-10-17 | `src/nnue/network.cpp` | With `STOCKFISH_DART_BRIDGE`, the default network is provided at runtime by the dispatcher library | One copy of the 98 MB network shared by all CPU variants |
| 2026-10-17 | `src/misc.cpp` | With `STOCKFISH_DART_BRIDGE`, ignore the process command line on Windows | It belongs to the host application |
| 2026-10-17 | `src/misc.cpp` | Append ` (modified by stockfish_dart)` to the version string | GPL-3 section 5(a) notice |
| 2026-10-17 | `src/ucioption.cpp` | Count option insertion order per `OptionsMap` instead of per process | A re-created engine must still print its options |
| 2026-10-17 | `src/numa.h` | Add `#include <iterator>` | Builds with newer libc++ |

The remaining `std::exit`/`abort` calls (NUMA bookkeeping, duplicate option
registration, failures to *free* memory) guard internal invariants and are
left unchanged. CI checks that their number stays the same, so new sites are
reviewed when Stockfish is upgraded.

## Updating

1. Replace `native/stockfish/src`, `Copying.txt` and `AUTHORS` with the new
   release and commit that unmodified.
2. Re-apply `stockfish_dart.patch` (`git apply --3way`) and resolve conflicts.
3. Review new `exit()` sites, then regenerate the patch:
   `git diff <import commit> HEAD -- native/stockfish > native/patches/stockfish_dart.patch`.
