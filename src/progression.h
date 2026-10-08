#pragma once
#include "net_protocol.h"
#include <algorithm>
#include <limits>

namespace isaac::lan {
inline Progress mergeProgress(const Progress& local, const Progress& common,
                              const Progress& current) {
    Progress result = local;
    for (unsigned i = 0; i < result.achievements.size(); ++i)
        if (current.achievements[i] && !common.achievements[i])
            result.achievements[i] = 1;
    for (unsigned i = 0; i < result.counters.size(); ++i) {
        const auto delta =
            static_cast<std::int64_t>(static_cast<std::int32_t>(current.counters[i])) -
            static_cast<std::int32_t>(common.counters[i]);
        result.counters[i] = static_cast<std::uint32_t>(
            std::clamp<std::int64_t>(static_cast<std::int32_t>(local.counters[i]) + delta, 0,
                                     std::numeric_limits<std::int32_t>::max()));
    }
    return result;
}
} // namespace isaac::lan
