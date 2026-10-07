#pragma once
#include <cstdint>
#include <filesystem>
#include <string>

namespace isaac::build {
inline constexpr char version[] = "1.9.7.17.J460";
// Empty means supported. Reads the PE without loading/executing game code.
std::string checkFile(const std::filesystem::path& path, bool checkCode = false);
// Called before installing any engine hooks. Relocated addresses are masked.
std::string checkMemory(std::uintptr_t image);
}
