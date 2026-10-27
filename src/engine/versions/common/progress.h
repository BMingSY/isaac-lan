#pragma once
#include "net/protocol.h"
#include <cstring>

namespace isaac::engine::native_progress {
struct Layout {
    unsigned achievements, achievementCount, counters, counterCount;
    consteval Layout(unsigned achievements, unsigned achievementCount, unsigned counters,
                     unsigned counterCount)
        : achievements(achievements), achievementCount(achievementCount), counters(counters),
          counterCount(counterCount) {
        if (achievementCount > lan::Progress{}.achievements.size() ||
            counterCount > lan::Progress{}.counters.size())
            throw "Native progression exceeds the shared wire format";
    }
};
inline lan::Progress read(std::uintptr_t progress, const Layout& layout) {
    lan::Progress value;
    std::memcpy(value.achievements.data(), reinterpret_cast<void*>(progress + layout.achievements),
                layout.achievementCount);
    std::memcpy(value.counters.data(), reinterpret_cast<void*>(progress + layout.counters),
                layout.counterCount * sizeof(value.counters[0]));
    return value;
}
inline void write(std::uintptr_t progress, const Layout& layout, const lan::Progress& value) {
    std::memcpy(reinterpret_cast<void*>(progress + layout.achievements), value.achievements.data(),
                layout.achievementCount);
    std::memcpy(reinterpret_cast<void*>(progress + layout.counters), value.counters.data(),
                layout.counterCount * sizeof(value.counters[0]));
}
} // namespace isaac::engine::native_progress
