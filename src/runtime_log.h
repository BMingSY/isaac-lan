#pragma once
#include <filesystem>
#include <string>

namespace isaac::logging {
bool initialize(const std::filesystem::path& gameLogDirectory);
void nativeFileOpened(const wchar_t* name);
void write(const std::string& message);
} // namespace isaac::logging
