// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Packages built libraries as release assets and writes native/manifest.json.
//
//   dart run tool/make_manifest.dart --release native-v0.1.0 \
//       --input artifacts/ --output release-assets/
//
// <input>/<target>/ holds the libraries of each target (as produced by
// tool/build_native.dart). Every library is gzip-compressed into
// <output>/<target>-<file>.gz, and native/manifest.json records the
// SHA-256 and size of the uncompressed file.

import 'dart:convert';
import 'dart:io';

import 'package:stockfish_dart/src/native/library_fetcher.dart';
import 'package:stockfish_dart/src/native/native_manifest.dart';
import 'package:stockfish_dart/src/native/native_targets.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    options[args[i].replaceFirst('--', '')] = args[i + 1];
  }
  final release = options['release'] ?? (throw ArgumentError('--release'));
  final input = Directory(options['input'] ?? 'artifacts');
  final output = Directory(options['output'] ?? 'release-assets');
  final repo = options['repo'] ?? 'vlidholt/stockfish_dart';
  await output.create(recursive: true);

  final targets = <String, List<ManifestFile>>{};
  for (final target in NativeTarget.all) {
    final dir = Directory('${input.path}/${target.name}');
    if (!dir.existsSync()) {
      stderr.writeln('warning: no libraries for ${target.name}');
      continue;
    }
    final names = [
      target.dispatcherFileName,
      for (final v in target.variants) target.variantFileName(v),
    ];
    final files = <ManifestFile>[];
    for (final name in names) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) {
        throw StateError('Missing ${file.path}');
      }
      final asset = '${target.name}-$name.gz';
      final bytes = await file.readAsBytes();
      await File('${output.path}/$asset').writeAsBytes(gzip.encode(bytes));
      files.add(
        ManifestFile(
          name: name,
          asset: asset,
          sha256: await sha256OfFile(file),
          size: bytes.length,
        ),
      );
      stdout.writeln('${target.name}: $name -> $asset');
    }
    targets[target.name] = files;
  }

  final manifest = NativeManifest(
    release: release,
    baseUrl: 'https://github.com/$repo/releases/download/$release/',
    targets: targets,
  );
  final json =
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n';
  await File('native/manifest.json').writeAsString(json);
  await File('${output.path}/manifest.json').writeAsString(json);
  stdout.writeln('Wrote native/manifest.json for ${targets.length} targets');
}
