#pragma once
#include <optional>
#include <span>

namespace isaac::compat::characters {
struct GhostRoomActor {
    unsigned slot;
    int dimension, room;
    bool ghost, connected;
    float x, y;
};
inline std::optional<GhostRoomActor> ghostFollowTarget(const GhostRoomActor& actor,
                                                       std::span<const GhostRoomActor> actors) {
    if (!actor.ghost || !actor.connected)
        return std::nullopt;
    std::optional<GhostRoomActor> survivor;
    for (const auto& candidate : actors) {
        if (candidate.ghost || !candidate.connected)
            continue;
        if (candidate.dimension == actor.dimension && candidate.room == actor.room)
            return std::nullopt;
        if (!survivor)
            survivor = candidate;
    }
    // A follower arrives beside the survivor in the destination's coordinates.
    // Retaining the departure coordinates can place it in an L-room's void.
    return survivor;
}
} // namespace isaac::compat::characters
