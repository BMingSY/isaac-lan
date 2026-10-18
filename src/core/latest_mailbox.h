#pragma once
#include <atomic>
#include <memory>

namespace isaac {
// Ownership transfer, not shared mutable state. At most one waiting value;
// replacement releases obsolete work on the producer without blocking either end.
template <class T> class LatestMailbox {
    std::atomic<T*> value{nullptr};

  public:
    ~LatestMailbox() {
        delete value.load();
    }
    void publish(std::unique_ptr<T> next) {
        delete value.exchange(next.release(), std::memory_order_acq_rel);
    }
    std::unique_ptr<T> take() {
        return std::unique_ptr<T>(value.exchange(nullptr, std::memory_order_acq_rel));
    }
};
} // namespace isaac
