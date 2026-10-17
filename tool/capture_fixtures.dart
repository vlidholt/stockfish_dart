// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Records engine transcripts into test/fixtures/sf19/ for parser tests.
//
//   dart run tool/capture_fixtures.dart

import 'dart:io';

import 'package:stockfish_dart/src/session/engine_session.dart';
import 'package:stockfish_dart/src/transport/ffi_transport.dart';

Future<void> main() async {
  final dir = Directory.fromUri(
    Platform.script.resolve('../test/fixtures/sf19/'),
  );
  await dir.create(recursive: true);

  final session = EngineSession(FfiTransport());
  final handshake = <String>[];
  final sub = session.rawOutput.listen(handshake.add);
  await session.start();
  await sub.cancel();
  await _write(dir, 'uci', handshake, const []);

  Future<void> capture(
    String name,
    List<String> commands, {
    Duration? timeout,
  }) async {
    final out = <String>[];
    final s = session.rawOutput.listen(out.add);
    final err = <String>[];
    try {
      await session.enqueue(
        () => session.exchange(commands, timeout: timeout, onStderr: err.add),
      );
    } on Object catch (e) {
      out.add('# exception: $e');
    }
    await s.cancel();
    await _write(dir, name, out.where((l) => l != 'readyok').toList(), err);
    stdout.writeln('captured $name');
  }

  Future<void> search(String name, List<String> setup, String go) async {
    final out = <String>[];
    final s = session.rawOutput.listen(out.add);
    await session.enqueue(() => session.exchange(setup));
    out.clear();
    await session.enqueue(() async {
      session.sendImmediately(go);
      final done = session.rawOutput.firstWhere(
        (l) => l.startsWith('bestmove'),
      );
      await done;
    });
    await s.cancel();
    await _write(dir, name, out, const []);
    stdout.writeln('captured $name');
  }

  await search('search_multipv_wdl', [
    'setoption name MultiPV value 3',
    'setoption name UCI_ShowWDL value true',
    'position startpos moves e2e4',
  ], 'go depth 14');
  await search('search_mate', [
    'setoption name MultiPV value 1',
    'position fen r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
  ], 'go mate 2');
  await search('search_checkmated', [
    'position fen rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
  ], 'go depth 5');
  await search('search_stalemate', [
    'position fen 7k/5Q2/6K1/8/8/8/8/8 b - - 0 1',
  ], 'go depth 5');
  await search('search_currmove', [
    'setoption name UCI_ShowWDL value false',
    'position startpos',
  ], 'go movetime 3500');

  await capture('display', ['position startpos moves e2e4 c7c5', 'd']);
  await capture('eval', ['position startpos moves e2e4', 'eval']);
  await capture('compiler', ['compiler']);
  await capture('help', ['help']);
  await capture('perft', ['position startpos', 'go perft 3']);
  await capture('flip', ['position startpos moves e2e4', 'flip', 'd']);
  await capture('bench', [
    'bench 16 1 6 default depth',
  ], timeout: const Duration(minutes: 5));
  await capture('speedtest', [
    'speedtest 1 16 1',
  ], timeout: const Duration(minutes: 5));
  await capture('critical_fen', ['position fen invalid fen string']);
  await capture('critical_move', ['position startpos moves e2e5']);
  await capture('unknown_option', ['setoption name NoSuchOption value 1']);
  await capture('unknown_command', ['frobnicate']);
  await capture('numa_invalid', ['setoption name NumaPolicy value garbage']);
  await capture('threads', [
    'setoption name Threads value 2',
    'setoption name Threads value 1',
  ]);

  await session.dispose();
}

Future<void> _write(
  Directory dir,
  String name,
  List<String> out,
  List<String> err,
) async {
  await File('${dir.path}$name.out.txt').writeAsString('${out.join('\n')}\n');
  if (err.isNotEmpty) {
    await File('${dir.path}$name.err.txt').writeAsString('${err.join('\n')}\n');
  }
}
