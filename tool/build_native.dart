// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

// Builds the native libraries for the host (or a given) target.
//
//   dart run tool/build_native.dart [--target linux-x64] [--variants a,b]
//       [--out native/out/<target>] [--cxx clang++] [--jobs N]
//
// Release builds run in CI (.github/workflows/native.yml).

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:stockfish_dart/src/native/native_builder.dart';
import 'package:stockfish_dart/src/native/native_targets.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--') || i + 1 >= args.length) {
      stderr.writeln('Unexpected argument: $arg');
      exit(64);
    }
    options[arg.substring(2)] = args[++i];
  }

  final target = options['target'] != null
      ? NativeTarget.parse(options['target']!)
      : hostTarget();
  final root = Directory.fromUri(Platform.script.resolve('../'));
  final out = Directory(
    options['out'] ?? '${root.path}native/out/${target.name}/',
  );
  final outDir = Directory(out.path.endsWith(Platform.pathSeparator) || out.path.endsWith('/')
      ? out.path
      : '${out.path}${Platform.pathSeparator}');

  final net = await ensureNet(
    File('${root.path}native/.cache/$defaultNetName'),
    log: print,
  );

  final builder = NativeBuilder(
    packageRoot: root,
    target: target,
    outputDirectory: outDir,
    netFile: net,
    compiler: options['cxx'],
    variants: options['variants']?.split(','),
    jobs: options['jobs'] != null ? int.parse(options['jobs']!) : null,
  );

  final watch = Stopwatch()..start();
  final files = await builder.build();
  await writeBuildInfo(outDir, target, files, builder.compiler);
  print('Built ${files.length} libraries in ${watch.elapsed.inSeconds}s:');
  for (final f in files) {
    print('  ${f.path} (${(await f.length()) ~/ 1024} KiB)');
  }
}

NativeTarget hostTarget() => switch (Abi.current()) {
  Abi.linuxX64 => const NativeTarget(NativeOS.linux, NativeArch.x64),
  Abi.linuxArm64 => const NativeTarget(NativeOS.linux, NativeArch.arm64),
  Abi.macosX64 => const NativeTarget(NativeOS.macos, NativeArch.x64),
  Abi.macosArm64 => const NativeTarget(NativeOS.macos, NativeArch.arm64),
  Abi.windowsX64 => const NativeTarget(NativeOS.windows, NativeArch.x64),
  Abi.windowsArm64 => const NativeTarget(NativeOS.windows, NativeArch.arm64),
  final abi => throw UnsupportedError('No native target for $abi'),
};
