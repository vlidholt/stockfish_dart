# 05: Licensing

> This is an engineering plan, not legal advice.

## 1. The package

- **License:** `GPL-3.0-or-later` (decided). It matches Stockfish's source
  headers. `/LICENSE` holds the verbatim GPL-3.0 text from gnu.org (SHA-256
  `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`), and
  pub.dev detects it automatically.
- **Every source file** we write (Dart, C++ bridge, build scripts) starts with:

  ```dart
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 stockfish_dart authors
  ```

  `tool/check_headers.dart` enforces this in CI.
- **Why GPL is not optional here.** The package links Stockfish into the same
  process through FFI, which makes it a combined work. So the package and
  anything *distributed* together with it must be under GPL-3-compatible
  terms. (With the optional `ProcessTransport`, the engine is a separate
  program. The package itself is still GPL-3.)

## 2. We now distribute modified Stockfish object code

Because the native libraries are **built and published by us** (GitHub
releases, fetched by the build hook) and include **our patches**, we take on the GPL-3 duties of a distributor of a modified
version.

| GPL-3 clause | What we do |
|---|---|
| §4/§5: keep notices, license the whole as GPL-3 | Stockfish's `Copying.txt` and `AUTHORS` are shipped in `native/stockfish/` (published) and inside every release asset bundle. |
| §5(a): prominent notice of modification, with date | `native/patches/README.md` lists every patch with its purpose and date. `engine_info()` reports `… (stockfish_dart X.Y.Z, modified)`, and `id name` shows it to every UCI consumer. CHANGELOG notes patch changes. |
| §6: corresponding source with object code | The libraries are distributed from our GitHub release. Each release carries `stockfish_dart-native-source-X.Y.Z.tar.gz` (Stockfish source, patches, bridge, build scripts) next to the binaries, which meets §6(d) (equivalent access from the same place). The pub package also contains the same sources (about 300 KB; the net is excluded and published by the Stockfish project), which `build_from_source` uses. |
| §6: "Installation Information" | Not applicable: no user products with locked-down hardware. |
| Build reproducibility | `build-info.json` records compiler, flags, Stockfish commit and patch hashes. The workflow is public. |

The NNUE network file is published by the Stockfish project under the same
licensing as the engine. We embed the unmodified file, and its name and hash
are recorded in `build-info.json`.

## 3. Downstream users: what to tell them (README + `doc/licensing.md`)

- **Using the package in a server or internal tool you don't distribute:**
  GPL-3 imposes no source-release duty. The obligations trigger on
  *conveying* (distributing) the software. Network use alone is not conveying
  (that gap is what AGPL closes, and neither Stockfish nor this package is
  AGPL).
- **Distributing an app built with the package** (`dart build cli` output,
  desktop app, Docker image given to customers, on-prem install): the whole
  app must be licensed GPL-3-compatibly. It must ship the license text, and
  must offer corresponding source for both the app and the bundled Stockfish
  library. `doc/distributing.md` gives a checklist and links to our
  native-source tarball for the Stockfish part.
- **Proprietary apps that need Stockfish:** the docs point to running an
  unmodified external Stockfish through `ProcessTransport`, communicating
  "at arm's length" over UCI. They note that the *package itself* is still
  GPL-3, so such an app would need its own UCI client, not this package. This
  is stated plainly so nobody is misled.

## 4. Trademark

"Stockfish" is the engine's name. The README states that the package is not
affiliated with or endorsed by the Stockfish project, and does not use the
Stockfish logo.
