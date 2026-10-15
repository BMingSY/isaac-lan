#include "engine/versions/j460/rails.h"
#include "test_support.h"
#include <array>
#include <iostream>
#include <vector>

int main() {
    using namespace isaac::engine::j460::rails;
    try {
        std::vector<std::uint32_t> storage((offset + count) / 4 + 1);
        const auto room = reinterpret_cast<std::uintptr_t>(storage.data());
        storage[0xc / 4] = 15;
        storage[0x10 / 4] = 9;
        storage[(offset - 4) / 4] = room;
        std::array<std::uint8_t, count> state;
        state.fill(255);
        state[17] = 0;
        state[18] = 64;  // Rail over a pit.
        state[19] = 82;  // Mineshaft corner.
        state[20] = 160; // Rail entrance.
        restore(room, state);
        require(std::equal(state.begin(), state.end(), grid(room).begin()), "Rail layout lost");
        restore(room, state);
        auto rejects = [&](auto invalid) {
            bool rejected = false;
            try {
                restore(room, invalid);
            } catch (const std::runtime_error&) {
                rejected = true;
            }
            require(rejected, "Invalid rail layout accepted");
            require(grid(room)[17] == 0 && grid(room)[20] == 160,
                    "Invalid rails partially changed the room");
        };
        rejects(std::span(state).first(count - 1));
        state[17] = 1;
        state.back() = 254;
        rejects(std::span(state));
        state.fill(255);
        restore(room, state);
        require(std::all_of(grid(room).begin(), grid(room).end(), [](auto v) { return v == 255; }),
                "Next room retained old rails");
        require(storage[(offset + count) / 4] == 0, "Rail write escaped its fixed array");
        storage[(offset - 4) / 4] = 0;
        bool rejected = false;
        try {
            grid(room);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected, "Wrong RailManager owner accepted");
        std::cout
            << "PASS room rails, pit/entrance variants, repeat, clear and atomic validation\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
