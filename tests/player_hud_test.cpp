#include "engine/versions/j460/player_hud.h"
#include <array>
#include <cstddef>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace {
template <class T> void write(std::uintptr_t address, unsigned offset, T value) {
    std::memcpy(reinterpret_cast<void*>(address + offset), &value, sizeof(value));
}
void require(bool condition, const char* message) {
    if (!condition)
        throw std::runtime_error(message);
}
} // namespace
int main() {
    using isaac::engine::j460::player_hud::anchor;
    alignas(std::uintptr_t) std::array<std::byte, 0x54d0> hudBytes{};
    alignas(std::uintptr_t) std::array<std::byte, 0x1620> playerBytes{};
    const auto hud = reinterpret_cast<std::uintptr_t>(hudBytes.data());
    const auto player = reinterpret_cast<std::uintptr_t>(playerBytes.data());
    int calls = 0, mode = 0;
    float x = 100, y = 20;
    auto layout = [&](auto receiver, auto index, auto actor) {
        require(receiver == hud && index < 4 && actor == player, "Wrong native layout receiver");
        return mode;
    };
    auto position = [&](auto receiver, float* point, auto index, auto selected) {
        require(receiver == hud && index < 4 && selected == mode,
                "Wrong native position arguments");
        ++calls;
        point[0] = x;
        point[1] = y;
    };
    auto get = [&](auto root, unsigned index) {
        return anchor(root, index, 480, 270, layout, position);
    };
    try {
        require(!get(0, 0), "Missing HUD accepted");
        require(!get(hud, 0), "Hidden HUD accepted");
        write(hud, 0x54cc, true);
        require(!get(hud, 0) && calls == 0, "Empty HUD reached native position code");
        for (unsigned index = 0; index < 4; ++index) {
            write(hud + index * 0x6dc, 0, player);
            write(player, 0x1618, 4 - static_cast<int>(index));
            mode = index;
            auto value = get(hud, index);
            require(value && value->slot == 3 - static_cast<int>(index) && value->layout == mode &&
                        value->x == 100 && value->y == 20,
                    "HUD position was confused with network identity");
            y = std::numeric_limits<float>::quiet_NaN();
            require(!get(hud, index), "Non-finite HUD coordinate accepted");
            y = 300;
            require(!get(hud, index), "Offscreen HUD accepted");
            y = 20;
            const auto before = calls;
            for (int controller : {0, -1, 5, std::numeric_limits<int>::min()}) {
                write(player, 0x1618, controller);
                require(!get(hud, index), "Invalid controller accepted");
            }
            require(calls == before, "Invalid player reached native position code");
        }
        require(!get(hud, 4), "Twin HUD produced a duplicate indicator");
        write(player, 0x1618, 1);
        mode = 4;
        require(!get(hud, 0), "Invalid native layout accepted");
        mode = 0;
        write(hud, 0x54cc, false);
        require(!get(hud, 0), "HUD hide retained a visible anchor");
        std::cout
            << "PASS native player HUD anchors, layout arguments, identity and visibility fences\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
