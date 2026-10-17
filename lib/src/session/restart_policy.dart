// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// @docImport '../errors.dart';
library;

import 'package:meta/meta.dart';

/// What to do when the engine hits an unrecoverable error.
///
/// After a restart, every option set through this package is re-applied in
/// its original order and the last successfully applied position is sent
/// again. The operation that was running fails with
/// [EngineFatalException].
@immutable
sealed class RestartPolicy {
  const RestartPolicy();

  /// Never restart; the engine stays unusable after a fatal error.
  static const RestartPolicy never = _Never();

  /// Always restart.
  static const RestartPolicy always = _Limited(null, null);

  /// Restart at most [maxRestarts] times within [window].
  const factory RestartPolicy.limited(int maxRestarts, Duration window) =
      _Limited;

  /// Whether another restart is allowed, given previous restart times.
  bool allows(List<DateTime> previousRestarts, DateTime now);
}

final class _Never extends RestartPolicy {
  const _Never();

  @override
  bool allows(List<DateTime> previousRestarts, DateTime now) => false;
}

final class _Limited extends RestartPolicy {
  const _Limited(this.maxRestarts, this.window);

  final int? maxRestarts;
  final Duration? window;

  @override
  bool allows(List<DateTime> previousRestarts, DateTime now) {
    final max = maxRestarts;
    if (max == null) return true;
    final recent = window == null
        ? previousRestarts
        : previousRestarts.where((t) => now.difference(t) <= window!);
    return recent.length < max;
  }
}
