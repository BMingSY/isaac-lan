#include "runtime/update_notice.h"
#include <thread>

namespace isaac::updates {
namespace {
constexpr auto retryInterval = std::chrono::seconds(2);
}
void Notice::poll(Clock::time_point now) {
    if (dismissed || !available.empty() || !check)
        return;
    if (result.valid()) {
        if (result.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
            return;
        try {
            available = result.get();
        } catch (...) {
            // Missing, changing or unreadable updates leave this launch usable.
        }
        nextCheck = now + retryInterval;
        return;
    }
    if (now < nextCheck)
        return;
    try {
        // Unlike std::async, destroying this future never waits on file I/O.
        // The task owns its copied inputs and cannot access the Notice or Lua.
        std::packaged_task<std::string()> task(check);
        result = task.get_future();
        std::thread(std::move(task)).detach();
    } catch (...) {
        result = {};
        nextCheck = now + retryInterval;
    }
}
void Notice::dismiss() {
    dismissed = true;
    available.clear();
    result = {};
    check = {};
}
Notice& startupNotice() {
    // The extension stays loaded until process exit. Do not destruct worker
    // state under the Windows loader lock after other threads have stopped.
    static auto* notice = new Notice;
    return *notice;
}
} // namespace isaac::updates
