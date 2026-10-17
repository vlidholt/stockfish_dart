// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import '../model/option_spec.dart';
import '../model/score.dart';
import '../model/search_info.dart';
import '../model/uci_move.dart';

/// A parsed line of engine output.
@immutable
sealed class UciEvent {
  const UciEvent(this.line);

  /// The original line.
  final String line;

  @override
  String toString() => line;
}

/// `id name …` or `id author …`.
final class IdEvent extends UciEvent {
  /// Creates the event.
  const IdEvent(super.line, this.key, this.value);

  /// `name` or `author`.
  final String key;

  /// The value.
  final String value;
}

/// `option name … type …`.
final class OptionEvent extends UciEvent {
  /// Creates the event.
  const OptionEvent(super.line, this.spec);

  /// The parsed option.
  final UciOptionSpec spec;
}

/// `uciok`.
final class UciOkEvent extends UciEvent {
  /// Creates the event.
  const UciOkEvent(super.line);
}

/// `readyok`.
final class ReadyOkEvent extends UciEvent {
  /// Creates the event.
  const ReadyOkEvent(super.line);
}

/// An `info` line with search data.
final class InfoEvent extends UciEvent {
  /// Creates the event.
  const InfoEvent(super.line, this.info);

  /// The parsed data.
  final SearchInfo info;
}

/// An `info … currmove … currmovenumber …` line.
final class CurrentMoveEvent extends UciEvent {
  /// Creates the event.
  const CurrentMoveEvent(super.line, this.info);

  /// The parsed data.
  final CurrentMoveInfo info;
}

/// `info string …`.
final class InfoStringEvent extends UciEvent {
  /// Creates the event.
  const InfoStringEvent(super.line, this.text);

  /// The text after `info string`.
  final String text;
}

/// `info string CRITICAL ERROR: Command `…` failed. Reason: …`.
final class CriticalErrorEvent extends UciEvent {
  /// Creates the event.
  const CriticalErrorEvent(super.line, this.command, this.reason);

  /// The command that failed.
  final String command;

  /// Why it failed.
  final String reason;
}

/// `bestmove <move> [ponder <move>]`; `bestmove (none)` without legal moves.
final class BestMoveEvent extends UciEvent {
  /// Creates the event.
  const BestMoveEvent(super.line, this.move, this.ponder);

  /// The best move, null for `(none)`.
  final UciMove? move;

  /// The expected reply.
  final UciMove? ponder;
}

/// `No such option: <name>`.
final class UnknownOptionEvent extends UciEvent {
  /// Creates the event.
  const UnknownOptionEvent(super.line, this.name);

  /// The unknown option name.
  final String name;
}

/// `Unknown command: '…'. Type help for more information.`
final class UnknownCommandEvent extends UciEvent {
  /// Creates the event.
  const UnknownCommandEvent(super.line, this.command);

  /// The unknown command.
  final String command;
}

/// Any other line (board diagrams, `eval` tables, perft output, ...).
final class TextEvent extends UciEvent {
  /// Creates the event.
  const TextEvent(super.line);
}

final _criticalError = RegExp(
  r'^CRITICAL ERROR: Command `(.*)` failed\. Reason: (.*)$',
);
final _unknownCommand = RegExp(r"^Unknown command: '(.*)'\. Type help");

/// Parses one line of engine output.
UciEvent parseUciLine(String line) {
  final trimmed = line.trim();
  final space = trimmed.indexOf(' ');
  final head = space < 0 ? trimmed : trimmed.substring(0, space);
  final rest = space < 0 ? '' : trimmed.substring(space + 1).trim();

  switch (head) {
    case 'uciok':
      return UciOkEvent(line);
    case 'readyok':
      return ReadyOkEvent(line);
    case 'id':
      final s = rest.indexOf(' ');
      return s < 0
          ? IdEvent(line, rest, '')
          : IdEvent(line, rest.substring(0, s), rest.substring(s + 1).trim());
    case 'option':
      final spec = UciOptionSpec.tryParse(trimmed);
      return spec == null ? TextEvent(line) : OptionEvent(line, spec);
    case 'bestmove':
      final t = rest.split(RegExp(r'\s+'));
      final move = t.isEmpty || t.first == '(none)'
          ? null
          : UciMove.tryParse(t.first);
      final ponderIndex = t.indexOf('ponder');
      final ponder = ponderIndex >= 0 && ponderIndex + 1 < t.length
          ? UciMove.tryParse(t[ponderIndex + 1])
          : null;
      return BestMoveEvent(line, move, ponder);
    case 'info':
      return _parseInfo(line, rest);
    case 'No':
      if (trimmed.startsWith('No such option: ')) {
        return UnknownOptionEvent(
          line,
          trimmed.substring('No such option: '.length),
        );
      }
  }
  if (_unknownCommand.firstMatch(trimmed) case final m?) {
    return UnknownCommandEvent(line, m.group(1)!);
  }
  return TextEvent(line);
}

UciEvent _parseInfo(String line, String rest) {
  if (rest.startsWith('string')) {
    final text = rest.length > 6 ? rest.substring(7) : '';
    if (_criticalError.firstMatch(text) case final m?) {
      return CriticalErrorEvent(line, m.group(1)!, m.group(2)!);
    }
    return InfoStringEvent(line, text);
  }

  final tokens = rest.split(RegExp(r'\s+'));
  int? depth, selDepth, multiPv, nodes, nps, hashFull, tbHits, timeMs;
  int? currMoveNumber;
  UciMove? currMove;
  Score? score;
  Wdl? wdl;
  var pv = const <UciMove>[];
  final extra = <String, String>{};

  int? intAt(int i) => i < tokens.length ? int.tryParse(tokens[i]) : null;

  for (var i = 0; i < tokens.length; i++) {
    final key = tokens[i];
    switch (key) {
      case 'depth':
        depth = intAt(++i);
      case 'seldepth':
        selDepth = intAt(++i);
      case 'multipv':
        multiPv = intAt(++i);
      case 'nodes':
        nodes = intAt(++i);
      case 'nps':
        nps = intAt(++i);
      case 'hashfull':
        hashFull = intAt(++i);
      case 'tbhits':
        tbHits = intAt(++i);
      case 'time':
        timeMs = intAt(++i);
      case 'currmovenumber':
        currMoveNumber = intAt(++i);
      case 'currmove':
        currMove = i + 1 < tokens.length ? UciMove.tryParse(tokens[++i]) : null;
      case 'score':
        if (i + 2 < tokens.length) {
          final kind = tokens[++i];
          final value = tokens[++i];
          String? bound;
          if (i + 1 < tokens.length &&
              (tokens[i + 1] == 'lowerbound' ||
                  tokens[i + 1] == 'upperbound')) {
            bound = tokens[++i];
          }
          score = Score.tryParse(kind, value, bound);
        }
      case 'wdl':
        if (i + 3 < tokens.length) {
          final w = int.tryParse(tokens[++i]);
          final d = int.tryParse(tokens[++i]);
          final l = int.tryParse(tokens[++i]);
          if (w != null && d != null && l != null) wdl = Wdl(w, d, l);
        }
      case 'pv':
        pv = [for (final t in tokens.skip(i + 1)) ?UciMove.tryParse(t)];
        i = tokens.length;
      default:
        if (i + 1 < tokens.length) extra[key] = tokens[++i];
    }
  }

  if (currMove != null) {
    return CurrentMoveEvent(
      line,
      CurrentMoveInfo(
        depth: depth ?? 0,
        move: currMove,
        moveNumber: currMoveNumber ?? 0,
        raw: line,
      ),
    );
  }

  return InfoEvent(
    line,
    SearchInfo(
      raw: line,
      depth: depth,
      selDepth: selDepth,
      multiPv: multiPv,
      score: score,
      wdl: wdl,
      nodes: nodes,
      nps: nps,
      hashFull: hashFull,
      tbHits: tbHits,
      time: timeMs == null ? null : Duration(milliseconds: timeMs),
      pv: List.unmodifiable(pv),
      extra: Map.unmodifiable(extra),
    ),
  );
}
