// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'package:meta/meta.dart';

/// Name, author and version from the `id` lines of the UCI handshake.
@immutable
final class EngineIdentity {
  /// Creates an identity.
  const EngineIdentity({required this.name, required this.author});

  /// `id name`, e.g. `Stockfish 19 (modified by stockfish_dart)`.
  final String name;

  /// `id author`.
  final String author;

  /// The version parsed from [name] (`19`, `dev-20261017-effdc3fd`), or null.
  String? get version =>
      RegExp(r'^Stockfish\s+(\S+)').firstMatch(name)?.group(1);

  @override
  String toString() => '$name by $author';
}

/// An engine option as advertised in the `uci` handshake
/// (`option name … type … default …`).
@immutable
sealed class UciOptionSpec {
  const UciOptionSpec(this.name);

  /// The option name, as the engine spells it.
  final String name;

  /// Parses an `option …` line. Returns null if malformed.
  static UciOptionSpec? tryParse(String line) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.first != 'option') return null;

    const keywords = {'name', 'type', 'default', 'min', 'max', 'var'};
    final fields = <String, List<String>>{};
    final vars = <String>[];
    String? key;
    final buffer = <String>[];
    void flush() {
      if (key == null) return;
      final value = buffer.join(' ');
      if (key == 'var') {
        vars.add(value);
      } else {
        fields[key] = [value];
      }
      buffer.clear();
    }

    for (final t in tokens.skip(1)) {
      if (keywords.contains(t)) {
        flush();
        key = t;
      } else {
        buffer.add(t);
      }
    }
    flush();

    final name = fields['name']?.first;
    final type = fields['type']?.first;
    if (name == null || name.isEmpty || type == null) return null;
    final def = fields['default']?.first;

    switch (type) {
      case 'check':
        return CheckOptionSpec(name, defaultValue: def == 'true');
      case 'spin':
        final d = int.tryParse(def ?? '');
        final min = int.tryParse(fields['min']?.first ?? '');
        final max = int.tryParse(fields['max']?.first ?? '');
        if (d == null || min == null || max == null) return null;
        return SpinOptionSpec(name, defaultValue: d, min: min, max: max);
      case 'combo':
        return ComboOptionSpec(
          name,
          defaultValue: def ?? '',
          values: List.unmodifiable(vars),
        );
      case 'string':
        return StringOptionSpec(
          name,
          defaultValue: def == null || def == '<empty>' ? '' : def,
        );
      case 'button':
        return ButtonOptionSpec(name);
    }
    return null;
  }
}

/// A boolean option (`type check`).
final class CheckOptionSpec extends UciOptionSpec {
  /// Creates the spec.
  const CheckOptionSpec(super.name, {required this.defaultValue});

  /// Default value.
  final bool defaultValue;

  @override
  String toString() => 'option $name check default $defaultValue';
}

/// An integer option (`type spin`).
final class SpinOptionSpec extends UciOptionSpec {
  /// Creates the spec.
  const SpinOptionSpec(
    super.name, {
    required this.defaultValue,
    required this.min,
    required this.max,
  });

  /// Default value.
  final int defaultValue;

  /// Smallest allowed value.
  final int min;

  /// Largest allowed value.
  final int max;

  @override
  String toString() =>
      'option $name spin default $defaultValue min $min max $max';
}

/// A choice between fixed strings (`type combo`).
final class ComboOptionSpec extends UciOptionSpec {
  /// Creates the spec.
  const ComboOptionSpec(
    super.name, {
    required this.defaultValue,
    required this.values,
  });

  /// Default value.
  final String defaultValue;

  /// Allowed values.
  final List<String> values;

  @override
  String toString() =>
      'option $name combo default $defaultValue var ${values.join(' var ')}';
}

/// A free-form string option (`type string`).
final class StringOptionSpec extends UciOptionSpec {
  /// Creates the spec.
  const StringOptionSpec(super.name, {required this.defaultValue});

  /// Default value (`<empty>` is reported as the empty string).
  final String defaultValue;

  @override
  String toString() => 'option $name string default $defaultValue';
}

/// An action without a value (`type button`).
final class ButtonOptionSpec extends UciOptionSpec {
  /// Creates the spec.
  const ButtonOptionSpec(super.name);

  @override
  String toString() => 'option $name button';
}
