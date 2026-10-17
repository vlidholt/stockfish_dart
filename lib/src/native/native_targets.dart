// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Native library layout shared by the build hook, the native build tool and
/// the runtime. Pure Dart, so it can be imported from `hook/build.dart`.
library;

/// Operating systems the prebuilt libraries are made for.
enum NativeOS {
  /// Linux (glibc).
  linux,

  /// macOS.
  macos,

  /// Windows.
  windows;

  /// File name prefix of shared libraries on this OS.
  String get libraryPrefix => this == windows ? '' : 'lib';

  /// File name extension of shared libraries on this OS (with dot).
  String get libraryExtension => switch (this) {
    linux => '.so',
    macos => '.dylib',
    windows => '.dll',
  };
}

/// CPU architectures the prebuilt libraries are made for.
enum NativeArch {
  /// 64-bit x86.
  x64,

  /// 64-bit ARM.
  arm64,
}

/// One supported OS/architecture combination.
final class NativeTarget {
  /// Creates a target.
  const NativeTarget(this.os, this.arch);

  /// The operating system.
  final NativeOS os;

  /// The CPU architecture.
  final NativeArch arch;

  /// Every target that has prebuilt libraries.
  static const all = [
    NativeTarget(NativeOS.linux, NativeArch.x64),
    NativeTarget(NativeOS.linux, NativeArch.arm64),
    NativeTarget(NativeOS.macos, NativeArch.x64),
    NativeTarget(NativeOS.macos, NativeArch.arm64),
    NativeTarget(NativeOS.windows, NativeArch.x64),
    NativeTarget(NativeOS.windows, NativeArch.arm64),
  ];

  /// Parses `linux-x64` style names.
  static NativeTarget parse(String name) {
    for (final t in all) {
      if (t.name == name) return t;
    }
    throw ArgumentError.value(name, 'name', 'Unknown native target');
  }

  /// `linux-x64`, `macos-arm64`, ...
  String get name => '${os.name}-${arch.name}';

  /// Engine variants built for this target, slowest/most compatible first.
  ///
  /// The dispatcher picks the best one the CPU supports at runtime.
  List<String> get variants => switch (arch) {
    NativeArch.x64 => const [
      'x86_64',
      'x86_64_sse41_popcnt',
      'x86_64_avx2',
      'x86_64_bmi2',
      'x86_64_avxvnni',
      'x86_64_avx512',
      'x86_64_vnni512',
      'x86_64_avx512icl',
    ],
    // Every Apple silicon CPU supports the dot product instructions.
    NativeArch.arm64 when os == NativeOS.macos => const ['armv8_dotprod'],
    NativeArch.arm64 => const ['armv8', 'armv8_dotprod'],
  };

  /// File name of the dispatcher library (the `stockfish` code asset).
  String get dispatcherFileName =>
      '${os.libraryPrefix}stockfish${os.libraryExtension}';

  /// File name of the engine library for [variant].
  String variantFileName(String variant) =>
      '${os.libraryPrefix}stockfish_$variant${os.libraryExtension}';

  @override
  bool operator ==(Object other) =>
      other is NativeTarget && other.os == os && other.arch == arch;

  @override
  int get hashCode => Object.hash(os, arch);

  @override
  String toString() => name;
}

/// Code asset name of the dispatcher library.
const dispatcherAssetName = 'stockfish';

/// Code asset name of the engine library for [variant].
String variantAssetName(String variant) => 'stockfish_$variant';

/// File name of the NNUE network embedded in the dispatcher.
const defaultNetName = 'nn-1a298aa575a0.nnue';

/// Where the build tool downloads [defaultNetName] from.
const defaultNetUrl = 'https://tests.stockfishchess.org/api/nn/$defaultNetName';
