#include "engine/versions/common/room_queries.h"
#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/common/hooks.h"
#include "runtime/session.h"
#include <type_traits>

namespace isaac::engine::native_room_queries {
namespace {
template <class Result> using Query = Result(__attribute__((thiscall)) *)(void*, int);
Query<void*> originalPointer = nullptr;
Query<bool> originalBoolean = nullptr;
std::uintptr_t image = 0;
Scope scope = nullptr;
bool installed = false;
template <class Result>
Result __attribute__((fastcall, noinline)) query(void* manager, void*, int kind) {
    Result result{};
    const auto caller = reinterpret_cast<std::uintptr_t>(__builtin_return_address(0)) - image;
    try {
        scope(kind, caller, [&] {
            if constexpr (std::is_pointer_v<Result>)
                result = originalPointer(manager, kind);
            else
                result = originalBoolean(manager, kind);
        });
    } catch (...) {
        runtime::abort("Native character query failed");
        return {};
    }
    return result;
}
} // namespace
bool install(std::uintptr_t base, Scope callback) {
    if (!base || !callback)
        return false;
    if (installed)
        return image == base && scope == callback;
    native_hooks::Group<1> hooks;
    image = base;
    scope = callback;
    const bool created = bindings.returnsPointer
                             ? hooks.add(base + bindings.query, query<void*>, originalPointer)
                             : hooks.add(base + bindings.query, query<bool>, originalBoolean);
    if (!created || !hooks.enable()) {
        image = 0;
        scope = nullptr;
        originalPointer = nullptr;
        originalBoolean = nullptr;
        return false;
    }
    installed = true;
    return true;
}
bool hasType(void* manager, int kind) {
    if (!installed || !manager)
        return false;
    return bindings.returnsPointer ? originalPointer(manager, kind) != nullptr
                                   : originalBoolean(manager, kind);
}
} // namespace isaac::engine::native_room_queries
