#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::generated_items {
inline constexpr int maxDefinitions = 1024;
inline constexpr unsigned maxPayloadBytes = maxDefinitions * sizeof(std::uint32_t);
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
} // namespace isaac::generated_items
