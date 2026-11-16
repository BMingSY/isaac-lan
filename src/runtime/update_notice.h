#pragma once
#include <chrono>
#include <functional>
#include <future>
#include <string>
#include <utility>

namespace isaac::updates {
// Main-thread lifecycle; file work receives only copied paths/version strings.
// Dismissal also discards late results, including after Lua/menu reconstruction.
class Notice {
  public:
    using Clock = std::chrono::steady_clock;
    using Check = std::function<std::string()>;
    explicit Notice(Check check = {}) : check(std::move(check)) {}
    void poll(Clock::time_point now = Clock::now());
    void dismiss();
    const std::string& version() const {
        return available;
    }

  private:
    Check check;
    std::future<std::string> result;
    Clock::time_point nextCheck{};
    std::string available;
    bool dismissed = false;
};
Notice& startupNotice();
} // namespace isaac::updates
