// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Compiles the dispatcher and the engine variant libraries from the vendored
/// Stockfish sources. Used by `tool/build_native.dart` (CI release builds)
/// and by the build hook when `build_from_source: true` is configured.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_targets.dart';

/// Stockfish translation units (upstream Makefile `SRCS` without main.cpp).
const stockfishSources = [
  'attacks.cpp',
  'benchmark.cpp',
  'bitboard.cpp',
  'evaluate.cpp',
  'misc.cpp',
  'movegen.cpp',
  'movepick.cpp',
  'position.cpp',
  'search.cpp',
  'thread.cpp',
  'timeman.cpp',
  'tt.cpp',
  'uci.cpp',
  'ucioption.cpp',
  'tune.cpp',
  'syzygy/tbprobe.cpp',
  'nnue/nnue_accumulator.cpp',
  'nnue/nnue_misc.cpp',
  'nnue/network.cpp',
  'nnue/features/half_ka_v2_hm.cpp',
  'nnue/features/full_threats.cpp',
  'nnue/features/pp_3wide.cpp',
  'engine.cpp',
  'score.cpp',
  'memory.cpp',
];

/// Compiler flags per engine variant, mirroring Stockfish's Makefile.
Map<String, List<String>> variantFlags() {
  const sse2 = ['-msse', '-DUSE_SSE2', '-msse2'];
  const sse41 = [
    ...sse2,
    '-msse3',
    '-mpopcnt',
    '-DUSE_POPCNT',
    '-DUSE_SSSE3',
    '-mssse3',
    '-DUSE_SSE41',
    '-msse4.1',
  ];
  const avx2 = [...sse41, '-DUSE_AVX2', '-mavx2', '-mbmi'];
  const bmi2 = [...avx2, '-DUSE_PEXT', '-mbmi2'];
  const avx512 = [
    ...bmi2,
    '-DUSE_AVX512',
    '-mavx512f',
    '-mavx512bw',
    '-mavx512dq',
    '-mavx512vl',
  ];
  const vnni512 = [...avx512, '-DUSE_VNNI', '-mavx512vnni'];
  const armv8 = ['-DUSE_NEON=8', '-DUSE_POPCNT'];
  return {
    'x86_64': sse2,
    'x86_64_sse41_popcnt': sse41,
    'x86_64_avx2': avx2,
    'x86_64_bmi2': bmi2,
    'x86_64_avxvnni': [...bmi2, '-DUSE_VNNI', '-DUSE_AVXVNNI', '-mavxvnni'],
    'x86_64_avx512': avx512,
    'x86_64_vnni512': vnni512,
    'x86_64_avx512icl': [
      ...vnni512,
      '-DUSE_AVX512ICL',
      '-mavx512cd',
      '-mavx512ifma',
      '-mavx512vbmi',
      '-mavx512vbmi2',
      '-mavx512vpopcntdq',
      '-mavx512bitalg',
      '-mvpclmulqdq',
      '-mgfni',
      '-mvaes',
    ],
    'armv8': armv8,
    'armv8_dotprod': [
      ...armv8,
      '-march=armv8.2-a+dotprod',
      '-DUSE_NEON_DOTPROD',
    ],
  };
}

/// Stockfish's ARCH name for a variant (shown by the `compiler` command).
String upstreamArchName(String variant) => switch (variant) {
  'x86_64' => 'x86-64',
  'armv8' => 'armv8',
  'armv8_dotprod' => 'armv8-dotprod',
  _ => variant.replaceFirst('x86_64_', 'x86-64-').replaceAll('_', '-'),
};

/// Builds the native libraries for one [target].
final class NativeBuilder {
  /// Creates a builder.
  NativeBuilder({
    required this.packageRoot,
    required this.target,
    required this.outputDirectory,
    required this.netFile,
    String? compiler,
    this.variants,
    int? jobs,
    this.log = _printLog,
  }) : compiler = compiler ?? _defaultCompiler(target),
       jobs = jobs ?? Platform.numberOfProcessors;

  /// Root directory of the stockfish_dart package.
  final Directory packageRoot;

  /// What to build for.
  final NativeTarget target;

  /// Where the libraries are written.
  final Directory outputDirectory;

  /// The NNUE network embedded into the dispatcher.
  final File netFile;

  /// C++ compiler driver (clang++ or g++).
  final String compiler;

  /// Variants to build; defaults to [NativeTarget.variants].
  final List<String>? variants;

  /// Maximum number of parallel compiler processes.
  final int jobs;

  /// Progress output.
  final void Function(String message) log;

  static void _printLog(String message) => stdout.writeln(message);

  static String _defaultCompiler(NativeTarget target) {
    final env = Platform.environment['CXX'];
    if (env != null && env.isNotEmpty) return env;
    return target.os == NativeOS.linux ? 'g++' : 'clang++';
  }

  Directory get _src =>
      Directory.fromUri(packageRoot.uri.resolve('native/stockfish/src/'));
  Directory get _bridge =>
      Directory.fromUri(packageRoot.uri.resolve('native/bridge/'));

  List<String> get _targetFlags => switch (target.os) {
    NativeOS.macos => [
      '-arch',
      target.arch == NativeArch.x64 ? 'x86_64' : 'arm64',
      target.arch == NativeArch.x64
          ? '-mmacosx-version-min=10.15'
          : '-mmacosx-version-min=11.0',
    ],
    NativeOS.linux => ['-fPIC', '-pthread'],
    NativeOS.windows => const [],
  };

  List<String> get _commonFlags => [
    '-std=c++17',
    '-DNDEBUG',
    '-DIS_64BIT',
    '-DSTOCKFISH_DART_BRIDGE',
    '-fexceptions',
    '-fvisibility=hidden',
    '-Wall',
    '-Wcast-qual',
    '-I${_src.path}',
    '-I${_bridge.path}',
    ..._targetFlags,
  ];

  List<String> _linkFlags(String fileName) => switch (target.os) {
    NativeOS.linux => [
      '-shared',
      '-pthread',
      '-static-libstdc++',
      '-static-libgcc',
      '-Wl,--no-undefined',
      '-Wl,--exclude-libs,ALL',
      '-Wl,--no-as-needed',
      '-s',
    ],
    NativeOS.macos => [
      '-dynamiclib',
      '-install_name',
      '@rpath/$fileName',
      ..._targetFlags,
    ],
    NativeOS.windows => ['-shared', '-static', '-lpthread', '-s'],
  };

  /// Builds everything and returns the produced files.
  Future<List<File>> build() async {
    await outputDirectory.create(recursive: true);
    final objRoot = Directory.fromUri(
      outputDirectory.uri.resolve('obj/'),
    );
    final produced = <File>[];
    final flags = variantFlags();

    for (final variant in variants ?? target.variants) {
      final extra = flags[variant];
      if (extra == null) throw ArgumentError('Unknown variant $variant');
      log('Building engine variant $variant for ${target.name}');
      final objDir = Directory.fromUri(objRoot.uri.resolve('$variant/'));
      await objDir.create(recursive: true);
      final sources = [
        for (final s in stockfishSources) File('${_src.path}$s'),
        File('${_bridge.path}engine_bridge.cpp'),
      ];
      final objects = <String>[];
      await _parallel(sources.map((source) {
        final name = source.uri.pathSegments.last.replaceAll('.cpp', '.o');
        final obj = '${objDir.path}$name';
        objects.add(obj);
        return () => _run(compiler, [
          ..._commonFlags,
          '-O3',
          '-funroll-loops',
          '-DARCH=${upstreamArchName(variant)}',
          ...extra,
          '-c',
          source.path,
          '-o',
          obj,
        ]);
      }));
      final fileName = target.variantFileName(variant);
      final out = File('${outputDirectory.path}$fileName');
      await _run(compiler, [
        ...objects,
        '-o',
        out.path,
        ..._linkFlags(fileName),
      ]);
      produced.add(out);
    }

    log('Building dispatcher for ${target.name}');
    final netPath = netFile.absolute.path.replaceAll(r'\', '/');
    final dispatcherObj = '${objRoot.path}dispatcher.o';
    await _run(compiler, [
      ..._commonFlags,
      '-O2',
      '-DSFD_NET_PATH="$netPath"',
      '-c',
      '${_bridge.path}dispatcher.cpp',
      '-o',
      dispatcherObj,
    ]);
    final dispatcher = File('${outputDirectory.path}${target.dispatcherFileName}');
    await _run(compiler, [
      dispatcherObj,
      '-o',
      dispatcher.path,
      ..._linkFlags(target.dispatcherFileName),
      if (target.os == NativeOS.linux) '-ldl',
    ]);
    produced.add(dispatcher);
    return produced;
  }

  Future<void> _parallel(Iterable<Future<void> Function()> tasks) async {
    final queue = tasks.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        await queue[next++]();
      }
    }

    await Future.wait([for (var i = 0; i < jobs; i++) worker()]);
  }

  Future<void> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args, runInShell: false);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    final warnings = '${result.stderr}'.trim();
    if (warnings.isNotEmpty) log(warnings);
  }
}

/// Makes sure [file] contains the default NNUE network, downloading it if
/// needed. The network's file name encodes the start of its SHA-256.
Future<File> ensureNet(File file, {void Function(String)? log}) async {
  final expectedPrefix = defaultNetName.substring(3, 15);
  if (await file.exists() &&
      (await _sha256Hex(file)).startsWith(expectedPrefix)) {
    return file;
  }
  log?.call('Downloading $defaultNetUrl');
  await file.parent.create(recursive: true);
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final request = await client.getUrl(Uri.parse(defaultNetUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(defaultNetUrl));
    }
    final part = File('${file.path}.part');
    await response.pipe(part.openWrite());
    final hash = await _sha256Hex(part);
    if (!hash.startsWith(expectedPrefix)) {
      await part.delete();
      throw StateError('Downloaded network has unexpected SHA-256 $hash');
    }
    await part.rename(file.path);
  } finally {
    client.close();
  }
  return file;
}

Future<String> _sha256Hex(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Writes `build-info.json` describing a build.
Future<void> writeBuildInfo(
  Directory outputDirectory,
  NativeTarget target,
  List<File> files,
  String compiler,
) async {
  final version = await Process.run(compiler, ['--version']);
  final info = {
    'target': target.name,
    'stockfish': 'sf_19',
    'net': defaultNetName,
    'compiler': '${version.stdout}'.split('\n').first.trim(),
    'files': {
      for (final f in files)
        f.uri.pathSegments.last: {
          'size': await f.length(),
          'sha256': await _sha256Hex(f),
        },
    },
  };
  await File('${outputDirectory.path}build-info.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(info),
  );
}
