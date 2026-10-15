#include "engine/versions/j460/held_bombs.h"
#include "test_support.h"
#include <iostream>
#include <map>
#include <set>
#include <vector>

namespace {
using namespace isaac::engine::j460::held_bombs;
std::array<Address, 8> blocks{};
std::array<std::array<Address, 4>, 8> elements{};
std::map<Address, std::set<Address>> observers;
unsigned resizes = 0, assignments = 0;
// Match the two actual J460 calling conventions, including stack cleanup.
void __attribute__((thiscall)) resize(void* pointer, unsigned count) {
    require(count == 2 || count == 3, "Resize escaped the Boss slot bounds");
    ++resizes;
    const auto deque = reinterpret_cast<Address>(pointer);
    for (unsigned i = 0; i < blocks.size(); ++i)
        blocks[i] = reinterpret_cast<Address>(elements[i].data());
    field<Address>(deque, 4) = reinterpret_cast<Address>(blocks.data());
    field<unsigned>(deque, 8) = 8;
    // Exercise the block boundary and wrapping offset, not just fresh offset 0.
    field<unsigned>(deque, 12) = 31;
    field<unsigned>(deque, 16) = count;
}
void __attribute__((fastcall)) assign(void* pointer, void* value) {
    ++assignments;
    const auto slot = reinterpret_cast<Address>(pointer), bomb = reinterpret_cast<Address>(value);
    auto& previous = field<Address>(slot, 0);
    if (previous)
        observers[previous].erase(slot);
    previous = bomb;
    if (bomb)
        observers[bomb].insert(slot);
}
template <class Call> void rejects(Call call) {
    bool rejected = false;
    try {
        call();
    } catch (const std::runtime_error&) {
        rejected = true;
    }
    require(rejected, "Invalid native context accepted");
}
} // namespace
int main() {
    try {
        for (unsigned kind : {906u, 920u}) {
            resizes = assignments = 0;
            observers.clear();
            blocks = {};
            elements = {};
            std::vector<std::uint32_t> storage(0xf60 / 4);
            std::array<std::array<std::uint32_t, 0x410 / 4>, 3> bombs{};
            const auto npc = reinterpret_cast<Address>(storage.data());
            std::array<Address, 3> targets{reinterpret_cast<Address>(bombs[0].data()),
                                           reinterpret_cast<Address>(bombs[1].data()),
                                           kind == 920 ? reinterpret_cast<Address>(bombs[2].data())
                                                       : 0};
            field<unsigned>(npc, 0x28) = kind;
            for (unsigned i = 0; i < slotCount(npc); ++i) {
                field<unsigned>(targets[i], 0x28) = 4;
                field<int>(targets[i], 0x20) = 71 + i;
            }
            require(indices(npc) == std::array<int, 3>{-1, -1, -1},
                    "Empty constructor was dereferenced");
            restore(npc, {}, resize, assign);
            require(resizes == 1 && assignments == 0 && slots(npc)[0],
                    "An empty snapshot must still initialize both render slots");
            restore(npc, targets, resize, assign);
            require(indices(npc) == std::array<int, 3>{71, 72, kind == 920 ? 73 : -1} &&
                        assignments == slotCount(npc),
                    "Bomb identity or wrapped slot addressing changed");
            restore(npc, targets, resize, assign);
            require(resizes == 1 && assignments == slotCount(npc),
                    "Repeated snapshot reallocated or relinked");
            restore(npc, {targets[1], targets[0], targets[2]}, resize, assign);
            require(observers[targets[0]].size() == 1 && observers[targets[1]].size() == 1,
                    "Replacement leaked EntityPtr observers");
            // Native deletion notifies all registered slots before freeing a bomb.
            for (auto slot : observers[targets[1]])
                field<Address>(slot, 0) = 0;
            observers[targets[1]].clear();
            require(indices(npc) == std::array<int, 3>{-1, 71, kind == 920 ? 73 : -1},
                    "Deleted bomb retained a dangling link");
            restore(npc, {}, resize, assign);
            require(observers[targets[0]].empty() && observers[targets[2]].empty(),
                    "Room cleanup retained bomb references");
            field<unsigned>(npc, 0x28) = 907;
            rejects([&] { restore(npc, targets, resize, assign); });
            field<unsigned>(npc, 0x28) = kind;
            field<unsigned>(targets[1], 0x28) = 1;
            rejects([&] { restore(npc, targets, resize, assign); });
            require(indices(npc) == std::array<int, 3>{-1, -1, -1},
                    "Invalid second bomb partially applied");
            field<unsigned>(npc + bombsOffset, 16) = 1;
            rejects([&] { indices(npc); });
            field<unsigned>(npc + bombsOffset, 16) = slotCount(npc);
            field<unsigned>(npc + bombsOffset, 8) = 7;
            rejects([&] { indices(npc); });
            field<unsigned>(npc + bombsOffset, 8) = 8;
            blocks[7] = 0;
            rejects([&] { indices(npc); });
        }
        std::cout << "PASS Hornfel constructor, native resize/assign ABI, wrapped blocks, repeated "
                     "snapshots, deletion and invalid contexts\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
