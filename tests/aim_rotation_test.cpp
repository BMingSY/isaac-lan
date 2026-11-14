#include "compat/challenges/aim_rotation.h"
#include "net/protocol.h"
#include "test_support.h"
#include <cstdio>

int main() {
    using namespace isaac;
    using namespace compat::challenges;
    using namespace input::action;
    std::array<lan::InputFrame, maximumAimSeats> physical;
    for (unsigned seat = 0; seat < physical.size(); ++seat) {
        for (unsigned action = 0; action < lan::actionCount; ++action)
            physical[seat].values[action] = 1000 * (seat + 1) + action;
        physical[seat].triggered = (1u << (shootLeft + seat)) | (1u << bomb) | (1u << moveUp);
        physical[seat].pointer = {true, 50.0f * seat, 100.0f + seat};
    }
    for (unsigned players = 2; players <= maximumAimSeats; ++players)
        for (unsigned connected = 0; connected < (1u << players); ++connected) {
            auto actual = physical;
            rotateShooting(actual, players, connected);
            for (unsigned source = 0; source < players; ++source) {
                const auto target = (source + 1) % players;
                auto expected = physical[target];
                const auto shot = connected & (1u << source) ? physical[source] : lan::InputFrame{};
                for (int action = shootLeft; action <= shootDown; ++action)
                    expected.values[action] = shot.values[action];
                expected.triggered =
                    (expected.triggered & ~shootingMask) | (shot.triggered & shootingMask);
                expected.pointer = shot.pointer;
                require(actual[target] == expected,
                        "Opening-seat rotation changed owner input or selected a live-seat ring");
            }
            for (unsigned seat = players; seat < physical.size(); ++seat)
                require(actual[seat] == physical[seat], "Rotation touched an unused seat");
        }
    for (unsigned players : {0u, 1u, 5u}) {
        auto actual = physical;
        rotateShooting(actual, players, 15);
        require(actual == physical, "Invalid party changed input");
    }
    // Continuous holds have no new edge; releasing the source releases the
    // recipient's charged weapon. Reconnect uses the original opening seat.
    for (bool held : {true, true, false, true}) {
        std::array<lan::InputFrame, 4> actual{};
        actual[0].values[shootRight] = held ? lan::maxInputValue : 0;
        rotateShooting(actual, 4, 15);
        require(actual[1].values[shootRight] == (held ? lan::maxInputValue : 0) &&
                    actual[1].triggered == 0 && actual[0].values[shootRight] == 0 &&
                    actual[2].values[shootRight] == 0 && actual[3].values[shootRight] == 0,
                "Held fire/release was duplicated or sent to the wrong actor");
    }
    auto preview = physical[0];
    copyShooting(preview, lan::InputFrame{});
    require(!preview.pointer.active && !(preview.triggered & shootingMask) &&
                preview.values[moveLeft] == physical[0].values[moveLeft] &&
                preview.values[item] == physical[0].values[item] && preview.values[shootLeft] == 0,
            "Local movement preview retained shooting owned by another player");
    std::puts(
        "PASS two-to-four opening seats, disconnect masks, hold/release, pointer and owner input");
}
