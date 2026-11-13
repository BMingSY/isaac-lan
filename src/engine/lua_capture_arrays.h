#pragma once
#include "engine/lua_api.h"
#include <span>
#include <stdexcept>

namespace isaac::lua {
inline constexpr std::size_t maxCaptureArrays = 256;

// The caller owns an initially empty memo and treats both it and returned
// numeric leaves as immutable. No native objects or C++ allocations are kept.
inline void pushCaptureArray(lua_State* state, const API& api, std::span<const float> values,
                             int memo) {
    constexpr int nilType = 0, tableType = 5;
    const auto key = reinterpret_cast<const char*>(values.data());
    const auto keySize = values.size_bytes();
    if (memo) {
        api.pushLString(state, key, keySize);
        const auto kind = api.rawGet(state, memo);
        if (kind == tableType)
            return;
        if (kind != nilType)
            throw std::runtime_error("Invalid numeric capture cache");
        api.setTop(state, -2);
    }
    api.createTable(state, values.size(), 0);
    for (std::size_t i = 0; i < values.size(); ++i) {
        api.pushNumber(state, values[i]);
        api.rawSetI(state, -2, i + 1);
    }
    if (memo) {
        const auto entries = api.rawLength(state, memo);
        if (entries < maxCaptureArrays) {
            const auto result = api.getTop(state);
            // Reserve the bounded slot first. A failed hash allocation may
            // waste a slot, but cannot retain an unaccounted array.
            api.pushValue(state, result);
            api.rawSetI(state, memo, entries + 1);
            api.pushLString(state, key, keySize);
            api.pushValue(state, result);
            api.rawSet(state, memo);
        }
    }
}
} // namespace isaac::lua
