// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:test/test.dart';

void main() {
  group('UciMove', () {
    test('valid moves', () {
      expect(UciMove('e2e4').from, 'e2');
      expect(UciMove('e2e4').to, 'e4');
      expect(UciMove('e7e8q').promotion, 'q');
      expect(UciMove('E2E4'), UciMove('e2e4'));
      expect(UciMove('0000').isNull, isTrue);
      expect(UciMove.nullMove, UciMove('0000'));
    });

    test('invalid moves', () {
      for (final m in ['e2', 'e9e4', 'i2i4', 'e2e4x', 'Nf3', '']) {
        expect(
          () => UciMove(m),
          throwsA(isA<InvalidMoveException>()),
          reason: m,
        );
        expect(UciMove.tryParse(m), isNull);
      }
    });

    test('parseUciMoves', () {
      expect(parseUciMoves(' e2e4  e7e5 '), [UciMove('e2e4'), UciMove('e7e5')]);
    });
  });

  group('Position', () {
    test('startpos', () {
      final p = Position.startpos(moves: [UciMove('e2e4')]);
      expect(p.toUci(), 'startpos moves e2e4');
      expect(p.sideToMove, Side.black);
      expect(const Position.startpos().toUci(), 'startpos');
      expect(const Position.startpos().sideToMove, Side.white);
    });

    test('fen', () {
      final p = Position.fromFen('  8/8/8/8/8/8/8/K1k5   b - - 0 1 ');
      expect(p.fen, '8/8/8/8/8/8/8/K1k5 b - - 0 1');
      expect(p.toUci(), 'fen 8/8/8/8/8/8/8/K1k5 b - - 0 1');
      expect(p.sideToMove, Side.black);
      expect(p.play(UciMove('c1d2')).sideToMove, Side.white);
    });

    test('equality', () {
      expect(
        Position.startpos(moves: [UciMove('e2e4')]),
        const Position.startpos().play(UciMove('e2e4')),
      );
      expect(
        Position.startpos(moves: [UciMove('e2e4')]),
        isNot(const Position.startpos()),
      );
    });

    const valid = [
      Position.standardStartFen,
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
      'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
      // Chess960 X-FEN / Shredder-FEN castling.
      'bb1n1rkr/ppp1Q1pp/3n1p2/3p4/3P4/6Pq/PPP1PP1P/BB1NNRKR w HFhf - 0 5',
      'nqbnrkrb/pppppppp/8/8/8/8/PPPPPPPP/NQBNRKRB w GEge - 0 1',
      '7k/5Q2/6K1/8/8/8/8/8 b - - 0 0',
    ];
    for (final fen in valid) {
      test('accepts $fen', () => expect(Position.fromFen(fen).fen, fen));
    }

    const invalid = {
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -': '5 fields',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1': '7 ranks',
      'rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1': 'bad digit',
      'rnbqkbnr/ppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1': 'short rank',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQXBNR w KQkq - 0 1': 'bad piece',
      'rnbq1bnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1':
          'no black king',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKKNR w KQkq - 0 1': 'two kings',
      'rnbqkbnP/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w KQkq - 0 1': 'pawn on 8',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1': 'side',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkqZ - 0 1': 'castling',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e4 0 1': 'ep rank',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1': 'halfmove',
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 -1': 'fullmove',
    };
    for (final MapEntry(key: fen, value: why) in invalid.entries) {
      test('rejects ($why)', () {
        expect(
          () => Position.fromFen(fen),
          throwsA(isA<InvalidPositionException>()),
        );
      });
    }
  });

  group('Score', () {
    test('perspective', () {
      const s = CentipawnScore(35, bound: ScoreBound.lowerBound);
      expect(s.fromWhitePerspective(Side.white), s);
      expect(
        s.fromWhitePerspective(Side.black),
        const CentipawnScore(-35, bound: ScoreBound.upperBound),
      );
      expect(const MateScore(3).negated, const MateScore(-3));
    });

    test('ordering', () {
      final scores = <Score>[
        const MateScore(2),
        const CentipawnScore(-50),
        const MateScore(-1),
        const CentipawnScore(300),
        const MateScore(1),
        const MateScore(-4),
        const MateScore(0),
      ]..sort();
      expect(scores, const [
        MateScore(0),
        MateScore(-1),
        MateScore(-4),
        CentipawnScore(-50),
        CentipawnScore(300),
        MateScore(2),
        MateScore(1),
      ]);
    });

    test('tablebase scores', () {
      const win = CentipawnScore(19990);
      expect(win.isTablebaseWin, isTrue);
      expect(win.tablebasePlies, 10);
      expect(const CentipawnScore(-19980).isTablebaseLoss, isTrue);
      expect(const CentipawnScore(-19980).tablebasePlies, 20);
      expect(const CentipawnScore(500).tablebasePlies, isNull);
    });

    test('WDL', () {
      const wdl = Wdl(500, 300, 200);
      expect(wdl.expectedScore, closeTo(0.65, 1e-9));
      expect(wdl.fromWhitePerspective(Side.black), const Wdl(200, 300, 500));
    });
  });

  group('SearchLimits', () {
    test('unlimited', () {
      expect(const SearchLimits().isUnlimited, isTrue);
      expect(const SearchLimits.infinite().isUnlimited, isTrue);
      expect(const SearchLimits.depth(3).isUnlimited, isFalse);
      expect(
        SearchLimits.moveTime(const Duration(seconds: 2)).toUciArguments(),
        ['movetime', '2000'],
      );
      expect(const SearchLimits.nodes(1000).toUciArguments(), [
        'nodes',
        '1000',
      ]);
    });
  });
}
