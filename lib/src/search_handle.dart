// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';

import 'package:meta/meta.dart';

import 'model/search_info.dart';
import 'session/engine_session.dart';

/// A running (or queued) search, returned by `Stockfish.search`.
///
/// Listen to [info] right away to see progress; await [result] for the
/// `bestmove`.
///
/// ```dart
/// final handle = engine.search(position: p, limits: SearchLimits.depth(20));
/// handle.info.listen((i) => print('depth ${i.depth}: ${i.score}'));
/// final result = await handle.result;
/// ```
final class SearchHandle {
  /// Wraps a session search job.
  SearchHandle(this._job);

  final SearchJob _job;

  /// Info lines with search data (depth, score, PV). Broadcast; events are
  /// not replayed to late listeners.
  Stream<SearchInfo> get info => _job.info;

  /// `currmove` updates (Stockfish sends these after ~3 s of search).
  Stream<CurrentMoveInfo> get currentMove => _job.currentMove;

  /// `info string` lines emitted during this search.
  Stream<String> get infoStrings => _job.infoStrings;

  /// Completes with the engine's `bestmove`.
  Future<SearchResult> get result => _job.result;

  /// The latest info per principal variation so far, best line first.
  List<SearchInfo> get currentLines => _job.currentLines;

  /// Whether the search is pondering (started with `ponder: true` and no
  /// [ponderHit] yet).
  bool get isPondering => _job.isPondering;

  /// Whether the search only ends when stopped (infinite or pondering).
  bool get isUnbounded => _job.isUnbounded;

  /// Whether [result] is available.
  bool get isDone => _job.isDone;

  /// Sends `stop` and returns the result. Stopping a search that has not
  /// started yet makes it return immediately once it starts.
  Future<SearchResult> stop() {
    _job.requestStop();
    return result;
  }

  /// Sends `ponderhit`: the opponent played the expected move, so the
  /// ponder search continues as a normal search.
  void ponderHit() => _job.ponderHit();
}

/// A snapshot of a multi-PV analysis.
@immutable
final class AnalysisSnapshot {
  /// Creates a snapshot.
  const AnalysisSnapshot({required this.lines});

  /// The current principal variations, best first (at most `MultiPV`).
  final List<SearchInfo> lines;

  /// The best line.
  SearchInfo? get best => lines.isEmpty ? null : lines.first;

  /// Depth of the best line.
  int get depth => best?.depth ?? 0;

  /// Nodes searched so far.
  int get nodes => lines.fold(0, (m, l) => (l.nodes ?? 0) > m ? l.nodes! : m);

  /// Search speed.
  int get nps => best?.nps ?? 0;

  /// Time searched.
  Duration get time => best?.time ?? Duration.zero;

  @override
  String toString() => [
    for (final l in lines)
      '#${l.multiPv ?? 1} d${l.depth} ${l.score} ${l.pv.take(6).join(' ')}',
  ].join('\n');
}

/// A live analysis started with `Stockfish.analyze`: an infinite search whose
/// info lines are aggregated into [AnalysisSnapshot]s, one line per PV.
final class Analysis {
  /// Wraps [search].
  Analysis(this.search, {Duration? throttle}) : _throttle = throttle {
    _subscription = search.info.listen(_onInfo, onDone: _onDone);
  }

  /// The underlying search.
  final SearchHandle search;

  final Duration? _throttle;
  late final StreamSubscription<SearchInfo> _subscription;
  final _snapshots = StreamController<AnalysisSnapshot>.broadcast();
  final _lines = <int, SearchInfo>{};
  AnalysisSnapshot? _latest;
  Timer? _pending;
  DateTime? _lastEmit;
  final _finished = Completer<void>();

  /// Snapshots, emitted whenever a line changes (at most once per throttle
  /// interval, if one was given).
  Stream<AnalysisSnapshot> get snapshots => _snapshots.stream;

  /// The most recent snapshot.
  AnalysisSnapshot? get latest => _latest;

  /// Completes when the search ends.
  /// Completes after the last snapshot has been delivered.
  Future<SearchResult> get result => search.result.then((r) async {
    await _finished.future;
    return r;
  });

  /// Stops the analysis and returns the final result.
  Future<SearchResult> stop() {
    search.stop().ignore();
    return result;
  }

  void _onInfo(SearchInfo info) {
    if (info.pv.isEmpty || info.score == null) return;
    final index = info.multiPv ?? 1;
    _lines[index] = info;
    // Lines more than one ply behind the best line are stale.
    final depth = _lines[1]?.depth ?? info.depth ?? 0;
    _lines.removeWhere((k, v) => k != 1 && (v.depth ?? 0) < depth - 1);
    _latest = AnalysisSnapshot(
      lines: List.unmodifiable([
        for (final k in _lines.keys.toList()..sort()) _lines[k]!,
      ]),
    );
    _schedule();
  }

  void _schedule() {
    final throttle = _throttle;
    if (throttle == null) {
      _emit();
      return;
    }
    if (_pending != null) return;
    final since = _lastEmit == null
        ? throttle
        : DateTime.now().difference(_lastEmit!);
    _pending = Timer(
      since >= throttle ? Duration.zero : throttle - since,
      _emit,
    );
  }

  void _emit() {
    _pending = null;
    _lastEmit = DateTime.now();
    if (_latest != null && !_snapshots.isClosed) _snapshots.add(_latest!);
  }

  void _onDone() {
    _pending?.cancel();
    if (_pending != null) _emit();
    unawaited(_subscription.cancel());
    _snapshots.close().whenComplete(_finished.complete).ignore();
  }
}
