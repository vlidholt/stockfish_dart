// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

import 'model/uci_move.dart';

/// Result of `go perft <depth>`: leaf node counts per root move.
@immutable
final class PerftResult {
  /// Creates a result.
  const PerftResult({
    required this.depth,
    required this.nodes,
    required this.divide,
  });

  /// Parses the output lines of `go perft`.
  factory PerftResult.parse(int depth, Iterable<String> lines) {
    var nodes = 0;
    final divide = <UciMove, int>{};
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('Nodes searched:')) {
        nodes = int.tryParse(t.substring('Nodes searched:'.length).trim()) ?? 0;
        continue;
      }
      final colon = t.indexOf(':');
      if (colon <= 0) continue;
      final move = UciMove.tryParse(t.substring(0, colon));
      final count = int.tryParse(t.substring(colon + 1).trim());
      if (move != null && count != null) divide[move] = count;
    }
    return PerftResult(
      depth: depth,
      nodes: nodes,
      divide: Map.unmodifiable(divide),
    );
  }

  /// The perft depth.
  final int depth;

  /// Total leaf nodes.
  final int nodes;

  /// Leaf nodes after each legal root move.
  final Map<UciMove, int> divide;

  @override
  String toString() => 'PerftResult(depth: $depth, nodes: $nodes)';
}

/// A tablebase probe shown by `d` (only when tablebases are loaded and the
/// position has few enough pieces).
@immutable
final class TablebaseProbe {
  /// Creates a probe result.
  const TablebaseProbe({
    required this.wdl,
    required this.dtz,
    required this.raw,
  });

  /// WDL value (−2 loss … 2 win, from the side to move), if probed.
  final int? wdl;

  /// Distance to zeroing move, if probed.
  final int? dtz;

  /// The raw `Tablebases …` lines.
  final List<String> raw;
}

/// Output of the `d` command.
@immutable
final class BoardDisplay {
  /// Creates the record.
  const BoardDisplay({
    required this.ascii,
    required this.fen,
    required this.key,
    required this.checkers,
    required this.tablebase,
  });

  /// Parses the output lines of `d`.
  factory BoardDisplay.parse(Iterable<String> lines) {
    final board = <String>[];
    var fen = '', key = '';
    var checkers = <String>[];
    final tb = <String>[];
    int? wdl, dtz;
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('+---') ||
          t.startsWith('|') ||
          RegExp(r'^a\s+b\s+c').hasMatch(t)) {
        board.add(line);
      } else if (t.startsWith('Fen:')) {
        fen = t.substring(4).trim();
      } else if (t.startsWith('Key:')) {
        key = t.substring(4).trim();
      } else if (t.startsWith('Checkers:')) {
        checkers = t
            .substring(9)
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (t.startsWith('Tablebases WDL:')) {
        tb.add(t);
        wdl = int.tryParse(t.substring(15).trim().split(' ').first);
      } else if (t.startsWith('Tablebases DTZ:')) {
        tb.add(t);
        dtz = int.tryParse(t.substring(15).trim().split(' ').first);
      }
    }
    return BoardDisplay(
      ascii: board.join('\n'),
      fen: fen,
      key: key,
      checkers: List.unmodifiable(checkers),
      tablebase: tb.isEmpty
          ? null
          : TablebaseProbe(wdl: wdl, dtz: dtz, raw: tb),
    );
  }

  /// The ASCII board diagram.
  final String ascii;

  /// FEN of the current position.
  final String fen;

  /// Zobrist hash key (hex).
  final String key;

  /// Squares of pieces giving check.
  final List<String> checkers;

  /// Tablebase probe, if available.
  final TablebaseProbe? tablebase;

  @override
  String toString() => '$ascii\nFen: $fen';
}

/// One row of the NNUE contributions table printed by `eval`.
@immutable
final class EvalBucket {
  /// Creates a row.
  const EvalBucket({
    required this.bucket,
    required this.material,
    required this.positional,
    required this.total,
    required this.used,
  });

  /// Layer stack (bucket) index.
  final int bucket;

  /// Material (PSQT) contribution, in pawns.
  final double material;

  /// Positional (layers) contribution, in pawns.
  final double positional;

  /// Total, in pawns.
  final double total;

  /// Whether this bucket is the one used for the position.
  final bool used;
}

/// Output of the `eval` command (static evaluation breakdown).
@immutable
final class EvalTrace {
  /// Creates the record.
  const EvalTrace({
    required this.raw,
    required this.buckets,
    required this.nnueInternal,
    required this.nnueWhite,
    required this.finalWhite,
  });

  /// Parses the output lines of `eval`.
  factory EvalTrace.parse(Iterable<String> lines) {
    final raw = <String>[];
    final buckets = <EvalBucket>[];
    int? internal;
    double? nnue, finalEval;
    final row = RegExp(
      r'^\|\s*(\d+)\s*\|\s*([+-])\s*([\d.]+)\s*\|\s*([+-])\s*([\d.]+)\s*\|\s*([+-])\s*([\d.]+)\s*\|(.*)$',
    );
    double signed(String sign, String v) =>
        (sign == '-' ? -1 : 1) * double.parse(v);
    for (final line in lines) {
      if (line.startsWith('info string')) continue;
      raw.add(line);
      final t = line.trim();
      if (row.firstMatch(t) case final m?) {
        buckets.add(
          EvalBucket(
            bucket: int.parse(m.group(1)!),
            material: signed(m.group(2)!, m.group(3)!),
            positional: signed(m.group(4)!, m.group(5)!),
            total: signed(m.group(6)!, m.group(7)!),
            used: m.group(8)!.contains('used'),
          ),
        );
      } else if (t.startsWith('NNUE evaluation') &&
          t.contains('internal units')) {
        internal = int.tryParse(t.split(RegExp(r'\s+'))[2]);
      } else if (t.startsWith('NNUE evaluation') && t.contains('white side')) {
        nnue = double.tryParse(t.split(RegExp(r'\s+'))[2]);
      } else if (t.startsWith('Final evaluation')) {
        finalEval = double.tryParse(t.split(RegExp(r'\s+'))[2]);
      }
    }
    while (raw.isNotEmpty && raw.first.trim().isEmpty) {
      raw.removeAt(0);
    }
    return EvalTrace(
      raw: raw.join('\n').trimRight(),
      buckets: List.unmodifiable(buckets),
      nnueInternal: internal,
      nnueWhite: nnue,
      finalWhite: finalEval,
    );
  }

  /// The full text output.
  final String raw;

  /// NNUE contributions per bucket.
  final List<EvalBucket> buckets;

  /// Raw NNUE output in internal units, from the side to move.
  final int? nnueInternal;

  /// NNUE evaluation in pawns from White's point of view.
  final double? nnueWhite;

  /// Final evaluation in pawns from White's point of view; null when the
  /// side to move is in check (no static evaluation).
  final double? finalWhite;

  @override
  String toString() => raw;
}

/// Output of the `compiler` command.
@immutable
final class CompilerInfo {
  /// Creates the record.
  const CompilerInfo({required this.raw, required this.fields});

  /// Parses the output lines of `compiler`.
  factory CompilerInfo.parse(Iterable<String> lines) {
    final fields = <String, String>{};
    final raw = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      raw.add(line);
      final i = line.indexOf(':');
      if (i > 0) {
        fields[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
    }
    return CompilerInfo(raw: raw.join('\n'), fields: Map.unmodifiable(fields));
  }

  /// The full text output.
  final String raw;

  /// `key: value` pairs, e.g. `Compiled by`, `Compilation architecture`.
  final Map<String, String> fields;

  /// `Compiled by`.
  String? get compiledBy => fields['Compiled by'];

  /// `Compilation architecture` (e.g. `x86-64-avx2`).
  String? get architecture => fields['Compilation architecture'];

  /// `Compilation settings` (e.g. `64bit AVX2 SSE41 SSSE3 SSE2 POPCNT`).
  String? get settings => fields['Compilation settings'];

  @override
  String toString() => raw;
}

/// Positions searched by `bench`.
@immutable
sealed class BenchPositions {
  const BenchPositions();

  /// Stockfish's built-in benchmark positions.
  static const builtIn = _BenchPositionsNamed('default');

  /// Only the current position.
  static const current = _BenchPositionsNamed('current');

  /// FENs (one per line) from [path].
  const factory BenchPositions.file(String path) = _BenchPositionsNamed;

  /// The value passed to `bench`.
  String get argument;
}

final class _BenchPositionsNamed extends BenchPositions {
  const _BenchPositionsNamed(this.argument);

  @override
  final String argument;
}

/// What limits each `bench` search.
enum BenchLimitType {
  /// `go depth <limit>`.
  depth,

  /// `go nodes <limit>`.
  nodes,

  /// `go movetime <limit>` (milliseconds).
  movetime,

  /// `go perft <limit>`.
  perft,

  /// Static evaluation only (`eval`).
  eval,
}

/// Arguments of the `bench` command.
@immutable
final class BenchConfig {
  /// Creates a configuration (Stockfish's defaults).
  const BenchConfig({
    this.hashMb = 16,
    this.threads = 1,
    this.limit = 13,
    this.positions = BenchPositions.builtIn,
    this.limitType = BenchLimitType.depth,
  });

  /// Transposition table size in MiB.
  final int hashMb;

  /// Search threads.
  final int threads;

  /// Limit value (see [limitType]).
  final int limit;

  /// Positions to search.
  final BenchPositions positions;

  /// What [limit] means.
  final BenchLimitType limitType;

  /// The `bench` arguments.
  List<String> toArguments() => [
    '$hashMb',
    '$threads',
    '$limit',
    positions.argument,
    limitType.name,
  ];
}

/// Result of `bench`.
@immutable
final class BenchResult {
  /// Creates a result.
  const BenchResult({
    required this.totalTime,
    required this.nodes,
    required this.nodesPerSecond,
    required this.positions,
    required this.raw,
  });

  /// Parses `bench` output: [stdout] info lines and the [stderr] summary.
  factory BenchResult.parse(Iterable<String> stdout, Iterable<String> stderr) {
    var time = 0, nodes = 0, nps = 0, positions = 0;
    for (final line in stderr) {
      final t = line.trim();
      final value = int.tryParse(t.split(':').last.trim());
      if (t.startsWith('Total time (ms)')) time = value ?? 0;
      if (t.startsWith('Nodes searched')) nodes = value ?? 0;
      if (t.startsWith('Nodes/second')) nps = value ?? 0;
      if (t.startsWith('Position:')) positions++;
    }
    return BenchResult(
      totalTime: Duration(milliseconds: time),
      nodes: nodes,
      nodesPerSecond: nps,
      positions: positions,
      raw: stderr.join('\n'),
    );
  }

  /// Total search time.
  final Duration totalTime;

  /// Total nodes searched. This is Stockfish's "bench signature".
  final int nodes;

  /// Average speed.
  final int nodesPerSecond;

  /// Number of positions searched.
  final int positions;

  /// The raw summary text.
  final String raw;

  @override
  String toString() =>
      'BenchResult(nodes: $nodes, nps: $nodesPerSecond, time: $totalTime)';
}

/// Arguments of the `speedtest` command; null values use Stockfish's
/// defaults (all hardware threads, 128 MiB hash per thread, 150 seconds).
@immutable
final class SpeedtestConfig {
  /// Creates a configuration.
  const SpeedtestConfig({this.threads, this.hashMb, this.duration})
    : assert(hashMb == null || threads != null, 'hashMb needs threads'),
      assert(duration == null || hashMb != null, 'duration needs hashMb');

  /// Search threads.
  final int? threads;

  /// Transposition table size in MiB.
  final int? hashMb;

  /// How long to run (whole seconds, at least 1).
  final Duration? duration;

  /// The `speedtest` arguments.
  List<String> toArguments() => [
    if (threads != null) '$threads',
    if (hashMb != null) '$hashMb',
    if (duration != null)
      '${duration!.inSeconds < 1 ? 1 : duration!.inSeconds}',
  ];
}

/// Result of `speedtest`.
@immutable
final class SpeedtestResult {
  /// Creates a result.
  const SpeedtestResult({required this.fields, required this.raw});

  /// Parses the `speedtest` summary written to standard error.
  factory SpeedtestResult.parse(Iterable<String> stderr) {
    final fields = <String, String>{};
    final lines = stderr.toList();
    final start = lines.lastIndexWhere((l) => l.startsWith('====='));
    String? section;
    for (final line in lines.skip(start + 1)) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      var key = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      if (line.startsWith('    ') && section != null) {
        key = '$section $key';
      } else if (value.isEmpty) {
        section = key;
        continue;
      }
      fields[key] = value;
    }
    return SpeedtestResult(
      fields: Map.unmodifiable(fields),
      raw: lines.skip(start < 0 ? 0 : start).join('\n'),
    );
  }

  /// Every `key : value` pair of the summary.
  final Map<String, String> fields;

  /// The raw summary.
  final String raw;

  int? _int(String key) => int.tryParse(fields[key] ?? '');

  /// Engine version.
  String? get version => fields['Version'];

  /// Compiler description.
  String? get compiledBy => fields['Compiled by'];

  /// Whether large pages were used.
  bool get largePages => fields['Large pages'] == 'yes';

  /// Search threads.
  int? get threads => _int('Thread count');

  /// Transposition table size in MiB.
  int? get ttSizeMb => _int('TT size [MiB]');

  /// Total nodes searched.
  int? get nodes => _int('Total nodes searched');

  /// Total search time.
  Duration? get searchTime {
    final s = double.tryParse(fields['Total search time [s]'] ?? '');
    return s == null ? null : Duration(microseconds: (s * 1e6).round());
  }

  /// Average speed.
  int? get nodesPerSecond => _int('Nodes/second');

  @override
  String toString() =>
      'SpeedtestResult(nps: $nodesPerSecond, threads: $threads)';
}
