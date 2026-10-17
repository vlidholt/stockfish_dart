# 04: Native library build and distribution

## 1. Strategy (decided)

**Every target gets its library at build time from the package's build
hook.** The hook downloads the right prebuilt library from this repo's GitHub
release, verifies its SHA-256 against the manifest shipped in the package,
and caches it. All libraries are **built by this repo's GitHub Actions** from
the pinned Stockfish submodule, our patches and the bridge. No binaries are
committed to git or published inside the pub package.

| Target | Library | Delivered by |
|---|---|---|
| linux-x64 | `libstockfish-linux-x64.so` | build hook download |
| linux-arm64 | `libstockfish-linux-arm64.so` | build hook download |
| macos-arm64 / macos-x64 | `libstockfish-macos.dylib` (fat) | build hook download |
| windows-x64 | `stockfish-windows-x64.dll` | build hook download |
| windows-arm64 | `stockfish-windows-arm64.dll` | build hook download |
| anything else | n/a | `build_from_source: true`, or `ProcessTransport` with an external binary |

Why this replaced "prepackage Linux":

- **Size.** The embedded NNUE net is 78.9 MB, so each library is about 80 MB.
  Prepackaging both Linux architectures (~165 MB) exceeds pub.dev's ~100 MB
  limit, and prepackaging only x64 left arm64 servers behind. Downloading
  keeps the pub package under 1 MB and treats every target the same.
- **Docker gets the same automation.** In a Docker build, the hook runs
  during `dart build cli` (or the warm-up step, §5), which is exactly the
  moment network access is normally available. The final image needs no
  network and no setup at runtime.

### When the hook runs (verified on Dart 3.13.5)

| Command | Runs hooks? | Notes |
|---|---|---|
| `dart pub get` / `dart pub upgrade` | **no** | Pub only resolves and downloads packages. There is no supported way to run code on `pub get`. |
| `dart run`, `dart test` | yes | First run downloads, later runs hit the cache |
| `dart run stockfish_dart:setup` (from an app) | yes | Runs the dependency's hook in the *app's* `.dart_tool/hooks_runner/shared/stockfish_dart/` |
| `dart build cli` | yes | Re-invokes the hook (different config) but finds the verified file in the same shared dir, so no second download. Bundles the library into `bundle/lib/`. |
| `dart compile exe` | **refused** | `'dart compile' does not support build hooks, use 'dart build' instead.` Documented prominently. |

## 2. The build hook (`hook/build.dart`)

```dart
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final target = Target(input.config.code.targetOS, input.config.code.targetArchitecture);
    final manifest = NativeManifest.load(input.packageRoot.resolve('native/manifest.json'));
    final opts = HookOptions.from(input.userDefines);   // app pubspec `hooks: user_defines:`

    final Uri lib = switch (resolveSource(target, manifest, opts)) {
      LocalOverride(:final path) => await verifyOptional(path, opts.librarySha256),
      Download(:final url)       => await fetchVerified(url, manifest[target],
                                       cacheDir: input.outputDirectoryShared),
      BuildFromSource()          => await buildFromSource(input, target),
      Unsupported()              => throw UnsupportedTargetError(target),
    };

    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'stockfish',                  // assetId: package:stockfish_dart/stockfish
      linkMode: DynamicLoadingBundled(),
      file: lib,
    ));
    output.addDependency(input.packageRoot.resolve('native/manifest.json'));
  });
}
```

`fetchVerified`:

1. If `<shared>/<sha256>/<filename>` exists and its recorded hash marker
   matches, return it. This is the cache hit for `dart build cli` after
   `dart run`.
2. Otherwise take a lock file, download to `.part` with `HttpClient`
   (redirects, `findProxyFromEnvironment`; `HTTPS_PROXY`/`NO_PROXY` *do*
   reach hooks), hash while streaming, retry 3× with backoff, and
   decompress `.gz`.
3. If the hash matches, do an atomic rename. On mismatch, delete the file and
   fail the build with a clear message.

Logs go to the hook's stdout, so `dart build` shows "stockfish_dart:
downloading libstockfish-linux-x64.so (80.4 MB)…" and not a silent pause.

**Configuration: `user_defines` only.** Hooks get a filtered environment:
`PATH`, `HOME`, temp dirs, proxy variables, plus OS basics. Arbitrary
variables such as `STOCKFISH_DART_*` are *not* passed through (verified). All
knobs live in the app's `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    stockfish_dart:
      library_path: native/libstockfish.so     # offline / air-gapped: use this file
      library_sha256: 9def…                     # optional check for library_path
      download_base_url: https://artifacts.corp/stockfish_dart/   # mirror
      allow_download: false                     # fail rather than download (strict CI)
      build_from_source: true                   # compile locally (needs a C++17 toolchain)
```

**Runtime check.** On first use, `FfiTransport` compares `sf_api_version()`
with the Dart side's expected ABI. A mismatch raises `EngineLoadException`
with fix-it text.

## 3. CI build pipeline (`.github/workflows/native.yml`)

Triggers: PRs touching `native/` (build + test only), and the tag
`native-v*` / `workflow_dispatch` (build, test and release).

| Job | Runner | Toolchain | Output | Notes |
|---|---|---|---|---|
| linux-x64 | `ubuntu-24.04` in a `manylinux_2_28` container | GCC 14 / Clang 19 | `libstockfish-linux-x64.so` | glibc ≥ 2.28; `-static-libstdc++ -static-libgcc` so only glibc is needed (runs on the Dart image's `/runtime` + `scratch`); only `sf_*` exported |
| linux-arm64 | `ubuntu-24.04-arm` + `manylinux_2_28_aarch64` | same | `libstockfish-linux-arm64.so` | same |
| macos | `macos-15` | Apple Clang | `libstockfish-macos.dylib` (arm64 + x86_64 `lipo`) | `MACOSX_DEPLOYMENT_TARGET=11.0`, ad-hoc `codesign -s -` |
| windows-x64 | `windows-2025` + MSYS2 `clang64` | Clang + libc++ | `stockfish-windows-x64.dll` | fully static runtime |
| windows-arm64 | `windows-11-arm` + MSYS2 `clangarm64` | Clang + libc++ | `stockfish-windows-arm64.dll` | same |

Each job:

1. Applies `native/patches/*.patch` and runs `tool/audit_exits.dart`.
2. Builds the shared library (`-fPIC -shared -fexceptions`, bridge instead of
   `main.cpp`, net embedded).
3. Runs the C smoke harness and the Dart integration suite against the fresh
   library (`library_path`).
4. Uploads `<file>.gz`, `.sha256` and `build-info.json`.

The release job creates `native-vX.Y.Z` with all assets plus
`stockfish_dart-native-source-X.Y.Z.tar.gz` (the GPL corresponding source),
then opens a PR that updates `native/manifest.json`. The `publish.yml`
workflow (tag `vX.Y.Z`) refuses to publish unless every manifest URL resolves
and its hash matches. That guarantees no published package version points to
a missing asset. Release assets are never deleted.

### Open technical risk (M0 spike)

Stockfish 19's *universal* build (runtime CPU dispatch; LTO + assembly
section rewriting + its own net embedding) targets executables. M0 must prove
it can produce a position-independent shared library. Fallbacks:

- **A:** a tiny loader library that checks CPUID and `dlopen`s one of two
  variants (`x86-64-avx2` / `x86-64-sse41-popcnt`).
- **B:** `x86-64-avx2` only, which covers essentially every server CPU since
  about 2015.

## 4. Package size

The pub archive contains only Dart code, the bridge sources, the Stockfish
source (about 300 KB, net excluded), patches, build scripts and
`manifest.json`, for a total under 1 MB. The pub.dev size limit is no longer
a concern.

## 5. Docker (server side): zero manual setup

The package ships `bin/setup.dart`. Running it with
`dart run stockfish_dart:setup` triggers the hook (download + verify), then
starts the engine, runs `uci` + `go depth 1`, prints the target, library path
and engine id, and exits non-zero on any failure. It works as a build-time
smoke test and as a local "doctor" command.

Recommended Dockerfile, shipped as `example/docker/Dockerfile` and tested in CI:

```dockerfile
# syntax=docker/dockerfile:1
FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Downloads + verifies libstockfish for this image's architecture and smoke-tests
# it. Separate layer: only re-runs when pubspec.lock changes, not on code edits.
RUN dart run stockfish_dart:setup

COPY . .
RUN dart build cli -t bin/server.dart -o build    # reuses the cached library

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bundle/ /app/
ENTRYPOINT ["/app/bin/server"]
```

Notes for `doc/docker.md`:

- `.dockerignore` must exclude `.dart_tool/` and `build/`, so `COPY . .`
  doesn't clobber the warmed hook cache.
- **Multi-arch:** `docker buildx build --platform linux/amd64,linux/arm64`
  works without changes. Each platform's build stage runs the hook for its
  own architecture.
- **Never `dart compile exe`.** It refuses packages with hooks. Use
  `dart build cli`.
- **`FROM scratch` + `/runtime`:** the library needs only glibc (libstdc++
  is linked statically). M0 confirms that the official image's `/runtime`
  covers it. `debian:*-slim` also works. Alpine/musl is **not** supported by
  the prebuilt libraries (use `build_from_source` or `ProcessTransport` there).
- **Running with `dart run` in the container** (no AOT build) also works. Keep
  the `setup` step in the image so the first container start doesn't download.
- **No network at build time:** commit or `COPY` the library and set
  `library_path`, or point `download_base_url` at an internal mirror
  (Artifactory/Nexus generic repo, S3).
- **Optional BuildKit cache:**
  `RUN --mount=type=cache,target=/app/.dart_tool/hooks_runner/shared …`
  shares the download across unrelated image builds on the same builder.
- **Resources:** document `Threads`/`Hash` against container CPU/memory
  limits. The engine's `Hash` counts toward the container's memory limit.

## 6. `ProcessTransport` binaries

`ProcessTransport` resolves an *external* executable: explicit path →
`STOCKFISH_PATH` → `PATH`. It never downloads, so the package's network
behaviour stays limited to the build hook.

## 7. Maintainer runbook: upgrading Stockfish

1. `git -C native/stockfish checkout sf_20`; rebase `native/patches/`.
2. `dart run tool/audit_exits.dart --update`; classify new `exit()` sites (01 §5).
3. `dart run tool/capture_fixtures.dart` to refresh transcripts.
4. `dart run tool/check_option_coverage.dart`; add or remove typed options
   (removals → major version).
5. Bump the bridge ABI if `sf_bridge.h` changed. Tag `native-vX.Y.Z`, merge
   the manifest PR, tag `vX.Y.Z`.
