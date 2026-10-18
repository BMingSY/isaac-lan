#pragma once
#include <span>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace isaac::core {
// Match repeated names in original occurrence order. Missing names map to -1;
// no borrowed string survives this call.
inline std::vector<int> mapOccurrences(std::span<const std::string_view> local,
                                       std::span<const std::string_view> remote) {
    std::unordered_map<std::string_view, int> heads;
    heads.reserve(local.size());
    std::vector<int> next(local.size(), -1), result(remote.size(), -1);
    for (std::size_t i = local.size(); i-- > 0;) {
        const auto entry = heads.try_emplace(local[i], -1).first;
        next[i] = entry->second;
        entry->second = static_cast<int>(i);
    }
    for (std::size_t i = 0; i < remote.size(); ++i) {
        const auto found = heads.find(remote[i]);
        if (found != heads.end() && found->second >= 0) {
            result[i] = found->second;
            found->second = next[result[i]];
        }
    }
    return result;
}
} // namespace isaac::core
