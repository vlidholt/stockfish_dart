// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Test helpers: a scripted fake engine for unit-testing code that uses
/// `Stockfish`, without the native library.
///
/// ```dart
/// final fake = FakeStockfish()
///   ..onGo = (go) => ['info depth 1 score cp 20 pv e2e4', 'bestmove e2e4'];
/// final engine = await Stockfish.withTransport(fake);
/// final r = await engine.bestMove(const Position.startpos(),
///     limits: const SearchLimits.depth(1));
/// expect(r.bestMove, UciMove('e2e4'));
/// ```
library;

export 'src/testing/fake_stockfish.dart';
