# 02: Public API

All signatures are proposals. Every public member gets dartdoc (see
07-documentation.md). The examples use only `package:stockfish_dart/stockfish_dart.dart`.

## 1. Quick tour

```dart
import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main() async {
  final engine = await Stockfish.start(
    options: const StockfishOptions(threads: 4, hashMb: 256),
  );

  // One-shot best move.
  final result = await engine.bestMove(
    Position.startpos(moves: [UciMove('e2e4'), UciMove('e7e5')]),
    limits: SearchLimits(moveTime: Duration(seconds: 1)),
  );
  print('${result.bestMove} (ponder ${result.ponderMove}) '
        'score ${result.finalInfo?.score}');

  // Live multi-PV analysis.
  await engine.setOptions(engine.options.copyWith(multiPv: 3));
  final analysis = engine.analyze(Position.fromFen('r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3'));
  await for (final snapshot in analysis.snapshots.take(20)) {
    for (final line in snapshot.lines) {
      print('#${line.multiPv} d${line.depth} ${line.score} ${line.pv.take(5).join(' ')}');
    }
  }
  await analysis.stop();

  await engine.dispose();
}
```

## 2. `Stockfish` (facade)

```dart
final class Stockfish {
  /// Starts the engine, runs the `uci`/`isready` handshake and applies
  /// [options]. By default this uses the embedded native library (FFI); only
  /// one embedded engine may exist per process.
  /// Throws [EngineLoadException], [EngineAlreadyRunningException] or
  /// [EngineStartException].
  static Future<Stockfish> start({
    EngineSource engine = const EngineSource.embedded(),
    StockfishOptions options = const StockfishOptions(),
    RestartPolicy restartPolicy = RestartPolicy.always,
    Duration handshakeTimeout = const Duration(seconds: 10),
    Duration readyTimeout = const Duration(seconds: 30),
    void Function(UciTrafficEntry)? onTraffic, // debug hook: every line in/out
  });

  /// For tests or custom transports (e.g. remote engine over a socket).
  static Future<Stockfish> withTransport(EngineTransport transport, {…same named args…});

  /// True if an embedded engine is already running in this process.
  static bool get isEmbeddedEngineRunning;

  // ── Identity & capabilities ─────────────────────────────────────────
  EngineIdentity get identity;                 // id name / id author, parsed version
  Map<String, UciOptionSpec> get optionSpecs;  // as advertised by `uci`, case-insensitive keys
  EngineSource get source;

  // ── State ───────────────────────────────────────────────────────────
  EngineState get state;
  Stream<EngineState> get stateChanges;
  /// Every engine failure: recoverable command errors and fatal resets.
  Stream<StockfishException> get failures;
  bool get isDisposed;

  // ── Options ─────────────────────────────────────────────────────────
  StockfishOptions get options;                           // last applied
  Future<void> setOptions(StockfishOptions options);      // sends only changed fields
  Future<void> setOption(String name, Object? value);     // raw, validated against optionSpecs
  Future<void> clearHash();                               // button "Clear Hash"

  // ── Game lifecycle ──────────────────────────────────────────────────
  Future<void> newGame();                                 // ucinewgame + isready
  Future<void> setPosition(Position position);            // position … + isready
  Position? get position;                                 // last applied
  Future<void> isReady();                                 // explicit sync point

  // ── Search ──────────────────────────────────────────────────────────
  /// Starts a search and returns a live handle at once.
  SearchHandle search({
    Position? position,                 // if given, sent before `go`
    SearchLimits limits = const SearchLimits.infinite(),
    List<UciMove>? searchMoves,
    bool ponder = false,
    bool interrupt = false,             // stop a running search first
  });

  /// Convenience: search(...) and await its result.
  Future<SearchResult> bestMove(Position position, {required SearchLimits limits, List<UciMove>? searchMoves});

  /// Convenience: infinite search with aggregated multi-PV snapshots.
  Analysis analyze(Position position, {Duration? throttle, List<UciMove>? searchMoves});

  /// Stops the active search (no-op if idle). Completes once `bestmove` arrives.
  Future<SearchResult?> stop();

  /// The active search, if any.
  SearchHandle? get activeSearch;

  // ── Stockfish extensions ────────────────────────────────────────────
  Future<PerftResult> perft(int depth, {Position? position});
  Future<BoardDisplay> display({Position? position});       // `d`
  Future<EvalTrace> evaluate({Position? position});         // `eval`
  Future<void> flip();                                      // `flip`
  Future<BenchResult> bench([BenchConfig config = const BenchConfig()]);
  Future<SpeedtestResult> speedtest([SpeedtestConfig config = const SpeedtestConfig()]);
  Future<CompilerInfo> compilerInfo();                      // `compiler`
  Future<void> exportNet([String? filePath]);               // `export_net`
  Future<String> help();                                    // `help` / `license`

  // ── Raw access ──────────────────────────────────────────────────────
  Stream<String> get rawOutput;                    // every stdout line (broadcast)
  Stream<String> get rawErrorOutput;               // every stderr line (broadcast)
  Stream<String> get infoStrings;                  // `info string …` payloads
  /// Sends a raw line through the queue. Lines that would change tracked
  /// state (`setoption`, `position`, `go`) are rejected unless
  /// [unsafe] is true; this keeps the facade's bookkeeping correct.
  Future<List<String>> sendRaw(String line, {bool unsafe = false, bool awaitReady = true});

  // ── Shutdown ────────────────────────────────────────────────────────
  Future<void> dispose({Duration gracePeriod = const Duration(seconds: 2)});
}
```

## 3. Positions and moves

```dart
/// A UCI move in long algebraic notation: `e2e4`, `e7e8q`, `e1g1`
/// (standard castling) or `e1h1` (Chess960 castling), or `0000` (null move).
extension type const UciMove._(String value) {
  factory UciMove(String value);         // validates /^([a-h][1-8]){2}[qrbn]?$|^0000$/
  static UciMove? tryParse(String value);
  String get from; String get to; PieceKind? get promotion;
}

/// FEN plus a move list: what `position` sends.
final class Position {
  const Position.startpos({List<UciMove> moves = const []});
  factory Position.fromFen(String fen, {List<UciMove> moves = const []}); // structural validation
  static const standardStartFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  String? get fen;                 // null for startpos
  List<UciMove> get moves;
  bool get isStartpos;
  Position play(UciMove move);     // returns a copy with move appended
  Position playAll(Iterable<UciMove> moves);
  /// Side to move after the move list, derived from the FEN + parity, so it
  /// needs no move generator. Used to orient scores.
  Side get sideToMove;
  String toUci();                  // "startpos moves e2e4" / "fen … moves …"
}

enum Side { white, black }
```

`Position.fromFen` validation is structural only (open question Q3 asks
whether to go further):

- six fields; field 5 and 6 are non-negative integers;
- 8 ranks, each summing to 8 squares; only `pnbrqkPNBRQK1-8` chars;
- exactly one king per side; no pawns on ranks 1 or 8;
- side-to-move `w|b`; castling `-` or a subset of `KQkq` or Shredder/X-FEN
  file letters (`A-Ha-h`) for Chess960;
- en-passant `-` or a square on rank 3 or 6.

Anything that fails throws `InvalidPositionException`. Positions that are
illegal but well-formed (for example, side not to move is in check) reach the
engine. Stockfish 19 rejects them with `CRITICAL ERROR`. Our patched build
turns that into a recoverable error instead of `exit(1)`, so the call throws
`EngineCommandException(reason)` and the engine stays usable at the last
good position.

## 4. Search limits

```dart
final class SearchLimits {
  const SearchLimits({
    this.depth,              // go depth
    this.nodes,              // go nodes
    this.mate,               // go mate  (search for mate in N moves)
    this.moveTime,           // go movetime (Duration → ms)
    this.clock,              // wtime/btime/winc/binc/movestogo
    this.infinite = false,   // go infinite
  });
  const SearchLimits.infinite();
  const SearchLimits.depth(int depth);
  const SearchLimits.nodes(int nodes);
  const SearchLimits.mate(int moves);
  SearchLimits.moveTime(Duration d);
  const SearchLimits.clock(GameClock clock);
}

final class GameClock {
  const GameClock({
    required this.whiteTime, required this.blackTime,
    this.whiteIncrement = Duration.zero, this.blackIncrement = Duration.zero,
    this.movesToGo,
  });
}
```

Several limits can be combined, as UCI allows (`depth 20 movetime 5000`).
Asserts reject impossible combinations (`infinite` with anything else, negative values).

## 5. Search handle and results

```dart
final class SearchHandle {
  /// Every `info` line that carries search data (depth/score/pv), in order.
  Stream<SearchInfo> get info;
  /// `info depth … currmove … currmovenumber …` lines. Stockfish only emits
  /// these from the main thread after about 3 s of search.
  Stream<CurrentMoveInfo> get currentMove;
  /// `info string …` lines emitted during this search.
  Stream<String> get infoStrings;
  /// Completes when `bestmove` arrives.
  Future<SearchResult> get result;

  bool get isPondering;
  bool get isInfinite;
  bool get isDone;

  /// Sends `stop`. Completes with the result.
  Future<SearchResult> stop();
  /// Sends `ponderhit`: the predicted move was played, keep searching normally.
  Future<void> ponderHit();
}

final class SearchInfo {
  final int? depth, selDepth, multiPv;
  final Score? score;
  final Wdl? wdl;                       // only with UCI_ShowWDL
  final int? nodes, nps, hashFull, tbHits;
  final Duration? time;
  final List<UciMove> pv;
  final Map<String, String> extra;      // forward-compatible unknown keys
  final String raw;
}

final class CurrentMoveInfo { final int depth; final UciMove move; final int moveNumber; final String raw; }

final class SearchResult {
  /// null when Stockfish answers `bestmove (none)` (checkmate or stalemate).
  final UciMove? bestMove;
  final UciMove? ponderMove;
  /// Last full info line per multipv index (index 1 = best line).
  final List<SearchInfo> lines;
  SearchInfo? get finalInfo => lines.firstOrNull;
  /// Set when the position has no legal moves:
  /// mate → [TerminalState.checkmate], `score cp 0` → [TerminalState.stalemate].
  final TerminalState? terminal;
  final Duration elapsed;               // wall clock, measured in Dart
  final bool wasStopped;                // ended by stop() rather than by its limits
}
```

### Scores

```dart
sealed class Score {
  ScoreBound get bound;                 // exact | lowerBound | upperBound
  /// Scores in UCI are from the side to move. This flips to White's view.
  Score fromWhitePerspective(Side sideToMove);
}
final class CentipawnScore extends Score {
  final int centipawns;
  /// Stockfish 19 reports tablebase wins/losses as cp ±(20000 − plies).
  bool get isTablebaseWin;  bool get isTablebaseLoss;
  int? get tablebasePlies;
}
final class MateScore extends Score {
  final int moves;                      // >0: side to move mates in N; <0: gets mated in N; 0: is mated
}

final class Wdl {                        // per mille, sums to 1000
  final int win, draw, loss;
  double get expectedScore => (win + draw / 2) / 1000;
  Wdl fromWhitePerspective(Side sideToMove);
}
```

Note: Stockfish 19's centipawns are *normalised*: 100 cp means a 50% win
chance in the WDL model, not "one pawn of material". The dartdoc will say so.

## 6. Analysis (aggregated multi-PV)

```dart
final class Analysis {
  /// Emits a fresh snapshot whenever any PV line updates, coalesced by [throttle].
  Stream<AnalysisSnapshot> get snapshots;
  AnalysisSnapshot? get latest;
  Future<SearchResult> stop();
  Future<SearchResult> get result;
}

final class AnalysisSnapshot {
  final int depth;                       // depth of line #1
  final List<SearchInfo> lines;          // sorted by multipv, length ≤ MultiPV
  final int nodes, nps; final Duration time; final int hashFull, tbHits;
}
```

Aggregation rule: keep the most recent `SearchInfo` for each `multiPv`
index. When line #1 reaches a new depth, drop lines whose depth is two or
more behind, because Stockfish may have pruned them.

## 7. Options

### Typed options (Stockfish 19)

```dart
final class StockfishOptions {
  const StockfishOptions({
    this.threads,            // Threads            spin 1..max(1024, 4×cores)   default 1
    this.hashMb,             // Hash               spin 1..33554432 (64-bit)    default 16
    this.ponder,             // Ponder             check                        default false
    this.multiPv,            // MultiPV            spin 1..256                  default 1
    this.skillLevel,         // Skill Level        spin 0..20                   default 20
    this.moveOverhead,       // Move Overhead      spin 0..5000 ms              default 10
    this.nodesTime,          // nodestime          spin 0..10000                default 0
    this.chess960,           // UCI_Chess960       check                        default false
    this.limitStrength,      // UCI_LimitStrength  check                        default false
    this.elo,                // UCI_Elo            spin 1320..3190              default 1320
    this.showWdl,            // UCI_ShowWDL        check                        default false
    this.syzygyPath,         // SyzygyPath         string (paths joined by ';' on Windows, ':' elsewhere)
    this.syzygyProbeDepth,   // SyzygyProbeDepth   spin 1..100                  default 1
    this.syzygy50MoveRule,   // Syzygy50MoveRule   check                        default true
    this.syzygyProbeLimit,   // SyzygyProbeLimit   spin 0..7                    default 7
    this.evalFile,           // EvalFile           string                       default nn-1a298aa575a0.nnue (embedded)
    this.numaPolicy,         // NumaPolicy         string                       default auto
    this.debugLogFile,       // Debug Log File     string                       default "" (off)
  });
  // Every field is nullable: null means "leave at engine default".
  StockfishOptions copyWith({...});
  Map<String, String> toUciMap();  // name → value, only non-null fields
}
```

Typed helpers:

- `List<String>? syzygyPaths` and the `syzygyPathsFromList()` factory join
  paths with the platform separator (`;` on Windows, `:` elsewhere), as
  Stockfish expects.
- `NumaPolicy` is a sealed type: `NumaPolicy.auto`, `.system`, `.hardware`,
  `.none`, or `NumaPolicy.custom(String spec)` (Stockfish's
  `0-15:16-31`-style CPU list syntax).
- `Duration moveOverheadDuration` mirrors the `moveOverhead` ms field.
- `StrengthLimit`: `StrengthLimit.elo(1800)` sets `UCI_LimitStrength=true` +
  `UCI_Elo`; `StrengthLimit.skill(5)` sets `Skill Level`. Docs explain how
  the two interact: `UCI_LimitStrength` takes precedence over `Skill Level`.

Spin ranges are checked against `optionSpecs` (not hard-coded), so a build
with a different `Threads` maximum still validates correctly.
`setOptions` sends options in a deterministic, dependency-aware order:
`NumaPolicy` → `Threads` → `Hash` → everything else. This avoids allocating
hash twice and re-binding threads.

### Raw options

`setOption(name, value)` covers options that are not typed (future or forked
engines). Values are coerced by spec type: `check` ← `bool`,
`spin` ← `int`, `combo` ← one of the spec's `vars`, `string` ← `String`
(empty → `<empty>`), `button` ← `null`.

```dart
sealed class UciOptionSpec { String get name; }
final class CheckOptionSpec  extends UciOptionSpec { final bool defaultValue; }
final class SpinOptionSpec   extends UciOptionSpec { final int defaultValue, min, max; }
final class ComboOptionSpec  extends UciOptionSpec { final String defaultValue; final List<String> values; }
final class StringOptionSpec extends UciOptionSpec { final String defaultValue; }
final class ButtonOptionSpec extends UciOptionSpec {}
```

## 8. Diagnostics result types

| Method | Engine command | Result type (fields) |
|---|---|---|
| `perft(d)` | `go perft d` | `PerftResult { int depth; int nodes; Map<UciMove,int> divide; }` |
| `display()` | `d` | `BoardDisplay { String ascii; String fen; String key /* hex */; List<String> checkers; TablebaseProbe? tablebase; }` |
| `evaluate()` | `eval` | `EvalTrace { String raw; double? nnueEvaluationWhite; double? finalEvaluationWhite; int? nnueInternal; List<EvalBucket> buckets /* NNUE network contributions table */; }`. `raw` is always kept; structured fields are best effort. |
| `bench(cfg)` | `bench <hash> <threads> <limit> <fenFile> <limitType>` | `BenchResult { Duration totalTime; int nodes; int nodesPerSecond; List<SearchInfo> perPosition; }` |
| `speedtest(cfg)` | `speedtest [threads] [hash] [seconds]` | `SpeedtestResult { String version; String compiledBy; bool largePages; int threads; int ttSizeMb; String threadBinding; int nodes; Duration searchTime; int nodesPerSecond; ({int max, int avg}) hashfullSingleSearch, hashfullSingleGame; String raw; }` |
| `compilerInfo()` | `compiler` | `CompilerInfo { String raw; String? compiler; String? os; List<String> features; }` |
| `exportNet(path)` | `export_net [path]` | `void`; reads the `info string` confirmation or error |
| `help()` | `help` | raw text |

```dart
final class BenchConfig {
  const BenchConfig({
    this.hashMb = 16, this.threads = 1, this.limit = 13,
    this.positions = const BenchPositions.builtIn(), // default | current | file(path)
    this.limitType = BenchLimitType.depth,           // depth | perft | nodes | movetime | eval
  });
}
final class SpeedtestConfig {
  const SpeedtestConfig({this.threads, this.hashMb, this.duration});   // nulls → engine defaults
}
```

`bench` and `speedtest` can take a while (`speedtest` defaults to about
150 s). They take an optional `onProgress` callback that receives the
`Position n/m` stderr lines.

## 9. Engine source

```dart
sealed class EngineSource {
  /// The patched Stockfish 19 library bundled by the build hook (FFI). Default.
  const factory EngineSource.embedded() = EmbeddedEngine;

  /// An external Stockfish executable run as a child process (optional
  /// ProcessTransport). [path] null → STOCKFISH_PATH, then PATH.
  /// Allows several engines per process and full crash isolation.
  const factory EngineSource.process({String? path, List<String> args, String? workingDirectory}) = ProcessEngine;
}

abstract final class EmbeddedStockfish {
  /// Bridge ABI version and `engine_info()` string of the loaded library,
  /// e.g. "Stockfish 19 (stockfish_dart 1.0.0, modified)".
  static String get engineInfo;
  static int get bridgeAbiVersion;
  /// False on targets where the hook produced no library.
  static bool get isAvailable;
}
```

The library is *obtained at build time* by the build hook, not by runtime
API. See 04-native-build-and-distribution.md.

## 10. Low-level library: `package:stockfish_dart/uci.dart`

This exports `UciCommand` and its subclasses, `UciEvent` and its subclasses,
`UciParser`, `InfoParser`, `OptionSpecParser` and `EngineTransport`. It is for
users who want to build their own engine manager, or drive *other* UCI engines
(nothing in the codec is Stockfish-specific; Stockfish extensions live in
`Stockfish`).

## 11. Testing support: `package:stockfish_dart/testing.dart`

```dart
final class FakeStockfish implements EngineTransport {
  FakeStockfish({EngineIdentity identity = …, List<UciOptionSpec> options = stockfish19Options});
  void respondTo(Pattern command, List<String> lines, {Duration delay});
  void emit(String line); void crash({String? criticalReason, int exitCode = 1});
  List<String> get received;
}
```

This lets users unit-test code built on this package without a real binary.

## 12. Interop (optional, open question Q3)

If approved: a separate library, `package:stockfish_dart/dartchess.dart`,
that depends on `dartchess` (GPL-3, pure Dart) and adds:

- `Position.fromDartchess(dc.Position)` and `toDartchess()`;
- `SearchInfo.pvSan(dc.Position)` for PVs in SAN;
- full legality validation before sending, so invalid moves never reach the
  engine.
