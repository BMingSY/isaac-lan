#include "engine/versions/j460/entity_capacity.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <windows.h>
#include <array>
#include <cstring>

namespace isaac::engine::j460::entity_capacity {
namespace {
// Complete instructions from the three constructor allocation blocks. The
// update block includes its native allocator call and the returned data store.
constexpr std::array<unsigned char, 16> mainAllocation = {
    0xb9, 0x00, 0x00, 0x01, 0x00, 0xc6, 0x47, 0x20, 0x00, 0xc7, 0x47, 0x28, 0x00, 0x40, 0x00, 0x00};
constexpr std::array<unsigned char, 16> persistentAllocation = {
    0xb9, 0x00, 0x04, 0x00, 0x00, 0xc6, 0x47, 0x30, 0x00, 0xc7, 0x47, 0x38, 0x00, 0x01, 0x00, 0x00};
constexpr std::array<unsigned char, 31> updateAllocation = {
    0xb9, 0x00, 0x20, 0x00, 0x00, 0xc6, 0x47, 0x40, 0x00, 0xc7, 0x47, 0x48, 0x00, 0x08, 0x00, 0x00,
    0xc7, 0x47, 0x4c, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x1e, 0x7b, 0x5f, 0x00, 0x89, 0x47, 0x44};
constexpr unsigned allocationBytesImmediate = 1, capacityImmediate = 12;
constexpr std::uint32_t mergedCapacity =
    layout::entityList::mainCapacity + layout::entityList::persistentCapacity;
constexpr std::uint32_t mergedBytes = mergedCapacity * layout::entityList::pointerBytes;
constexpr std::uint32_t immediate(const auto& bytes, unsigned offset) {
    return std::uint32_t(bytes[offset]) | (std::uint32_t(bytes[offset + 1]) << 8) |
           (std::uint32_t(bytes[offset + 2]) << 16) | (std::uint32_t(bytes[offset + 3]) << 24);
}
static_assert(immediate(mainAllocation, capacityImmediate) == layout::entityList::mainCapacity);
static_assert(immediate(persistentAllocation, capacityImmediate) ==
              layout::entityList::persistentCapacity);
static_assert(immediate(mainAllocation, allocationBytesImmediate) ==
              layout::entityList::mainCapacity * layout::entityList::pointerBytes);
static_assert(immediate(persistentAllocation, allocationBytesImmediate) ==
              layout::entityList::persistentCapacity * layout::entityList::pointerBytes);
static_assert(immediate(updateAllocation, capacityImmediate) ==
              layout::entityList::initialUpdateCapacity);
static_assert(immediate(updateAllocation, allocationBytesImmediate) ==
              layout::entityList::initialUpdateCapacity * layout::entityList::pointerBytes);
static_assert(mergedCapacity == 16640 && mergedBytes == 66560);
static_assert(sizeof(void*) == layout::entityList::pointerBytes);

template <std::size_t N> bool read(std::uintptr_t address, std::array<unsigned char, N>& bytes) {
    SIZE_T count = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
                             bytes.data(), bytes.size(), &count) &&
           count == bytes.size();
}
void writePair(unsigned char* target, const auto& bytes) {
    std::memcpy(target + allocationBytesImmediate, bytes.data() + allocationBytesImmediate,
                sizeof(std::uint32_t));
    std::memcpy(target + capacityImmediate, bytes.data() + capacityImmediate,
                sizeof(std::uint32_t));
}
} // namespace

bool install(std::uintptr_t image) {
    std::array<unsigned char, mainAllocation.size()> main{};
    std::array<unsigned char, persistentAllocation.size()> persistent{};
    std::array<unsigned char, updateAllocation.size()> original{};
    if (!image || !read(image + entry::entityListMainAllocation, main) ||
        !read(image + entry::entityListPersistentAllocation, persistent) ||
        !read(image + entry::entityListUpdateAllocation, original) || main != mainAllocation ||
        persistent != persistentAllocation)
        return false;
    auto replacement = updateAllocation;
    std::memcpy(replacement.data() + allocationBytesImmediate, &mergedBytes, sizeof(mergedBytes));
    std::memcpy(replacement.data() + capacityImmediate, &mergedCapacity, sizeof(mergedCapacity));
    if (original == replacement)
        return true;
    if (original != updateAllocation)
        return false;

    auto* target = reinterpret_cast<unsigned char*>(image + entry::entityListUpdateAllocation);
    DWORD protection = 0, ignored = 0;
    if (!VirtualProtect(target, original.size(), PAGE_EXECUTE_READWRITE, &protection))
        return false;
    // The entry gate excludes game execution throughout this paired update.
    // Native allocation still happens later and owns its own size prefix.
    writePair(target, replacement);
    if (FlushInstructionCache(GetCurrentProcess(), target, original.size()) &&
        VirtualProtect(target, original.size(), protection, &ignored))
        return true;

    // A failed restore leaves the original writable protection in effect.
    // Restore both immediates before reporting failure to the startup gate.
    writePair(target, original);
    FlushInstructionCache(GetCurrentProcess(), target, original.size());
    VirtualProtect(target, original.size(), protection, &ignored);
    return false;
}
} // namespace isaac::engine::j460::entity_capacity
