#pragma once
#include <cstdint>
#include <string>

namespace isaac::engine::native_files {
using Observer = void (*)(const char* path);
// Observe successful native write opens without borrowing FILE ownership.
// Return the failed import name, or an empty string on success.
std::string install(std::uintptr_t image, Observer observer);
} // namespace isaac::engine::native_files
