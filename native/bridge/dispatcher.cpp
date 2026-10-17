// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors
//
// The dispatcher library is the native asset Dart talks to. It
//   * embeds the default NNUE network (once, shared by all engine variants),
//   * detects the CPU's instruction set extensions,
//   * loads the fastest engine library built for this CPU from its own
//     directory (stockfish_<variant>), and
//   * forwards the C API below to it.
//
// CPU feature detection follows Stockfish's universal/entry_x86.cpp and
// universal/entry_arm64.cpp (GPL-3.0-or-later, the Stockfish developers).

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
    #ifndef NOMINMAX
        #define NOMINMAX
    #endif
    #include <windows.h>
#else
    #include <dlfcn.h>
#endif

#if defined(__APPLE__)
    #include <sys/sysctl.h>
#endif

#if (defined(__aarch64__) || defined(_M_ARM64)) && defined(__linux__)
    #include <sys/auxv.h>
    #ifndef HWCAP_ASIMDDP
        #define HWCAP_ASIMDDP (1 << 20)
    #endif
#endif

#include "bridge_common.h"

#define INCBIN_PREFIX gSfd
#define INCBIN_SILENCE_BITCODE_WARNING
#include "incbin/incbin.h"

#ifndef SFD_NET_PATH
    #error "SFD_NET_PATH must name the NNUE network file to embed"
#endif

// Declares gSfdNetData (const unsigned char[]) and gSfdNetSize.
INCBIN(Net, SFD_NET_PATH);

namespace {

// ---------------------------------------------------------------------------
// CPU detection. Returns the variants this CPU can run, best first.

std::vector<std::string> supported_variants() {
    std::vector<std::string> v;

#if defined(__x86_64__) || defined(_M_X64)
    #if defined(__APPLE__)
    // Intel Macs supporting AVX512 only advertise it in xgetbv after the first
    // AVX512 instruction has run (see Stockfish's entry_x86.cpp).
    int    hasAvx512 = 0;
    size_t len       = sizeof(hasAvx512);
    if (sysctlbyname("hw.optional.avx512f", &hasAvx512, &len, nullptr, 0) == 0 && hasAvx512)
        asm volatile(".byte 0x62, 0xf1, 0x7d, 0x48, 0x6f, 0xc0");  // vmovdqa32 zmm0,zmm0
    #endif

    __builtin_cpu_init();
    const bool sse41   = __builtin_cpu_supports("sse4.1");
    const bool popcnt  = __builtin_cpu_supports("popcnt");
    const bool avx2    = __builtin_cpu_supports("avx2");
    const bool bmi2    = __builtin_cpu_supports("bmi2");
    const bool avx512  = __builtin_cpu_supports("avx512f") && __builtin_cpu_supports("avx512vl")
                     && __builtin_cpu_supports("avx512bw");
    const bool vnni512 = __builtin_cpu_supports("avx512vnni");
    const bool icl     = __builtin_cpu_supports("avx512ifma") && __builtin_cpu_supports("avx512vbmi")
                    && __builtin_cpu_supports("avx512vbmi2")
                    && __builtin_cpu_supports("avx512vpopcntdq")
                    && __builtin_cpu_supports("avx512bitalg")
                    && __builtin_cpu_supports("vpclmulqdq") && __builtin_cpu_supports("gfni")
                    && __builtin_cpu_supports("vaes");
    const bool avxvnni = __builtin_cpu_supports("avxvnni");
    // AMD Excavator and Zen/Zen+/Zen2 implement pdep/pext in microcode (slow).
    const bool slowBmi2 = __builtin_cpu_is("amd")
                       && (__builtin_cpu_is("bdver4") || __builtin_cpu_is("znver1")
                           || __builtin_cpu_is("znver2"));

    if (sse41 && popcnt && avx2 && bmi2 && !slowBmi2)
    {
        if (avx512)
        {
            if (vnni512)
            {
                if (icl)
                    v.push_back("x86_64_avx512icl");
                v.push_back("x86_64_vnni512");
            }
            v.push_back("x86_64_avx512");
        }
        if (avxvnni)
            v.push_back("x86_64_avxvnni");
        v.push_back("x86_64_bmi2");
    }
    if (sse41 && popcnt && avx2)
        v.push_back("x86_64_avx2");
    if (sse41 && popcnt)
        v.push_back("x86_64_sse41_popcnt");
    v.push_back("x86_64");

#elif defined(__aarch64__) || defined(_M_ARM64)
    bool dotprod = false;
    #if defined(__APPLE__)
    dotprod = true;  // every Apple silicon CPU supports it
    #elif defined(_WIN32)
    dotprod = IsProcessorFeaturePresent(PF_ARM_V82_DP_INSTRUCTIONS_AVAILABLE);
    #elif defined(__linux__)
    dotprod = (getauxval(AT_HWCAP) & HWCAP_ASIMDDP) != 0;
    #endif
    if (dotprod)
        v.push_back("armv8_dotprod");
    #if !defined(__APPLE__)
    // Only the dot product variant is built for macOS (every Apple CPU has it).
    v.push_back("armv8");
    #endif
#else
    #error "Unsupported CPU architecture"
#endif

    return v;
}

// ---------------------------------------------------------------------------
// Dynamic loading helpers.

#if defined(_WIN32)
using LibHandle = HMODULE;

std::wstring widen(const std::string& s) {
    int          n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1)
        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), n);
    return w;
}

std::string narrow(const std::wstring& w) {
    int         n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n - 1 : 0, '\0');
    if (n > 1)
        WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, s.data(), n, nullptr, nullptr);
    return s;
}

std::string own_directory() {
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                         | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&own_directory), &self);
    std::wstring path(32768, L'\0');
    DWORD        n = GetModuleFileNameW(self, path.data(), DWORD(path.size()));
    path.resize(n);
    auto slash = path.find_last_of(L"\\/");
    return narrow(slash == std::wstring::npos ? L"." : path.substr(0, slash));
}

const char* kSeparator = "\\";
const char* kPrefix    = "";
const char* kSuffix    = ".dll";

bool file_exists(const std::string& path) {
    DWORD attrs = GetFileAttributesW(widen(path).c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

LibHandle open_library(const std::string& path, std::string& error) {
    HMODULE h = LoadLibraryExW(widen(path).c_str(), nullptr,
                               LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (!h)
        error = "LoadLibrary failed for " + path + " (error " + std::to_string(GetLastError()) + ")";
    return h;
}

void* find_symbol(LibHandle h, const char* name) {
    return reinterpret_cast<void*>(GetProcAddress(h, name));
}
#else
using LibHandle = void*;

std::string own_directory() {
    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(&own_directory), &info) == 0 || !info.dli_fname)
        return ".";
    std::string path = info.dli_fname;
    auto        slash = path.find_last_of('/');
    return slash == std::string::npos ? "." : path.substr(0, slash);
}

const char* kSeparator = "/";
const char* kPrefix    = "lib";
    #if defined(__APPLE__)
const char* kSuffix = ".dylib";
    #else
const char* kSuffix = ".so";
    #endif

bool file_exists(const std::string& path) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (f)
        std::fclose(f);
    return f != nullptr;
}

LibHandle open_library(const std::string& path, std::string& error) {
    void* h = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!h)
    {
        const char* e = dlerror();
        error         = "dlopen failed for " + path + ": " + (e ? e : "unknown error");
    }
    return h;
}

void* find_symbol(LibHandle h, const char* name) { return dlsym(h, name); }
#endif

// ---------------------------------------------------------------------------
// The loaded engine library.

using ApiVersionFn = int32_t (*)();
using SetNetFn     = void (*)(const unsigned char*, uint32_t);
using StartFn      = int32_t (*)(sfd_line_callback, const char*);
using SendFn       = int32_t (*)(const char*);
using StateFn      = int32_t (*)();
using StopFn       = int32_t (*)(int32_t);

struct Engine {
    LibHandle    handle = nullptr;
    std::string  variant;
    std::string  path;
    ApiVersionFn apiVersion = nullptr;
    SetNetFn     setNet     = nullptr;
    StartFn      start      = nullptr;
    SendFn       send       = nullptr;
    StateFn      state      = nullptr;
    StopFn       stop       = nullptr;
};

std::mutex        loadMutex;
Engine            engine;
bool              loadAttempted = false;
std::string       loadError;
std::string       candidatesText;
std::atomic<sfd_line_callback> dartCallback{nullptr};

void forward_line(int32_t stream, const char* line) {
    sfd_line_callback cb = dartCallback.load();
    if (!cb)
        return;
    // Dart receives lines asynchronously and frees them with sf_free().
    size_t n    = std::strlen(line);
    char*  copy = static_cast<char*>(std::malloc(n + 1));
    if (!copy)
        return;
    std::memcpy(copy, line, n + 1);
    cb(stream, copy);
}

int32_t load_locked() {
    if (engine.handle)
        return SFD_OK;
    if (loadAttempted)
        return SFD_ERR_LOAD;
    loadAttempted = true;

    const std::string dir = own_directory();
    std::string       errors;

    // STOCKFISH_DART_VARIANT=<name> restricts loading to one variant (for
    // testing and diagnostics); it must still be supported by this CPU.
    std::vector<std::string> candidates = supported_variants();
    if (const char* forced = std::getenv("STOCKFISH_DART_VARIANT"); forced && *forced)
    {
        bool supported = false;
        for (const auto& v : candidates)
            supported = supported || v == forced;
        if (!supported)
        {
            loadError = std::string("STOCKFISH_DART_VARIANT=") + forced
                      + " is not supported by this CPU (supports: " + candidatesText + ").";
            return SFD_ERR_LOAD;
        }
        candidates = {forced};
    }

    for (const auto& variant : candidates)
    {
        std::string path = dir + kSeparator + kPrefix + "stockfish_" + variant + kSuffix;
        if (!file_exists(path))
            continue;

        std::string error;
        LibHandle   h = open_library(path, error);
        if (!h)
        {
            errors += error + "; ";
            continue;
        }

        Engine e;
        e.handle     = h;
        e.variant    = variant;
        e.path       = path;
        e.apiVersion = reinterpret_cast<ApiVersionFn>(find_symbol(h, "sfe_api_version"));
        e.setNet     = reinterpret_cast<SetNetFn>(find_symbol(h, "sfe_set_net"));
        e.start      = reinterpret_cast<StartFn>(find_symbol(h, "sfe_start"));
        e.send       = reinterpret_cast<SendFn>(find_symbol(h, "sfe_send"));
        e.state      = reinterpret_cast<StateFn>(find_symbol(h, "sfe_state"));
        e.stop       = reinterpret_cast<StopFn>(find_symbol(h, "sfe_stop"));

        if (!e.apiVersion || !e.setNet || !e.start || !e.send || !e.state || !e.stop)
        {
            errors += path + " is not a stockfish_dart engine library; ";
            continue;
        }
        if (e.apiVersion() != SFD_API_VERSION)
        {
            errors += path + " has bridge API version " + std::to_string(e.apiVersion())
                    + ", expected " + std::to_string(SFD_API_VERSION) + "; ";
            continue;
        }

        e.setNet(gSfdNetData, gSfdNetSize);
        engine = e;
        return SFD_OK;
    }

    loadError = "No usable Stockfish engine library found in " + dir
              + " (CPU supports: " + candidatesText + "). " + errors;
    return SFD_ERR_LOAD;
}

}  // namespace

SFD_EXPORT int32_t sf_api_version(void) { return SFD_API_VERSION; }

// Comma-separated variants this CPU supports, best first.
SFD_EXPORT const char* sf_supported_variants(void) {
    std::lock_guard<std::mutex> lock(loadMutex);
    if (candidatesText.empty())
    {
        for (const auto& v : supported_variants())
            candidatesText += (candidatesText.empty() ? "" : ",") + v;
    }
    return candidatesText.c_str();
}

// Loads the best engine library for this CPU. Safe to call repeatedly.
SFD_EXPORT int32_t sf_load(void) {
    sf_supported_variants();
    std::lock_guard<std::mutex> lock(loadMutex);
    return load_locked();
}

SFD_EXPORT const char* sf_load_error(void) { return loadError.c_str(); }

// Name of the loaded variant (e.g. "x86_64_avx2"), or "" before sf_load().
SFD_EXPORT const char* sf_variant(void) { return engine.variant.c_str(); }

SFD_EXPORT uint32_t sf_net_size(void) { return gSfdNetSize; }

// Starts the engine. [callback] receives (stream, line) for every output line;
// the receiver owns [line] and must release it with sf_free().
SFD_EXPORT int32_t sf_start(sfd_line_callback callback) {
    int32_t rc = sf_load();
    if (rc != SFD_OK)
        return rc;
    if (engine.state() != SFD_STATE_STOPPED)
        return SFD_ERR_ALREADY_RUNNING;
    dartCallback = callback;
    rc           = engine.start(forward_line, engine.path.c_str());
    if (rc != SFD_OK)
        dartCallback = nullptr;
    return rc;
}

SFD_EXPORT int32_t sf_send(const char* line) {
    if (!engine.handle)
        return SFD_ERR_NOT_RUNNING;
    return engine.send(line);
}

SFD_EXPORT int32_t sf_state(void) {
    if (!engine.handle)
        return SFD_STATE_STOPPED;
    return engine.state();
}

// Ends the UCI loop and joins its thread; see sfe_stop().
SFD_EXPORT int32_t sf_stop(int32_t timeoutMs) {
    if (!engine.handle)
        return SFD_ERR_NOT_RUNNING;
    int32_t rc = engine.stop(timeoutMs);
    if (rc == SFD_OK)
        dartCallback = nullptr;
    return rc;
}

SFD_EXPORT void sf_free(char* line) { std::free(line); }
