#pragma once
#include <exception>

namespace isaac::rooms {
// Logical ownership only. The version backend still activates/captures native
// state and owns all roster allocations. Bindings borrow their caller's saved
// roster and must be destroyed in stack order, after native restoration.
template <typename Room, typename Roster> class ScopeStack {
  public:
    class Binding {
      public:
        Binding(ScopeStack& stack, Room& room, Roster& savedRoster, Roster* currentRoster = nullptr)
            : stack_(stack), parent_(stack.top_), room_(&room), previousTeam_(stack.team_),
              depth_(parent_ ? parent_->depth_ + 1 : 1) {
            // A nested room can suspend an active complete-team borrow. Its
            // saved descriptor then owns the latest team, including growth.
            if (!stack_.team_ || stack_.team_ == currentRoster)
                stack_.team_ = &savedRoster;
            stack_.top_ = this;
        }
        Binding(const Binding&) = delete;
        Binding& operator=(const Binding&) = delete;
        // A native transition resolves its destination before entering it.
        // Keep the same borrowed roster and restore boundary during that handoff.
        void enter(Room& room) {
            if (stack_.top_ != this || restoring_)
                std::terminate();
            room_ = &room;
        }
        // Keep the depth barrier and borrowed team alive during native cleanup,
        // after scalar state and the roster have returned to the parent room.
        void restoreParent() {
            if (stack_.top_ != this)
                std::terminate();
            restoring_ = true;
        }
        ~Binding() {
            // Restoring an older native context while a child is alive is an
            // ownership violation in release builds too, never a valid reset.
            if (stack_.top_ != this)
                std::terminate();
            stack_.team_ = previousTeam_;
            stack_.top_ = parent_;
        }

      private:
        friend class ScopeStack;
        ScopeStack& stack_;
        Binding* parent_;
        Room* room_;
        Roster* previousTeam_;
        unsigned depth_;
        bool restoring_ = false;
        Room* current() const {
            return restoring_ ? (parent_ ? parent_->current() : nullptr) : room_;
        }
    };
    class TeamBinding {
      public:
        TeamBinding(ScopeStack& stack, Roster& current)
            : stack_(stack), parent_(stack.teamTop_), scope_(stack.top_), previous_(stack.team_),
              current_(&current) {
            stack_.teamTop_ = this;
            if (previous_)
                stack_.team_ = current_;
        }
        TeamBinding(const TeamBinding&) = delete;
        TeamBinding& operator=(const TeamBinding&) = delete;
        Roster* source() const {
            return previous_ == current_ ? nullptr : previous_;
        }
        ~TeamBinding() {
            if (stack_.teamTop_ != this || stack_.top_ != scope_)
                std::terminate();
            stack_.team_ = previous_;
            stack_.teamTop_ = parent_;
        }

      private:
        ScopeStack& stack_;
        TeamBinding* parent_;
        Binding* scope_;
        Roster* previous_;
        Roster* current_;
    };
    ScopeStack() = default;
    ScopeStack(const ScopeStack&) = delete;
    ScopeStack& operator=(const ScopeStack&) = delete;
    Room* current() const {
        return top_ ? top_->current() : nullptr;
    }
    Roster* teamRoster() const {
        return team_;
    }
    unsigned depth() const {
        return top_ ? top_->depth_ : 0;
    }

  private:
    Binding* top_ = nullptr;
    TeamBinding* teamTop_ = nullptr;
    Roster* team_ = nullptr;
};
} // namespace isaac::rooms
