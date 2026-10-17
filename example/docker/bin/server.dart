// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// A minimal best-move HTTP service.
//
//   GET /bestmove?fen=<FEN>&movetime=<ms>
//   -> {"bestMove":"e7e5","ponder":"g1f3","score":"cp 31","depth":20}
//
// `server --once <FEN>` prints one answer and exits (used by CI).

import 'dart:convert';
import 'dart:io';

import 'package:stockfish_dart/stockfish_dart.dart';

Future<void> main(List<String> args) async {
  final engine = await Stockfish.start(
    options: const StockfishOptions(threads: 1, hashMb: 64),
  );

  Future<Map<String, Object?>> answer(String fen, int movetime) async {
    final r = await engine.bestMove(
      Position.fromFen(fen),
      limits: SearchLimits.moveTime(Duration(milliseconds: movetime)),
    );
    return {
      'bestMove': r.bestMove?.value,
      'ponder': r.ponderMove?.value,
      'score': r.score?.toString(),
      'depth': r.finalInfo?.depth,
    };
  }

  if (args.length == 2 && args.first == '--once') {
    stdout.writeln(jsonEncode(await answer(args[1], 200)));
    await engine.dispose();
    return;
  }

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Listening on :$port (${engine.identity.name})');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    await engine.dispose();
    exit(0);
  });

  await for (final request in server) {
    final params = request.uri.queryParameters;
    final response = request.response..headers.contentType = ContentType.json;
    try {
      if (request.uri.path != '/bestmove' || params['fen'] == null) {
        response.statusCode = HttpStatus.notFound;
        response.write(
          jsonEncode({'error': 'GET /bestmove?fen=<FEN>&movetime=<ms>'}),
        );
      } else {
        final movetime = (int.tryParse(params['movetime'] ?? '') ?? 500).clamp(
          10,
          10000,
        );
        response.write(jsonEncode(await answer(params['fen']!, movetime)));
      }
    } on StockfishException catch (e) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': e.message}));
    }
    await response.close();
  }
}
