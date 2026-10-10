#pragma once
#include <algorithm>
#include <vector>

namespace isaac::actors {
template <class Actor>
std::vector<Actor> replacementView(const std::vector<Actor>& all, const std::vector<Actor>& scoped,
                                   Actor old, Actor next) {
    std::vector<Actor> result;
    for (auto actor : all)
        if (std::find(scoped.begin(), scoped.end(), actor) != scoped.end() ||
            (actor == next && std::find(scoped.begin(), scoped.end(), old) != scoped.end()))
            result.push_back(actor);
    return result;
}
template <class Actor, class SameOwner>
std::vector<Actor> reconcile(std::vector<Actor> all, const std::vector<Actor>& previous,
                             const std::vector<Actor>& current, SameOwner sameOwner) {
    // A UI view can intentionally put its local actor first. If the native
    // scoped roster did not change, that view order must not become gameplay.
    if (previous == current)
        return all;
    for (auto old : previous) {
        if (std::find(current.begin(), current.end(), old) != current.end())
            continue;
        const auto position = std::find(all.begin(), all.end(), old);
        if (position == all.end())
            continue;
        const auto replacement = std::find_if(current.begin(), current.end(), [&](Actor candidate) {
            return std::find(all.begin(), all.end(), candidate) == all.end() &&
                   sameOwner(old, candidate);
        });
        if (replacement != current.end())
            *position = *replacement;
        else
            all.erase(position);
    }
    for (auto actor : current)
        if (std::find(all.begin(), all.end(), actor) == all.end())
            all.push_back(actor);
    // Birthright keeps both Lazarus bodies listed and native Flip swaps their
    // positions. Preserve that scoped permutation without moving outsiders.
    auto next = current.begin();
    for (auto& actor : all)
        if (std::find(current.begin(), current.end(), actor) != current.end())
            actor = *next++;
    return all;
}
} // namespace isaac::actors
