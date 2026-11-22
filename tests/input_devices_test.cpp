#include "test_support.h"
#include "engine/versions/common/input_devices.h"
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/entrypoints.h"
#else
#include "engine/versions/repentance_plus/entrypoints.h"
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <thread>

namespace {
namespace devices = isaac::engine::native_devices;
#ifdef ISAAC_LAN_TEST_REPENTANCE
namespace backend = isaac::engine::repentance;
constexpr unsigned managerOffset = 0x7e7c98, beginOffset = 4, endOffset = 8;
constexpr unsigned stride = 4, idOffset = 8, updateEntry = 0x56a150;
#else
namespace backend = isaac::engine::repentance_plus;
constexpr unsigned managerOffset = 0x87f068, beginOffset = 8, endOffset = 12;
constexpr unsigned stride = 8, idOffset = 12, updateEntry = 0;
#endif
constexpr unsigned imageSize = privateGameImageBytes;
using Address = std::uintptr_t;
using Poll = void(__cdecl*)();
using Update = void(__attribute__((thiscall)) *)(void*);
unsigned char* image;
std::array<std::array<unsigned char, 32>, 7> objects;
std::array<unsigned char, 7 * stride> entries;
unsigned scans, polls, updates;
bool reenter;
void (*operation)();
template <class T> T& field(void* p, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(p) + offset);
}
Address base() {
    return reinterpret_cast<Address>(image);
}
void* manager() {
    return image + managerOffset;
}
void poll() {
    reinterpret_cast<Poll>(image + backend::entry::inputPollDevices)();
}
void scan() {
    reinterpret_cast<Poll>(image + backend::entry::inputEnumerateDevices)();
}
void update() {
    reinterpret_cast<Update>(image + updateEntry)(manager());
}
void __cdecl nativeScan() {
    ++scans;
    if (reenter)
        poll();
    else if (operation)
        operation();
}
void __cdecl nativePoll() {
    ++polls;
    if (operation)
        operation();
}
void __attribute__((fastcall)) nativeUpdate(void* receiver, void*) {
    require(receiver == manager(), "Native device update lost its thiscall receiver");
    ++updates;
    if (operation)
        operation();
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(fn) - base() - rva - 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void roster(unsigned count) {
    field<Address>(manager(), beginOffset) = reinterpret_cast<Address>(entries.data());
    field<Address>(manager(), endOffset) =
        reinterpret_cast<Address>(entries.data()) + count * stride;
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Create isolated device fixture");
    patch(backend::entry::inputEnumerateDevices, nativeScan);
    patch(backend::entry::inputPollDevices, nativePoll);
    if (updateEntry)
        patch(updateEntry, nativeUpdate);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    const auto conflictEntry = updateEntry ? updateEntry : backend::entry::inputPollDevices;
    void* conflict = image + conflictEntry;
    require(MH_CreateHook(conflict, reinterpret_cast<void*>(nativePoll), nullptr) == MH_OK,
            "Create foreign device hook");
    require(!devices::install(base(), nullptr), "Late hook conflict must fail installation");
    require(MH_RemoveHook(conflict) == MH_OK, "Rollback removed another component's hook");
    require(devices::install(base(), nullptr), "Retry after partial hook installation failed");
    require(devices::install(base(), nullptr) && !devices::install(base() + 4, nullptr),
            "Installed device hooks must retain their image identity");
    scan();
    poll();
    if (updateEntry)
        update();
    require(scans == 1 && polls == 1 && updates == (updateEntry ? 1u : 0u),
            "Installed device hooks did not forward their native calls");
}
void layoutAndRestore() {
#ifdef ISAAC_LAN_TEST_REPENTANCE
    constexpr int keyboard = 0, firstPad = 4;
#else
    constexpr int keyboard = -2, firstPad = 0;
#endif
    const std::array<int, 7> original{keyboard, 13, firstPad, 11, 7, -1, 99};
    entries.fill(0xa5);
    for (unsigned i = 0; i < objects.size(); ++i) {
        objects[i].fill(0xa5);
        field<int>(objects[i].data(), idOffset) = original[i];
        field<Address>(entries.data(), i * stride) = reinterpret_cast<Address>(objects[i].data());
    }
    roster(4); // Keyboard plus only three gamepads: do not partly assign.
    devices::assignLanIds(base());
    require(devices::ids(base()) == std::vector<int>({keyboard, 13, firstPad, 11}),
            "Partial device discovery changed identities");
    roster(objects.size());
    devices::assignLanIds(base());
    require(devices::ids(base()) == std::vector<int>({keyboard, 4, 1, 3, 2, -1, 99}),
            "Controller assignment changed keyboard, extra devices or native ordering");
    devices::assignLanIds(base());
    devices::restoreIds(base());
    require(devices::ids(base()) == std::vector<int>(original.begin(), original.end()),
            "Repeated assignment overwrote the original restore set");
    for (unsigned i = 0; i < objects.size(); ++i) {
        for (unsigned j = 0; j < objects[i].size(); ++j)
            if (j < idOffset || j >= idOffset + sizeof(int))
                require(objects[i][j] == 0xa5, "Device identity write escaped its native field");
        for (unsigned j = sizeof(Address); j < stride; ++j)
            require(entries[i * stride + j] == 0xa5, "Native vector ownership word changed");
    }
    devices::assignLanIds(base());
    field<Address>(entries.data(), stride) = 0; // Disconnected object is no longer borrowed.
    objects[1].fill(0x5a);
    field<int>(objects[2].data(), idOffset) = 88; // Native identity changed independently.
    devices::restoreIds(base());
    require(devices::ids(base()) == std::vector<int>({keyboard, 88, 11, 7, -1, 99}),
            "Restore touched a missing device or overwrote an independently changed identity");
    require(
        std::all_of(objects[1].begin(), objects[1].end(), [](auto byte) { return byte == 0x5a; }),
        "Restore dereferenced a disconnected native object");
    devices::restoreIds(base());
    roster(0);
    require(devices::ids(base()).empty(), "Empty native vector retained devices");
    field<Address>(manager(), endOffset) = reinterpret_cast<Address>(entries.data()) + 1;
    require(devices::ids(base()).empty(), "Misaligned native vector was traversed");
    roster(0);
}
struct DisconnectFixture {
    HANDLE entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE competing = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    std::atomic<unsigned> traversals{0}, frees{0};
    std::atomic<bool> live{true}, overlap{false};
    ~DisconnectFixture() {
        CloseHandle(entered);
        CloseHandle(release);
        CloseHandle(competing);
    }
    void disconnect() {
        const auto ordinal = ++traversals;
        const bool retained = live;
        if (ordinal == 1) {
            SetEvent(entered);
            WaitForSingleObject(release, 5000);
        } else
            SetEvent(competing);
        if (retained) {
            if (!live.exchange(false))
                overlap = true;
            ++frees;
        }
    }
};
DisconnectFixture* disconnectFixture;
void disconnectDevice() {
    disconnectFixture->disconnect();
}
void disconnectTransactions() {
    operation = disconnectDevice;
    {
        DisconnectFixture f;
        disconnectFixture = &f;
        std::thread foreground(disconnectDevice);
        const bool started = WaitForSingleObject(f.entered, 5000) == WAIT_OBJECT_0;
        std::thread background(disconnectDevice);
        const bool raced = WaitForSingleObject(f.competing, 5000) == WAIT_OBJECT_0;
        background.join();
        SetEvent(f.release);
        foreground.join();
        require(started && raced && f.frees == 2 && f.overlap,
                "Fixture did not reproduce the unguarded double release");
    }
    // Hooks remain installed through leave/rejoin and the native disconnect drain.
    for (unsigned round = 0; round < 2; ++round) {
        devices::restoreIds(base());
        for (const bool scanFirst : {true, false}) {
            DisconnectFixture f;
            disconnectFixture = &f;
            const auto first = scanFirst ? scan : poll;
            const auto second = scanFirst ? poll : scan;
            std::thread foreground(first);
            const bool started = WaitForSingleObject(f.entered, 5000) == WAIT_OBJECT_0;
            std::thread background(second);
            const auto competing = WaitForSingleObject(f.competing, 50);
            SetEvent(f.release);
            foreground.join();
            background.join();
            require(started && competing == WAIT_TIMEOUT && f.traversals == 2 && f.frees == 1 &&
                        !f.overlap,
                    "Scan and poll retained/released the same device concurrently");
        }
    }
    if (updateEntry) {
        DisconnectFixture f;
        disconnectFixture = &f;
        std::thread foreground(update);
        const bool started = WaitForSingleObject(f.entered, 5000) == WAIT_OBJECT_0;
        std::thread background(scan);
        const auto competing = WaitForSingleObject(f.competing, 50);
        SetEvent(f.release);
        foreground.join();
        background.join();
        require(started && competing == WAIT_TIMEOUT && f.frees == 1 && !f.overlap,
                "Native manager update escaped the device ownership transaction");
    }
    DisconnectFixture nested;
    disconnectFixture = &nested;
    SetEvent(nested.release);
    reenter = true;
    scan();
    require(nested.traversals == 1 && nested.frees == 1,
            "Native connect callback could not reenter polling");
    reenter = false;
    operation = nullptr;
    disconnectFixture = nullptr;
}
} // namespace
int main() {
    setup();
    layoutAndRestore();
    disconnectTransactions();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release isolated device fixture");
}
