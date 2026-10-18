#pragma once
#include <array>
#include <atomic>
#include <optional>
#include <utility>

namespace isaac {
// Exactly one producer and one consumer. A failed push leaves its value intact.
template <class T, std::size_t Capacity> class SpscQueue {
    static_assert(Capacity > 0);
    std::array<std::optional<T>, Capacity + 1> entries;
    alignas(64) std::atomic<std::size_t> head{0};
    alignas(64) std::atomic<std::size_t> tail{0};

  public:
    bool push(T&& value) {
        const auto at = tail.load(std::memory_order_relaxed);
        const auto next = (at + 1) % entries.size();
        if (next == head.load(std::memory_order_acquire))
            return false;
        entries[at].emplace(std::move(value));
        tail.store(next, std::memory_order_release);
        return true;
    }
    std::optional<T> pop() {
        const auto at = head.load(std::memory_order_relaxed);
        if (at == tail.load(std::memory_order_acquire))
            return {};
        auto value = std::move(entries[at]);
        entries[at].reset();
        head.store((at + 1) % entries.size(), std::memory_order_release);
        return value;
    }
    bool empty() const {
        return head.load(std::memory_order_acquire) == tail.load(std::memory_order_acquire);
    }
    bool full() const {
        return (tail.load(std::memory_order_acquire) + 1) % entries.size() ==
               head.load(std::memory_order_acquire);
    }
};
} // namespace isaac
