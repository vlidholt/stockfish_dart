# Licensing

> This is a summary for engineers, not legal advice.

stockfish_dart is licensed under the **GNU GPL v3.0 or later**, like
Stockfish. The native libraries contain a modified Stockfish 19; the
modifications are listed in [native/patches](../native/patches/README.md),
and the engine reports itself as `Stockfish 19 (modified by stockfish_dart)`.

## Using it on your own servers

The GPL's obligations apply when you **convey** (distribute) the software. If
your application runs only on infrastructure you operate and users interact
with it over a network, you are not distributing it, and you don't have to
publish your source code. (That gap is what the AGPL closes; neither
Stockfish nor this package uses the AGPL.)

## Distributing software that includes it

If you give others a copy, for example a desktop app, a CLI, an on-premise
installation or a Docker image you hand to customers, then:

- the whole program (your code plus this package plus Stockfish) must be
  licensed under GPL-3.0-compatible terms;
- you must include the license text (`LICENSE`);
- you must provide the corresponding source code of everything, including
  the native libraries. Their source is this repository at the matching
  release tag, and each native release on GitHub has a
  `stockfish_dart-native-source-*.tar.gz` attached.

## Using Stockfish from proprietary software

A program that is not GPL-compatible can still talk to an **unmodified,
separately distributed** Stockfish executable over UCI, as chess GUIs do. It
can't do so through this package, though, because this package is itself
GPL-licensed. Ask a lawyer about your specific case.

## Trademark

"Stockfish" is the name of the Stockfish project's engine. This package is
not affiliated with or endorsed by the Stockfish project.
