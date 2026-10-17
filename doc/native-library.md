# The native library

stockfish_dart embeds Stockfish as native code assets: one **dispatcher**
library (`stockfish`), which contains the 98 MB NNUE network, plus one small
**engine library** per CPU variant (`stockfish_x86_64_avx2`, ...). At
startup the dispatcher detects the CPU's instruction set extensions and loads
the fastest variant available.

| Target | Variants |
|---|---|
| x64 (Linux, macOS, Windows) | `x86_64` (SSE2), `x86_64_sse41_popcnt`, `x86_64_avx2`, `x86_64_bmi2`, `x86_64_avxvnni`, `x86_64_avx512`, `x86_64_vnni512`, `x86_64_avx512icl` |
| arm64 Linux/Windows | `armv8`, `armv8_dotprod` |
| arm64 macOS | `armv8_dotprod` |

`Stockfish.inspectEmbeddedLibrary()` reports the variants the CPU supports
and the one in use. Set the environment variable
`STOCKFISH_DART_VARIANT=<variant>` to force a specific (supported) variant.

## How the libraries are obtained

The package's build hook (`hook/build.dart`) runs on `dart run`, `dart test`
and `dart build cli`, but not on `dart pub get`. It provides the libraries
from the first of these sources that applies:

1. **`library_dir`** user-define: a directory with prebuilt libraries.
2. **`build_from_source: true`** user-define: compile the bundled Stockfish
   sources with the host's C++ compiler.
3. **Download** (default): fetch the files listed in `native/manifest.json`
   from this package's GitHub release, check each file's SHA-256 against the
   manifest, and cache them in `.dart_tool/hooks_runner/shared/`.

Configuration goes in your application's `pubspec.yaml`. Build hooks don't
see arbitrary environment variables, but they do honour `HTTPS_PROXY` and
`NO_PROXY`.

```yaml
hooks:
  user_defines:
    stockfish_dart:
      # Use prebuilt libraries from this directory (relative to pubspec.yaml).
      library_dir: third_party/stockfish
      # Download from a mirror of the release assets instead of GitHub.
      download_base_url: https://artifacts.example.com/stockfish_dart/native-v0.1.0/
      # Fail instead of downloading (for locked-down CI).
      allow_download: false
      # Compile locally (needs clang++ or g++ with C++17; slow).
      build_from_source: true
```

### Offline and air-gapped builds

Download the release assets for your target (`<target>-<file>.gz`) from the
GitHub release named in `native/manifest.json`. Decompress them into one
directory and point `library_dir` at it. The file names must stay as they
are (`libstockfish.so`, `libstockfish_x86_64_avx2.so`, ...).

### Building from source

`build_from_source: true` compiles every variant for the build machine's
target. This takes a few minutes and downloads the NNUE network from
`tests.stockfishchess.org` (verified by its SHA-256). The compiler is taken
from `CXX` in the hook's environment, or `g++` on Linux and `clang++`
elsewhere. Use this for platforms without prebuilt libraries, for example
musl-based Linux.

## Troubleshooting

| Problem | Fix |
|---|---|
| `EngineLoadException: The Stockfish native library is not available...` | Run with `dart run`/`dart test`/`dart build cli`, not `dart compile exe`. On unsupported platforms, use `build_from_source`. |
| `Checksum mismatch` during the build | A proxy or mirror altered the download. Check `download_base_url`, or delete `.dart_tool/hooks_runner` and retry. |
| `bridge API version ... needs ...` | The cached library belongs to another package version. Delete `.dart_tool/hooks_runner` and rebuild. |
| `EngineAlreadyRunningException` | Only one embedded engine can run per process; dispose the other one, or use `EngineSource.process`. |
