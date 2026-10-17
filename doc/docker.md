# Docker

The build hook downloads the native libraries while the image is **built**.
`dart build cli` then bundles them next to the executable, so the final
image needs no network access and no setup at runtime.

```dockerfile
# syntax=docker/dockerfile:1
FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Runs the stockfish_dart build hook (download + SHA-256 check) and a short
# smoke test. Its own layer: only re-runs when pubspec.lock changes.
RUN dart run stockfish_dart:setup

COPY . .
RUN dart build cli -t bin/server.dart -o build

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/build/bundle/ /app/
ENTRYPOINT ["/app/bin/server"]
```

`.dockerignore`:

```
.dart_tool/
build/
```

Excluding `.dart_tool/` matters: `COPY . .` must not overwrite the hook cache
that the setup layer filled.

## Notes

- **`dart build cli`, never `dart compile exe`.** The latter refuses packages
  with native assets.
- **Multi-architecture images** work unchanged:
  `docker buildx build --platform linux/amd64,linux/arm64 .`. Each
  platform's build stage fetches the libraries for its architecture.
- **`FROM scratch` + `/runtime/`** works: the libraries only need glibc,
  which the Dart image's `/runtime/` provides (C++ runtime libraries are
  linked statically). `debian:*-slim` bases work too. Alpine/musl is not
  supported by the prebuilt libraries.
- **No network during `docker build`?** Copy prebuilt libraries into the build
  context and set the `library_dir` user-define (see
  [native library](native-library.md)), or use a mirror with
  `download_base_url`.
- **Sharing the download across builds:** with BuildKit, add
  `--mount=type=cache,target=/app/.dart_tool/hooks_runner/shared` to the
  `RUN dart run stockfish_dart:setup` line.
- **Resources:** `Hash` memory is allocated inside your process and counts
  toward the container's memory limit. Keep `threads` at or below the
  container's CPU quota.

## Example

[`example/docker`](../example/docker) contains a small best-move HTTP
service and a Dockerfile, which CI builds and runs with `--network none` on
amd64 and arm64:

```bash
docker build -f example/docker/Dockerfile -t stockfish-server .
docker run --rm -p 8080:8080 stockfish-server
curl 'localhost:8080/bestmove?fen=rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR%20b%20KQkq%20-%200%201&movetime=500'
```
