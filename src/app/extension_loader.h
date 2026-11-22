#pragma once
#include <windows.h>
#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>
#include "core/startup_error.h"

namespace isaac::loader {
using Bootstrap = DWORD(WINAPI*)(void*);
struct Extension {
    HMODULE module = nullptr;
    Bootstrap bootstrap = nullptr;
    startup::Failure failure{startup::Code::extensionLoad, {}, {}, {}};
};
Extension load(const std::filesystem::path& game, std::string_view baselineVersion,
               const void* image, std::size_t imageSize);
Extension loadInstalled(const std::filesystem::path& path);
std::wstring failureMessage(const Extension& extension, DWORD code);
} // namespace isaac::loader
