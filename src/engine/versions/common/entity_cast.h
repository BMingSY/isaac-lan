#pragma once
#include <cstdint>
namespace isaac::engine::native_entity_cast {
struct Bindings {
    std::uint32_t cast, entityType, npcType;
};
inline std::uintptr_t npc(std::uintptr_t image, std::uintptr_t entity, const Bindings& bindings) {
    if (!entity)
        return 0;
    using Cast = void*(__cdecl*)(void*, long, const void*, const void*, int);
    return reinterpret_cast<std::uintptr_t>(reinterpret_cast<Cast>(image + bindings.cast)(
        reinterpret_cast<void*>(entity), 0,
        reinterpret_cast<const void*>(image + bindings.entityType),
        reinterpret_cast<const void*>(image + bindings.npcType), 0));
}
} // namespace isaac::engine::native_entity_cast
