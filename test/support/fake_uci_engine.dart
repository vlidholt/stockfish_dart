// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// A minimal UCI engine as a standalone program, for ProcessTransport tests.
// Like official Stockfish builds, it exits with code 1 after a CRITICAL ERROR.

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final cmd = line.trim();
    if (cmd == 'uci') {
      stdout
        ..writeln('id name FakeFish 1')
        ..writeln('id author tests')
        ..writeln('option name Hash type spin default 16 min 1 max 1024')
        ..writeln('option name Threads type spin default 1 min 1 max 8')
        ..writeln('uciok');
    } else if (cmd == 'isready') {
      stdout.writeln('readyok');
    } else if (cmd.startsWith('position') && cmd.contains('e2e5')) {
      stdout.writeln(
        'info string CRITICAL ERROR: Command `$cmd` failed. Reason: Illegal move: e2e5',
      );
      await stdout.flush();
      exit(1);
    } else if (cmd.startsWith('go')) {
      stdout
        ..writeln('info depth 1 score cp 15 nodes 10 pv d2d4')
        ..writeln('bestmove d2d4');
    } else if (cmd == 'quit') {
      await stdout.flush();
      exit(0);
    }
  }
}
