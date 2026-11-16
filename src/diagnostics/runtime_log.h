#pragma once
#include <filesystem>
#include <string>
#include <system_error>
#include "core/log_record.h"

namespace isaac::logging {
struct InitializationFailure {
    std::filesystem::path path;
    std::error_code error;
};
bool initialize(const std::filesystem::path& gameLogDirectory,
                InitializationFailure* failure = nullptr);
void configure(Level minimum);
bool enabled(Level severity);
bool beginRun(const std::string& seed, const std::string& role, bool continued);
void endRun();
void shutdown();
std::filesystem::path directory();
// isaac-lan/logs/<launch>; empty before initialize().
std::filesystem::path currentLaunch();
void nativeFileOpened(const wchar_t* name);
void write(const std::string& message);
} // namespace isaac::logging
