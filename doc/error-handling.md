# Errors and recovery

Every exception thrown by the package extends the sealed class
`StockfishException`:

| Exception | When | Engine afterwards |
|---|---|---|
| `InvalidPositionException` | `Position.fromFen` with a malformed FEN (checked in Dart) | unaffected |
| `InvalidMoveException` | `UciMove` with text that isn't UCI notation | unaffected |
| `InvalidOptionException` | unknown option, wrong type, out of range | unaffected (nothing sent) |
| `EngineCommandException` | the engine rejected a command: illegal move, illegal position, bad argument, unopenable file | **usable**; the last good position is restored |
| `EngineFatalException` | out of memory, corrupt tablebase, thread creation failure, engine exit | restarted (see below); `restarted` says whether |
| `EngineBusyException` | a command was issued during an infinite or ponder search | unaffected |
| `EngineTimeoutException` | the engine did not answer in time | restarted |
| `EngineLoadException` | the native library is missing or incompatible | not started |
| `EngineAlreadyRunningException` | a second embedded engine in the same process | not started |
| `EngineStartException` | the UCI handshake failed | not started |
| `EngineDisposedException` | used after `dispose()` | disposed |

## Why the host process survives

Upstream Stockfish calls `exit()` when it meets invalid input or runs out of
resources. That's fine for a standalone program, but fatal for a library
running inside your process. The embedded build patches those call sites into
C++ exceptions (see [native/patches](../native/patches/README.md)):

- **Command errors** are caught by the UCI loop, reported as
  `info string CRITICAL ERROR ...`, and the engine continues.
- **Fatal errors** end the engine's UCI thread (or abort the search on a
  search thread). The bridge reports them, and the session starts a fresh
  engine in the same process.

A few `exit()` calls remain. They guard internal invariants (bugs), not
input. If you need complete isolation from any engine failure, run Stockfish
as a separate process with `EngineSource.process`.

## Restart policy

```dart
final engine = await Stockfish.start(
  restartPolicy: RestartPolicy.limited(3, const Duration(minutes: 1)),
);
engine.failures.listen((e) => log.warning('stockfish: $e'));
```

- `RestartPolicy.always` (default): restart after every fatal error.
- `RestartPolicy.limited(n, window)`: at most `n` restarts within `window`.
- `RestartPolicy.never`: the engine stays in `EngineState.failed`.

After a restart, every option set through the API is applied again in its
original order, and the last good position is sent again. The operation
that was running fails with `EngineFatalException(restarted: true)`;
operations queued behind it run normally.

## One embedded engine per process

Stockfish redirects the process's standard streams and keeps global state,
so `Stockfish.start()` refuses to create a second embedded engine
(`EngineAlreadyRunningException`) until the first is disposed. For parallel
engines, use `EngineSource.process(path: ...)` with a Stockfish executable,
or separate processes.
