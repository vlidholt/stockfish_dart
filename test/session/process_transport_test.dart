// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';
import 'package:stockfish_dart/uci.dart';
import 'package:test/test.dart';

/// Runs test/support/fake_uci_engine.dart in a child Dart process.
ProcessTransport fakeProcess() => ProcessTransport(
  Platform.resolvedExecutable,
  // Runs on the VM directly: no dartdev, so no build hooks are involved.
  arguments: ['--disable-dart-dev', 'test/support/fake_uci_engine.dart'],
);

void main() {
  test('drives an external engine', () async {
    final engine = await Stockfish.withTransport(
      fakeProcess(),
      handshakeTimeout: const Duration(seconds: 60),
    );
    addTearDown(engine.dispose);
    expect(engine.identity.name, 'FakeFish 1');
    expect(engine.optionSpecs.keys, unorderedEquals(['Hash', 'Threads']));

    await engine.setOptions(const StockfishOptions(hashMb: 64));
    final r = await engine.bestMove(
      const Position.startpos(),
      limits: const SearchLimits.depth(1),
    );
    expect(r.bestMove, UciMove('d2d4'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('restarts after the engine exits on a critical error', () async {
    final engine = await Stockfish.withTransport(
      fakeProcess(),
      handshakeTimeout: const Duration(seconds: 60),
    );
    addTearDown(engine.dispose);
    await engine.setOptions(const StockfishOptions(hashMb: 32));
    await engine.setPosition(Position.startpos(moves: [UciMove('d2d4')]));

    await expectLater(
      engine.setPosition(Position.startpos(moves: [UciMove('e2e5')])),
      throwsA(isA<EngineCommandException>()),
    );
    expect(engine.position, Position.startpos(moves: [UciMove('d2d4')]));
    // The process died; the next call waits for the restart and works.
    final r = await engine.bestMove(
      const Position.startpos(),
      limits: const SearchLimits.depth(1),
    );
    expect(r.bestMove, UciMove('d2d4'));
    expect(engine.options.hashMb, 32);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('resolveExecutable uses an explicit path as given', () {
    expect(
      () => ProcessTransport.resolveExecutable(
        '${Directory.systemTemp.path}/definitely-not-stockfish',
      ),
      returnsNormally, // an explicit path is used as given
    );
  });

  test('EngineSource.process fails clearly for a missing executable', () async {
    await expectLater(
      Stockfish.start(
        engine: const EngineSource.process(path: 'no-such-stockfish-binary'),
      ),
      throwsA(isA<EngineLoadException>()),
    );
  });
}
