#pragma once
#include <windows.h>
#include <cstdint>
#include <cstring>

namespace isaac::engine::imports {
enum class Result { replaced, missing, failed };
// The caller has already validated the loaded x86 game image.
inline IMAGE_THUNK_DATA* find(std::uintptr_t image, const char* name,
                              const char* library = nullptr) {
    const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    const auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(image + dos->e_lfanew);
    const auto directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!directory.VirtualAddress)
        return nullptr;
    auto imports =
        reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image + directory.VirtualAddress);
    for (; imports->Name; ++imports) {
        if (!imports->OriginalFirstThunk ||
            (library && _stricmp(reinterpret_cast<const char*>(image + imports->Name), library)))
            continue;
        auto names = reinterpret_cast<const IMAGE_THUNK_DATA*>(image + imports->OriginalFirstThunk);
        auto addresses = reinterpret_cast<IMAGE_THUNK_DATA*>(image + imports->FirstThunk);
        for (; names->u1.AddressOfData; ++names, ++addresses) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))
                continue;
            const auto entry =
                reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(image + names->u1.AddressOfData);
            if (std::strcmp(reinterpret_cast<const char*>(entry->Name), name) != 0)
                continue;
            return addresses;
        }
    }
    return nullptr;
}
inline Result replace(std::uintptr_t image, const char* name, void* replacement,
                      void** original = nullptr) {
    const auto slot = find(image, name);
    if (!slot)
        return Result::missing;
    DWORD before;
    if (!VirtualProtect(&slot->u1.Function, sizeof(void*), PAGE_READWRITE, &before))
        return Result::failed;
    if (original)
        *original = reinterpret_cast<void*>(slot->u1.Function);
    slot->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
    DWORD ignored;
    VirtualProtect(&slot->u1.Function, sizeof(void*), before, &ignored);
    return Result::replaced;
}
} // namespace isaac::engine::imports
