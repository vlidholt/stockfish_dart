# syntax=docker/dockerfile:1
#
# Builds the example best-move server. Build from the repository root:
#
#   docker build -f example/docker/Dockerfile -t stockfish-server .
#   docker run --rm -p 8080:8080 stockfish-server
#   curl 'localhost:8080/bestmove?fen=<fen>&movetime=500'
#
# In your own project, depend on stockfish_dart from pub.dev and use the same
# stages: `dart pub get`, `dart run stockfish_dart:setup`, `dart build cli`.

FROM dart:stable AS build
WORKDIR /src
COPY . .
WORKDIR /src/example/docker
RUN dart pub get
# Runs the stockfish_dart build hook: downloads and verifies the native
# library for this image's architecture, then smoke-tests the engine.
RUN dart run stockfish_dart:setup
RUN dart build cli -t bin/server.dart -o /out

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/bundle/ /app/
EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]
