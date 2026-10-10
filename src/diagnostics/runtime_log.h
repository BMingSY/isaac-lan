#pragma once
#include <filesystem>
#include <string>
#include "core/log_record.h"

namespace isaac::logging {
bool initialize(const std::filesystem::path& gameLogDirectory);
void configure(Level minimum);
bool enabled(Level severity);
bool beginRun(const std::string& seed, const std::string& role, bool continued);
void endRun();
void shutdown();
std::filesystem::path directory();
void nativeFileOpened(const wchar_t* name);
void write(const std::string& message);
} // namespace isaac::logging
