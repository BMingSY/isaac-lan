#pragma once
#include <windows.h>
#include <filesystem>
#include <string>
#include <string_view>

namespace isaac::loader {
using Bootstrap = DWORD(WINAPI*)(void*);
struct Extension {
    HMODULE module = nullptr;
    Bootstrap bootstrap = nullptr;
};
std::string fileHash(const std::filesystem::path& path);
Extension load(const std::filesystem::path& game, std::string_view baselineVersion,
               std::string_view gameBuild);
} // namespace isaac::loader
