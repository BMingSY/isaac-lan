#pragma once
#include <cstdint>
#include <functional>

namespace isaac::engine::native_room_queries {
// The scheduler lends its roster only around a specific native query. The
// callback and manager are borrowed for the duration of the synchronous call.
using Scope = void (*)(int kind, std::uintptr_t caller, const std::function<void()>& query);
bool install(std::uintptr_t image, Scope scope);
bool hasType(void* manager, int kind);
} // namespace isaac::engine::native_room_queries
