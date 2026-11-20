#pragma once
#include "engine/versions/common/entity_links.h"
#include "engine/versions/common/held_bombs.h"
namespace isaac::engine::native_references {
struct Bindings {
    unsigned sprite, assign, resize;
    native_entity_links::Layout entities;
    native_held_bombs::Layout bombs;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_references
