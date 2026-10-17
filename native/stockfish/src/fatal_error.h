/*
  Stockfish, a UCI chess playing engine derived from Glaurung 2.1
  Copyright (C) 2004-2026 The Stockfish developers (see AUTHORS file)

  Stockfish is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Stockfish is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// stockfish_dart modification (2026-10-17): upstream Stockfish terminates the
// process with std::exit() on bad input and on resource failures. When the
// engine is embedded as a library inside a host process that is not
// acceptable, so those call sites throw one of the exceptions below instead.

#ifndef FATAL_ERROR_H_INCLUDED
#define FATAL_ERROR_H_INCLUDED

#include <stdexcept>
#include <string>

namespace Stockfish {

// A command could not be executed (invalid FEN, illegal move, bad argument,
// unreadable file, ...). The UCI loop reports it and keeps running.
class CommandError: public std::runtime_error {
   public:
    using std::runtime_error::runtime_error;
};

// The engine is in an unusable state (out of memory, corrupt tablebase,
// failed thread creation, ...). The embedding host must restart the engine.
class FatalError: public std::runtime_error {
   public:
    using std::runtime_error::runtime_error;
};

[[noreturn]] inline void command_error(const std::string& message) { throw CommandError(message); }

[[noreturn]] inline void fatal_error(const std::string& message) { throw FatalError(message); }

// Called when a FatalError escapes a job running on a search thread, where it
// can't propagate to the UCI thread. Installed by the embedding bridge.
inline void (*asyncFatalHandler)(const char* message) = nullptr;

}  // namespace Stockfish

#endif  // #ifndef FATAL_ERROR_H_INCLUDED
