#pragma once
#include "engine/versions/common/entity_size.h"
#include "engine/versions/j460/layout.h"
namespace isaac::engine::j460::entity_size {
using native_entity_size::configurationMultiplier;
using native_entity_size::Multiplier;
inline constexpr native_entity_size::Layout fields{layout::entity::configuration,
                                                   layout::entity::sizeMultiplier,
                                                   layout::entity::gridCollisionPoints,
                                                   layout::vector::begin,
                                                   layout::vector::end,
                                                   layout::vector::capacity};
template <class DefaultSetter, class ExplicitSetter>
void restore(std::uintptr_t entity, float radius, DefaultSetter defaults,
             ExplicitSetter explicitSize) {
    native_entity_size::restore(fields, entity, radius, defaults, explicitSize);
}
} // namespace isaac::engine::j460::entity_size
