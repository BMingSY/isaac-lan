#pragma once
#include <optional>
#include <type_traits>

namespace isaac::engine::j460 {
// Borrows only the native vector descriptor. PlayerManager retains allocation
// ownership; callers reconcile any room-local roster after the borrow ends.
template <class Stack, class Roster> class TeamRoster {
    static_assert(std::is_trivially_copyable_v<Roster>);

  public:
    TeamRoster(Stack& stack, Roster& current, bool enabled = true)
        : current_(current), saved_(current) {
        if (enabled) {
            binding_.emplace(stack, current);
            if (auto source = binding_->source())
                current_ = *source;
        }
    }
    TeamRoster(const TeamRoster&) = delete;
    TeamRoster& operator=(const TeamRoster&) = delete;
    ~TeamRoster() {
        if (binding_)
            if (auto source = binding_->source()) {
                *source = current_;
                current_ = saved_;
            }
    }

  private:
    Roster& current_;
    Roster saved_;
    std::optional<typename Stack::TeamBinding> binding_;
};
} // namespace isaac::engine::j460
