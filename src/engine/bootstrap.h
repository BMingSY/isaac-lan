#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include <filesystem>
#include "core/startup_error.h"
struct lua_State;
namespace isaac::engine::bootstrap {
enum class HookTiming { immediate, deferred, missingImport };
HookTiming scheduleGameHooks(std::uintptr_t image, const std::filesystem::path& directory,
                             void (*ready)());
startup::Code installUpdates(std::uintptr_t image, void (*logger)(const std::string&));
startup::Code installRendering();
void halfUpdate();
void restorePositions();
bool scopeActive();
bool bind(lua_State* state, HMODULE module);
} // namespace isaac::engine::bootstrap
