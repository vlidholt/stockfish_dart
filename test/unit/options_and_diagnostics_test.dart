// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:test/test.dart';

List<String> lines(String name) =>
    File('test/fixtures/sf19/$name').readAsLinesSync();

void main() {
  group('StockfishOptions', () {
    test('toUciMap applies NUMA, threads and hash first', () {
      const o = StockfishOptions(
        multiPv: 3,
        hashMb: 256,
        threads: 4,
        numaPolicy: NumaPolicy.none,
        showWdl: true,
      );
      expect(o.toUciMap().keys.toList(), [
        'NumaPolicy',
        'Threads',
        'Hash',
        'MultiPV',
        'UCI_ShowWDL',
      ]);
      expect(o.toUciMap()['UCI_ShowWDL'], 'true');
    });

    test('round trip through fromUciMap', () {
      const o = StockfishOptions(
        threads: 2,
        hashMb: 64,
        ponder: true,
        multiPv: 2,
        skillLevel: 10,
        moveOverhead: 50,
        nodesTime: 0,
        chess960: true,
        limitStrength: true,
        elo: 2000,
        showWdl: true,
        syzygyPath: '/tb',
        syzygyProbeDepth: 4,
        syzygy50MoveRule: false,
        syzygyProbeLimit: 6,
        evalFile: 'net.nnue',
        numaPolicy: NumaPolicy.hardware,
        debugLogFile: 'log.txt',
      );
      expect(o.toUciMap(), hasLength(18));
      expect(StockfishOptions.fromUciMap(o.toUciMap()), o);
    });

    test('copyWith and merge', () {
      const o = StockfishOptions(threads: 2, multiPv: 3);
      expect(o.copyWith(threads: 4).threads, 4);
      expect(o.copyWith(threads: null).threads, isNull);
      expect(o.copyWith().multiPv, 3);
      final m = o.merge(const StockfishOptions(multiPv: 1, hashMb: 32));
      expect(m, const StockfishOptions(threads: 2, multiPv: 1, hashMb: 32));
    });

    test('strength limits', () {
      expect(
        StockfishOptions.strength(const StrengthLimit.elo(1800)),
        const StockfishOptions(limitStrength: true, elo: 1800),
      );
      expect(
        StockfishOptions.strength(const StrengthLimit.skill(5)),
        const StockfishOptions(limitStrength: false, skillLevel: 5),
      );
      expect(
        StockfishOptions.strength(StrengthLimit.full),
        const StockfishOptions(limitStrength: false, skillLevel: 20),
      );
    });

    test('syzygy path helper', () {
      final sep = Platform.isWindows ? ';' : ':';
      expect(StockfishOptions.syzygyPathsFromList(['a', 'b']), 'a${sep}b');
    });
  });

  group('diagnostics parsers', () {
    test('perft', () {
      final r = PerftResult.parse(3, lines('perft.out.txt'));
      expect(r.nodes, 8902);
      expect(r.divide, hasLength(20));
      expect(r.divide[UciMove('e2e4')], 600);
      expect(r.divide.values.fold(0, (a, b) => a + b), 8902);
    });

    test('d', () {
      final d = BoardDisplay.parse(lines('display.out.txt'));
      expect(
        d.fen,
        'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      );
      expect(d.key, matches(RegExp(r'^[0-9A-F]{16}$')));
      expect(d.checkers, isEmpty);
      expect(d.ascii, contains('| r | n | b | q | k | b | n | r | 8'));
      expect(d.tablebase, isNull);
    });

    test('d with checkers and tablebases', () {
      final d = BoardDisplay.parse([
        'Fen: 4k3/8/8/8/8/8/4R3/4K3 b - - 0 1',
        'Key: 0123456789ABCDEF',
        'Checkers: e2 ',
        'Tablebases WDL:   -2 (1)',
        'Tablebases DTZ:  -11 (1)',
      ]);
      expect(d.checkers, ['e2']);
      expect(d.tablebase!.wdl, -2);
      expect(d.tablebase!.dtz, -11);
    });

    test('eval', () {
      final e = EvalTrace.parse(lines('eval.out.txt'));
      expect(e.buckets, hasLength(8));
      expect(e.buckets.where((b) => b.used).single.bucket, 7);
      expect(e.buckets.first.material, 0.15);
      expect(e.buckets.first.positional, -0.29);
      expect(e.nnueInternal, -60);
      expect(e.nnueWhite, 0.21);
      expect(e.finalWhite, 0.27);
      expect(e.raw, startsWith('NNUE network contributions'));
    });

    test('compiler', () {
      final c = CompilerInfo.parse(lines('compiler.out.txt'));
      expect(c.compiledBy, startsWith('clang++'));
      expect(c.architecture, 'x86-64-avx2');
      expect(c.settings, contains('AVX2'));
    });

    test('bench', () {
      final b = BenchResult.parse(
        lines('bench.out.txt'),
        lines('bench.err.txt'),
      );
      expect(b.nodes, 74059);
      expect(b.nodesPerSecond, 861151);
      expect(b.totalTime, const Duration(milliseconds: 86));
      expect(b.positions, 51);
    });

    test('speedtest', () {
      final s = SpeedtestResult.parse(lines('speedtest.err.txt'));
      expect(s.version, 'Stockfish 19 (modified by stockfish_dart)');
      expect(s.threads, 1);
      expect(s.ttSizeMb, 16);
      expect(s.nodes, 930455);
      expect(s.nodesPerSecond, 1107684);
      expect(s.searchTime, const Duration(milliseconds: 840));
      expect(s.largePages, isFalse);
      expect(s.fields['Hash max, avg [per mille] single game'], '56, 32');
    });

    test('bench and speedtest arguments', () {
      expect(const BenchConfig().toArguments(), [
        '16',
        '1',
        '13',
        'default',
        'depth',
      ]);
      expect(
        const BenchConfig(
          positions: BenchPositions.current,
          limitType: BenchLimitType.nodes,
          limit: 1000,
        ).toArguments(),
        ['16', '1', '1000', 'current', 'nodes'],
      );
      expect(const SpeedtestConfig().toArguments(), isEmpty);
      expect(
        const SpeedtestConfig(
          threads: 2,
          hashMb: 64,
          duration: Duration(seconds: 5),
        ).toArguments(),
        ['2', '64', '5'],
      );
    });
  });

  group('EngineIdentity', () {
    test('version', () {
      expect(
        const EngineIdentity(
          name: 'Stockfish 19 (modified by stockfish_dart)',
          author: 'x',
        ).version,
        '19',
      );
      expect(
        const EngineIdentity(
          name: 'Stockfish dev-20261017-effdc3fd',
          author: 'x',
        ).version,
        'dev-20261017-effdc3fd',
      );
      expect(const EngineIdentity(name: 'Lc0', author: 'x').version, isNull);
    });
  });
}
