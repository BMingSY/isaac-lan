#pragma once
#include "engine/versions/j460/profile.h"
#include <cstdint>
#include <filesystem>
#include <string>

namespace isaac::build {
inline constexpr auto& version = engine::j460::version;
// Empty means supported. Reads the PE without loading/executing game code.
std::string checkFile(const std::filesystem::path& path, bool checkCode = false);
// Called before installing any engine hooks. Relocated addresses are masked.
std::string checkMemory(std::uintptr_t image);
} // namespace isaac::build
