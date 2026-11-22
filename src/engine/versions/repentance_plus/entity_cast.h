#pragma once
#include <windows.h>
#include "engine/versions/common/entity_cast.h"
#include "engine/versions/repentance_plus/entrypoints.h"
namespace isaac::engine::repentance_plus::entity_cast {
using Address = std::uintptr_t;
inline Address npc(Address image, Address entity) {
    return native_entity_cast::npc(image, entity,
                                   {entry::entityDynamicCast, rtti::entity, rtti::npc});
}
} // namespace isaac::engine::repentance_plus::entity_cast
