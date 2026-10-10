#pragma once
#include "core/config.h"
#include <chrono>
#include <string_view>

namespace isaac::diagnostics {
void configure(const configuration::Settings& settings);
bool enabled();
void sample(std::string_view operation, double milliseconds);
void counter(std::string_view name, std::uint64_t value);
void render();
void beginRun();
void endRun();
class Scope {
    const char* operation;
    std::chrono::steady_clock::time_point start;

  public:
    explicit Scope(const char* name) : operation(enabled() ? name : nullptr) {
        if (operation)
            start = std::chrono::steady_clock::now();
    }
    ~Scope() {
        if (operation)
            sample(operation, std::chrono::duration<double, std::milli>(
                                  std::chrono::steady_clock::now() - start)
                                  .count());
    }
};
} // namespace isaac::diagnostics
