// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';

import '../transport/engine_transport.dart';

/// The `option` lines Stockfish 19 prints in the `uci` handshake.
const stockfish19OptionLines = [
  'option name Debug Log File type string default <empty>',
  'option name NumaPolicy type string default auto',
  'option name Threads type spin default 1 min 1 max 1024',
  'option name Hash type spin default 16 min 1 max 33554432',
  'option name Clear Hash type button',
  'option name Ponder type check default false',
  'option name MultiPV type spin default 1 min 1 max 256',
  'option name Skill Level type spin default 20 min 0 max 20',
  'option name Move Overhead type spin default 10 min 0 max 5000',
  'option name nodestime type spin default 0 min 0 max 10000',
  'option name UCI_Chess960 type check default false',
  'option name UCI_LimitStrength type check default false',
  'option name UCI_Elo type spin default 1320 min 1320 max 3190',
  'option name UCI_ShowWDL type check default false',
  'option name SyzygyPath type string default <empty>',
  'option name SyzygyProbeDepth type spin default 1 min 1 max 100',
  'option name Syzygy50MoveRule type check default true',
  'option name SyzygyProbeLimit type spin default 7 min 0 max 7',
  'option name EvalFile type string default nn-1a298aa575a0.nnue',
];

/// A scripted stand-in for Stockfish that speaks enough UCI for
/// `Stockfish.withTransport`: handshake, `isready`, options, positions,
/// searches (finite, infinite and ponder), plus canned responses for any
/// other command.
final class FakeStockfish extends EngineTransport {
  /// Creates a fake engine.
  FakeStockfish({
    this.name = 'Stockfish 19 (fake)',
    List<String> optionLines = stockfish19OptionLines,
  }) : _optionLines = optionLines;

  /// The `id name` reported.
  final String name;
  final List<String> _optionLines;

  final _events = StreamController<TransportEvent>.broadcast();
  final _responses = <(Pattern, List<String>)>[];
  final _received = <String>[];
  final _options = <String, String?>{};
  bool _running = false;
  List<String>? _pendingSearchOutput;
  bool _respondToUci = true;

  /// Produces the output of a `go` command (info lines and `bestmove`).
  /// For infinite and ponder searches it is emitted when `stop` (or, for
  /// finite ponder searches, `ponderhit`) arrives.
  List<String> Function(String goCommand) onGo = (_) => const [
    'info depth 1 seldepth 1 multipv 1 score cp 20 nodes 20 nps 20000 hashfull 0 tbhits 0 time 1 pv e2e4',
    'bestmove e2e4 ponder e7e5',
  ];

  /// Returns a reason to reject a `position` command (as Stockfish's
  /// `CRITICAL ERROR`), or null to accept it.
  String? Function(String positionCommand) validatePosition = (_) => null;

  /// Every line received, in order.
  List<String> get received => List.unmodifiable(_received);

  /// Option values set with `setoption`.
  Map<String, String?> get options => Map.unmodifiable(_options);

  /// Whether the fake engine is running.
  bool get isRunning => _running;

  /// Answer commands matching [command] with [lines] (before `readyok` when
  /// followed by `isready`). Later registrations take precedence.
  void respondTo(Pattern command, List<String> lines) =>
      _responses.insert(0, (command, lines));

  /// Makes the next handshake hang (to test timeouts).
  void ignoreHandshake() => _respondToUci = false;

  /// Emits an engine output line.
  void emit(String line, {bool isError = false}) =>
      _events.add(OutputLine(line, isError: isError));

  /// Simulates an unrecoverable engine error.
  void crash([String reason = 'simulated crash']) {
    if (!_running) return;
    _running = false;
    _pendingSearchOutput = null;
    _events
      ..add(FatalEvent(reason))
      ..add(const ExitedEvent());
  }

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  String get description => 'fake Stockfish';

  @override
  Future<void> start() async {
    _running = true;
  }

  @override
  void send(String line) {
    _received.add(line);
    if (!_running) return;
    // Respond asynchronously, like a real engine.
    scheduleMicrotask(() => _handle(line));
  }

  void _handle(String line) {
    if (!_running) return;
    final head = line.split(' ').first;
    for (final (pattern, lines) in _responses) {
      if (pattern.matchAsPrefix(line) != null) {
        lines.forEach(emit);
        return;
      }
    }
    switch (head) {
      case 'uci':
        if (!_respondToUci) return;
        emit('id name $name');
        emit('id author the Stockfish developers (see AUTHORS file)');
        emit('');
        _optionLines.forEach(emit);
        emit('uciok');
      case 'isready':
        emit('readyok');
      case 'setoption':
        final m = RegExp(
          r'^setoption name (.+?)(?: value (.*))?$',
        ).firstMatch(line);
        final optionName = m?.group(1) ?? '';
        final known = _optionLines.any(
          (l) => l.toLowerCase().startsWith(
            'option name ${optionName.toLowerCase()} type',
          ),
        );
        if (!known) {
          emit('No such option: $optionName');
        } else {
          _options[optionName] = m?.group(2);
        }
      case 'position':
        final reason = validatePosition(line);
        if (reason != null) {
          emit(
            'info string CRITICAL ERROR: Command `$line` failed. Reason: $reason',
          );
        }
      case 'go':
        final output = onGo(line);
        final tokens = line.split(' ');
        if (tokens.contains('infinite') || tokens.contains('ponder')) {
          final bestIndex = output.indexWhere((l) => l.startsWith('bestmove'));
          output.take(bestIndex < 0 ? output.length : bestIndex).forEach(emit);
          _pendingSearchOutput = bestIndex < 0
              ? const []
              : output.sublist(bestIndex);
        } else {
          output.forEach(emit);
        }
      case 'stop':
        final pending = _pendingSearchOutput;
        _pendingSearchOutput = null;
        pending?.forEach(emit);
      case 'ponderhit':
        break;
      case 'quit':
        _running = false;
        _pendingSearchOutput = null;
        _events.add(const ExitedEvent(0));
      case 'ucinewgame':
        break;
      default:
        emit("Unknown command: '$line'. Type help for more information.");
    }
  }

  @override
  Future<void> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (!_running) return;
    _running = false;
    _pendingSearchOutput = null;
    _events.add(const ExitedEvent(0));
  }
}
