#include "engine/versions/repentance_plus/player_hud.h"
#include "engine/versions/repentance/player_hud.h"
#include <vector>
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
void checkRepentance() {
    using isaac::engine::repentance::player_hud::anchor;
    std::vector<std::byte> bytes(0xc3eb7);
    std::array<std::array<std::byte, 0x1554>, 4> players{};
    const auto hud = reinterpret_cast<std::uintptr_t>(bytes.data());
    constexpr unsigned stride = 0x6b0, visible = 0xc3eb6, controller = 0x154c;
    const std::array<int, 4> order{2, 0, 3, 1};
    require(!anchor(0, 0, 480, 270, 0), "Repentance missing HUD accepted");
    require(!anchor(hud, 0, 480, 270, 0), "Repentance hidden HUD accepted");
    write(hud, visible, true);
    require(!anchor(hud, 0, 480, 270, 0), "Repentance empty HUD accepted");
    for (unsigned index = 0; index < 4; ++index) {
        write(hud + index * stride, 0, reinterpret_cast<std::uintptr_t>(players[index].data()));
        write(reinterpret_cast<std::uintptr_t>(players[index].data()), controller,
              order[index] + 1);
    }
    struct Geometry {
        float width, height, hudOffset;
        std::array<std::array<float, 2>, 4> expected;
    };
    const auto before = bytes;
    const auto playersBefore = players;
    for (const Geometry geometry : {
             Geometry{480, 270, 0, {{{48, 12}, {369, 12}, {58, 243}, {361, 243}}}},
             Geometry{480, 270, 1, {{{68, 24}, {345, 24}, {80, 237}, {345, 237}}}},
             Geometry{480, 270, 0.5f, {{{58, 18}, {357, 18}, {69, 240}, {353, 240}}}},
             Geometry{640, 360, 0, {{{48, 12}, {529, 12}, {58, 333}, {521, 333}}}},
         }) {
        for (unsigned index = 0; index < 4; ++index) {
            const auto result =
                anchor(hud, index, geometry.width, geometry.height, geometry.hudOffset);
            require(result && result->slot == order[index] &&
                        result->layout == static_cast<int>(index) &&
                        result->x == geometry.expected[index][0] &&
                        result->y == geometry.expected[index][1],
                    "Repentance HUD anchor differs from native heart coordinates or controller "
                    "identity");
        }
    }
    require(bytes == before && players == playersBefore,
            "Repentance HUD query changed native objects");
    require(!anchor(hud, 4, 480, 270, 0),
            "Repentance companion HUD produced a duplicate indicator");
    require(!anchor(hud, 1, 100, 270, 0) && !anchor(hud, 2, 480, 20, 0),
            "Repentance offscreen heart anchor accepted");
    for (float invalid : {0.f, -1.f, std::numeric_limits<float>::infinity(),
                          std::numeric_limits<float>::quiet_NaN()}) {
        require(!anchor(hud, 0, invalid, 270, 0) && !anchor(hud, 0, 480, invalid, 0),
                "Invalid viewport produced a Repentance HUD anchor");
    }
    for (float invalid :
         {std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
        require(!anchor(hud, 0, 480, 270, invalid), "Nonfinite HUD option accepted");
    const auto first = reinterpret_cast<std::uintptr_t>(players[0].data());
    for (int invalid : {-1, 0, 5}) {
        write(first, controller, invalid);
        require(!anchor(hud, 0, 480, 270, 0), "Repentance invalid controller accepted");
    }
    write(first, controller, 1);
    write(hud, visible, false);
    require(!anchor(hud, 0, 480, 270, 0), "Repentance HUD hide retained an anchor");
}
} // namespace
int main() {
    using isaac::engine::repentance_plus::player_hud::anchor;
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
        checkRepentance();
        require(!get(0, 0), "Missing HUD accepted");
        require(!get(hud, 0), "Hidden HUD accepted");
        write(hud, 0x54cc, true);
        require(!get(hud, 0) && calls == 0, "Empty HUD reached native position code");
        for (unsigned index = 0; index < 4; ++index) {
            write(hud + index * 0x6dc, 0, player);
            write(player, 0x161c, 4 - static_cast<int>(index));
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
                write(player, 0x161c, controller);
                require(!get(hud, index), "Invalid controller accepted");
            }
            require(calls == before, "Invalid player reached native position code");
        }
        require(!get(hud, 4), "Twin HUD produced a duplicate indicator");
        write(player, 0x161c, 1);
        mode = 4;
        require(!get(hud, 0), "Invalid native layout accepted");
        mode = 0;
        for (float invalid : {0.f, -1.f, std::numeric_limits<float>::infinity(),
                              std::numeric_limits<float>::quiet_NaN()})
            require(!anchor(hud, 0, invalid, 270, layout, position) &&
                        !anchor(hud, 0, 480, invalid, layout, position),
                    "Repentance+ invalid viewport accepted");
        write(hud, 0x54cc, false);
        require(!get(hud, 0), "HUD hide retained a visible anchor");
        std::cout << "PASS both native player HUD layouts, heart coordinates, identity and "
                     "visibility fences\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
