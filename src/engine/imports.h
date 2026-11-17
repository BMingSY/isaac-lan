#pragma once
#include <windows.h>
#include <cstdint>
#include <cstring>

namespace isaac::engine::imports {
enum class Result { replaced, missing, failed };
// The loaded x86 image is validated before bootstrap. An absent optional CRT
// import differs from a present slot that cannot be made writable.
inline Result replace(std::uintptr_t image, const char* name, void* replacement,
                      void** original = nullptr) {
    const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    const auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(image + dos->e_lfanew);
    const auto directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!directory.VirtualAddress)
        return Result::missing;
    auto imports =
        reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image + directory.VirtualAddress);
    for (; imports->Name; ++imports) {
        if (!imports->OriginalFirstThunk)
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
            DWORD before;
            if (!VirtualProtect(&addresses->u1.Function, sizeof(void*), PAGE_READWRITE, &before))
                return Result::failed;
            if (original)
                *original = reinterpret_cast<void*>(addresses->u1.Function);
            addresses->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
            DWORD ignored;
            VirtualProtect(&addresses->u1.Function, sizeof(void*), before, &ignored);
            return Result::replaced;
        }
    }
    return Result::missing;
}
} // namespace isaac::engine::imports
