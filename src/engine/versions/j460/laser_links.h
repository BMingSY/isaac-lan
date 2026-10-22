#pragma once
#include <cstdint>
#include "engine/versions/j460/layout.h"
#include "core/parent_chain.h"

namespace isaac::engine::j460::laser_links {
using SetParent = void(__attribute__((thiscall)) *)(void*, void*);
using Update = void(__attribute__((thiscall)) *)(void*);
inline void update(void* laser, SetParent nativeSetParent, Update nativeUpdate) {
    const auto next = [](void* node) {
        return *reinterpret_cast<void* const*>(static_cast<const char*>(node) +
                                               layout::laser::parent);
    };
    if (!core::parent_chain::accepts(laser, next(laser), next))
        nativeSetParent(laser, nullptr);
    nativeUpdate(laser);
}
bool install(std::uintptr_t image);
} // namespace isaac::engine::j460::laser_links
