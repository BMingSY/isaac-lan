#include "engine/visuals.h"
#include "engine/versions/common/entity_pose_bindings.h"
#include "engine/versions/common/sprite_state_bindings.h"
#include "engine/versions/common/sprite_state.h"
#include "compat/game_ids.h"
#include "net/protocol.h"

namespace isaac::visuals {
std::string actorDepartureAnimation(std::uintptr_t player) {
    namespace pose = engine::native_entity_pose;
    namespace sprite = engine::native_sprite;
    const auto read = [player]<class T>(unsigned offset) {
        return *reinterpret_cast<const T*>(player + offset);
    };
    if (!player ||
        read.operator()<unsigned>(pose::bindings.entity.type) != compat::ids::entity::player)
        throw std::runtime_error("Departure animation requires a live player");
    // The first pose flag is the native extra-animation active flag.
    if (!read.operator()<bool>(pose::bindings.player.poseFlags.front()))
        return {};
    const auto data = read.operator()<std::uintptr_t>(pose::bindings.entity.sprite +
                                                      sprite::bindings.sprite.animation +
                                                      sprite::bindings.animation.data);
    if (!data)
        return {};
    const auto name = sprite::path(data + sprite::bindings.data.name);
    if (name.size() > lan::Stage::maxDepartureAnimationLength)
        throw std::runtime_error("Departure animation name exceeds its presentation limit");
    return std::string(name);
}
} // namespace isaac::visuals
