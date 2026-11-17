#include "test_support.h"
#include "engine/native_files.h"
#include <windows.h>
#include <cstring>
#include <string>

namespace {
using Address = std::uintptr_t;
using Open = void*(__cdecl*)(const char*, const char*);
using StreamOpen = void*(__cdecl*)(const char*, int, int);
constexpr unsigned imageSize = 0x4000, fopenSlot = 0x1004, streamSlot = 0x2000;
constexpr char streamName[] = "?_Fiopen@std@@YAPAU_iobuf@@PBDHH@Z";
constexpr char filename[] = "native-log.txt";
constexpr DWORD openError = 0x1234;
void* const nativeFile = reinterpret_cast<void*>(0x12345678);
unsigned opens = 0, observed = 0;
bool success = true, throwObserver = false;
unsigned char* image = nullptr;
template <class T> T& at(unsigned rva) {
    return *reinterpret_cast<T*>(image + rva);
}
void* __cdecl nativeOpen(const char* path, const char* mode) {
    require(path == filename && (!mode || std::strlen(mode) <= 3), "Native fopen ABI changed");
    ++opens;
    SetLastError(openError);
    return success ? nativeFile : nullptr;
}
void* __cdecl nativeStream(const char* path, int mode, int protection) {
    require(path == filename && mode >= 0 && protection == 0x40, "Native stream ABI changed");
    ++opens;
    SetLastError(openError);
    return success ? nativeFile : nullptr;
}
void observe(const char* path) {
    require(path == filename, "Native observer changed the filename");
    ++observed;
    SetLastError(0);
    if (throwObserver)
        throw std::runtime_error("Fixture observer failure");
}
void prepare(bool stream) {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    require(image, "Allocate native import fixture");
    at<IMAGE_DOS_HEADER>(0).e_lfanew = 0x80;
    auto& nt = at<IMAGE_NT_HEADERS>(0x80);
    nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress = 0x200;
    auto& imports = at<IMAGE_IMPORT_DESCRIPTOR>(0x200);
    imports.Name = 0x400;
    imports.OriginalFirstThunk = 0x500;
    imports.FirstThunk = 0x1000;
    std::strcpy(reinterpret_cast<char*>(image + 0x400), "fixture-crt.dll");
    at<IMAGE_THUNK_DATA>(0x500).u1.Ordinal = IMAGE_ORDINAL_FLAG | 15;
    at<IMAGE_THUNK_DATA>(0x500 + sizeof(IMAGE_THUNK_DATA)).u1.AddressOfData = 0x800;
    at<Address>(0x1000) = 0x13572468;
    std::strcpy(reinterpret_cast<char*>(at<IMAGE_IMPORT_BY_NAME>(0x800).Name), "fopen");
    at<Open>(fopenSlot) = nativeOpen;
    if (stream) {
        auto& cpp = at<IMAGE_IMPORT_DESCRIPTOR>(0x200 + sizeof(IMAGE_IMPORT_DESCRIPTOR));
        cpp.Name = 0x400;
        cpp.OriginalFirstThunk = 0x520;
        cpp.FirstThunk = streamSlot;
        at<IMAGE_THUNK_DATA>(0x520).u1.AddressOfData = 0x840;
        std::strcpy(reinterpret_cast<char*>(at<IMAGE_IMPORT_BY_NAME>(0x840).Name), streamName);
        at<StreamOpen>(streamSlot) = nativeStream;
    }
}
void install(bool stream) {
    namespace files = isaac::engine::native_files;
    const auto base = reinterpret_cast<Address>(image);
    require(!files::install(0, observe).empty() && !files::install(base, nullptr).empty(),
            "Missing observer configuration was accepted");
    auto& symbol = at<IMAGE_IMPORT_BY_NAME>(0x800);
    symbol.Name[0] = 'x';
    require(files::install(base, observe) == "fopen" && at<Open>(fopenSlot) == nativeOpen,
            "Missing required stdio import changed the table");
    symbol.Name[0] = 'f';
    if (stream) {
        require(VirtualFree(image + streamSlot, 0x1000, MEM_DECOMMIT), "Decommit stream slot");
        require(files::install(base, observe) == streamName && at<Open>(fopenSlot) == nativeOpen,
                "Failed stream hook was treated as absent, or did not restore stdio");
        require(VirtualAlloc(image + streamSlot, 0x1000, MEM_COMMIT, PAGE_READWRITE),
                "Restore stream slot");
        at<StreamOpen>(streamSlot) = nativeStream;
    }
    DWORD before;
    require(VirtualProtect(image + 0x1000, 0x1000, PAGE_READONLY, &before), "Protect IAT");
    require(files::install(base, observe).empty() && files::install(base, observe).empty() &&
                !files::install(base + 1, observe).empty() &&
                !files::install(base, nullptr).empty(),
            "Native observers could not install/reuse or accepted different ownership");
    MEMORY_BASIC_INFORMATION memory{};
    require(VirtualQuery(image + fopenSlot, &memory, sizeof(memory)) &&
                memory.Protect == PAGE_READONLY && at<Address>(0x1000) == 0x13572468,
            "Observer changed IAT protection or ordinal imports");
}
void stdio() {
    for (const char* mode : {"r", "rb", "w", "a", "r+", "wb+", static_cast<const char*>(nullptr)}) {
        const auto before = observed;
        const auto write = mode && std::strpbrk(mode, "wa+");
        for (bool opened : {false, true}) {
            success = opened;
            require(at<Open>(fopenSlot)(filename, mode) == (opened ? nativeFile : nullptr) &&
                        GetLastError() == openError,
                    "Observer replaced native FILE ownership or last error");
        }
        require(observed == before + (write ? 1 : 0), "Observer reported read/failed stdio opens");
    }
}
void streams() {
    for (int mode : {0, 1, 2, 8, 10, 0x20}) {
        const auto before = observed;
        for (bool opened : {false, true}) {
            success = opened;
            require(at<StreamOpen>(streamSlot)(filename, mode, 0x40) ==
                            (opened ? nativeFile : nullptr) &&
                        GetLastError() == openError,
                    "Stream observer replaced native FILE ownership or last error");
        }
        require(observed == before + ((mode & 10) ? 1 : 0),
                "Observer reported read/failed stream opens");
    }
}
} // namespace
int main(int argc, char**) {
    const bool stream = argc > 1;
    prepare(stream);
    install(stream);
    stdio();
    if (stream)
        streams();
    success = true;
    throwObserver = true;
    require(at<Open>(fopenSlot)(filename, "w") == nativeFile && GetLastError() == openError,
            "Observer exception crossed the native stdio boundary");
    if (stream)
        require(at<StreamOpen>(streamSlot)(filename, 2, 0x40) == nativeFile &&
                    GetLastError() == openError,
                "Observer exception crossed the native stream boundary");
    require(opens > observed && VirtualFree(image, 0, MEM_RELEASE), "Release native file fixture");
}
