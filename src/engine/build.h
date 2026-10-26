#pragma once
#include "engine/profile.h"
#include <cstdint>
#include <filesystem>
#include <string>

namespace isaac::build {
inline const char* version() {
    return engine::profile().version;
}
// Empty means supported. Reads the PE without loading/executing game code.
std::string checkFile(const std::filesystem::path& path, bool checkCode = false);
// Called before installing any engine hooks. Relocated addresses are masked.
std::string checkMemory(std::uintptr_t image);
} // namespace isaac::build
