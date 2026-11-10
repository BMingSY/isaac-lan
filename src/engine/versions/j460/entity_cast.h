#pragma once
#include "engine/versions/j460/entrypoints.h"
#include <windows.h>
#include <cstdint>

namespace isaac::engine::j460::entity_cast {
using Address = std::uintptr_t;
// Use the game's MSVC RTTI and CRT, as Entity:ToNPC does. Entity.Type is a
// content identifier; custom NPCs need not fit the vanilla numeric range.
inline Address npc(Address image, Address entity) {
    if (!entity)
        return 0;
    using Cast = void*(__cdecl*)(void*, long, const void*, const void*, int);
    return reinterpret_cast<Address>(reinterpret_cast<Cast>(image + entry::entityDynamicCast)(
        reinterpret_cast<void*>(entity), 0, reinterpret_cast<const void*>(image + rtti::entity),
        reinterpret_cast<const void*>(image + rtti::npc), 0));
}
} // namespace isaac::engine::j460::entity_cast
