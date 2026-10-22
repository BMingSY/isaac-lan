// Execute the audited J460 allocation/append instructions in a private x86
// image. Only the platform allocator/logger and executable-memory operations
// are substituted; the production installer writes the actual constructor.
#include <windows.h>
BOOL WINAPI testProtect(void*, SIZE_T, DWORD, DWORD*);
BOOL WINAPI testFlush(HANDLE, const void*, SIZE_T);
#define VirtualProtect testProtect
#define FlushInstructionCache testFlush
#include "engine/versions/j460/entity_capacity.cpp"
#undef VirtualProtect
#undef FlushInstructionCache
#include "test_support.h"
#include <algorithm>
#include <array>
#include <map>
#include <vector>

namespace {
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
constexpr unsigned imageSize = 0x612000, wrapperRva = 0x100;
constexpr unsigned allocateRva = 0x60f4e0, appendRva = 0x17630, logRva = 0x6112c0;
constexpr unsigned guardWords = 16, guard = 0xe2b34c5d;
unsigned protects = 0, flushes = 0, failProtect = 0, failFlush = 0, logCalls = 0;
bool failEveryFlush = false;
std::vector<unsigned> allocationBytes;
std::map<void*, unsigned> allocations;

struct Array {
    std::uint8_t borrowed;
    std::uint8_t padding[3];
    std::uint32_t* data;
    std::uint32_t capacity, count;
};
static_assert(sizeof(Array) == 16 && sizeof(void*) == 4);
template <class T> T& field(void* memory, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(memory) + offset);
}
void* __attribute__((fastcall)) allocate(unsigned bytes, void*) {
    allocationBytes.push_back(bytes);
    auto* memory = new std::uint32_t[1 + bytes / 4 + guardWords];
    memory[0] = bytes + 4;
    std::fill(memory + 1, memory + 1 + bytes / 4 + guardWords, guard);
    allocations.emplace(memory + 1, bytes);
    return memory + 1;
}
void __cdecl nativeLog(unsigned severity, const char*) {
    require(severity == 16, "Native Append used an unexpected logging severity");
    ++logCalls;
}
struct Fixture {
    unsigned char* image = nullptr;
    std::array<unsigned char, 0xa0> list{};
    std::array<unsigned char, 0x90> originalCode{};
    Fixture() {
        require(allocations.empty(), "Previous fixture retained an allocation");
        protects = flushes = failProtect = failFlush = logCalls = 0;
        failEveryFlush = false;
        allocationBytes.clear();
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image != nullptr, "Cannot allocate private constructor image");
        // Disk bytes from J460 EntityList::Construct, RVA1795d..179c4.
        const unsigned char main[] = {0xb9, 0,    0,    1,    0, 0xc6, 0x47, 0x20,
                                      0,    0xc7, 0x47, 0x28, 0, 0x40, 0,    0};
        const unsigned char persistent[] = {0xb9, 0,    4,    0,    0, 0xc6, 0x47, 0x30,
                                            0,    0xc7, 0x47, 0x38, 0, 1,    0,    0};
        const unsigned char updates[] = {
            0xb9, 0,    0x20, 0, 0, 0xc6, 0x47, 0x40, 0,    0xc7, 0x47, 0x48, 0,    8,    0,   0,
            0xc7, 0x47, 0x4c, 0, 0, 0,    0,    0xe8, 0x1e, 0x7b, 0x5f, 0,    0x89, 0x47, 0x44};
        std::memcpy(image + native::entry::entityListMainAllocation, main, sizeof(main));
        std::memcpy(image + native::entry::entityListPersistentAllocation, persistent,
                    sizeof(persistent));
        std::memcpy(image + native::entry::entityListUpdateAllocation, updates, sizeof(updates));
        image[native::entry::entityListUpdateAllocation + sizeof(updates)] = 0xc3;
        // Preserve EDI around the real constructor block: push edi; mov edi,ecx;
        // call native block; pop edi; ret. The block passes payload bytes in ECX.
        image[wrapperRva] = 0x57;
        image[wrapperRva + 1] = 0x8b;
        image[wrapperRva + 2] = 0xf9;
        image[wrapperRva + 3] = 0xe8;
        field<std::uint32_t>(image, wrapperRva + 4) =
            native::entry::entityListUpdateAllocation - (wrapperRva + 8);
        image[wrapperRva + 8] = 0x5f;
        image[wrapperRva + 9] = 0xc3;
        const auto jump = [&](unsigned rva, auto callback) {
            image[rva] = 0xe9;
            field<std::uint32_t>(image, rva + 1) = static_cast<std::uint32_t>(
                reinterpret_cast<Address>(callback) - reinterpret_cast<Address>(image + rva + 5));
        };
        jump(allocateRva, allocate);
        jump(logRva, nativeLog);
        // Entire native Array::Append (RVA17630), including its log-and-continue
        // failure path. Relative logger displacement is unchanged in this image.
        const unsigned char append[] = {
            0x55, 0x8b, 0xec, 0x56, 0x8b, 0xf1, 0x8b, 0x56, 0x0c, 0x8d, 0x42, 0x01, 0x3b,
            0x46, 0x08, 0x76, 0x12, 0x68, 0x40, 0xb7, 0xb1, 0x00, 0x6a, 0x10, 0xe8, 0x73,
            0x9c, 0x5f, 0x00, 0x8b, 0x56, 0x0c, 0x83, 0xc4, 0x08, 0x8b, 0x4e, 0x04, 0x8b,
            0x45, 0x08, 0x89, 0x04, 0x91, 0xff, 0x46, 0x0c, 0x5e, 0x5d, 0xc2, 0x04, 0x00};
        std::memcpy(image + appendRva, append, sizeof(append));
        std::memcpy(originalCode.data(), image + native::entry::entityListMainAllocation,
                    originalCode.size());
        std::fill(list.begin(), list.end(), 0x5a);
        require(FlushInstructionCache(GetCurrentProcess(), image, imageSize) != 0,
                "Cannot publish private native instructions");
        DWORD previous = 0;
        require(VirtualProtect(image, imageSize, PAGE_EXECUTE_READ, &previous) != 0,
                "Cannot protect private native instructions");
    }
    ~Fixture() {
        for (const auto& [data, bytes] : allocations) {
            require(static_cast<std::uint32_t*>(data)[-1] == bytes + 4,
                    "Native allocation prefix was altered");
            delete[] (static_cast<std::uint32_t*>(data) - 1);
        }
        allocations.clear();
        VirtualFree(image, 0, MEM_RELEASE);
    }
    Address base() const {
        return reinterpret_cast<Address>(image);
    }
    Array& array() {
        return field<Array>(list.data(), native::layout::entityList::renderArray);
    }
    void construct() {
        using Construct = void(__attribute__((thiscall))*)(void*);
        reinterpret_cast<Construct>(image + wrapperRva)(list.data());
    }
    void append(std::uint32_t value) {
        using Append = void(__attribute__((thiscall))*)(void*, std::uint32_t);
        reinterpret_cast<Append>(image + appendRva)(&array(), value);
    }
    bool original() const {
        return std::memcmp(originalCode.data(), image + native::entry::entityListMainAllocation,
                           originalCode.size()) == 0;
    }
    DWORD protection() const {
        MEMORY_BASIC_INFORMATION info{};
        require(VirtualQuery(image + native::entry::entityListUpdateAllocation, &info,
                             sizeof(info)) == sizeof(info),
                "Cannot inspect constructor page protection");
        return info.Protect;
    }
    void change(unsigned rva, unsigned char byte) {
        DWORD previous = 0, ignored = 0;
        require(VirtualProtect(image + rva, 1, PAGE_EXECUTE_READWRITE, &previous) != 0,
                "Cannot prepare incompatible constructor fixture");
        image[rva] = byte;
        require(VirtualProtect(image + rva, 1, previous, &ignored) != 0,
                "Cannot restore incompatible constructor fixture protection");
    }
};
void baseline() {
    Fixture f;
    f.construct();
    require(allocationBytes == std::vector<unsigned>{8192} && f.array().capacity == 2048 &&
                f.array().count == 0 && f.array().borrowed == 0,
            "Unmodified constructor fixture differs from native allocation contract");
    for (unsigned i = 0; i <= 2048; ++i)
        f.append(i + 1);
    // The allocation fixture reserves guard words outside native payload, so
    // this demonstrates the native overrun without writing outside test memory.
    require(logCalls == 1 && f.array().count == 2049 && f.array().data[2048] == 2049,
            "Native baseline no longer reproduces log followed by an out-of-payload write");
}
void capacityAndOrder() {
    Fixture f;
    require(native::entity_capacity::install(f.base()), "Constructor capacity install failed");
    require(protects == 2 && flushes == 1 && f.protection() == PAGE_EXECUTE_READ,
            "Successful install did not restore executable protection");
    auto expectedCode = f.originalCode;
    const auto relative =
        native::entry::entityListUpdateAllocation - native::entry::entityListMainAllocation;
    field<std::uint32_t>(expectedCode.data(), relative + 1) = 66560;
    field<std::uint32_t>(expectedCode.data(), relative + 12) = 16640;
    require(std::memcmp(expectedCode.data(), f.image + native::entry::entityListMainAllocation,
                        expectedCode.size()) == 0,
            "Install altered source capacities or unrelated constructor instructions");
    for (unsigned room = 0; room < 3; ++room) {
        f.construct();
        const auto pointer = f.array().data;
        require(f.array().capacity == 16640 && f.array().count == 0 && f.array().borrowed == 0 &&
                    pointer[-1] == 66564,
                "Native constructor did not pair capacity with payload and allocator prefix");
        for (unsigned i = 0; i < 16640; ++i)
            f.append(i + 100);
        for (unsigned i = 0; i < 16640; ++i)
            require(pointer[i] == i + 100, "Expanded array lost pointer identity or order");
        require(f.array().data == pointer && f.array().count == 16640 && logCalls == 0 &&
                    std::all_of(pointer + 16640, pointer + 16640 + guardWords,
                                [](auto value) { return value == guard; }),
                "Append relocated storage, truncated entries, or damaged its boundary");
        require(native::entity_capacity::install(f.base()) && protects == 2 && flushes == 1,
                "Repeated install changed already constructed arrays or rewrote code");
    }
    require(allocationBytes == std::vector<unsigned>({66560, 66560, 66560}),
            "Constructor bypassed native allocation or added its own prefix bytes");
    require(std::all_of(f.list.begin(), f.list.begin() + 0x40,
                        [](auto byte) { return byte == 0x5a; }) &&
                std::all_of(f.list.begin() + 0x50, f.list.end(),
                            [](auto byte) { return byte == 0x5a; }),
            "Constructing update storage modified other arrays or entity state");
}
void validation() {
    require(!native::entity_capacity::install(0), "Null image was accepted");
    for (const auto& [start, length] :
         {std::pair{native::entry::entityListMainAllocation, 16u},
          std::pair{native::entry::entityListPersistentAllocation, 16u},
          std::pair{native::entry::entityListUpdateAllocation, 31u}}) {
        Fixture f;
        for (unsigned i = 0; i < length; ++i) {
            const auto before = f.image[start + i];
            f.change(start + i, before ^ 1);
            require(!native::entity_capacity::install(f.base()) && protects == 0 && flushes == 0,
                    "Incompatible allocation instructions reached the mutation phase");
            f.change(start + i, before);
            require(f.original(), "Rejected install left a partial instruction change");
        }
    }
    Fixture f;
    f.change(native::entry::entityListUpdateAllocation + 2, 4);
    f.change(native::entry::entityListUpdateAllocation + 3, 1);
    require(!native::entity_capacity::install(f.base()) && protects == 0,
            "Already mismatched allocation bytes and capacity were accepted");
}
void failureRollback() {
    for (unsigned mode = 0; mode < 4; ++mode) {
        Fixture f;
        if (mode == 0)
            failProtect = 1;
        if (mode == 1)
            failFlush = 1;
        if (mode == 2)
            failProtect = 2;
        if (mode == 3)
            failEveryFlush = true;
        require(!native::entity_capacity::install(f.base()),
                "Failed protection or cache publication reported successful installation");
        require(f.original() && f.protection() == PAGE_EXECUTE_READ,
                "Failed install left mismatched constants or writable code");
        failProtect = failFlush = 0;
        failEveryFlush = false;
        f.construct();
        require(allocationBytes == std::vector<unsigned>{8192} && f.array().capacity == 2048,
                "Rollback did not restore the original executable allocation behavior");
    }
}
} // namespace

BOOL WINAPI testProtect(void* address, SIZE_T bytes, DWORD protection, DWORD* previous) {
    if (++protects == failProtect)
        return FALSE;
    return VirtualProtect(address, bytes, protection, previous);
}
BOOL WINAPI testFlush(HANDLE process, const void* address, SIZE_T bytes) {
    ++flushes;
    if (failEveryFlush || flushes == failFlush)
        return FALSE;
    return FlushInstructionCache(process, address, bytes);
}
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"native-baseline", baseline},
                     {"capacity-order-lifecycle", capacityAndOrder},
                     {"validation", validation},
                     {"failure-rollback", failureRollback}});
}
