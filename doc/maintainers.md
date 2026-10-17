# Maintainers: building and releasing

## Local development

```bash
# Build every variant for this machine into native/out/<target>/.
# Uses $CXX, or g++ on Linux and clang++ elsewhere (Windows: llvm-mingw).
dart run tool/build_native.dart
dart run tool/build_native.dart --variants x86_64_avx2   # faster: one variant

dart test                           # unit, session and integration tests
dart run tool/smoke_variants.dart   # every variant this CPU supports
dart run tool/capture_fixtures.dart # refresh test/fixtures/sf19
```

The build hook prefers `native/out/<target>/` when it exists, so tests and
examples use your local build.

## Releasing

1. Push to `main`. The `native` workflow builds and tests all six targets.
2. Tag the native release: `git tag native-v0.1.0 && git push origin native-v0.1.0`.
   The workflow publishes the libraries (gzip-compressed), their
   `build-info.json`, the corresponding-source tarball, and commits the
   updated `native/manifest.json` to `main`.
3. Pull, check that `ci` passes (it now tests the download path and the
   Docker image), bump `version` in `pubspec.yaml`, update `CHANGELOG.md`,
   and publish with `dart pub publish`.

Each package version's manifest points to a fixed native release, so never
delete or replace release assets that a published version uses.

## Upgrading Stockfish

See [native/patches/README.md](../native/patches/README.md). Afterwards:

- update `EvalFileDefaultName`-dependent constants (`defaultNetName` in
  `lib/src/native/native_targets.dart`);
- run `dart run tool/capture_fixtures.dart` and fix any parser changes;
- check new or removed options against `StockfishOptions` (the
  `every advertised option has a typed field` test fails when they differ);
- update the expected `exit()`/`abort()` count in `.github/workflows/ci.yml`
  after reviewing new sites.
