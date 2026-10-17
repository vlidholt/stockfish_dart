// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Low-level UCI building blocks: typed commands, an output parser, the
/// protocol session and the transports.
///
/// Nothing here is Stockfish-specific, so it can drive other UCI engines
/// too, for example through a `ProcessTransport`:
///
/// ```dart
/// final session = EngineSession(ProcessTransport('/usr/bin/lc0'));
/// await session.start();
/// print(session.identity);
/// ```
library;

export 'src/session/engine_session.dart';
export 'src/transport/engine_transport.dart';
export 'src/transport/ffi_transport.dart';
export 'src/transport/process_transport.dart';
export 'src/uci/uci_command.dart';
export 'src/uci/uci_event.dart';
