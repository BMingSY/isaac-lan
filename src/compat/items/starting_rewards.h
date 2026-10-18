#pragma once
#include <array>
#include <vector>

namespace isaac::compat::items {
// Share the native first player's Blessing roll, once per joining peer.
// Starting inventories and the Blessing collectible itself remain personal.
class StartingRewards {
    static constexpr unsigned maxNativeRewards = 2;
    std::vector<int> items;
    std::array<bool, 4> granted{};
    bool recording = false;

  public:
    void begin() {
        items.clear();
        granted = {};
        granted[0] = true;
        recording = true;
    }
    void finish() {
        recording = false;
    }
    void record(int item) {
        if (recording && item > 0 && items.size() < maxNativeRewards)
            items.push_back(item);
    }
    std::vector<int> take(unsigned slot) {
        if (slot >= granted.size() || granted[slot])
            return {};
        granted[slot] = true;
        return items;
    }
};
} // namespace isaac::compat::items
