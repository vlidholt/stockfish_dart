// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

/// Remaining clock time and increments, sent as `wtime`/`btime`/`winc`/
/// `binc`/`movestogo` so the engine manages its own time.
@immutable
final class GameClock {
  /// Creates a clock.
  const GameClock({
    required this.whiteTime,
    required this.blackTime,
    this.whiteIncrement = Duration.zero,
    this.blackIncrement = Duration.zero,
    this.movesToGo,
  });

  /// Time left on White's clock (`wtime`).
  final Duration whiteTime;

  /// Time left on Black's clock (`btime`).
  final Duration blackTime;

  /// White's increment per move (`winc`).
  final Duration whiteIncrement;

  /// Black's increment per move (`binc`).
  final Duration blackIncrement;

  /// Moves until the next time control (`movestogo`); null for sudden death.
  final int? movesToGo;
}

/// When a search should stop: the arguments of the UCI `go` command.
///
/// Limits can be combined (the search stops at the first one reached):
///
/// ```dart
/// const SearchLimits(depth: 20, moveTime: Duration(seconds: 5))
/// ```
@immutable
final class SearchLimits {
  /// Creates limits. With no arguments the search is infinite.
  const SearchLimits({
    this.depth,
    this.nodes,
    this.mate,
    this.moveTime,
    this.clock,
    this.infinite = false,
  }) : assert(depth == null || depth > 0, 'depth must be positive'),
       assert(nodes == null || nodes > 0, 'nodes must be positive'),
       assert(mate == null || mate > 0, 'mate must be positive');

  /// Search until stopped (`go infinite`).
  const SearchLimits.infinite() : this(infinite: true);

  /// Search to [depth] plies (`go depth`).
  const SearchLimits.depth(int depth) : this(depth: depth);

  /// Search [nodes] nodes (`go nodes`).
  const SearchLimits.nodes(int nodes) : this(nodes: nodes);

  /// Search for a mate in [moves] moves (`go mate`).
  const SearchLimits.mate(int moves) : this(mate: moves);

  /// Search for exactly [time] (`go movetime`).
  const SearchLimits.moveTime(Duration time) : this(moveTime: time);

  /// Let the engine manage its time from [clock].
  const SearchLimits.clock(GameClock clock) : this(clock: clock);

  /// Maximum depth in plies.
  final int? depth;

  /// Maximum number of nodes.
  final int? nodes;

  /// Look for a mate in this many moves.
  final int? mate;

  /// Exact time to search.
  final Duration? moveTime;

  /// Clock state for engine-managed time.
  final GameClock? clock;

  /// Search until `stop` is sent.
  final bool infinite;

  /// Whether no limit at all was given, i.e. the search only ends on `stop`.
  bool get isUnlimited =>
      infinite ||
      (depth == null &&
          nodes == null &&
          mate == null &&
          moveTime == null &&
          clock == null);

  /// The `go` arguments for these limits (without `ponder`/`searchmoves`).
  List<String> toUciArguments() => [
    if (clock case final c?) ...[
      'wtime',
      '${c.whiteTime.inMilliseconds}',
      'btime',
      '${c.blackTime.inMilliseconds}',
      if (c.whiteIncrement > Duration.zero) ...[
        'winc',
        '${c.whiteIncrement.inMilliseconds}',
      ],
      if (c.blackIncrement > Duration.zero) ...[
        'binc',
        '${c.blackIncrement.inMilliseconds}',
      ],
      if (c.movesToGo case final m?) ...['movestogo', '$m'],
    ],
    if (depth case final d?) ...['depth', '$d'],
    if (nodes case final n?) ...['nodes', '$n'],
    if (mate case final m?) ...['mate', '$m'],
    if (moveTime case final t?) ...['movetime', '${t.inMilliseconds}'],
    if (isUnlimited) 'infinite',
  ];
}
