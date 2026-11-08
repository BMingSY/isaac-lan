#pragma once
#include <filesystem>
#include <string>

namespace isaac::updates {
std::filesystem::path workshopSource(const std::filesystem::path& game);
std::string fileHash(const std::filesystem::path& path);
} // namespace isaac::updates
