#include "test_support.h"
#include "engine/versions/j460/active_items.h"
#include <cstdio>
#include <vector>

int main() {
    try {
        using namespace isaac::engine::j460;
        using namespace active_items;
        std::vector<std::uint8_t> playerBytes(0x2200, 0), gameBytes(0x24000, 0xa5);
        const auto player = reinterpret_cast<Address>(playerBytes.data());
        const auto game = reinterpret_cast<Address>(gameBytes.data());
        State desired{{{489, 6}, {284, 3}, {489, (9 << 16) | 12}, {0, 0}}};
        for (unsigned slot = 0; slot < desired.size(); ++slot)
            field<int>(player, layout::player::primaryActive + slot * layout::activeItem::stride) =
                desired[slot].id;
        for (unsigned i = 0; i < layout::playerHud::count; ++i) {
            const auto hud = game + layout::game::playerHuds + i * layout::playerHud::size;
            field<Address>(hud, 0) = i == 3 || i == 6 ? player : 0;
        }
        auto expectedGame = gameBytes;
        for (unsigned slot = 0; slot < 3; ++slot)
            for (unsigned i : {3, 6})
                field<int>(reinterpret_cast<Address>(expectedGame.data()),
                           layout::game::playerHuds + i * layout::playerHud::size +
                               layout::playerHud::activeItems +
                               slot * layout::playerHud::activeStride) = 0;
        restore(player, game, desired);
        require(capture(player) == desired && gameBytes == expectedGame,
                "Active state or unrelated HUD/texture ownership changed");
        // Model the next native HUD draw repopulating its icon key.
        field<int>(game, layout::game::playerHuds + 3 * layout::playerHud::size +
                             layout::playerHud::activeItems) = 489;
        const auto beforePlayer = playerBytes, beforeGame = gameBytes;
        restore(player, game, desired);
        require(playerBytes == beforePlayer && gameBytes == beforeGame,
                "Repeated state mutated native data or icon caches");
        for (int selected = 0; selected < 10; ++selected) {
            desired[0].data = (selected << 16) | 6;
            restore(player, game, desired);
            require(capture(player) == desired, "D Infinity selection did not round trip");
        }
        for (unsigned failure = 0; failure < 3; ++failure) {
            auto invalid = desired;
            invalid[0].data = 2 << 16;
            if (failure == 0)
                invalid[2].id = 105;
            if (failure == 1)
                invalid[2].data = 10 << 16;
            if (failure == 2)
                invalid[3].data = 1;
            const auto savedPlayer = playerBytes, savedGame = gameBytes;
            bool rejected = false;
            try {
                restore(player, game, invalid);
            } catch (const std::runtime_error&) {
                rejected = true;
            }
            require(rejected && playerBytes == savedPlayer && gameBytes == savedGame,
                    "Invalid late slot partially restored earlier active data");
        }
        // Replacing a slot and later restoring it must use the new inventory ID.
        field<int>(player, layout::player::primaryActive) = 105;
        desired[0] = {105, 0};
        restore(player, game, desired);
        require(capture(player) == desired, "Replaced active retained D Infinity selection");
        std::puts("PASS active slot state, all dice, stable caches, validation and replacement");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
