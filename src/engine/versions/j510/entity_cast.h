#pragma once
#include <windows.h>
#include "engine/versions/common/entity_cast.h"
#include "engine/versions/j510/entrypoints.h"
namespace isaac::engine::j510::entity_cast {
using Address = std::uintptr_t;
inline Address npc(Address image, Address entity) {
    return native_entity_cast::npc(image, entity,
                                   {entry::entityDynamicCast, rtti::entity, rtti::npc});
}
} // namespace isaac::engine::j510::entity_cast
