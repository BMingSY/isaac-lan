#include "test_support.h"
#include "engine/save.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
namespace backend = isaac::engine::j835;
#else
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
namespace backend = isaac::engine::j460;
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <array>
#include <cstring>
#include <limits>

namespace {
constexpr unsigned imageSize = 0x900000, stateSize = 0x21000;
constexpr std::uintptr_t previousStream = 0x12345678;
constexpr unsigned previousChecksum = 0x13579bdf;
constexpr std::array<std::uint8_t, 24> payload{'s', 'a', 'v', 'e', 1, 2,  3,  4,  5,  6,  7,  8,
                                               9,   10,  11,  12,  0, 17, 18, 19, 20, 21, 22, 23};
enum class Mode { normal, reject, shortRead, badSeek, overflow, writeOnRead, throwError };
Mode mode;
unsigned clears, captures, writes, reads;
std::vector<std::uint8_t> manager(backend::layout::manager::saveState + stateSize);
std::vector<std::uint8_t> separate(stateSize);
std::uint8_t* image;
void* expectedState;
std::array<std::uint8_t, 4> game;

template <class T> T& at(void* memory, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<std::uint8_t*>(memory) + offset);
}
template <class Fn> Fn method(void* stream, unsigned slot) {
    return reinterpret_cast<Fn>(at<void**>(stream, 0)[slot]);
}
using Transfer = unsigned(__attribute__((thiscall)) *)(void*, void*, unsigned, unsigned);
using Tell = long(__attribute__((thiscall)) *)(void*);
using Seek = void(__attribute__((thiscall)) *)(void*, long, int);
using Eof = bool(__attribute__((thiscall)) *)(void*);

void* contextStream(void* state, void* context) {
    require(state == expectedState, "Wrong GameState thiscall receiver");
    const auto stream = at<void*>(context, 0);
    require(reinterpret_cast<std::uintptr_t>(stream) ==
                at<std::uintptr_t>(state, backend::layout::gameState::stream),
            "Context and bound native stream differ");
    require(std::strcmp(at<const char*>(context, 4), "isaac-lan/session") == 0,
            "Context path differs");
    require(at<unsigned>(context, 8) == 0 && at<unsigned>(context, 12) == 0 &&
                at<unsigned>(context, 16) == 0 && at<unsigned>(context, 20) == 0xfedcba76 &&
                at<unsigned>(context, 24) == 1,
            "Native checksum context layout differs");
    return stream;
}
bool __attribute__((thiscall)) writer(void* state, void* context) {
    ++writes;
    const auto stream = contextStream(state, context);
    if (mode == Mode::throwError)
        throw std::runtime_error("fixture failure");
    const auto write = method<Transfer>(stream, 7);
    require(write(stream, const_cast<std::uint8_t*>(payload.data()), 4, payload.size() / 4) == 6,
            "Stream write returns element count");
    require(method<Tell>(stream, 1)(stream) == static_cast<long>(payload.size()) &&
                method<Tell>(stream, 2)(stream) == static_cast<long>(payload.size()),
            "Size and position slots differ");
    if (mode == Mode::overflow)
        require(write(stream, nullptr, std::numeric_limits<unsigned>::max(), 2) == 0,
                "Overflowing write must fail before touching its buffer");
    return mode != Mode::reject;
}
bool readState(void* state, void* context) {
    ++reads;
    const auto stream = contextStream(state, context);
#ifdef ISAAC_LAN_TEST_J835
    // Model the mandatory J835 disk-save checksum comparison independently
    // of its production layout. The reader must still reject invalid bytes.
    std::uint32_t trailer;
    std::memcpy(&trailer, payload.data() + payload.size() - sizeof(trailer), sizeof(trailer));
    require(at<unsigned>(manager.data(), 0xf28) == (trailer ^ 0x96696996),
            "Memory restore compared against the unrelated last disk save");
#endif
    for (const auto offset : backend::layout::gameState::fileNames)
        require(at<char>(state, offset) == 0 && at<unsigned>(state, offset + 16) == 0 &&
                    at<unsigned>(state, offset + 20) == 15,
                "Native error handler must not see local or Steam save filenames");
    if (mode == Mode::throwError)
        throw std::runtime_error("fixture failure");
    std::array<std::uint8_t, payload.size() + 1> actual{};
    const auto read = method<Transfer>(stream, 5);
    const auto count = mode == Mode::shortRead ? actual.size() : payload.size();
    require(read(stream, actual.data(), 1, count) == payload.size(), "Unexpected read count");
    if (!std::equal(payload.begin(), payload.end(), actual.begin()))
        return false;
    require(method<Eof>(stream, 4)(stream), "EOF vtable slot differs");
    const auto seek = method<Seek>(stream, 3);
    seek(stream, -4, 2);
    require(method<Tell>(stream, 2)(stream) == 20, "Relative-to-end seek differs");
    if (mode == Mode::badSeek)
        seek(stream, -25, 2);
    if (mode == Mode::writeOnRead)
        require(method<Transfer>(stream, 7)(stream, actual.data(), 1, 1) == 0,
                "Read stream must reject writes");
    return mode != Mode::reject;
}
#ifdef ISAAC_LAN_TEST_J835
bool __attribute__((thiscall)) reader(void* state, void* context) {
    return readState(state, context);
}
#else
bool __attribute__((thiscall)) reader(void* state, void* context, bool checkProgress) {
    require(!checkProgress, "LAN reader must not reject host progress");
    return readState(state, context);
}
#endif
void __attribute__((thiscall)) clear(void* state) {
    ++clears;
    require(state == expectedState, "Clear received another state");
    require(at<std::uintptr_t>(state, backend::layout::gameState::stream) == previousStream,
            "Native Clear must precede borrowing the stream slot");
}
void __attribute__((thiscall)) capture(void* object, void* state) {
    ++captures;
    require(object == game.data() && state == expectedState, "Capture receivers differ");
}
void jump(unsigned rva, auto fn) {
    const auto target = reinterpret_cast<std::uintptr_t>(fn);
    image[rva] = 0xe9;
    at<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(target - reinterpret_cast<std::uintptr_t>(image + rva + 5));
}
void prepare(void* state, Mode next = Mode::normal) {
    mode = next;
    expectedState = state;
    clears = reads = writes = captures = 0;
    std::memset(state, 0xa5, stateSize);
    at<std::uintptr_t>(state, backend::layout::gameState::stream) = previousStream;
#ifdef ISAAC_LAN_TEST_J835
    at<unsigned>(manager.data(), 0xf28) = previousChecksum;
#endif
    // Exact-byte restoration includes strings with heap storage and embedded
    // nulls; the extension must neither allocate nor free those native buffers.
    for (const auto offset : backend::layout::gameState::fileNames)
        at<unsigned>(state, offset + 20) = 32;
}
void checkRestored(const std::vector<std::uint8_t>& before) {
    require(std::memcmp(expectedState, before.data(), stateSize) == 0,
            "Borrowed native stream/filename fields were not restored");
#ifdef ISAAC_LAN_TEST_J835
    require(at<unsigned>(manager.data(), 0xf28) == previousChecksum,
            "Memory restore retained a checkpoint's checksum in native disk-save state");
#endif
}
void contract() {
    const auto base = reinterpret_cast<std::uintptr_t>(image);
    auto* native = manager.data() + backend::layout::manager::saveState;
    for (auto* state : {native, separate.data()}) {
        prepare(state);
        const std::vector<std::uint8_t> before(state, state + stateSize);
        const auto encoded =
            state == native ? isaac::save::capture(base)
                            : isaac::save::encodeAt(base, reinterpret_cast<std::uintptr_t>(state));
        require(encoded == std::vector<std::uint8_t>(payload.begin(), payload.end()),
                "Save encoding differs from native output");
        require(writes == 1 && captures == (state == native ? 1u : 0u), "Capture order differs");
        checkRestored(before);
        for (unsigned repeat = 0; repeat < 3; ++repeat) {
            const bool ok =
                state == native
                    ? isaac::save::decode(base, encoded)
                    : isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state), encoded);
            require(ok && clears == repeat + 1 && reads == repeat + 1,
                    "Repeated decode did not clear and read exactly once");
            checkRestored(before);
        }
        for (auto next : {Mode::reject, Mode::shortRead, Mode::badSeek, Mode::writeOnRead}) {
            mode = next;
            require(!isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state), encoded),
                    "Native/stream read failure was ignored");
            checkRestored(before);
        }
        mode = Mode::normal;
        auto damaged = encoded;
        damaged[16] ^= 1;
        require(!isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state), damaged),
                "Memory restore ignored native rejection of a damaged body with the same trailer");
        checkRestored(before);
        for (auto next : {Mode::reject, Mode::overflow}) {
            mode = next;
            require(isaac::save::encodeAt(base, reinterpret_cast<std::uintptr_t>(state)).empty(),
                    "Native/stream write failure was ignored");
            checkRestored(before);
        }
        mode = Mode::throwError;
        rejects(
            [&] { isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state), encoded); },
            "Read fixture exception was lost");
        checkRestored(before);
        rejects([&] { isaac::save::encodeAt(base, reinterpret_cast<std::uintptr_t>(state)); },
                "Write fixture exception was lost");
        checkRestored(before);
        mode = Mode::normal;
        clears = reads = 0;
        const std::vector<std::uint8_t> oversized(8 * 1024 * 1024 + 1);
        require(
            !isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state),
                                   std::span(payload).first(19)) &&
                !isaac::save::decodeAt(base, reinterpret_cast<std::uintptr_t>(state), oversized),
            "Unbounded save was accepted");
        require(clears == 0 && reads == 0, "Rejected sizes touched native state");
        checkRestored(before);
    }
}
} // namespace
int main(int argc, char** argv) {
    image = static_cast<std::uint8_t*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!image)
        return 2;
    at<void*>(image, backend::globals::manager) = manager.data();
    at<void*>(image, backend::globals::game) = game.data();
    jump(backend::entry::engineSaveWrite, writer);
    jump(backend::entry::engineSaveRead, reader);
    jump(backend::entry::runtimeNetClear, clear);
    jump(backend::entry::runtimeNetCapture, capture);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    const auto result = runTests(argc, argv, {{"save-contract", contract}});
    VirtualFree(image, 0, MEM_RELEASE);
    return result;
}
