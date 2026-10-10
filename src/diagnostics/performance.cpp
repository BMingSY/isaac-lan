#include "diagnostics/performance.h"
#include "diagnostics/runtime_log.h"
#include "core/performance.h"
#include <windows.h>
#include <psapi.h>
#include <fstream>
#include <map>

namespace isaac::diagnostics {
namespace {
using Clock = std::chrono::steady_clock;
bool active = false;
unsigned interval = 1000;
Clock::time_point previous{}, lastRender{};
Clock::time_point runStart{};
std::uint64_t previousCpu = 0;
std::map<std::string, Window> costs;
std::map<std::string, std::uint64_t> counters;
std::ofstream file;
bool nameAllowed(std::string_view name) {
    if (name.empty() || name.size() > 64)
        return false;
    for (char c : name)
        if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '_' && c != '.')
            return false;
    return true;
}
std::uint64_t cpuTicks() {
    FILETIME created{}, exited{}, kernel{}, user{};
    if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user))
        return 0;
    const auto ticks = [](FILETIME t) {
        return (static_cast<std::uint64_t>(t.dwHighDateTime) << 32) | t.dwLowDateTime;
    };
    return ticks(kernel) + ticks(user);
}
void flush() {
    if (!active || !file.is_open() || !file)
        return;
    const auto now = Clock::now();
    const auto elapsed = std::chrono::duration<double, std::milli>(now - previous).count();
    const auto cpu = cpuTicks();
    PROCESS_MEMORY_COUNTERS_EX memory{};
    memory.cb = sizeof(memory);
    const bool memoryRead = GetProcessMemoryInfo(
        GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory));
    DWORD handles = 0;
    const bool handlesRead = GetProcessHandleCount(GetCurrentProcess(), &handles);
    file << "{\"run_ms\":" << std::chrono::duration<double, std::milli>(now - runStart).count()
         << ",\"elapsed_ms\":" << elapsed << ",\"cpu_core_percent\":";
    if (cpu && previousCpu && elapsed > 0)
        file << static_cast<double>(cpu - previousCpu) / (elapsed * 100);
    else
        file << "null";
    file << ",\"private_bytes\":";
    if (memoryRead)
        file << memory.PrivateUsage;
    else
        file << "null";
    file << ",\"working_set_bytes\":";
    if (memoryRead)
        file << memory.WorkingSetSize;
    else
        file << "null";
    file << ",\"handles\":";
    if (handlesRead)
        file << handles;
    else
        file << "null";
    file << ",\"costs\":{";
    bool first = true;
    for (const auto& [name, window] : costs) {
        if (!window.count)
            continue;
        file << (first ? "" : ",") << '"' << name << "\":{\"count\":" << window.count
             << ",\"percentile_samples\":" << std::min<std::uint64_t>(window.count, 512)
             << ",\"mean_ms\":" << window.total / window.count << ",\"max_ms\":" << window.maximum
             << ",\"p50_ms\":" << window.percentile(50) << ",\"p95_ms\":" << window.percentile(95)
             << ",\"p99_ms\":" << window.percentile(99) << '}';
        first = false;
    }
    file << "},\"counters\":{";
    first = true;
    for (const auto& [name, value] : counters) {
        file << (first ? "" : ",") << '"' << name << "\":" << value;
        first = false;
    }
    file << "}}\n";
    file.flush();
    previous = now;
    previousCpu = cpu;
    costs.clear();
}
} // namespace
void configure(const configuration::Settings& settings) {
    active = settings.performance;
    interval = settings.sampleIntervalMs;
}
bool enabled() {
    return active;
}
void sample(std::string_view operation, double milliseconds) {
    if (!active || !nameAllowed(operation))
        return;
    const std::string name(operation);
    if (costs.contains(name) || costs.size() < 64)
        costs[name].add(milliseconds);
}
void counter(std::string_view name, std::uint64_t value) {
    if (!active || !nameAllowed(name))
        return;
    const std::string key(name);
    if (counters.contains(key) || counters.size() < 64)
        counters[key] = value;
}
void render() {
    if (!active || !file.is_open())
        return;
    const auto now = Clock::now();
    if (lastRender != Clock::time_point{})
        sample("render_interval",
               std::chrono::duration<double, std::milli>(now - lastRender).count());
    lastRender = now;
    if (now - previous >= std::chrono::milliseconds(interval))
        flush();
}
void beginRun() {
    if (!active)
        return;
    file.close();
    file.clear();
    file.open(logging::directory() / L"performance.jsonl", std::ios::binary | std::ios::app);
    costs.clear();
    counters.clear();
    previous = Clock::now();
    runStart = previous;
    previousCpu = cpuTicks();
    lastRender = {};
}
void endRun() {
    flush();
    file.close();
    costs.clear();
    counters.clear();
    lastRender = {};
}
} // namespace isaac::diagnostics
