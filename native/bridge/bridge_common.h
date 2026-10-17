// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors
//
// Definitions shared by the dispatcher library and the engine libraries.

#ifndef STOCKFISH_DART_BRIDGE_COMMON_H
#define STOCKFISH_DART_BRIDGE_COMMON_H

#include <stdint.h>

#if defined(_WIN32)
    #define SFD_EXPORT extern "C" __declspec(dllexport)
#else
    #define SFD_EXPORT extern "C" __attribute__((visibility("default")))
#endif

// Version of the C ABI between Dart and the dispatcher, and between the
// dispatcher and the engine libraries. Bump on any incompatible change.
#define SFD_API_VERSION 1

// Output streams passed to the line callback.
#define SFD_STREAM_STDOUT 0
#define SFD_STREAM_STDERR 1
#define SFD_STREAM_FATAL 2  // engine hit an unrecoverable error; restart it
#define SFD_STREAM_EXITED 3 // the UCI loop has ended (after quit or fatal error)

// Engine states reported by sfe_state() / sf_state().
#define SFD_STATE_STOPPED 0
#define SFD_STATE_RUNNING 1
#define SFD_STATE_FINISHED 2  // UCI thread ended on its own; call stop before restarting

// Return codes.
#define SFD_OK 0
#define SFD_ERR_ALREADY_RUNNING 1
#define SFD_ERR_NOT_RUNNING 2
#define SFD_ERR_TIMEOUT 3
#define SFD_ERR_LOAD 4
#define SFD_ERR_NO_NET 5

// Called for every complete output line. The line is only valid during the call.
typedef void (*sfd_line_callback)(int32_t stream, const char* line);

#endif
