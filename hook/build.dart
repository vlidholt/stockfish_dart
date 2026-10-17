// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Provides the Stockfish native libraries as code assets.
//
// Where the libraries come from, in order of precedence:
//  1. `library_dir` user-define: a directory with prebuilt libraries.
//  2. `native/out/<target>/` inside this package (local development builds
//     made with `dart run tool/build_native.dart`).
//  3. `build_from_source: true` user-define: compile with the host toolchain.
//  4. Download from the GitHub release listed in `native/manifest.json`,
//     verified against its SHA-256 hashes (default).
//
// Configure in the application's pubspec.yaml:
//
//   hooks:
//     user_defines:
//       stockfish_dart:
//         library_dir: path/to/libs        # offline / air-gapped builds
//         download_base_url: https://...   # mirror of the release assets
//         allow_download: false            # fail instead of downloading
//         build_from_source: true          # needs a C++17 compiler

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:stockfish_dart/src/native/library_fetcher.dart';
import 'package:stockfish_dart/src/native/native_builder.dart';
import 'package:stockfish_dart/src/native/native_manifest.dart';
import 'package:stockfish_dart/src/native/native_targets.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final target = _target(input.config.code);
    if (target == null) {
      // Unsupported platform: no assets. Using the engine throws a clear
      // EngineLoadException at runtime.
      return;
    }

    final packageRoot = Directory.fromUri(input.packageRoot);
    final manifestUri = input.packageRoot.resolve('native/manifest.json');
    output.dependencies.add(manifestUri);

    final files = await _resolveFiles(input, output, target, packageRoot);

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final String assetName;
      if (name == target.dispatcherFileName) {
        assetName = dispatcherAssetName;
      } else {
        final variant = target.variants.firstWhere(
          (v) => target.variantFileName(v) == name,
          orElse: () => '',
        );
        if (variant.isEmpty) continue;
        assetName = variantAssetName(variant);
      }
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: assetName,
          linkMode: DynamicLoadingBundled(),
          file: file.absolute.uri,
        ),
      );
    }
  });
}

NativeTarget? _target(CodeConfig code) {
  final os = switch (code.targetOS) {
    OS.linux => NativeOS.linux,
    OS.macOS => NativeOS.macos,
    OS.windows => NativeOS.windows,
    _ => null,
  };
  final arch = switch (code.targetArchitecture) {
    Architecture.x64 => NativeArch.x64,
    Architecture.arm64 => NativeArch.arm64,
    _ => null,
  };
  if (os == null || arch == null) return null;
  return NativeTarget(os, arch);
}

Future<List<File>> _resolveFiles(
  BuildInput input,
  BuildOutputBuilder output,
  NativeTarget target,
  Directory packageRoot,
) async {
  void log(String message) => stdout.writeln('stockfish_dart: $message');

  // 1. Explicit directory.
  final libraryDir = input.userDefines.path('library_dir');
  if (libraryDir != null) {
    final files = _filesIn(Directory.fromUri(libraryDir), target);
    if (files.isEmpty) {
      throw LibraryFetchException(
        'library_dir ${libraryDir.toFilePath()} contains no '
        '${target.dispatcherFileName}.',
      );
    }
    output.dependencies.addAll(files.map((f) => f.uri));
    return files;
  }

  // 2. Local development build inside this package.
  final localOut = Directory.fromUri(
    input.packageRoot.resolve('native/out/${target.name}/'),
  );
  // Always a dependency, so creating or deleting a local build re-runs the
  // hook instead of reusing a cached result.
  output.dependencies.add(localOut.uri);
  final localFiles = _filesIn(localOut, target);
  if (localFiles.isNotEmpty) {
    log('using local build in ${localOut.path}');
    output.dependencies.addAll(localFiles.map((f) => f.uri));
    return localFiles;
  }

  final shared = Directory.fromUri(input.outputDirectoryShared);

  // 3. Build from source.
  if (input.userDefines['build_from_source'] == true) {
    final outDir = Directory('${shared.path}build-${target.name}/');
    final net = await ensureNet(
      File('${shared.path}$defaultNetName'),
      log: log,
    );
    final builder = NativeBuilder(
      packageRoot: packageRoot,
      target: target,
      outputDirectory: outDir,
      netFile: net,
      log: log,
    );
    return builder.build();
  }

  // 4. Download.
  final manifest = NativeManifest.load(
    File.fromUri(input.packageRoot.resolve('native/manifest.json')),
  );
  final entries = manifest.targets[target.name];
  if (entries == null || manifest.baseUrl == null) {
    // Not an error at build time: code that doesn't start the embedded
    // engine (tools, FakeStockfish tests, EngineSource.process) still works.
    // Starting the engine throws EngineLoadException.
    log(
      'WARNING: this version of stockfish_dart has no prebuilt libraries '
      'for ${target.name}; the embedded engine will not be available. Set '
      'the user-define stockfish_dart.build_from_source: true (needs a C++17 '
      'compiler) or stockfish_dart.library_dir.',
    );
    return const [];
  }
  if (input.userDefines['allow_download'] == false) {
    throw LibraryFetchException(
      'Downloading is disabled (allow_download: false) and no library_dir is '
      'configured.',
    );
  }
  final baseUrlDefine = input.userDefines['download_base_url'];
  var baseUrl = baseUrlDefine is String ? baseUrlDefine : manifest.baseUrl!;
  if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';

  final fetcher = LibraryFetcher(
    cacheDirectory: Directory(
      '${shared.path}${manifest.release ?? 'unversioned'}${Platform.pathSeparator}'
      '${target.name}',
    ),
    baseUrl: Uri.parse(baseUrl),
    log: log,
  );
  return fetcher.fetch(entries);
}

List<File> _filesIn(Directory dir, NativeTarget target) {
  final dispatcher = File(
    '${dir.path}${Platform.pathSeparator}${target.dispatcherFileName}',
  );
  if (!dispatcher.existsSync()) return const [];
  return [
    dispatcher,
    for (final v in target.variants)
      if (File(
        '${dir.path}${Platform.pathSeparator}${target.variantFileName(v)}',
      ).existsSync())
        File(
          '${dir.path}${Platform.pathSeparator}${target.variantFileName(v)}',
        ),
  ];
}
