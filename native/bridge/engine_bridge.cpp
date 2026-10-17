// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors
//
// Engine side of the bridge. This file is compiled together with the
// Stockfish sources into one engine library per CPU variant. It runs
// Stockfish's own UCI loop on a dedicated thread, feeding std::cin from a
// line queue and turning std::cout / std::cerr output into line callbacks.

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <exception>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>

#include "attacks.h"
#include "fatal_error.h"
#include "misc.h"
#include "position.h"
#include "thread_native.h"
#include "tune.h"
#include "uci.h"

#include "bridge_common.h"

// The default network, provided by the dispatcher (see nnue/network.cpp).
const unsigned char* gEmbeddedNNUEData = nullptr;
unsigned int         gEmbeddedNNUESize = 0;

namespace {

std::mutex        callbackMutex;
sfd_line_callback callback = nullptr;

void emit(int32_t stream, const std::string& line) {
    std::lock_guard<std::mutex> lock(callbackMutex);
    if (callback)
        callback(stream, line.c_str());
}

// std::streambuf that hands every completed line to the callback.
class LineOutputBuffer: public std::streambuf {
   public:
    explicit LineOutputBuffer(int32_t stream) :
        stream_(stream) {}

   protected:
    int_type overflow(int_type ch) override {
        if (traits_type::eq_int_type(ch, traits_type::eof()))
            return traits_type::not_eof(ch);
        put(traits_type::to_char_type(ch));
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        for (std::streamsize i = 0; i < n; ++i)
            put(s[i]);
        return n;
    }

   private:
    void put(char c) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (c == '\n' || c == '\r')
        {
            // '\r' is used by bench/speedtest for progress lines.
            if (c == '\n' || !line_.empty())
                emit(stream_, line_);
            line_.clear();
        }
        else
            line_.push_back(c);
    }

    const int32_t stream_;
    std::mutex    mutex_;
    std::string   line_;
};

// std::streambuf that serves lines pushed with push() and blocks when empty.
class LineInputBuffer: public std::streambuf {
   public:
    void push(const std::string& line) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            queue_.push_back(line + '\n');
        }
        cv_.notify_one();
    }

    void close() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            closed_ = true;
        }
        cv_.notify_all();
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        queue_.clear();
        current_.clear();
        closed_ = false;
        setg(nullptr, nullptr, nullptr);
    }

   protected:
    int_type underflow() override {
        if (gptr() && gptr() < egptr())
            return traits_type::to_int_type(*gptr());

        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return !queue_.empty() || closed_; });
        if (queue_.empty())
            return traits_type::eof();

        current_ = std::move(queue_.front());
        queue_.pop_front();
        char* begin = current_.data();
        setg(begin, begin, begin + current_.size());
        return traits_type::to_int_type(*gptr());
    }

   private:
    std::mutex              mutex_;
    std::condition_variable cv_;
    std::deque<std::string> queue_;
    std::string             current_;
    bool                    closed_ = false;
};

// These live for the whole process: Stockfish's debug logger keeps pointers
// to whatever buffers std::cin/std::cout use when it is first started.
LineInputBuffer&  inputBuffer() {
    static auto* b = new LineInputBuffer();
    return *b;
}
LineOutputBuffer& stdoutBuffer() {
    static auto* b = new LineOutputBuffer(SFD_STREAM_STDOUT);
    return *b;
}
LineOutputBuffer& stderrBuffer() {
    static auto* b = new LineOutputBuffer(SFD_STREAM_STDERR);
    return *b;
}

std::mutex               lifecycleMutex;
std::condition_variable  finishedCv;
std::atomic<int>         state{SFD_STATE_STOPPED};
bool                     finished = false;
std::unique_ptr<Stockfish::NativeThread> uciThread;
std::string              binaryPath;

std::streambuf* originalCin  = nullptr;
std::streambuf* originalCout = nullptr;
std::streambuf* originalCerr = nullptr;

void on_async_fatal(const char* message) { emit(SFD_STREAM_FATAL, message); }

void uci_thread_main() {
    try
    {
        static std::once_flag initOnce;
        std::call_once(initOnce, [] {
            Stockfish::Attacks::init();
            Stockfish::Position::init();
        });

        std::string argv0   = binaryPath;
        char*       argv[2] = {argv0.data(), nullptr};

        auto uci = std::make_unique<Stockfish::UCIEngine>(Stockfish::CommandLine(1, argv));
        Stockfish::Tune::init(uci->engine_options());
        uci->loop();
    } catch (const std::exception& e)
    {
        emit(SFD_STREAM_FATAL, e.what());
    } catch (...)
    {
        emit(SFD_STREAM_FATAL, "unknown error");
    }

    emit(SFD_STREAM_EXITED, "");

    {
        std::lock_guard<std::mutex> lock(lifecycleMutex);
        finished = true;
        state    = SFD_STATE_FINISHED;
    }
    finishedCv.notify_all();
}

}  // namespace

SFD_EXPORT int32_t sfe_api_version(void) { return SFD_API_VERSION; }

SFD_EXPORT void sfe_set_net(const unsigned char* data, uint32_t size) {
    gEmbeddedNNUEData = data;
    gEmbeddedNNUESize = size;
}

// Starts the UCI loop on its own thread. [path] is used like argv[0]: relative
// EvalFile names are resolved against its directory.
SFD_EXPORT int32_t sfe_start(sfd_line_callback cb, const char* path) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (state != SFD_STATE_STOPPED)
        return SFD_ERR_ALREADY_RUNNING;
    if (gEmbeddedNNUEData == nullptr)
        return SFD_ERR_NO_NET;

    {
        std::lock_guard<std::mutex> cbLock(callbackMutex);
        callback = cb;
    }
    binaryPath = path ? path : "stockfish";

    inputBuffer().reset();
    originalCin  = std::cin.rdbuf(&inputBuffer());
    originalCout = std::cout.rdbuf(&stdoutBuffer());
    originalCerr = std::cerr.rdbuf(&stderrBuffer());
    std::cin.clear();
    std::cout.clear();
    std::cerr.clear();

    Stockfish::asyncFatalHandler = on_async_fatal;

    finished = false;
    state    = SFD_STATE_RUNNING;
    // The UCI thread runs bench/perft itself, so give it a large stack too
    // (secondary threads only get 512KB by default on macOS).
    uciThread = std::make_unique<Stockfish::NativeThread>(Stockfish::create_native_thread(
      Stockfish::NativeThreadOptions{}.setLargeStack(true), uci_thread_main));
    if (!uciThread->joinable())
    {
        uciThread.reset();
        std::cin.rdbuf(originalCin);
        std::cout.rdbuf(originalCout);
        std::cerr.rdbuf(originalCerr);
        state = SFD_STATE_STOPPED;
        return SFD_ERR_LOAD;
    }
    return SFD_OK;
}

SFD_EXPORT int32_t sfe_send(const char* line) {
    if (state != SFD_STATE_RUNNING)
        return SFD_ERR_NOT_RUNNING;
    inputBuffer().push(line);
    return SFD_OK;
}

SFD_EXPORT int32_t sfe_state(void) { return state; }

// Stops a search, ends the UCI loop and joins its thread. Returns
// SFD_ERR_TIMEOUT if the loop did not end within [timeoutMs]; the engine is
// then left running and this call may be retried.
SFD_EXPORT int32_t sfe_stop(int32_t timeoutMs) {
    std::unique_lock<std::mutex> lock(lifecycleMutex);
    if (state == SFD_STATE_STOPPED)
        return SFD_ERR_NOT_RUNNING;

    if (!finished)
    {
        inputBuffer().push("stop");
        // Closes the debug log (if any) so it releases our stream buffers.
        inputBuffer().push("setoption name Debug Log File value <empty>");
        inputBuffer().push("quit");
        inputBuffer().close();

        if (!finishedCv.wait_for(lock, std::chrono::milliseconds(timeoutMs),
                                 [] { return finished; }))
            return SFD_ERR_TIMEOUT;
    }

    lock.unlock();
    if (uciThread && uciThread->joinable())
        uciThread->join();
    lock.lock();
    uciThread.reset();

    std::cin.rdbuf(originalCin);
    std::cout.rdbuf(originalCout);
    std::cerr.rdbuf(originalCerr);

    {
        std::lock_guard<std::mutex> cbLock(callbackMutex);
        callback = nullptr;
    }
    state = SFD_STATE_STOPPED;
    return SFD_OK;
}
