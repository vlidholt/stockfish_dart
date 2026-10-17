// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:stockfish_dart/uci.dart';
import 'package:test/test.dart';

List<String> fixture(String name) => File(
  'test/fixtures/sf19/$name',
).readAsLinesSync().where((l) => l.isNotEmpty).toList();

void main() {
  group('parseUciLine', () {
    test('handshake lines', () {
      expect(parseUciLine('uciok'), isA<UciOkEvent>());
      expect(parseUciLine('readyok'), isA<ReadyOkEvent>());
      final id = parseUciLine('id name Stockfish 19') as IdEvent;
      expect(id.key, 'name');
      expect(id.value, 'Stockfish 19');
    });

    test('full info line', () {
      final e =
          parseUciLine(
                'info depth 20 seldepth 31 multipv 2 score cp -34 upperbound '
                'wdl 31 912 57 nodes 1234567 nps 987654 hashfull 123 tbhits 7 '
                'time 1250 pv b8c6 f1b5 a7a6',
              )
              as InfoEvent;
      final i = e.info;
      expect(i.depth, 20);
      expect(i.selDepth, 31);
      expect(i.multiPv, 2);
      expect(i.score, const CentipawnScore(-34, bound: ScoreBound.upperBound));
      expect(i.wdl, const Wdl(31, 912, 57));
      expect(i.nodes, 1234567);
      expect(i.nps, 987654);
      expect(i.hashFull, 123);
      expect(i.tbHits, 7);
      expect(i.time, const Duration(milliseconds: 1250));
      expect(i.pv, [UciMove('b8c6'), UciMove('f1b5'), UciMove('a7a6')]);
      expect(i.bestMove, UciMove('b8c6'));
    });

    test('mate scores and lowerbound', () {
      final i =
          (parseUciLine('info depth 5 score mate -3 lowerbound pv e1e2')
                  as InfoEvent)
              .info;
      expect(i.score, const MateScore(-3, bound: ScoreBound.lowerBound));
    });

    test('no-move position', () {
      final i = (parseUciLine('info depth 0 score mate 0') as InfoEvent).info;
      expect(i.depth, 0);
      expect(i.score, const MateScore(0));
      expect(i.pv, isEmpty);
    });

    test('currmove', () {
      final e =
          parseUciLine('info depth 24 currmove e2e4 currmovenumber 3')
              as CurrentMoveEvent;
      expect(e.info.depth, 24);
      expect(e.info.move, UciMove('e2e4'));
      expect(e.info.moveNumber, 3);
    });

    test('unknown info fields are kept', () {
      final i =
          (parseUciLine('info depth 3 frob 42 pv e2e4') as InfoEvent).info;
      expect(i.extra, {'frob': '42'});
      expect(i.pv, [UciMove('e2e4')]);
    });

    test('info string and critical errors', () {
      final s = parseUciLine('info string Using 2 threads') as InfoStringEvent;
      expect(s.text, 'Using 2 threads');
      final c =
          parseUciLine(
                'info string CRITICAL ERROR: Command `position startpos moves '
                'e2e5` failed. Reason: Illegal move: e2e5',
              )
              as CriticalErrorEvent;
      expect(c.command, 'position startpos moves e2e5');
      expect(c.reason, 'Illegal move: e2e5');
    });

    test('bestmove', () {
      final b = parseUciLine('bestmove e2e4 ponder e7e5') as BestMoveEvent;
      expect(b.move, UciMove('e2e4'));
      expect(b.ponder, UciMove('e7e5'));
      final none = parseUciLine('bestmove (none)') as BestMoveEvent;
      expect(none.move, isNull);
      expect(none.ponder, isNull);
    });

    test('errors', () {
      expect(
        (parseUciLine('No such option: Foo Bar') as UnknownOptionEvent).name,
        'Foo Bar',
      );
      expect(
        (parseUciLine(
                  "Unknown command: 'frob'. Type help for more information.",
                )
                as UnknownCommandEvent)
            .command,
        'frob',
      );
      expect(parseUciLine(' +---+---+'), isA<TextEvent>());
    });

    test('every fixture line parses', () {
      final dir = Directory('test/fixtures/sf19');
      for (final f in dir.listSync().whereType<File>()) {
        for (final line in f.readAsLinesSync()) {
          expect(() => parseUciLine(line), returnsNormally, reason: f.path);
        }
      }
    });

    test('multipv fixture yields three lines per depth', () {
      final infos = fixture('search_multipv_wdl.out.txt')
          .map(parseUciLine)
          .whereType<InfoEvent>()
          .map((e) => e.info)
          .where((i) => i.depth == 10)
          .toList();
      expect(infos.map((i) => i.multiPv), [1, 2, 3]);
      expect(infos.every((i) => i.wdl != null), isTrue);
    });

    test('mate fixture finds mate in 1', () {
      final last = fixture(
        'search_mate.out.txt',
      ).map(parseUciLine).whereType<InfoEvent>().last;
      expect(last.info.score, const MateScore(1));
      final best = fixture(
        'search_mate.out.txt',
      ).map(parseUciLine).whereType<BestMoveEvent>().single;
      expect(best.move, UciMove('h5f7'));
    });
  });

  group('UciOptionSpec', () {
    test('parses every Stockfish 19 option', () {
      final specs = fixture(
        'uci.out.txt',
      ).map(parseUciLine).whereType<OptionEvent>().map((e) => e.spec).toList();
      expect(specs, hasLength(19));
      final byName = {for (final s in specs) s.name: s};
      expect(byName['Hash'], isA<SpinOptionSpec>());
      final threads = byName['Threads']! as SpinOptionSpec;
      expect(threads.defaultValue, 1);
      expect(threads.min, 1);
      expect(byName['Clear Hash'], isA<ButtonOptionSpec>());
      expect((byName['UCI_Elo']! as SpinOptionSpec).max, 3190);
      expect((byName['Debug Log File']! as StringOptionSpec).defaultValue, '');
      expect(
        (byName['Syzygy50MoveRule']! as CheckOptionSpec).defaultValue,
        isTrue,
      );
    });

    test('combo options', () {
      final s =
          UciOptionSpec.tryParse(
                'option name Style type combo default Normal var Solid var Normal var Risky',
              )!
              as ComboOptionSpec;
      expect(s.values, ['Solid', 'Normal', 'Risky']);
      expect(s.defaultValue, 'Normal');
    });

    test('every advertised option has a typed field', () {
      final names = fixture('uci.out.txt')
          .map(parseUciLine)
          .whereType<OptionEvent>()
          .map((e) => e.spec.name)
          .where((n) => n != OptionNames.clearHash)
          .toSet();
      expect(names, OptionNames.ordered.toSet());
    });
  });

  group('commands', () {
    test('setoption', () {
      expect(
        const SetOptionCommand('Hash', '128').toUci(),
        'setoption name Hash value 128',
      );
      expect(
        const SetOptionCommand('SyzygyPath', '').toUci(),
        'setoption name SyzygyPath value <empty>',
      );
      expect(
        const SetOptionCommand('Clear Hash').toUci(),
        'setoption name Clear Hash',
      );
    });

    test('go puts searchmoves last', () {
      final go = GoCommand(
        limits: const SearchLimits(
          depth: 10,
          clock: GameClock(
            whiteTime: Duration(minutes: 1),
            blackTime: Duration(seconds: 50),
            whiteIncrement: Duration(seconds: 1),
            movesToGo: 20,
          ),
        ),
        searchMoves: [UciMove('e2e4'), UciMove('d2d4')],
        ponder: true,
      );
      expect(
        go.toUci(),
        'go ponder wtime 60000 btime 50000 winc 1000 movestogo 20 depth 10 '
        'searchmoves e2e4 d2d4',
      );
      expect(const GoCommand().toUci(), 'go infinite');
      expect(
        const GoCommand(limits: SearchLimits.mate(3)).toUci(),
        'go mate 3',
      );
    });

    test('line breaks are rejected', () {
      expect(() => checkSingleLine('d\ngo infinite'), throwsArgumentError);
      expect(() => checkSingleLine('isready\r'), throwsArgumentError);
      checkSingleLine('position startpos');
    });
  });
}
