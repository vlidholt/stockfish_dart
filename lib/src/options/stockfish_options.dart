// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:io' show Platform;

import 'package:meta/meta.dart';

/// UCI names of the Stockfish 19 options.
abstract final class OptionNames {
  /// `Debug Log File`.
  static const debugLogFile = 'Debug Log File';

  /// `NumaPolicy`.
  static const numaPolicy = 'NumaPolicy';

  /// `Threads`.
  static const threads = 'Threads';

  /// `Hash`.
  static const hash = 'Hash';

  /// `Clear Hash`.
  static const clearHash = 'Clear Hash';

  /// `Ponder`.
  static const ponder = 'Ponder';

  /// `MultiPV`.
  static const multiPv = 'MultiPV';

  /// `Skill Level`.
  static const skillLevel = 'Skill Level';

  /// `Move Overhead`.
  static const moveOverhead = 'Move Overhead';

  /// `nodestime`.
  static const nodesTime = 'nodestime';

  /// `UCI_Chess960`.
  static const chess960 = 'UCI_Chess960';

  /// `UCI_LimitStrength`.
  static const limitStrength = 'UCI_LimitStrength';

  /// `UCI_Elo`.
  static const elo = 'UCI_Elo';

  /// `UCI_ShowWDL`.
  static const showWdl = 'UCI_ShowWDL';

  /// `SyzygyPath`.
  static const syzygyPath = 'SyzygyPath';

  /// `SyzygyProbeDepth`.
  static const syzygyProbeDepth = 'SyzygyProbeDepth';

  /// `Syzygy50MoveRule`.
  static const syzygy50MoveRule = 'Syzygy50MoveRule';

  /// `SyzygyProbeLimit`.
  static const syzygyProbeLimit = 'SyzygyProbeLimit';

  /// `EvalFile`.
  static const evalFile = 'EvalFile';

  /// All options with a value, in the order they are applied: NUMA, threads
  /// and hash first so memory is allocated once, with the right binding.
  static const ordered = [
    numaPolicy,
    threads,
    hash,
    debugLogFile,
    ponder,
    multiPv,
    skillLevel,
    moveOverhead,
    nodesTime,
    chess960,
    limitStrength,
    elo,
    showWdl,
    syzygyPath,
    syzygyProbeDepth,
    syzygy50MoveRule,
    syzygyProbeLimit,
    evalFile,
  ];
}

/// How search threads are bound to NUMA nodes (`NumaPolicy`).
@immutable
sealed class NumaPolicy {
  const NumaPolicy();

  /// Let Stockfish decide (default).
  static const auto = _NamedNumaPolicy('auto');

  /// Use the NUMA layout reported by the OS, respecting process affinity.
  static const system = _NamedNumaPolicy('system');

  /// Use the hardware NUMA layout, ignoring process affinity.
  static const hardware = _NamedNumaPolicy('hardware');

  /// Don't bind threads.
  static const none = _NamedNumaPolicy('none');

  /// A custom layout in Stockfish's syntax, e.g. `0-7:8-15` (one node per
  /// `:`-separated CPU list).
  const factory NumaPolicy.custom(String spec) = _NamedNumaPolicy;

  /// The value sent to the engine.
  String get value;

  @override
  String toString() => value;
}

final class _NamedNumaPolicy extends NumaPolicy {
  const _NamedNumaPolicy(this.value);

  @override
  final String value;

  @override
  bool operator ==(Object other) => other is NumaPolicy && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Ways to make the engine play weaker.
@immutable
sealed class StrengthLimit {
  const StrengthLimit();

  /// Full strength (`UCI_LimitStrength false`, `Skill Level 20`).
  static const full = _FullStrength();

  /// Play at roughly [elo] (1320–3190): sets `UCI_LimitStrength` and
  /// `UCI_Elo`. Takes precedence over `Skill Level`.
  const factory StrengthLimit.elo(int elo) = _EloLimit;

  /// Use `Skill Level` [level] (0–20, 20 is full strength).
  const factory StrengthLimit.skill(int level) = _SkillLimit;
}

final class _FullStrength extends StrengthLimit {
  const _FullStrength();
}

final class _EloLimit extends StrengthLimit {
  const _EloLimit(this.elo);
  final int elo;
}

final class _SkillLimit extends StrengthLimit {
  const _SkillLimit(this.level);
  final int level;
}

const _unset = Object();

/// Typed values for every Stockfish 19 option. A null field leaves that
/// option at its current value (initially the engine default).
///
/// ```dart
/// const StockfishOptions(threads: 4, hashMb: 256, multiPv: 3, showWdl: true)
/// ```
@immutable
final class StockfishOptions {
  /// Creates options.
  const StockfishOptions({
    this.threads,
    this.hashMb,
    this.ponder,
    this.multiPv,
    this.skillLevel,
    this.moveOverhead,
    this.nodesTime,
    this.chess960,
    this.limitStrength,
    this.elo,
    this.showWdl,
    this.syzygyPath,
    this.syzygyProbeDepth,
    this.syzygy50MoveRule,
    this.syzygyProbeLimit,
    this.evalFile,
    this.numaPolicy,
    this.debugLogFile,
  });

  /// Options that apply [limit].
  factory StockfishOptions.strength(StrengthLimit limit) => switch (limit) {
    _FullStrength() => const StockfishOptions(
      limitStrength: false,
      skillLevel: 20,
    ),
    _EloLimit(:final elo) => StockfishOptions(limitStrength: true, elo: elo),
    _SkillLimit(:final level) => StockfishOptions(
      limitStrength: false,
      skillLevel: level,
    ),
  };

  /// `Threads`: search threads (1 – max(1024, 4 × CPUs); default 1).
  final int? threads;

  /// `Hash`: transposition table size in MiB (1 – 33554432; default 16).
  final int? hashMb;

  /// `Ponder`: tells the engine it may ponder, which affects its time use
  /// (default false). Pondering itself is `search(ponder: true)`.
  final bool? ponder;

  /// `MultiPV`: number of principal variations reported (1–256; default 1).
  final int? multiPv;

  /// `Skill Level`: 0–20, lower is weaker (default 20).
  final int? skillLevel;

  /// `Move Overhead`: milliseconds reserved per move for communication
  /// delays (0–5000; default 10).
  final int? moveOverhead;

  /// `nodestime`: treat N nodes as one millisecond, for testing (0–10000;
  /// default 0 = off).
  final int? nodesTime;

  /// `UCI_Chess960`: Chess960 mode; castling is written king-takes-rook
  /// (default false).
  final bool? chess960;

  /// `UCI_LimitStrength`: play at [elo] strength (default false).
  final bool? limitStrength;

  /// `UCI_Elo`: target strength with [limitStrength] (1320–3190).
  final int? elo;

  /// `UCI_ShowWDL`: report win/draw/loss probabilities (default false).
  final bool? showWdl;

  /// `SyzygyPath`: tablebase directories, separated by `;` on Windows and
  /// `:` elsewhere (default empty). See [syzygyPathsFromList].
  final String? syzygyPath;

  /// `SyzygyProbeDepth`: minimum depth to probe tablebases (1–100; default 1).
  final int? syzygyProbeDepth;

  /// `Syzygy50MoveRule`: respect the 50-move rule in tablebase results
  /// (default true).
  final bool? syzygy50MoveRule;

  /// `SyzygyProbeLimit`: maximum number of pieces to probe (0–7; default 7).
  final int? syzygyProbeLimit;

  /// `EvalFile`: NNUE network file (default: the embedded network).
  final String? evalFile;

  /// `NumaPolicy`: thread binding (default [NumaPolicy.auto]).
  final NumaPolicy? numaPolicy;

  /// `Debug Log File`: log all UCI traffic to this file (default empty = off).
  final String? debugLogFile;

  /// `Move Overhead` as a [Duration].
  Duration? get moveOverheadDuration =>
      moveOverhead == null ? null : Duration(milliseconds: moveOverhead!);

  /// Joins [paths] with the platform's separator, for [syzygyPath].
  static String syzygyPathsFromList(List<String> paths) =>
      paths.join(Platform.isWindows ? ';' : ':');

  /// A copy with the given fields replaced. Pass null explicitly to unset.
  StockfishOptions copyWith({
    Object? threads = _unset,
    Object? hashMb = _unset,
    Object? ponder = _unset,
    Object? multiPv = _unset,
    Object? skillLevel = _unset,
    Object? moveOverhead = _unset,
    Object? nodesTime = _unset,
    Object? chess960 = _unset,
    Object? limitStrength = _unset,
    Object? elo = _unset,
    Object? showWdl = _unset,
    Object? syzygyPath = _unset,
    Object? syzygyProbeDepth = _unset,
    Object? syzygy50MoveRule = _unset,
    Object? syzygyProbeLimit = _unset,
    Object? evalFile = _unset,
    Object? numaPolicy = _unset,
    Object? debugLogFile = _unset,
  }) {
    T? pick<T>(Object? v, T? current) =>
        identical(v, _unset) ? current : v as T?;
    return StockfishOptions(
      threads: pick(threads, this.threads),
      hashMb: pick(hashMb, this.hashMb),
      ponder: pick(ponder, this.ponder),
      multiPv: pick(multiPv, this.multiPv),
      skillLevel: pick(skillLevel, this.skillLevel),
      moveOverhead: pick(moveOverhead, this.moveOverhead),
      nodesTime: pick(nodesTime, this.nodesTime),
      chess960: pick(chess960, this.chess960),
      limitStrength: pick(limitStrength, this.limitStrength),
      elo: pick(elo, this.elo),
      showWdl: pick(showWdl, this.showWdl),
      syzygyPath: pick(syzygyPath, this.syzygyPath),
      syzygyProbeDepth: pick(syzygyProbeDepth, this.syzygyProbeDepth),
      syzygy50MoveRule: pick(syzygy50MoveRule, this.syzygy50MoveRule),
      syzygyProbeLimit: pick(syzygyProbeLimit, this.syzygyProbeLimit),
      evalFile: pick(evalFile, this.evalFile),
      numaPolicy: pick(numaPolicy, this.numaPolicy),
      debugLogFile: pick(debugLogFile, this.debugLogFile),
    );
  }

  /// These options with every non-null field of [other] applied on top.
  StockfishOptions merge(StockfishOptions other) {
    final a = toUciMap(), b = other.toUciMap();
    return StockfishOptions.fromUciMap({...a, ...b});
  }

  /// Builds options from UCI name/value pairs (unknown names are ignored).
  factory StockfishOptions.fromUciMap(Map<String, String> map) {
    int? i(String n) => map[n] == null ? null : int.tryParse(map[n]!);
    bool? b(String n) => map[n] == null ? null : map[n] == 'true';
    return StockfishOptions(
      threads: i(OptionNames.threads),
      hashMb: i(OptionNames.hash),
      ponder: b(OptionNames.ponder),
      multiPv: i(OptionNames.multiPv),
      skillLevel: i(OptionNames.skillLevel),
      moveOverhead: i(OptionNames.moveOverhead),
      nodesTime: i(OptionNames.nodesTime),
      chess960: b(OptionNames.chess960),
      limitStrength: b(OptionNames.limitStrength),
      elo: i(OptionNames.elo),
      showWdl: b(OptionNames.showWdl),
      syzygyPath: map[OptionNames.syzygyPath],
      syzygyProbeDepth: i(OptionNames.syzygyProbeDepth),
      syzygy50MoveRule: b(OptionNames.syzygy50MoveRule),
      syzygyProbeLimit: i(OptionNames.syzygyProbeLimit),
      evalFile: map[OptionNames.evalFile],
      numaPolicy: map[OptionNames.numaPolicy] == null
          ? null
          : NumaPolicy.custom(map[OptionNames.numaPolicy]!),
      debugLogFile: map[OptionNames.debugLogFile],
    );
  }

  /// The non-null fields as UCI name/value pairs, in application order.
  Map<String, String> toUciMap() {
    final values = <String, Object?>{
      OptionNames.numaPolicy: numaPolicy?.value,
      OptionNames.threads: threads,
      OptionNames.hash: hashMb,
      OptionNames.debugLogFile: debugLogFile,
      OptionNames.ponder: ponder,
      OptionNames.multiPv: multiPv,
      OptionNames.skillLevel: skillLevel,
      OptionNames.moveOverhead: moveOverhead,
      OptionNames.nodesTime: nodesTime,
      OptionNames.chess960: chess960,
      OptionNames.limitStrength: limitStrength,
      OptionNames.elo: elo,
      OptionNames.showWdl: showWdl,
      OptionNames.syzygyPath: syzygyPath,
      OptionNames.syzygyProbeDepth: syzygyProbeDepth,
      OptionNames.syzygy50MoveRule: syzygy50MoveRule,
      OptionNames.syzygyProbeLimit: syzygyProbeLimit,
      OptionNames.evalFile: evalFile,
    };
    return {
      for (final name in OptionNames.ordered)
        if (values[name] != null) name: '${values[name]}',
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! StockfishOptions) return false;
    final a = toUciMap(), b = other.toUciMap();
    return a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    toUciMap().entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'StockfishOptions(${toUciMap()})';
}
