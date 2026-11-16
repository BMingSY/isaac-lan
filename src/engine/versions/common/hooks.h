#pragma once
#include <MinHook.h>
#include <array>
#include <cstdint>

namespace isaac::engine::native_hooks {
// A component publishes all of its hooks together. Failure removes only hooks
// created by this attempt, including hooks already enabled before a later error.
template <unsigned capacity> class Group {
  public:
    Group() = default;
    Group(const Group&) = delete;
    Group& operator=(const Group&) = delete;
    ~Group() {
        if (!committed)
            while (count)
                MH_RemoveHook(targets[--count]);
    }
    template <class Replacement, class Original>
    bool add(std::uintptr_t target, Replacement replacement, Original& original) {
        auto* address = reinterpret_cast<void*>(target);
        if (committed || count == capacity ||
            MH_CreateHook(address, reinterpret_cast<void*>(replacement),
                          reinterpret_cast<void**>(&original)) != MH_OK)
            return false;
        targets[count++] = address;
        return true;
    }
    bool enable() {
        for (unsigned i = 0; i < count; ++i)
            if (MH_EnableHook(targets[i]) != MH_OK)
                return false;
        committed = true;
        return true;
    }

  private:
    std::array<void*, capacity> targets{};
    unsigned count = 0;
    bool committed = false;
};
} // namespace isaac::engine::native_hooks
