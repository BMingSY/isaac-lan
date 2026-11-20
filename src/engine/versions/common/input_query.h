#pragma once
#include <cstdint>

namespace isaac::engine::native_input {
// Private x86 action-query ABI used by the LAN input router. The callback is a
// version-owned query-kind token, never a function supplied by Lua or the network.
// Action and output pointers are borrowed only for this synchronous call.
using Query = bool(__attribute__((thiscall)) *)(void*, int, void*, const int*, void*, int*);
using Detour = bool(__attribute__((fastcall)) *)(void*, void*, int, void*, const int*, void*, int*);
} // namespace isaac::engine::native_input
