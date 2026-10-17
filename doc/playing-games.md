# Playing games

## Game loop with a clock

```dart
await engine.newGame(); // ucinewgame: clears hash and history
var game = const Position.startpos();
var clock = const GameClock(
  whiteTime: Duration(minutes: 5),
  blackTime: Duration(minutes: 5),
  whiteIncrement: Duration(seconds: 3),
  blackIncrement: Duration(seconds: 3),
);

final result = await engine.bestMove(game, limits: SearchLimits.clock(clock));
game = game.play(result.bestMove!);
```

The engine decides how long to think from the remaining time, the increments
and `movesToGo` (for classical time controls). `Move Overhead` (option
`moveOverhead`, default 10 ms) is reserved per move for communication
delays; raise it if moves arrive late over a network.

Send the whole game every time (start position plus all moves), not just the
last position. Stockfish uses the move history to detect repetitions.

## Pondering

While the opponent thinks, the engine can search the position after the
reply it expects (`ponderMove`):

```dart
await engine.setOptions(const StockfishOptions(ponder: true));

final result = await engine.bestMove(game, limits: SearchLimits.clock(clock));
game = game.play(result.bestMove!);

SearchHandle? ponder;
if (result.ponderMove case final expected?) {
  ponder = engine.search(
    position: game.play(expected),
    limits: SearchLimits.clock(clock),
    ponder: true,
  );
}

final opponentMove = await waitForOpponent();
if (ponder != null && opponentMove == result.ponderMove) {
  ponder.ponderHit();                 // keep searching, now on our clock
  final reply = await ponder.result;  // our next move
} else {
  await ponder?.stop();               // discard; search the actual position
}
```

`ponder: true` in `StockfishOptions` only tells Stockfish that pondering may
happen, which affects its time management. The ponder search itself is
`search(ponder: true)`.

## Strength

```dart
await engine.setOptions(StockfishOptions.strength(const StrengthLimit.elo(1500)));
await engine.setOptions(StockfishOptions.strength(const StrengthLimit.skill(5)));
await engine.setOptions(StockfishOptions.strength(StrengthLimit.full));
```

`StrengthLimit.elo` (1320–3190) sets `UCI_LimitStrength` and `UCI_Elo`,
which take precedence over `Skill Level`. Weakened play deliberately picks
sub-optimal moves, so give it a real time or depth limit.
