#include "test_support.h"
#include "engine/versions/j460/inventory_order.h"
#include <algorithm>
#include <cstdio>
#include <vector>

int main() {
    try {
        using namespace isaac::engine::j460;
        using namespace inventory_order;
        std::vector<std::uint8_t> bytes(0x2200), history(6 * layout::historyItem::size),
            gameBytes(0x24000);
        const auto game = reinterpret_cast<Address>(gameBytes.data());
        const auto hud = game + layout::game::playerHuds + 3 * layout::playerHud::size;
        const auto player = reinterpret_cast<Address>(bytes.data());
        field<Address>(hud, layout::playerHud::player) = player;
        const auto first = reinterpret_cast<Address>(history.data());
        field<Address>(player, layout::player::history) = first;
        field<Address>(player, layout::player::history + layout::vector::end) =
            first + history.size();
        for (unsigned i = 0; i < layout::player::inventorySlots; ++i)
            field<int>(player, layout::player::inventoryOrder + i * sizeof(int)) = -1;
        const std::array<int, 6> ids{99, 1, 12, 1, -2, 25};
        for (unsigned i = 0; i < ids.size(); ++i)
            field<int>(first + i * layout::historyItem::size, layout::historyItem::id) = ids[i];
        field<bool>(first, layout::historyItem::trinket) = true;
        for (unsigned i = 0; i < 5; ++i)
            field<int>(player, layout::player::inventoryOrder + i * sizeof(int)) = i + 1;
        State desired{12, 1, -2, 25, 1};
        const auto historyBefore = history;
        restore(player, game, desired);
        require(capture(player) == desired && history == historyBefore,
                "Inventory order lost duplicate/generated items or mutated native history");
        require(field<bool>(hud, layout::playerHud::refreshFlags),
                "Changed inventory left stale HUD icons");
        field<bool>(hud, layout::playerHud::refreshFlags) = false;
        const auto beforeGame = gameBytes;
        auto before = bytes;
        restore(player, game, desired);
        require(bytes == before && gameBytes == beforeGame,
                "Repeated inventory order changed selection or invalidated HUD");
        for (unsigned i = 0; i < 5; ++i) {
            std::rotate(desired.begin(), desired.begin() + 1, desired.begin() + 5);
            restore(player, game, desired);
            require(capture(player) == desired, "Cycling did not select the expected item");
        }
        for (int replacement : {0, 999, 1}) {
            auto invalid = desired;
            invalid[0] = replacement;
            before = bytes;
            bool rejected = false;
            try {
                restore(player, game, invalid);
            } catch (const std::runtime_error&) {
                rejected = true;
            }
            require(rejected && bytes == before,
                    "Invalid inventory order partially changed selection");
        }
        field<int>(player, layout::player::inventoryOrder) = 6;
        bool rejected = false;
        try {
            capture(player);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected, "Out-of-bounds history index was accepted");
        std::puts(
            "PASS inventory order, duplicates, generated IDs, repeated state and atomic rejection");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
