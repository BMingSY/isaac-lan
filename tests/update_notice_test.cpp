#include "runtime/update_notice.h"
#include <atomic>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <thread>

namespace {
using isaac::updates::Notice;
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
template <class Predicate> void until(Predicate predicate) {
    const auto deadline = Notice::Clock::now() + std::chrono::seconds(3);
    while (!predicate()) {
        require(Notice::Clock::now() < deadline, "worker did not complete");
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}
} // namespace
int main() {
    try {
        const auto now = Notice::Clock::now();
        std::promise<void> release;
        auto gate = release.get_future().share();
        std::atomic<unsigned> checks = 0;
        Notice notice([&checks, gate] {
            ++checks;
            gate.wait();
            return "0.7.1";
        });
        notice.poll(now);
        until([&] { return checks == 1; });
        for (int i = 0; i < 100; ++i)
            notice.poll(now + std::chrono::seconds(10));
        require(checks == 1 && notice.version().empty(), "one background check, no premature UI");
        release.set_value();
        until([&] {
            notice.poll(now);
            return !notice.version().empty();
        });
        require(notice.version() == "0.7.1", "completed result reaches the main thread");
        notice.dismiss();
        notice.poll(now + std::chrono::hours(1));
        require(checks == 1 && notice.version().empty(), "continue suppresses the entire launch");

        std::atomic<unsigned> retries = 0;
        Notice late([&] {
            if (++retries == 1)
                throw std::runtime_error("download is being replaced");
            return std::string("0.7.2");
        });
        late.poll(now);
        until([&] { return retries == 1; });
        // Repeated main-thread frames consume the failure without a retry storm.
        for (int i = 0; i < 100; ++i) {
            late.poll(now);
            std::this_thread::yield();
        }
        require(retries == 1 && late.version().empty(), "file failure leaves the game usable");
        until([&] {
            late.poll(Notice::Clock::now() + std::chrono::hours(1));
            return !late.version().empty();
        });
        require(retries == 2 && late.version() == "0.7.2", "a later completed download is found");

        std::promise<void> finish;
        auto finishing = finish.get_future().share();
        auto completed = std::make_shared<std::atomic<bool>>(false);
        Notice discarded([finishing, completed] {
            finishing.wait();
            *completed = true;
            return "0.7.3";
        });
        discarded.poll(now);
        discarded.dismiss();
        finish.set_value();
        until([&] { return completed->load(); });
        discarded.poll(now + std::chrono::hours(1));
        require(discarded.version().empty(), "entering gameplay discards an in-flight result");
        std::cout << "PASS asynchronous update checks, retry, dismissal and late completion\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
