#include "engine/versions/j460/entity_links.h"
#include "test_support.h"
#include <array>
#include <iostream>
#include <map>
#include <set>
namespace {
using namespace isaac::engine::j460::entity_links;
std::map<Address, std::set<Address>> observers;
unsigned writes = 0;
void __attribute__((fastcall)) assign(void* slot, void* value) {
    const auto pointer = reinterpret_cast<Address>(slot), target = reinterpret_cast<Address>(value);
    auto& prior = field<Address>(pointer, 0);
    if (prior)
        observers[prior].erase(pointer);
    prior = target;
    if (target)
        observers[target].insert(pointer);
    ++writes;
}
} // namespace
int main() {
    try {
        std::array<std::array<unsigned, 0x410 / 4>, 3> storage{};
        const auto owner = reinterpret_cast<Address>(storage[0].data());
        const auto first = reinterpret_cast<Address>(storage[1].data());
        const auto second = reinterpret_cast<Address>(storage[2].data());
        field<unsigned>(owner, 0x28) = 906;
        field<unsigned>(first, 0x28) = field<unsigned>(second, 0x28) = 965;
        field<int>(first, 0x20) = 17;
        field<int>(second, 0x20) = 81;
        require(index(owner) == -1, "Fresh owner already has a cart");
        restore(owner, first, assign);
        restore(owner, first, assign);
        require(index(owner) == 17 && writes == 1, "Repeat changed the reference");
        restore(owner, second, assign);
        require(index(owner) == 81 && observers[first].empty(), "Old cart retained an observer");
        field<unsigned>(first, 0x28) = 4;
        bool rejected = false;
        try {
            restore(owner, first, assign);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected && index(owner) == 81, "Invalid cart changed the owner");
        // The game's EntityPtr destructor clears every registered slot.
        for (auto slot : observers[second])
            field<Address>(slot, 0) = 0;
        observers[second].clear();
        require(index(owner) == -1, "Removed cart left a dangling reference");
        restore(owner, second, assign);
        restore(owner, 0, assign);
        require(observers[second].empty(), "Dismount retained an observer");
        std::array<unsigned, 0x1420 / 4> actor{};
        const auto player = reinterpret_cast<Address>(actor.data());
        field<unsigned>(player, 0x28) = playerType;
        field<unsigned>(first, 0x28) = playerType;
        const auto previousWrites = writes;
        restoreHeld(player, first, assign);
        restoreHeld(player, first, assign);
        require(heldIndex(player) == 17 && writes == previousWrites + 1,
                "Repeated carry changed the registered reference");
        restoreHeld(player, second, assign);
        require(observers[first].empty() && heldIndex(player) == 81,
                "Replacement retained the previous held entity");
        rejected = false;
        try {
            restoreHeld(player, player, assign);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected && heldIndex(player) == 81, "Self carry changed the link");
        for (auto slot : observers[second])
            field<Address>(slot, 0) = 0;
        observers[second].clear();
        require(heldIndex(player) == -1, "Removed held entity retained a dangling reference");
        restoreHeld(player, first, assign);
        restoreHeld(player, 0, assign);
        require(observers[first].empty(), "Throw retained the held entity observer");
        rejected = false;
        try {
            restoreHeld(owner, first, assign);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        require(rejected, "Non-player received a held entity field");
        std::cout
            << "PASS minecart native reference ABI, repeat, replace, removal and validation\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
