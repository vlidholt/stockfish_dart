// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// `native/manifest.json`: where the prebuilt libraries of this package
/// version are published and what their hashes are.
library;

import 'dart:convert';
import 'dart:io';

/// One prebuilt library file.
final class ManifestFile {
  /// Creates an entry.
  const ManifestFile({
    required this.name,
    required this.asset,
    required this.sha256,
    required this.size,
  });

  /// File name of the (uncompressed) library, e.g. `libstockfish.so`.
  final String name;

  /// Name of the gzip-compressed release asset, e.g.
  /// `linux-x64-libstockfish.so.gz`.
  final String asset;

  /// Hex SHA-256 of the uncompressed library.
  final String sha256;

  /// Size of the uncompressed library in bytes.
  final int size;

  /// Parses a JSON entry.
  factory ManifestFile.fromJson(String name, Map<String, Object?> json) =>
      ManifestFile(
        name: name,
        asset: json['asset']! as String,
        sha256: json['sha256']! as String,
        size: json['size']! as int,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'asset': asset,
    'sha256': sha256,
    'size': size,
  };
}

/// The parsed manifest.
final class NativeManifest {
  /// Creates a manifest.
  const NativeManifest({
    required this.release,
    required this.baseUrl,
    required this.targets,
  });

  /// Git tag of the GitHub release holding the files (e.g. `native-v0.1.0`).
  final String? release;

  /// URL the asset names are resolved against.
  final String? baseUrl;

  /// Files per target name (`linux-x64`, ...).
  final Map<String, List<ManifestFile>> targets;

  /// Reads [file].
  static NativeManifest load(File file) =>
      parse(jsonDecode(file.readAsStringSync()) as Map<String, Object?>);

  /// Parses decoded JSON.
  static NativeManifest parse(Map<String, Object?> json) {
    final targets = <String, List<ManifestFile>>{};
    final rawTargets = (json['targets'] as Map<String, Object?>?) ?? const {};
    for (final MapEntry(:key, :value) in rawTargets.entries) {
      final files =
          (value! as Map<String, Object?>)['files']! as Map<String, Object?>;
      targets[key] = [
        for (final f in files.entries)
          ManifestFile.fromJson(f.key, f.value! as Map<String, Object?>),
      ];
    }
    return NativeManifest(
      release: json['release'] as String?,
      baseUrl: json['baseUrl'] as String?,
      targets: targets,
    );
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'release': release,
    'baseUrl': baseUrl,
    'targets': {
      for (final MapEntry(:key, :value) in targets.entries)
        key: {
          'files': {for (final f in value) f.name: f.toJson()},
        },
    },
  };
}
