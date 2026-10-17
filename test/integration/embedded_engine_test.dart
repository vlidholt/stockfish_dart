// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Tests against the real embedded engine. Kept in one file: only one
// embedded engine can run per process, and test suites share the process.
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:test/test.dart';

void main() {
  late Stockfish engine;

  setUpAll(() async {
    engine = await Stockfish.start();
  });

  tearDownAll(() => engine.dispose());

  test('library info', () {
    final info = Stockfish.inspectEmbeddedLibrary();
    expect(info.loadedVariant, isNotNull, reason: info.loadError);
    expect(info.supportedVariants, contains(info.loadedVariant));
    expect(info.netSize, greaterThan(50 * 1024 * 1024));
  });

  test('handshake', () {
    expect(engine.identity.name, 'Stockfish 19 (modified by stockfish_dart)');
    expect(engine.identity.version, '19');
    expect(engine.optionSpecs.keys.toSet(), {
      ...OptionNames.ordered,
      OptionNames.clearHash,
    });
  });

  test('a second embedded engine is refused', () async {
    await expectLater(
      Stockfish.start(),
      throwsA(isA<EngineAlreadyRunningException>()),
    );
  });

  test('every option can be set', () async {
    final dir = await Directory.systemTemp.createTemp('sfd');
    addTearDown(() => dir.delete(recursive: true));
    await engine.setOptions(
      StockfishOptions(
        threads: 2,
        hashMb: 32,
        ponder: true,
        multiPv: 2,
        skillLevel: 19,
        moveOverhead: 20,
        nodesTime: 0,
        chess960: false,
        limitStrength: false,
        elo: 2500,
        showWdl: true,
        syzygyPath: '',
        syzygyProbeDepth: 2,
        syzygy50MoveRule: true,
        syzygyProbeLimit: 6,
        numaPolicy: NumaPolicy.auto,
        debugLogFile: '${dir.path}${Platform.pathSeparator}uci.log',
      ),
    );
    final r = await engine.bestMove(
      Position.startpos(),
      limits: const SearchLimits.depth(8),
    );
    expect(r.lines, hasLength(2));
    expect(r.finalInfo!.wdl, isNotNull);
    await engine.setOptions(
      const StockfishOptions(
        threads: 1,
        hashMb: 16,
        ponder: false,
        multiPv: 1,
        skillLevel: 20,
        showWdl: false,
        debugLogFile: '',
      ),
    );
    final log = File('${dir.path}${Platform.pathSeparator}uci.log');
    expect(log.readAsStringSync(), contains('go depth 8'));
  });

  test('bestMove from the start position', () async {
    final r = await engine.bestMove(
      Position.startpos(moves: [UciMove('e2e4')]),
      limits: const SearchLimits.depth(12),
    );
    expect(r.bestMove, isNotNull);
    expect(r.finalInfo!.depth, 12);
    expect(r.score, isA<CentipawnScore>());
  });

  test('finds a mate', () async {
    final r = await engine.bestMove(
      Position.fromFen(
        'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
      ),
      limits: const SearchLimits.mate(2),
    );
    expect(r.bestMove, UciMove('h5f7'));
    expect(r.score, const MateScore(1));
  });

  test('checkmate and stalemate positions', () async {
    final mated = await engine.bestMove(
      Position.fromFen(
        'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
      ),
      limits: const SearchLimits.depth(3),
    );
    expect(mated.bestMove, isNull);
    expect(mated.terminal, TerminalState.checkmate);
    final stalemate = await engine.bestMove(
      Position.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'),
      limits: const SearchLimits.depth(3),
    );
    expect(stalemate.terminal, TerminalState.stalemate);
  });

  test('infinite analysis with multi-PV', () async {
    await engine.setOptions(const StockfishOptions(multiPv: 3));
    addTearDown(() => engine.setOptions(const StockfishOptions(multiPv: 1)));
    final analysis = engine.analyze(
      Position.startpos(),
      throttle: const Duration(milliseconds: 50),
    );
    final snapshot = await analysis.snapshots.firstWhere((s) => s.depth >= 8);
    expect(snapshot.lines, hasLength(3));
    final result = await analysis.stop();
    expect(result.wasStopped, isTrue);
    expect(result.lines, hasLength(3));
  });

  test('searchmoves restricts the root moves', () async {
    final r = await engine.bestMove(
      Position.startpos(),
      limits: const SearchLimits.depth(6),
      searchMoves: [UciMove('a2a3')],
    );
    expect(r.bestMove, UciMove('a2a3'));
  });

  test('pondering', () async {
    final handle = engine.search(
      position: Position.startpos(moves: [UciMove('e2e4'), UciMove('e7e5')]),
      ponder: true,
      limits: const SearchLimits.clock(
        GameClock(
          whiteTime: Duration(seconds: 2),
          blackTime: Duration(seconds: 2),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(handle.isDone, isFalse);
    handle.ponderHit();
    final r = await handle.result;
    expect(r.bestMove, isNotNull);
  });

  test('Chess960 castling notation', () async {
    await engine.setOptions(const StockfishOptions(chess960: true));
    addTearDown(
      () => engine.setOptions(const StockfishOptions(chess960: false)),
    );
    // In Chess960 mode castling is written as the king taking its rook.
    final p = Position.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    final r = await engine.perft(1, position: p);
    expect(r.divide.keys, containsAll([UciMove('e1h1'), UciMove('e1a1')]));
    expect(r.divide.keys, isNot(contains(UciMove('e1g1'))));
  });

  test('perft', () async {
    final r = await engine.perft(4, position: Position.startpos());
    expect(r.nodes, 197281);
    final kiwipete = await engine.perft(
      3,
      position: Position.fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      ),
    );
    expect(kiwipete.nodes, 97862);
  });

  test('d, eval, flip, compiler, help', () async {
    final d = await engine.display(position: Position.startpos());
    expect(d.fen, Position.standardStartFen);
    final e = await engine.evaluate(
      position: Position.startpos(moves: [UciMove('e2e4')]),
    );
    expect(e.buckets, isNotEmpty);
    expect(e.finalWhite, isNotNull);
    final flipped = await engine.flip();
    expect(flipped.fen, startsWith('rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP'));
    final c = await engine.compilerInfo();
    expect(c.architecture, isNotNull);
    expect(await engine.help(), contains('GNU GPLv3'));
  });

  test('bench and speedtest restore settings', () async {
    await engine.setOptions(const StockfishOptions(hashMb: 32));
    await engine.setPosition(Position.startpos(moves: [UciMove('d2d4')]));
    final progress = <String>[];
    final b = await engine.bench(
      const BenchConfig(limit: 4, hashMb: 8),
      progress.add,
    );
    expect(b.nodes, greaterThan(0));
    expect(progress, isNotEmpty);
    final s = await engine.speedtest(
      const SpeedtestConfig(
        threads: 1,
        hashMb: 16,
        duration: Duration(seconds: 1),
      ),
    );
    expect(s.nodesPerSecond, greaterThan(0));
    final d = await engine.display();
    expect(d.fen, startsWith('rnbqkbnr/pppppppp/8/8/3P4'));
    expect(engine.options.hashMb, 32);
    await engine.setOptions(const StockfishOptions(hashMb: 16));
  });

  test('export_net', () async {
    final dir = await Directory.systemTemp.createTemp('sfd');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}net.nnue';
    final message = await engine.exportNet(path);
    expect(message, contains('saved successfully'));
    expect(File(path).lengthSync(), greaterThan(50 * 1024 * 1024));
  });

  group('recoverable errors', () {
    test('illegal move', () async {
      final good = Position.startpos(moves: [UciMove('e2e4')]);
      await engine.setPosition(good);
      await expectLater(
        engine.setPosition(Position.startpos(moves: [UciMove('e2e5')])),
        throwsA(isA<EngineCommandException>()),
      );
      expect((await engine.display()).fen, contains('4P3'));
    });

    test('illegal FEN', () async {
      await expectLater(
        engine.bestMove(
          // Structurally fine, but the side not to move is in check.
          Position.fromFen(
            '4k3/8/8/8/8/8/4R3/4K3 w - - 0 1',
          ).play(UciMove('e2e3')),
          limits: const SearchLimits.depth(2),
        ),
        throwsA(isA<StockfishException>()),
      );
      final r = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(2),
      );
      expect(r.bestMove, isNotNull);
    });

    test('unopenable debug log file', () async {
      await expectLater(
        engine.setOptions(
          StockfishOptions(
            debugLogFile:
                '${Directory.systemTemp.path}/does/not/exist/sfd-${DateTime.now().microsecondsSinceEpoch}/log.txt',
          ),
        ),
        throwsA(isA<EngineCommandException>()),
      );
      expect(engine.state, EngineState.idle);
    });

    test('impossible hash size restarts the engine', () async {
      await expectLater(
        engine.setOptions(const StockfishOptions(hashMb: 33554432)),
        throwsA(
          isA<EngineFatalException>().having(
            (e) => e.restarted,
            'restarted',
            true,
          ),
        ),
      );
      final r = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(4),
      );
      expect(r.bestMove, isNotNull);
      expect(engine.options.hashMb, isNot(33554432));
    }, skip: Platform.isMacOS ? 'macOS overcommits memory' : null);

    test('corrupt tablebase probed during search', () async {
      final dir = await Directory.systemTemp.createTemp('sfd-tb');
      addTearDown(() async {
        await engine.setOptions(const StockfishOptions(syzygyPath: ''));
        await dir.delete(recursive: true);
      });
      for (final name in ['KQvK.rtbw', 'KQvK.rtbz', 'KRvK.rtbw', 'KRvK.rtbz']) {
        File(
          '${dir.path}${Platform.pathSeparator}$name',
        ).writeAsBytesSync(List.filled(100, 7));
      }
      await engine.setOptions(StockfishOptions(syzygyPath: dir.path));
      try {
        await engine.bestMove(
          Position.fromFen('8/8/8/4k3/8/8/8/KQ6 w - - 0 1'),
          limits: const SearchLimits.depth(6),
        );
      } on StockfishException {
        // Expected: the corrupt file is detected (on a search thread).
      }
      final r = await engine.bestMove(
        Position.startpos(),
        limits: const SearchLimits.depth(4),
      );
      expect(r.bestMove, isNotNull);
      expect(engine.optionSpecs, hasLength(19));
    });
  });
}
