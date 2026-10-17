# Analysis

## Watching a search

`search()` returns a `SearchHandle` right away. The engine streams its
progress while it thinks:

```dart
final handle = engine.search(
  position: position,
  limits: const SearchLimits.depth(24),
);
handle.info.listen((info) {
  print('depth ${info.depth}/${info.selDepth} ${info.score} '
      'nodes ${info.nodes} nps ${info.nps} pv ${info.pv.join(' ')}');
});
handle.currentMove.listen((c) => print('searching ${c.move} (#${c.moveNumber})'));
final result = await handle.result;
```

The streams are broadcast streams, so listen before awaiting the result.
Stockfish only reports `currmove` after about three seconds of search.

## Infinite analysis with several lines

```dart
await engine.setOptions(const StockfishOptions(multiPv: 4, showWdl: true));
final analysis = engine.analyze(
  position,
  throttle: const Duration(milliseconds: 200), // at most 5 snapshots/s
);
analysis.snapshots.listen((snapshot) {
  for (final line in snapshot.lines) {
    print('#${line.multiPv} ${line.score} ${line.wdl} ${line.pv.take(8).join(' ')}');
  }
});
// ...later
final result = await analysis.stop();
```

An `AnalysisSnapshot` holds the most recent line for every `multipv` index,
best first. Lines that fall more than one ply behind the best line are
dropped. While an infinite analysis runs, other commands throw
`EngineBusyException`; stop it first, or pass `interrupt: true` to the next
`search`/`analyze` call.

## Scores

- `CentipawnScore(centipawns)`: Stockfish 19 *normalises* centipawns, so
  +100 means about a 50% chance of winning. Tablebase results appear as
  ±(20000 − plies); see `isTablebaseWin` and `tablebasePlies`.
- `MateScore(moves)`: positive when the side to move mates in that many moves.
- `bound`: `lowerBound`/`upperBound` when the search failed high or low at
  that iteration. Bounded scores are not exact.
- `Wdl(win, draw, loss)`: per mille, reported with `showWdl: true`.
  `expectedScore` gives the expected game result between 0 and 1.

Everything is from the side to move's point of view. Convert with
`score.fromWhitePerspective(position.sideToMove)`.

## Restricting the root moves

```dart
final r = await engine.bestMove(
  position,
  limits: const SearchLimits.depth(20),
  searchMoves: [UciMove('e2e4'), UciMove('d2d4')],
);
```

## No legal moves

For a checkmated or stalemated position, `bestMove` is null and
`result.terminal` is `TerminalState.checkmate` or `TerminalState.stalemate`.
