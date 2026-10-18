#pragma once
#include "core/spsc_queue.h"
#include "net/compression.h"
#include <winsock2.h>
#include <windows.h>
#include <functional>
#include <chrono>
#include <stdexcept>

namespace isaac::lan {
class WakeEvent {
    HANDLE value = CreateEventW(nullptr, FALSE, FALSE, nullptr);

  public:
    WakeEvent() {
        if (!value)
            throw std::runtime_error("Cannot create network wake event");
    }
    ~WakeEvent() {
        CloseHandle(value);
    }
    WakeEvent(const WakeEvent&) = delete;
    HANDLE handle() const {
        return value;
    }
    void signal() const {
        SetEvent(value);
    }
};
template <class T> struct ByteResult {
    std::atomic<bool> done{false}, cancelled{false};
    std::optional<T> value;
    std::exception_ptr error;
    double milliseconds = 0;
    bool ready() const {
        return done.load(std::memory_order_acquire);
    }
    T take() {
        if (!ready())
            throw std::runtime_error("Byte task is still running");
        if (error)
            std::rethrow_exception(error);
        return std::move(value.value());
    }
};
// Tasks own immutable byte inputs; they never capture Session, Peer, Lua or game
// objects. Dropping a ticket cancels queued work; running work only owns itself.
class ByteTasks {
    using Job = std::function<void(StateCompression&)>;
    SpscQueue<Job, 4> jobs;

  public:
    template <class F> auto submit(F work) {
        using T = decltype(work(std::declval<StateCompression&>()));
        auto result = std::make_shared<ByteResult<T>>();
        Job job = [weak = std::weak_ptr(result),
                   work = std::move(work)](StateCompression& codec) mutable {
            auto result = weak.lock();
            if (!result || result->cancelled.load(std::memory_order_relaxed))
                return;
            const auto began = std::chrono::steady_clock::now();
            try {
                result->value = work(codec);
            } catch (...) {
                result->error = std::current_exception();
            }
            result->milliseconds =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began)
                    .count();
            result->done.store(true, std::memory_order_release);
        };
        if (!jobs.push(std::move(job)))
            throw std::runtime_error("Byte task queue limit exceeded");
        return result;
    }
    bool runOne(StateCompression& codec) {
        auto job = jobs.pop();
        if (!job)
            return false;
        (*job)(codec);
        return true;
    }
    bool empty() const {
        return jobs.empty();
    }
};
// One bounded worker for native archive bytes, separate from socket service.
class BulkWorker {
    WakeEvent wake;
    std::atomic<bool> stopping{false};
    std::atomic<bool> failed{false};
    std::string failure;
    ByteTasks tasks;
    HANDLE thread = nullptr;
    static DWORD WINAPI run(void* self);

  public:
    BulkWorker();
    ~BulkWorker();
    BulkWorker(const BulkWorker&) = delete;
    void stop() {
        stopping.store(true, std::memory_order_release);
        wake.signal();
    }
    bool finished() const {
        return WaitForSingleObject(thread, 0) == WAIT_OBJECT_0;
    }
    void check() const {
        if (failed.load(std::memory_order_acquire))
            throw std::runtime_error(failure);
    }
    template <class F> auto submit(F work) {
        auto result = tasks.submit(std::move(work));
        wake.signal();
        return result;
    }
};
} // namespace isaac::lan
