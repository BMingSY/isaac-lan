#pragma once
#include <array>
#include <optional>
#include <utility>

namespace isaac::compat::items {
// One native checkpoint per controller; concurrent users cannot replace a
// pending user's target. Checkpoint payload/ownership belongs to the backend.
template <class T, unsigned players> class RewindTargets {
    std::array<std::optional<T>, players> checkpoints;
    std::optional<unsigned> pending;

  public:
    void remember(unsigned slot, T checkpoint) {
        checkpoints.at(slot) = std::move(checkpoint);
    }
    const T& at(unsigned slot) const {
        return checkpoints.at(slot).value();
    }
    bool request(unsigned slot) {
        if (slot >= players || !checkpoints[slot] || (pending && *pending != slot))
            return false;
        pending = slot;
        return true;
    }
    std::optional<unsigned> take() {
        return std::exchange(pending, std::nullopt);
    }
    void reset() {
        checkpoints = {};
        pending.reset();
    }
};
} // namespace isaac::compat::items
