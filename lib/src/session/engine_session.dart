// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';
import 'dart:collection';

import '../errors.dart';
import '../model/option_spec.dart';
import '../model/position.dart';
import '../model/search_info.dart';
import '../model/search_limits.dart';
import '../model/uci_move.dart';
import '../transport/engine_transport.dart';
import '../uci/uci_command.dart';
import '../uci/uci_event.dart';
import 'restart_policy.dart';

/// Lifecycle state of an engine.
enum EngineState {
  /// Not started yet.
  created,

  /// Starting up (UCI handshake).
  starting,

  /// Ready for commands.
  idle,

  /// A search is running.
  searching,

  /// Restarting after a fatal error.
  restarting,

  /// Unusable after a fatal error that was not (or could not be) recovered.
  failed,

  /// Shutting down.
  disposing,

  /// Shut down.
  disposed,
}

/// One line of UCI traffic, for debugging (see `Stockfish.start(onTraffic:)`).
final class UciTrafficEntry {
  /// Creates an entry.
  const UciTrafficEntry(
    this.line, {
    required this.outgoing,
    this.isError = false,
  });

  /// The line.
  final String line;

  /// True for commands sent to the engine, false for engine output.
  final bool outgoing;

  /// Whether the engine wrote the line to standard error.
  final bool isError;

  @override
  String toString() =>
      '${outgoing
          ? '>>'
          : isError
          ? '!!'
          : '<<'} $line';
}

/// Output of a command bracketed by `isready`.
final class ExchangeResult {
  /// Creates the result.
  const ExchangeResult(this.events, this.stderr);

  /// Every stdout event before `readyok`.
  final List<UciEvent> events;

  /// Every stderr line before `readyok`.
  final List<String> stderr;

  /// The text of the [TextEvent]s, i.e. the command's free-form output.
  List<String> get textLines => [
    for (final e in events)
      if (e is TextEvent) e.line,
  ];
}

/// The UCI protocol driver behind `Stockfish`: command queue, handshake,
/// synchronisation, searches, error handling and restarts.
///
/// Public so custom front ends can be built on it; most users want
/// `Stockfish` instead.
final class EngineSession {
  /// Creates a session on [transport]. Call [start] next.
  EngineSession(
    this.transport, {
    this.restartPolicy = RestartPolicy.always,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.readyTimeout = const Duration(seconds: 30),
    this.onTraffic,
  }) {
    _subscription = transport.events.listen(_onTransportEvent);
  }

  /// The connection to the engine.
  final EngineTransport transport;

  /// What happens after fatal errors.
  final RestartPolicy restartPolicy;

  /// Maximum time for the `uci` handshake.
  final Duration handshakeTimeout;

  /// Maximum time to wait for `readyok`.
  final Duration readyTimeout;

  /// Called for every line sent or received.
  final void Function(UciTrafficEntry entry)? onTraffic;

  late final StreamSubscription<TransportEvent> _subscription;
  final _rawOutput = StreamController<String>.broadcast();
  final _rawErrorOutput = StreamController<String>.broadcast();
  final _infoStrings = StreamController<String>.broadcast();
  final _states = StreamController<EngineState>.broadcast();
  final _failures = StreamController<StockfishException>.broadcast();

  EngineState _state = EngineState.created;
  EngineIdentity _identity = const EngineIdentity(name: '', author: '');
  final _optionSpecs = SplayTreeMap<String, UciOptionSpec>(
    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );

  // State replayed after a restart.
  final _appliedOptions = <String, String>{};
  Position? _position;

  // The operation currently waiting for engine output.
  void Function(UciEvent event)? _sink;
  void Function(String line)? _stderrSink;
  void Function(Object error)? _fail;

  Future<void> _queueTail = Future.value();
  int _pending = 0;
  SearchJob? _activeSearch;
  final _openSearches = <SearchJob>{};

  Future<void>? _restarting;
  bool _expectExit = false;
  final _restartTimes = <DateTime>[];

  /// Current lifecycle state.
  EngineState get state => _state;

  /// State changes.
  Stream<EngineState> get stateChanges => _states.stream;

  /// Every failure (command errors and fatal errors), including those that
  /// were recovered from.
  Stream<StockfishException> get failures => _failures.stream;

  /// `id name` / `id author` from the handshake.
  EngineIdentity get identity => _identity;

  /// Options advertised by the engine, keyed case-insensitively by name.
  Map<String, UciOptionSpec> get optionSpecs =>
      UnmodifiableMapView(_optionSpecs);

  /// Every line the engine writes to standard output.
  Stream<String> get rawOutput => _rawOutput.stream;

  /// Every line the engine writes to standard error.
  Stream<String> get rawErrorOutput => _rawErrorOutput.stream;

  /// The text of every `info string` line.
  Stream<String> get infoStrings => _infoStrings.stream;

  /// Options set through this session, by UCI name, in the order applied.
  Map<String, String> get appliedOptions =>
      UnmodifiableMapView(_appliedOptions);

  /// The last position applied successfully.
  Position? get position => _position;

  /// The running search, if any.
  SearchJob? get activeSearch => _activeSearch;

  bool get _isDisposed =>
      _state == EngineState.disposing || _state == EngineState.disposed;

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle

  /// Starts the engine and performs the UCI handshake.
  Future<void> start() async {
    _setState(EngineState.starting);
    transport.setKeepAlive(true);
    try {
      await _handshake();
      _setState(EngineState.idle);
    } catch (e) {
      _setState(EngineState.failed);
      try {
        _expectExit = true;
        await transport.stop(timeout: const Duration(seconds: 2));
      } catch (_) {
        // Best effort.
      }
      rethrow;
    } finally {
      _updateKeepAlive();
    }
  }

  Future<void> _handshake() async {
    await transport.start();
    _expectExit = false;
    _optionSpecs.clear();
    var name = '', author = '';
    final done = Completer<void>();
    _sink = (e) {
      switch (e) {
        case IdEvent(key: 'name', :final value):
          name = value;
        case IdEvent(key: 'author', :final value):
          author = value;
        case OptionEvent(:final spec):
          _optionSpecs[spec.name] = spec;
        case UciOkEvent():
          if (!done.isCompleted) done.complete();
        default:
          break;
      }
    };
    _fail = (error) {
      if (!done.isCompleted) done.completeError(error);
    };
    _send(const UciHandshakeCommand().toUci());
    try {
      await done.future.timeout(handshakeTimeout);
    } on TimeoutException {
      throw EngineStartException(
        '${transport.description} did not answer the UCI handshake within $handshakeTimeout.',
      );
    } finally {
      _sink = null;
      _fail = null;
    }
    _identity = EngineIdentity(name: name, author: author);
    await exchange(const []);
  }

  /// Stops any search and shuts the engine down. Pending operations fail
  /// with [EngineDisposedException].
  Future<void> dispose({Duration timeout = const Duration(seconds: 5)}) async {
    if (_isDisposed) return;
    _setState(EngineState.disposing);
    _expectExit = true;
    _fail?.call(const EngineDisposedException());
    for (final job in _openSearches.toList()) {
      job._fail(const EngineDisposedException());
    }
    try {
      await transport.stop(timeout: timeout);
    } finally {
      await _subscription.cancel();
      _setState(EngineState.disposed);
      await Future.wait([
        _rawOutput.close(),
        _rawErrorOutput.close(),
        _infoStrings.close(),
        _states.close(),
        _failures.close(),
      ]);
    }
  }

  // ---------------------------------------------------------------------------
  // Engine output

  void _send(String line) {
    onTraffic?.call(UciTrafficEntry(line, outgoing: true));
    transport.send(line);
  }

  void _onTransportEvent(TransportEvent event) {
    switch (event) {
      case OutputLine(:final line, isError: false):
        onTraffic?.call(UciTrafficEntry(line, outgoing: false));
        if (!_rawOutput.isClosed) _rawOutput.add(line);
        final parsed = parseUciLine(line);
        if (parsed case InfoStringEvent(
          :final text,
        ) when !_infoStrings.isClosed) {
          _infoStrings.add(text);
        }
        if (parsed case CriticalErrorEvent(
          :final command,
          :final reason,
        ) when !_infoStrings.isClosed) {
          _infoStrings.add(
            'CRITICAL ERROR: Command `$command` failed. Reason: $reason',
          );
        }
        _sink?.call(parsed);
      case OutputLine(:final line, isError: true):
        onTraffic?.call(UciTrafficEntry(line, outgoing: false, isError: true));
        if (!_rawErrorOutput.isClosed) _rawErrorOutput.add(line);
        _stderrSink?.call(line);
      case FatalEvent(:final reason):
        onTraffic?.call(
          UciTrafficEntry('FATAL: $reason', outgoing: false, isError: true),
        );
        _onFatal(reason);
      case ExitedEvent(:final exitCode):
        if (!_expectExit) {
          _onFatal(
            'The engine (${transport.description}) exited unexpectedly'
            '${exitCode == null ? '' : ' with code $exitCode'}.',
          );
        }
    }
  }

  void _onFatal(String reason) {
    if (_isDisposed || _restarting != null) return;
    _expectExit = true;
    final willRestart = restartPolicy.allows(_restartTimes, DateTime.now());
    final error = EngineFatalException(reason, restarted: willRestart);
    if (!_failures.isClosed) _failures.add(error);
    _fail?.call(error);
    for (final job in _openSearches.toList()) {
      job._fail(error);
    }
    if (willRestart) {
      _restartTimes.add(DateTime.now());
      _setState(EngineState.restarting);
      _restarting = _restart().whenComplete(() => _restarting = null);
    } else {
      _setState(EngineState.failed);
      unawaited(transport.stop().catchError((Object _) {}));
    }
  }

  Future<void> _restart() async {
    transport.setKeepAlive(true);
    try {
      try {
        await transport.stop(timeout: const Duration(seconds: 5));
      } catch (_) {
        // The engine is being replaced anyway.
      }
      await _handshake();
      for (final MapEntry(:key, :value) in _appliedOptions.entries) {
        await exchange([SetOptionCommand(key, value).toUci()]);
      }
      if (_position case final p?) {
        await exchange([PositionCommand(p).toUci()]);
      }
      _setState(EngineState.idle);
    } catch (e) {
      _setState(EngineState.failed);
      if (!_failures.isClosed) {
        _failures.add(EngineFatalException('Restarting the engine failed: $e'));
      }
    } finally {
      _updateKeepAlive();
    }
  }

  void _updateKeepAlive() {
    transport.setKeepAlive(
      _pending > 0 || _activeSearch != null || _restarting != null,
    );
  }

  // ---------------------------------------------------------------------------
  // Operations

  /// Runs [body] when every earlier operation has finished.
  ///
  /// Throws [EngineBusyException] if an infinite or ponder search is running
  /// (it would never finish), unless [interrupt] is true, which stops it
  /// first.
  Future<T> enqueue<T>(Future<T> Function() body, {bool interrupt = false}) {
    if (_isDisposed) return Future.error(const EngineDisposedException());
    final unbounded = _openSearches.where(
      (j) => j.isUnbounded && !j._stopRequested,
    );
    if (unbounded.isNotEmpty) {
      if (!interrupt) return Future.error(const EngineBusyException());
      for (final job in unbounded.toList()) {
        job.requestStop();
      }
    }

    _pending++;
    _updateKeepAlive();
    final result = _queueTail.then((_) => _runQueued(body));
    _queueTail = result.then<void>((_) {}, onError: (Object _) {});
    return result.whenComplete(() {
      _pending--;
      _updateKeepAlive();
    });
  }

  Future<T> _runQueued<T>(Future<T> Function() body) async {
    if (_restarting case final r?) await r;
    if (_isDisposed) throw const EngineDisposedException();
    if (_state == EngineState.failed) {
      throw const EngineFatalException(
        'The engine failed and was not restarted.',
      );
    }
    try {
      return await body();
    } on EngineCommandException {
      // Stockfish resets to the start position after a failed command.
      await _restorePosition();
      rethrow;
    }
  }

  Future<void> _restorePosition() async {
    final p = _position;
    if (p == null || _isDisposed || _restarting != null) return;
    try {
      await exchange([PositionCommand(p).toUci()]);
    } catch (_) {
      // A restart (if any) replays the position anyway.
    }
  }

  /// Sends [commands] followed by `isready` and collects the output until
  /// `readyok`. Must be called from inside [enqueue].
  ///
  /// Throws [EngineCommandException] for `CRITICAL ERROR` lines and
  /// [InvalidOptionException] for unknown options.
  Future<ExchangeResult> exchange(
    List<String> commands, {
    Duration? timeout,
    void Function(String line)? onStderr,
  }) async {
    final events = <UciEvent>[];
    final stderr = <String>[];
    final done = Completer<void>();
    _sink = (e) {
      if (e is ReadyOkEvent) {
        if (!done.isCompleted) done.complete();
      } else {
        events.add(e);
      }
    };
    _stderrSink = (line) {
      stderr.add(line);
      onStderr?.call(line);
    };
    _fail = (error) {
      if (!done.isCompleted) done.completeError(error);
    };
    try {
      for (final c in commands) {
        _send(c);
      }
      _send(const IsReadyCommand().toUci());
      await done.future.timeout(timeout ?? readyTimeout);
    } on TimeoutException {
      _onFatal(
        'The engine did not answer `isready` within ${timeout ?? readyTimeout}.',
      );
      throw EngineTimeoutException(
        'The engine did not answer `isready` in time.',
      );
    } finally {
      _sink = null;
      _stderrSink = null;
      _fail = null;
    }

    for (final e in events) {
      switch (e) {
        case CriticalErrorEvent(:final command, :final reason):
          final error = EngineCommandException(command, reason);
          if (!_failures.isClosed) _failures.add(error);
          throw error;
        case UnknownOptionEvent(:final name):
          throw InvalidOptionException(
            name,
            'The engine has no option named "$name".',
          );
        default:
          break;
      }
    }
    return ExchangeResult(events, stderr);
  }

  /// Sets an option and records it for replay after restarts. Must be called
  /// from inside [enqueue].
  Future<void> applyOption(String name, String? value) async {
    final result = await exchange([SetOptionCommand(name, value).toUci()]);
    for (final e in result.events) {
      if (e case InfoStringEvent(
        :final text,
      ) when text.startsWith('$name: invalid value')) {
        throw InvalidOptionException(name, text);
      }
    }
    if (value != null) {
      _appliedOptions.remove(name);
      _appliedOptions[name] = value;
    }
  }

  /// Sets the position. Must be called from inside [enqueue].
  Future<void> applyPosition(Position position) async {
    await exchange([PositionCommand(position).toUci()]);
    _position = position;
  }

  /// Sends `ucinewgame`. Must be called from inside [enqueue].
  Future<void> applyNewGame() async {
    await exchange([const UciNewGameCommand().toUci()]);
  }

  /// Starts a search. The returned job is queued like any operation.
  SearchJob search({
    Position? position,
    SearchLimits limits = const SearchLimits.infinite(),
    List<UciMove> searchMoves = const [],
    bool ponder = false,
    bool interrupt = false,
  }) {
    final job = SearchJob._(this, limits: limits, ponder: ponder);
    _openSearches.add(job);
    final run = enqueue(() async {
      if (position != null) await applyPosition(position);
      await _runSearch(
        job,
        GoCommand(limits: limits, searchMoves: searchMoves, ponder: ponder),
      );
    }, interrupt: interrupt);
    run
        .then((_) {}, onError: (Object e, StackTrace s) => job._fail(e, s))
        .whenComplete(() => _openSearches.remove(job));
    return job;
  }

  Future<void> _runSearch(SearchJob job, GoCommand go) async {
    if (job.isDone) return;
    _activeSearch = job;
    _setState(EngineState.searching);
    _updateKeepAlive();
    _sink = job._onEvent;
    _fail = job._fail;
    try {
      job._started = true;
      job._watch.start();
      _send(go.toUci());
      if (job._stopRequested) _send(const StopCommand().toUci());
      await job.result;
    } finally {
      _sink = null;
      _fail = null;
      _activeSearch = null;
      if (_state == EngineState.searching) _setState(EngineState.idle);
      _updateKeepAlive();
    }
  }

  /// Sends a line outside the queue (used for `stop` and `ponderhit`).
  void sendImmediately(String line) => _send(line);

  /// Records [position] as the engine's current position without sending
  /// it (after commands such as `flip` that change it inside the engine).
  void trackPosition(Position position) => _position = position;

  /// Searches that are running or queued.
  List<SearchJob> get openSearches => List.unmodifiable(_openSearches);
}

/// A search started with [EngineSession.search]; see `SearchHandle`.
final class SearchJob {
  SearchJob._(this._session, {required this.limits, required bool ponder})
    : _pondering = ponder {
    // Errors are delivered to whoever awaits [result]; a search nobody awaits
    // must not surface as an unhandled error.
    _result.future.ignore();
  }

  final EngineSession _session;

  /// The limits the search was started with.
  final SearchLimits limits;

  final _info = StreamController<SearchInfo>.broadcast();
  final _currentMove = StreamController<CurrentMoveInfo>.broadcast();
  final _infoStrings = StreamController<String>.broadcast();
  final _result = Completer<SearchResult>();
  final _lines = SplayTreeMap<int, SearchInfo>();
  final _watch = Stopwatch();
  bool _pondering;
  bool _started = false;
  bool _stopRequested = false;
  SearchInfo? _lastInfo;

  /// Info lines with search data.
  Stream<SearchInfo> get info => _info.stream;

  /// `currmove` lines.
  Stream<CurrentMoveInfo> get currentMove => _currentMove.stream;

  /// `info string` lines emitted during this search.
  Stream<String> get infoStrings => _infoStrings.stream;

  /// Completes with the `bestmove`.
  Future<SearchResult> get result => _result.future;

  /// Whether the search is in ponder mode (until [ponderHit]).
  bool get isPondering => _pondering;

  /// Whether the search only ends when stopped.
  bool get isUnbounded => _pondering || limits.isUnlimited;

  /// Whether the result is available.
  bool get isDone => _result.isCompleted;

  /// The latest info per principal variation, best line first.
  List<SearchInfo> get currentLines => List.unmodifiable(_lines.values);

  /// Asks the engine to stop; [result] completes when `bestmove` arrives.
  void requestStop() {
    if (isDone || _stopRequested) return;
    _stopRequested = true;
    if (_started) _session.sendImmediately(const StopCommand().toUci());
  }

  /// Sends `ponderhit`.
  void ponderHit() {
    if (isDone || !_pondering) return;
    _pondering = false;
    if (_started) _session.sendImmediately(const PonderHitCommand().toUci());
  }

  void _onEvent(UciEvent event) {
    switch (event) {
      case InfoEvent(:final info):
        _lastInfo = info;
        if (info.pv.isNotEmpty || info.score != null) {
          _lines[info.multiPv ?? 1] = info;
        }
        if (!_info.isClosed) _info.add(info);
      case CurrentMoveEvent(:final info):
        if (!_currentMove.isClosed) _currentMove.add(info);
      case InfoStringEvent(:final text):
        if (!_infoStrings.isClosed) _infoStrings.add(text);
      case CriticalErrorEvent(:final command, :final reason):
        _fail(EngineCommandException(command, reason));
      case BestMoveEvent(:final move, :final ponder):
        _complete(move, ponder);
      default:
        break;
    }
  }

  void _complete(UciMove? move, UciMove? ponder) {
    if (_result.isCompleted) return;
    _watch.stop();
    TerminalState? terminal;
    if (move == null) {
      final score = _lastInfo?.score;
      terminal = score.toString().startsWith('mate')
          ? TerminalState.checkmate
          : TerminalState.stalemate;
    }
    _result.complete(
      SearchResult(
        bestMove: move,
        ponderMove: ponder,
        lines: List.unmodifiable(_lines.values),
        elapsed: _watch.elapsed,
        wasStopped: _stopRequested,
        terminal: terminal,
      ),
    );
    _close();
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_result.isCompleted) return;
    _result.completeError(error, stack);
    _close();
  }

  void _close() {
    _info.close();
    _currentMove.close();
    _infoStrings.close();
  }
}
