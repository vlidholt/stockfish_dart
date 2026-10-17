// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';

import 'diagnostics.dart';
import 'engine_source.dart';
import 'errors.dart';
import 'model/option_spec.dart';
import 'model/position.dart';
import 'model/search_info.dart';
import 'model/search_limits.dart';
import 'model/uci_move.dart';
import 'options/stockfish_options.dart';
import 'search_handle.dart';
import 'session/engine_session.dart';
import 'session/restart_policy.dart';
import 'transport/engine_transport.dart';
import 'transport/ffi_transport.dart';
import 'uci/uci_command.dart';

/// A Stockfish chess engine.
///
/// ```dart
/// final engine = await Stockfish.start(
///   options: const StockfishOptions(threads: 2, hashMb: 128),
/// );
/// final result = await engine.bestMove(
///   Position.startpos(moves: [UciMove('e2e4')]),
///   limits: const SearchLimits.depth(18),
/// );
/// print(result.bestMove);
/// await engine.dispose();
/// ```
///
/// Commands are executed one at a time in the order they are called. Always
/// call [dispose] when done.
final class Stockfish {
  Stockfish._(this._session, this.source);

  final EngineSession _session;

  /// Where the engine runs.
  final EngineSource source;

  /// Starts an engine, performs the UCI handshake and applies [options].
  ///
  /// By default this runs the embedded Stockfish 19 library ([engine] =
  /// [EngineSource.embedded]); only one embedded engine can run per process.
  ///
  /// Throws [EngineLoadException] if the engine can't be loaded,
  /// [EngineAlreadyRunningException] if an embedded engine is already
  /// running, [EngineStartException] if the handshake fails, and
  /// [InvalidOptionException] for invalid [options].
  static Future<Stockfish> start({
    EngineSource engine = const EngineSource.embedded(),
    StockfishOptions options = const StockfishOptions(),
    RestartPolicy restartPolicy = RestartPolicy.always,
    Duration handshakeTimeout = const Duration(seconds: 10),
    Duration readyTimeout = const Duration(seconds: 30),
    void Function(UciTrafficEntry entry)? onTraffic,
  }) => _start(
    engine.createTransport(),
    engine,
    options: options,
    restartPolicy: restartPolicy,
    handshakeTimeout: handshakeTimeout,
    readyTimeout: readyTimeout,
    onTraffic: onTraffic,
  );

  /// Starts an engine on a custom [transport] (for tests, see
  /// `package:stockfish_dart/testing.dart`, or remote engines).
  static Future<Stockfish> withTransport(
    EngineTransport transport, {
    StockfishOptions options = const StockfishOptions(),
    RestartPolicy restartPolicy = RestartPolicy.always,
    Duration handshakeTimeout = const Duration(seconds: 10),
    Duration readyTimeout = const Duration(seconds: 30),
    void Function(UciTrafficEntry entry)? onTraffic,
  }) => _start(
    transport,
    const EngineSource.embedded(),
    options: options,
    restartPolicy: restartPolicy,
    handshakeTimeout: handshakeTimeout,
    readyTimeout: readyTimeout,
    onTraffic: onTraffic,
  );

  static Future<Stockfish> _start(
    EngineTransport transport,
    EngineSource source, {
    required StockfishOptions options,
    required RestartPolicy restartPolicy,
    required Duration handshakeTimeout,
    required Duration readyTimeout,
    required void Function(UciTrafficEntry entry)? onTraffic,
  }) async {
    final session = EngineSession(
      transport,
      restartPolicy: restartPolicy,
      handshakeTimeout: handshakeTimeout,
      readyTimeout: readyTimeout,
      onTraffic: onTraffic,
    );
    await session.start();
    final engine = Stockfish._(session, source);
    try {
      if (options.toUciMap().isNotEmpty) await engine.setOptions(options);
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
    return engine;
  }

  /// Information about the embedded native library on this machine: which
  /// CPU variants are supported and which one is used.
  ///
  /// Throws [EngineLoadException] if the library is not available.
  static EmbeddedLibraryInfo inspectEmbeddedLibrary() => FfiTransport.inspect();

  // ---------------------------------------------------------------------------
  // Identity and state

  /// Name and author reported by the engine.
  EngineIdentity get identity => _session.identity;

  /// Options advertised by the engine, keyed case-insensitively by name.
  Map<String, UciOptionSpec> get optionSpecs => _session.optionSpecs;

  /// Current lifecycle state.
  EngineState get state => _session.state;

  /// Lifecycle state changes.
  Stream<EngineState> get stateChanges => _session.stateChanges;

  /// Every failure (rejected commands and fatal errors), including those
  /// that were recovered from.
  Stream<StockfishException> get failures => _session.failures;

  /// Whether [dispose] has been called.
  bool get isDisposed =>
      state == EngineState.disposing || state == EngineState.disposed;

  // ---------------------------------------------------------------------------
  // Options

  /// The options set through this object so far.
  StockfishOptions get options =>
      StockfishOptions.fromUciMap(_session.appliedOptions);

  /// Applies every non-null field of [options] that differs from the current
  /// value (`setoption name … value …`). NUMA policy, threads and hash are
  /// applied first.
  ///
  /// Values are validated against the engine's advertised ranges first,
  /// because Stockfish silently ignores invalid values. Throws
  /// [InvalidOptionException].
  Future<void> setOptions(StockfishOptions options) {
    final wanted = options.toUciMap();
    final validated = <String, String>{
      for (final MapEntry(:key, :value) in wanted.entries)
        key: _validate(key, value),
    };
    return _session.enqueue(() async {
      for (final MapEntry(:key, :value) in validated.entries) {
        if (_session.appliedOptions[key] == value) continue;
        await _session.applyOption(key, value);
      }
    });
  }

  /// Sets any option by its UCI [name]. [value] must match the option's
  /// type: `bool` (check), `int` (spin), `String` (combo, string) or `null`
  /// (button).
  Future<void> setOption(String name, Object? value) {
    final spec = optionSpecs[name];
    if (spec == null) {
      return Future.error(
        InvalidOptionException(name, 'The engine has no option named "$name".'),
      );
    }
    final String? text;
    try {
      text = spec is ButtonOptionSpec ? null : _validate(spec.name, value);
    } on InvalidOptionException catch (e) {
      return Future.error(e);
    }
    return _session.enqueue(() => _session.applyOption(spec.name, text));
  }

  String _validate(String name, Object? value) {
    final spec = optionSpecs[name];
    if (spec == null) {
      throw InvalidOptionException(
        name,
        'The engine has no option named "$name".',
      );
    }
    Never bad(String why) => throw InvalidOptionException(
      name,
      'Invalid value "$value" for $name: $why',
    );
    switch (spec) {
      case CheckOptionSpec():
        if (value is bool) return '$value';
        if (value == 'true' || value == 'false') return '$value';
        bad('expected a bool');
      case SpinOptionSpec(:final min, :final max):
        final v = value is int ? value : int.tryParse('$value');
        if (v == null) bad('expected an integer');
        if (v < min || v > max) bad('must be between $min and $max');
        return '$v';
      case ComboOptionSpec(:final values):
        final match = values.where(
          (v) => v.toLowerCase() == '$value'.toLowerCase(),
        );
        if (match.isEmpty) bad('expected one of ${values.join(', ')}');
        return match.first;
      case StringOptionSpec():
        if (value is! String) bad('expected a string');
        checkSingleLine(value);
        return value;
      case ButtonOptionSpec():
        bad('is a button; use setOption(name, null)');
    }
  }

  /// Clears the transposition table (`setoption name Clear Hash`).
  Future<void> clearHash() =>
      _session.enqueue(() => _session.applyOption(OptionNames.clearHash, null));

  // ---------------------------------------------------------------------------
  // Positions

  /// Tells the engine a new game starts (`ucinewgame`), clearing its hash
  /// and history.
  Future<void> newGame() => _session.enqueue(_session.applyNewGame);

  /// Sets the position (`position …`). Throws [EngineCommandException] if
  /// the engine rejects it (illegal move or position); the previous position
  /// stays active.
  Future<void> setPosition(Position position) =>
      _session.enqueue(() => _session.applyPosition(position));

  /// The last position applied successfully.
  Position? get position => _session.position;

  /// Waits until the engine has processed everything sent so far (`isready`).
  Future<void> isReady() => _session.enqueue(() => _session.exchange(const []));

  // ---------------------------------------------------------------------------
  // Searching

  /// Starts a search (`go …`) and returns a handle immediately.
  ///
  /// If [position] is given it is set first. [searchMoves] restricts the
  /// search to those root moves. With [ponder] the search runs in ponder
  /// mode until [SearchHandle.ponderHit] or [SearchHandle.stop].
  ///
  /// Searches are queued behind earlier commands. While an infinite or
  /// ponder search runs, other commands throw [EngineBusyException] unless
  /// [interrupt] is true, which stops the running search first.
  SearchHandle search({
    Position? position,
    SearchLimits limits = const SearchLimits.infinite(),
    List<UciMove> searchMoves = const [],
    bool ponder = false,
    bool interrupt = false,
  }) => SearchHandle(
    _session.search(
      position: position,
      limits: limits,
      searchMoves: searchMoves,
      ponder: ponder,
      interrupt: interrupt,
    ),
  );

  /// Searches [position] within [limits] and returns the result.
  ///
  /// ```dart
  /// final r = await engine.bestMove(p, limits: SearchLimits.moveTime(Duration(seconds: 1)));
  /// ```
  Future<SearchResult> bestMove(
    Position position, {
    required SearchLimits limits,
    List<UciMove> searchMoves = const [],
  }) {
    if (limits.isUnlimited) {
      throw ArgumentError.value(
        limits,
        'limits',
        'bestMove needs a finite limit',
      );
    }
    return search(
      position: position,
      limits: limits,
      searchMoves: searchMoves,
    ).result;
  }

  /// Starts an infinite analysis of [position]. Use `MultiPV` (see
  /// [StockfishOptions.multiPv]) to get several lines.
  ///
  /// ```dart
  /// final analysis = engine.analyze(p, throttle: Duration(milliseconds: 200));
  /// analysis.snapshots.listen(print);
  /// await Future.delayed(Duration(seconds: 5));
  /// final result = await analysis.stop();
  /// ```
  Analysis analyze(
    Position position, {
    Duration? throttle,
    List<UciMove> searchMoves = const [],
    bool interrupt = false,
  }) => Analysis(
    search(position: position, searchMoves: searchMoves, interrupt: interrupt),
    throttle: throttle,
  );

  /// Stops every running or queued search. Returns the result of the search
  /// that was running, if any.
  Future<SearchResult?> stop() async {
    final active = _session.activeSearch;
    for (final job in _session.openSearches) {
      job.requestStop();
    }
    if (active == null) return null;
    try {
      return await active.result;
    } on StockfishException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Stockfish extensions

  /// Counts leaf nodes to [depth] (`go perft`), per root move. Uses
  /// [position] if given, else the current position.
  Future<PerftResult> perft(int depth, {Position? position}) {
    if (depth < 1) {
      throw ArgumentError.value(depth, 'depth', 'must be positive');
    }
    return _session.enqueue(() async {
      if (position != null) await _session.applyPosition(position);
      final r = await _session.exchange([
        PerftCommand(depth).toUci(),
      ], timeout: const Duration(hours: 1));
      return PerftResult.parse(depth, r.textLines);
    });
  }

  /// The board, FEN, hash key and checkers of the current (or given)
  /// position (`d`).
  Future<BoardDisplay> display({Position? position}) =>
      _session.enqueue(() async {
        if (position != null) await _session.applyPosition(position);
        final r = await _session.exchange([const DisplayCommand().toUci()]);
        return BoardDisplay.parse(r.textLines);
      });

  /// The static evaluation breakdown of the current (or given) position
  /// (`eval`).
  Future<EvalTrace> evaluate({Position? position}) =>
      _session.enqueue(() async {
        if (position != null) await _session.applyPosition(position);
        final r = await _session.exchange([const EvalCommand().toUci()]);
        return EvalTrace.parse(r.textLines);
      });

  /// Mirrors the current position, swapping colours (`flip`). Returns the
  /// new position, which also becomes [position].
  Future<Position> flip() => _session.enqueue(() async {
    final r = await _session.exchange([
      const FlipCommand().toUci(),
      const DisplayCommand().toUci(),
    ]);
    final flipped = Position.fromFen(BoardDisplay.parse(r.textLines).fen);
    _session.trackPosition(flipped);
    return flipped;
  });

  /// Runs Stockfish's benchmark (`bench`). [onProgress] receives the
  /// `Position n/m` progress lines.
  ///
  /// The benchmark changes `Threads`, `Hash` and the position; they are
  /// restored afterwards.
  Future<BenchResult> bench([
    BenchConfig config = const BenchConfig(),
    void Function(String line)? onProgress,
  ]) => _session.enqueue(() async {
    try {
      final r = await _session.exchange(
        [BenchCommand(config.toArguments()).toUci()],
        timeout: const Duration(hours: 2),
        onStderr: onProgress,
      );
      final stderr = await _settleStderr(r.stderr, 'Nodes/second');
      return BenchResult.parse(r.textLines, stderr);
    } finally {
      await _restoreAfterBenchmark();
    }
  });

  /// Runs Stockfish's speed test (`speedtest`), which reports nodes per
  /// second over a realistic game. [onProgress] receives progress lines.
  ///
  /// Settings are restored afterwards, as for [bench].
  Future<SpeedtestResult> speedtest([
    SpeedtestConfig config = const SpeedtestConfig(),
    void Function(String line)? onProgress,
  ]) => _session.enqueue(() async {
    try {
      final r = await _session.exchange(
        [SpeedtestCommand(config.toArguments()).toUci()],
        timeout: const Duration(hours: 2),
        onStderr: onProgress,
      );
      final stderr = await _settleStderr(r.stderr, 'Nodes/second');
      return SpeedtestResult.parse(stderr);
    } finally {
      await _restoreAfterBenchmark();
    }
  });

  // With a child process, stderr may arrive slightly after readyok.
  Future<List<String>> _settleStderr(
    List<String> stderr,
    String lastPrefix,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!stderr.any((l) => l.trim().startsWith(lastPrefix)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return stderr;
  }

  Future<void> _restoreAfterBenchmark() async {
    final commands = <String>[
      for (final name in [
        OptionNames.threads,
        OptionNames.hash,
        OptionNames.chess960,
      ])
        if (_session.appliedOptions[name] ?? _defaultOf(name) case final v?)
          SetOptionCommand(name, v).toUci(),
      const UciNewGameCommand().toUci(),
      PositionCommand(_session.position ?? const Position.startpos()).toUci(),
    ];
    await _session.exchange(commands);
  }

  String? _defaultOf(String name) => switch (optionSpecs[name]) {
    SpinOptionSpec(:final defaultValue) => '$defaultValue',
    CheckOptionSpec(:final defaultValue) => '$defaultValue',
    _ => null,
  };

  /// Compiler and build information (`compiler`).
  Future<CompilerInfo> compilerInfo() => _session.enqueue(() async {
    final r = await _session.exchange([const CompilerCommand().toUci()]);
    return CompilerInfo.parse(r.textLines);
  });

  /// Saves the current network to [filePath] (`export_net`). Without a
  /// path, the network's default name in the working directory is used
  /// (only possible for the embedded network). Returns the engine's message.
  Future<String> exportNet([String? filePath]) {
    if (filePath != null) checkSingleLine(filePath);
    return _session.enqueue(() async {
      final r = await _session.exchange([ExportNetCommand(filePath).toUci()]);
      final message = r.textLines.where((l) => l.trim().isNotEmpty).join('\n');
      if (message.startsWith('Failed')) {
        throw EngineCommandException(
          ExportNetCommand(filePath).toUci(),
          message,
        );
      }
      return message;
    });
  }

  /// Stockfish's help and license notice (`help`).
  Future<String> help() => _session.enqueue(() async {
    final r = await _session.exchange([const HelpCommand().toUci()]);
    return r.textLines.join('\n').trim();
  });

  // ---------------------------------------------------------------------------
  // Raw access

  /// Every line the engine writes to standard output.
  Stream<String> get rawOutput => _session.rawOutput;

  /// Every line the engine writes to standard error.
  Stream<String> get rawErrorOutput => _session.rawErrorOutput;

  /// The text of every `info string` line.
  Stream<String> get infoStrings => _session.infoStrings;

  /// Sends [line] followed by `isready` and returns the output lines in
  /// between.
  ///
  /// Commands that change state tracked by this object (`setoption`,
  /// `position`, `go`, `ucinewgame`, `stop`, `ponderhit`, `quit`, `uci`,
  /// `flip`) are rejected unless [unsafe] is true; use the typed methods
  /// instead.
  Future<List<String>> sendRaw(String line, {bool unsafe = false}) {
    checkSingleLine(line);
    final head = line.trim().split(RegExp(r'\s+')).first;
    const tracked = {
      'setoption',
      'position',
      'go',
      'ucinewgame',
      'stop',
      'ponderhit',
      'quit',
      'uci',
      'flip',
    };
    if (!unsafe && tracked.contains(head)) {
      throw ArgumentError.value(
        line,
        'line',
        'Use the typed API for `$head`, or pass unsafe: true',
      );
    }
    return _session.enqueue(() async {
      final r = await _session.exchange([line]);
      return [for (final e in r.events) e.line];
    });
  }

  // ---------------------------------------------------------------------------

  /// Stops any search and shuts the engine down. Safe to call repeatedly.
  Future<void> dispose({Duration timeout = const Duration(seconds: 5)}) =>
      _session.dispose(timeout: timeout);
}
