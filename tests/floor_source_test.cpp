#include "test_support.h"
#include "engine/versions/j460/floor_source.h"
#include <stdexcept>

int main() {
    using isaac::engine::j460::FloorSource;
    FloorSource source;
    // J460 SetNextStage's Womb II branch: source index -8 selects Blue Womb;
    // the ordinary departure selects stage 10 (Sheol/Cathedral).
    for (int authority : {-8, -9, 84, 168}) {
        for (int viewport : {-8, -9, 84, 168}) {
            int current = viewport, destination = 0, calls = 0;
            auto nativeSelect = [&] {
                ++calls;
                destination = current == -8 ? 9 : current == -9 ? 12 : 10;
            };
            source.reset();
            source.select(current, nativeSelect);
            const int expected = authority == -8 ? 9 : authority == -9 ? 12 : 10;
            if ((authority < 0 || viewport < 0) && authority != viewport)
                require(destination != expected, "Fixture did not reproduce split-room routing");
            require(source.begin(authority), "Valid departure room rejected");
            for (int repeat = 0; repeat < 3; ++repeat) {
                source.select(current, nativeSelect);
                require(destination == expected, "Next floor followed the replica viewport");
                require(current == viewport, "Native route selection changed the viewport");
            }
            require(calls == 4 && source.room(viewport) == authority,
                    "Native selection was skipped or the reliable source was lost");
        }
    }
    int current = 84;
    require(source.begin(-8), "Cannot arm the departure");
    struct NativeExit {};
    bool unwound = false;
    try {
        source.select(current, [&] {
            require(current == -8, "Source was not installed before native selection");
            source.select(current, [&] { require(current == -8, "Nested source differs"); });
            throw NativeExit{};
        });
    } catch (const NativeExit&) {
        unwound = true;
    }
    require(unwound && current == 84, "Exceptional native exit leaked the departure room");
    for (int invalid : {-32768, -21, 169, 32767})
        require(!source.begin(invalid) && source.room(current) == -8,
                "Invalid source replaced an accepted departure");
    // Completion, cancellation, restart and rewind all clear this context.
    source.reset();
    source.select(current, [&] { require(current == 84, "Old floor source survived reset"); });
    require(source.begin(0) && source.room(84) == 0, "Room zero was treated as an absent source");
    source.reset();
    require(source.room(84) == 84, "Reset retained a pending source");
    std::puts("PASS native floor source selection, split-room branches and cleanup");
}
