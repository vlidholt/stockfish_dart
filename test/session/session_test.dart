// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:async';

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:stockfish_dart/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeStockfish fake;
  late Stockfish engine;

  Future<Stockfish> startEngine({
    RestartPolicy restartPolicy = RestartPolicy.always,
    StockfishOptions options = const StockfishOptions(),
  }) async => engine = await Stockfish.withTransport(
    fake,
    restartPolicy: restartPolicy,
    options: options,
  );

  setUp(() => fake = FakeStockfish());
  tearDown(() => engine.dispose());

  group('handshake', () {
    test('reads identity and options', () async {
      await startEngine();
      expect(engine.identity.name, 'Stockfish 19 (fake)');
      expect(engine.identity.version, '19');
      expect(engine.optionSpecs, hasLength(19));
      expect(engine.optionSpecs['hash'], isA<SpinOptionSpec>());
      expect(engine.state, EngineState.idle);
      expect(fake.received.take(2), ['uci', 'isready']);
    });

    test('times out', () async {
      fake.ignoreHandshake();
      await expectLater(
        Stockfish.withTransport(
          fake,
          handshakeTimeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<EngineStartException>()),
      );
      engine = await Stockfish.withTransport(FakeStockfish());
    });

    test('applies initial options', () async {
      await startEngine(
        options: const StockfishOptions(threads: 2, multiPv: 3),
      );
      expect(fake.options, {'Threads': '2', 'MultiPV': '3'});
      expect(engine.options, const StockfishOptions(threads: 2, multiPv: 3));
    });
  });

  group('options', () {
    setUp(() => startEngine());

    test('only changed values are sent, in order', () async {
      await engine.setOptions(const StockfishOptions(multiPv: 2, hashMb: 64));
      await engine.setOptions(const StockfishOptions(multiPv: 2, threads: 3));
      final sent = fake.received.where((l) => l.startsWith('setoption'));
      expect(sent, [
        'setoption name Hash value 64',
        'setoption name MultiPV value 2',
        'setoption name Threads value 3',
      ]);
    });

    test('out of range values are rejected before sending', () async {
      await expectLater(
        engine.setOptions(const StockfishOptions(multiPv: 0)),
        throwsA(isA<InvalidOptionException>()),
      );
      await expectLater(
        engine.setOption('UCI_Elo', 5000),
        throwsA(isA<InvalidOptionException>()),
      );
      await expectLater(
        engine.setOption('Ponder', 'maybe'),
        throwsA(isA<InvalidOptionException>()),
      );
      await expectLater(
        engine.setOption('Nope', 1),
        throwsA(isA<InvalidOptionException>()),
      );
      expect(fake.received.where((l) => l.startsWith('setoption')), isEmpty);
    });

    test('raw options and buttons', () async {
      await engine.setOption('skill level', 7);
      await engine.clearHash();
      expect(fake.received.where((l) => l.startsWith('setoption')), [
        'setoption name Skill Level value 7',
        'setoption name Clear Hash',
      ]);
      expect(engine.options.skillLevel, 7);
    });

    test('empty strings are sent as <empty>', () async {
      await engine.setOptions(const StockfishOptions(syzygyPath: ''));
      expect(
        fake.received,
        contains('setoption name SyzygyPath value <empty>'),
      );
    });
  });

  group('searching', () {
    setUp(() => startEngine());

    test('bestMove returns the result', () async {
      final r = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(5),
      );
      expect(r.bestMove, UciMove('e2e4'));
      expect(r.ponderMove, UciMove('e7e5'));
      expect(r.score, const CentipawnScore(20));
      expect(r.wasStopped, isFalse);
      expect(
        fake.received,
        containsAllInOrder(['position startpos', 'go depth 5']),
      );
    });

    test('bestMove needs a finite limit', () {
      expect(
        () =>
            engine.bestMove(Position.startpos(), limits: const SearchLimits()),
        throwsArgumentError,
      );
    });

    test('info lines are streamed', () async {
      fake.onGo = (_) => [
        'info depth 1 score cp 10 pv d2d4',
        'info depth 2 score cp 12 pv d2d4 d7d5',
        'bestmove d2d4',
      ];
      final handle = engine.search(limits: const SearchLimits.depth(2));
      final infos = handle.info.toList();
      final result = await handle.result;
      expect((await infos).map((i) => i.depth), [1, 2]);
      expect(result.bestMove, UciMove('d2d4'));
      expect(result.ponderMove, isNull);
    });

    test('infinite search blocks other commands until stopped', () async {
      final handle = engine.search();
      await pumpEventQueue();
      expect(handle.isUnbounded, isTrue);
      expect(
        () => engine.setPosition(Position.startpos()),
        throwsA(isA<EngineBusyException>()),
      );
      final result = await handle.stop();
      expect(result.wasStopped, isTrue);
      await engine.setPosition(Position.startpos());
    });

    test('interrupt stops the running search', () async {
      final first = engine.search();
      final second = engine.search(
        limits: const SearchLimits.depth(3),
        interrupt: true,
      );
      expect((await first.result).wasStopped, isTrue);
      expect((await second.result).bestMove, UciMove('e2e4'));
    });

    test('stop() stops the active search', () async {
      engine.search();
      await pumpEventQueue();
      final result = await engine.stop();
      expect(result?.bestMove, UciMove('e2e4'));
      expect(await engine.stop(), isNull);
    });

    test('ponder and ponderhit', () async {
      final handle = engine.search(
        ponder: true,
        limits: const SearchLimits.clock(
          GameClock(
            whiteTime: Duration(minutes: 1),
            blackTime: Duration(minutes: 1),
          ),
        ),
      );
      await pumpEventQueue();
      expect(handle.isPondering, isTrue);
      expect(fake.received.last, startsWith('go ponder wtime 60000'));
      handle.ponderHit();
      expect(fake.received.last, 'ponderhit');
      expect(handle.isPondering, isFalse);
      await handle.stop();
    });

    test('checkmate and stalemate', () async {
      fake.onGo = (_) => ['info depth 0 score mate 0', 'bestmove (none)'];
      final mate = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(1),
      );
      expect(mate.bestMove, isNull);
      expect(mate.terminal, TerminalState.checkmate);

      fake.onGo = (_) => ['info depth 0 score cp 0', 'bestmove (none)'];
      final stale = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(1),
      );
      expect(stale.terminal, TerminalState.stalemate);
    });

    test('analysis aggregates multi-PV lines', () async {
      fake.onGo = (_) => [
        'info depth 1 multipv 1 score cp 30 pv e2e4',
        'info depth 1 multipv 2 score cp 20 pv d2d4',
        'info depth 2 multipv 1 score cp 25 pv e2e4 e7e5',
        'info depth 2 multipv 2 score cp 22 pv d2d4 d7d5',
        'info depth 3 multipv 1 score cp 28 pv e2e4 e7e5 g1f3',
        'bestmove e2e4',
      ];
      final analysis = engine.analyze(Position.startpos());
      final snapshots = analysis.snapshots.toList();
      await pumpEventQueue();
      final result = await analysis.stop();
      final all = await snapshots;
      expect(all, hasLength(5));
      expect(all.last.lines.map((l) => l.pv.first), [
        UciMove('e2e4'),
        UciMove('d2d4'),
      ]);
      expect(all.last.depth, 3);
      expect(analysis.latest!.best!.score, const CentipawnScore(28));
      expect(result.lines, hasLength(2));
    });
  });

  group('errors', () {
    test('rejected position keeps the previous one', () async {
      await startEngine();
      fake.validatePosition = (cmd) =>
          cmd.contains('e2e5') ? 'Illegal move: e2e5' : null;
      final good = Position.startpos(moves: [UciMove('e2e4')]);
      await engine.setPosition(good);
      await expectLater(
        engine.setPosition(Position.startpos(moves: [UciMove('e2e5')])),
        throwsA(
          isA<EngineCommandException>().having(
            (e) => e.reason,
            'reason',
            'Illegal move: e2e5',
          ),
        ),
      );
      expect(engine.position, good);
      // The good position is re-sent, as Stockfish resets after an error.
      expect(
        fake.received.where((l) => l == 'position startpos moves e2e4'),
        hasLength(2),
      );
    });

    test('search on an invalid position fails without searching', () async {
      await startEngine();
      fake.validatePosition = (_) => 'Invalid FEN';
      await expectLater(
        engine.bestMove(
          Position.startpos(),
          limits: const SearchLimits.depth(1),
        ),
        throwsA(isA<EngineCommandException>()),
      );
      expect(fake.received.where((l) => l.startsWith('go')), isEmpty);
    });

    test('unknown option reported by the engine', () async {
      await startEngine();
      await expectLater(
        engine.sendRaw('setoption name Bogus value 1', unsafe: true),
        throwsA(isA<InvalidOptionException>()),
      );
    });

    test('sendRaw rejects tracked commands', () async {
      await startEngine();
      expect(() => engine.sendRaw('position startpos'), throwsArgumentError);
      expect(() => engine.sendRaw('d\ngo'), throwsArgumentError);
      fake.respondTo('d', ['Fen: x']);
      expect(await engine.sendRaw('d'), ['Fen: x']);
    });

    test('crash during a search restarts and replays state', () async {
      await startEngine(options: const StockfishOptions(threads: 2));
      await engine.setPosition(Position.startpos(moves: [UciMove('d2d4')]));
      final failures = <StockfishException>[];
      engine.failures.listen(failures.add);

      final handle = engine.search();
      await pumpEventQueue();
      fake.crash('Failed to allocate 1 bytes.');
      await expectLater(
        handle.result,
        throwsA(
          isA<EngineFatalException>()
              .having((e) => e.restarted, 'restarted', isTrue)
              .having((e) => e.reason, 'reason', contains('allocate')),
        ),
      );
      final r = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(1),
      );
      expect(r.bestMove, UciMove('e2e4'));
      expect(fake.received.where((l) => l == 'uci'), hasLength(2));
      final afterCrash = fake.received
          .skip(fake.received.lastIndexOf('uci'))
          .toList();
      expect(afterCrash, contains('setoption name Threads value 2'));
      expect(afterCrash, contains('position startpos moves d2d4'));
      expect(failures.single, isA<EngineFatalException>());
    });

    test('RestartPolicy.never leaves the engine failed', () async {
      await startEngine(restartPolicy: RestartPolicy.never);
      fake.crash();
      await pumpEventQueue();
      expect(engine.state, EngineState.failed);
      await expectLater(engine.isReady(), throwsA(isA<EngineFatalException>()));
    });

    test('limited restart policy', () {
      const p = RestartPolicy.limited(2, Duration(minutes: 1));
      final now = DateTime(2026);
      expect(p.allows([], now), isTrue);
      expect(p.allows([now, now], now), isFalse);
      expect(
        p.allows([now.subtract(const Duration(minutes: 5)), now], now),
        isTrue,
      );
    });
  });

  group('lifecycle', () {
    test('dispose fails pending work and is idempotent', () async {
      await startEngine();
      final handle = engine.search();
      await pumpEventQueue();
      await engine.dispose();
      await expectLater(handle.result, throwsA(isA<EngineDisposedException>()));
      expect(engine.isDisposed, isTrue);
      await engine.dispose();
      await expectLater(
        engine.isReady(),
        throwsA(isA<EngineDisposedException>()),
      );
    });

    test('traffic hook sees both directions', () async {
      final traffic = <UciTrafficEntry>[];
      engine = await Stockfish.withTransport(fake, onTraffic: traffic.add);
      expect(traffic.first.outgoing, isTrue);
      expect(traffic.first.line, 'uci');
      expect(traffic.any((t) => !t.outgoing && t.line == 'uciok'), isTrue);
    });

    test('flip tracks the new position', () async {
      await startEngine();
      fake.respondTo('d', [
        'Fen: rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      ]);
      fake.respondTo('flip', const []);
      final p = await engine.flip();
      expect(p.fen, startsWith('rnbqkbnr/pppp1ppp'));
      expect(engine.position, p);
    });
  });
}
