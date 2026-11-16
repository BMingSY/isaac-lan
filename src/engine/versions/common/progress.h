#pragma once
#include "net/protocol.h"
#include "engine/versions/common/completion_marks.h"
#include <cstring>

namespace isaac::engine::native_progress {
struct Layout {
    unsigned achievements, achievementCount, counters, counterCount;
    bool ordinalCompletion;
    consteval Layout(unsigned achievements, unsigned achievementCount, unsigned counters,
                     unsigned counterCount, bool ordinalCompletion = false)
        : achievements(achievements), achievementCount(achievementCount), counters(counters),
          counterCount(counterCount), ordinalCompletion(ordinalCompletion) {
        if (achievementCount > lan::Progress{}.achievements.size() ||
            counterCount > lan::Progress{}.counters.size())
            throw "Native progression exceeds the shared wire format";
    }
};
inline lan::Progress readNative(std::uintptr_t progress, const Layout& layout) {
    lan::Progress value;
    std::memcpy(value.achievements.data(), reinterpret_cast<void*>(progress + layout.achievements),
                layout.achievementCount);
    std::memcpy(value.counters.data(), reinterpret_cast<void*>(progress + layout.counters),
                layout.counterCount * sizeof(value.counters[0]));
    return value;
}
inline lan::Progress read(std::uintptr_t progress, const Layout& layout) {
    auto value = readNative(progress, layout);
    if (layout.ordinalCompletion)
        for (unsigned id = 0; id < layout.counterCount; ++id)
            if (native_completion::bitCounters[id] && value.counters[id] >= 2)
                value.counters[id] = native_completion::hardBits;
    return value;
}
inline void writeNative(std::uintptr_t progress, const Layout& layout, const lan::Progress& value) {
    std::memcpy(reinterpret_cast<void*>(progress + layout.achievements), value.achievements.data(),
                layout.achievementCount);
    std::memcpy(reinterpret_cast<void*>(progress + layout.counters), value.counters.data(),
                layout.counterCount * sizeof(value.counters[0]));
}
inline void write(std::uintptr_t progress, const Layout& layout, const lan::Progress& value) {
    std::memcpy(reinterpret_cast<void*>(progress + layout.achievements), value.achievements.data(),
                layout.achievementCount);
    auto counters = value.counters;
    if (layout.ordinalCompletion)
        for (unsigned id = 0; id < layout.counterCount; ++id)
            if (native_completion::bitCounters[id])
                counters[id] = counters[id] & 2 ? 2 : counters[id] & 1;
    std::memcpy(reinterpret_cast<void*>(progress + layout.counters), counters.data(),
                layout.counterCount * sizeof(counters[0]));
}
} // namespace isaac::engine::native_progress
