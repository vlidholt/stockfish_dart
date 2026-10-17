# Testing your code

`package:stockfish_dart/testing.dart` provides `FakeStockfish`, a scripted
transport that speaks enough UCI for `Stockfish.withTransport`. Your tests
then run without the native library, fast and deterministic.

```dart
import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:stockfish_dart/testing.dart';
import 'package:test/test.dart';

void main() {
  test('plays the engine move', () async {
    final fake = FakeStockfish()
      ..onGo = (go) => [
            'info depth 12 score cp 35 pv g1f3 b8c6',
            'bestmove g1f3 ponder b8c6',
          ];
    final engine = await Stockfish.withTransport(fake);

    final r = await engine.bestMove(
      const Position.startpos(),
      limits: const SearchLimits.depth(12),
    );

    expect(r.bestMove, UciMove('g1f3'));
    expect(fake.received, contains('go depth 12'));
    await engine.dispose();
  });
}
```

What the fake does:

- answers `uci` with Stockfish 19's identity and full option list, and
  `isready` with `readyok`;
- records `setoption` values (`fake.options`) and rejects unknown options
  like Stockfish;
- `validatePosition` lets you reject positions with a `CRITICAL ERROR`;
- `onGo` produces search output. Infinite and ponder searches hold back
  their `bestmove` until `stop`;
- `respondTo(prefix, lines)` scripts any other command (`d`, `eval`, ...);
- `crash(reason)` simulates a fatal engine error, to test recovery;
- `received` lists every command sent.

To test against the real engine, use `Stockfish.start()` in tests tagged as
integration tests, and keep them in **one test file**. `dart test` runs test
files as isolates of one process, and only one embedded engine can run per
process.
