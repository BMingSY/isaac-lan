#include "engine/versions/j835/menu_navigation.h"
#include "presentation/main_menu.h"
#include <windows.h>
#include <array>
#include <cstring>

namespace isaac::engine::j835::menu_navigation {
namespace {
using Address = std::uintptr_t;
// Menu_Game::Update has a six-action dispatch table and two wrap bounds.
// Its input polling, repeat timer, sounds and tests for Continue stay native.
constexpr unsigned confirmLimit = 0x4d95e0, dispatch = 0x4d95e9, wrapUp = 0x4d9a93,
                   wrapDown = 0x4d9b05, stockTable = 0x4d9f58, finishUpdate = 0x4d9c6d;
constexpr std::array<unsigned, 6> actions{0x4d95f0, 0x4d969e, 0x4d9750,
                                          0x4d97e7, 0x4d98a2, 0x4d9950};
std::array<Address, actions.size() + 1> sevenActions;
} // namespace
bool install(Address image) {
    static_assert(sizeof(Address) == 4);
    if (!image)
        return false;
    auto* confirm = reinterpret_cast<unsigned char*>(image + confirmLimit);
    auto* table = reinterpret_cast<unsigned char*>(image + dispatch);
    auto* up = reinterpret_cast<unsigned char*>(image + wrapUp);
    auto* down = reinterpret_cast<unsigned char*>(image + wrapDown);
    Address tableAddress;
    std::memcpy(&tableAddress, table + 3, sizeof(tableAddress));
    if (tableAddress == reinterpret_cast<Address>(sevenActions.data()))
        return confirm[2] == actions.size() && up[1] == actions.size() &&
               down[2] == sevenActions.size();
    if (std::memcmp(confirm, "\x83\xf8\x05", 3) || std::memcmp(table, "\xff\x24\x85", 3) ||
        tableAddress != image + stockTable || std::memcmp(up, "\xba\x05\x00\x00\x00", 5) ||
        std::memcmp(down, "\x83\xf9\x06", 3))
        return false;
    const auto* stock = reinterpret_cast<const Address*>(tableAddress);
    for (unsigned i = 0; i < actions.size(); ++i) {
        if (stock[i] != image + actions[i])
            return false;
        sevenActions[presentation::main_menu::displayRow(i)] = stock[i];
    }
    // The frontend handles LAN confirm. If it is unavailable the original
    // switch simply finishes updating this row without dispatching another action.
    sevenActions[presentation::main_menu::online] = image + finishUpdate;
    const Address extended = reinterpret_cast<Address>(sevenActions.data());
    const auto size = wrapDown + 3 - confirmLimit;
    DWORD protection, ignored;
    if (!VirtualProtect(confirm, size, PAGE_EXECUTE_READWRITE, &protection))
        return false;
    const auto apply = [&](Address address, unsigned char last) {
        std::memcpy(table + 3, &address, sizeof(address));
        confirm[2] = up[1] = last;
        down[2] = last + 1;
    };
    apply(extended, actions.size());
    if (FlushInstructionCache(GetCurrentProcess(), confirm, size) &&
        VirtualProtect(confirm, size, protection, &ignored))
        return true;
    apply(tableAddress, actions.size() - 1);
    FlushInstructionCache(GetCurrentProcess(), confirm, size);
    VirtualProtect(confirm, size, protection, &ignored);
    return false;
}
} // namespace isaac::engine::j835::menu_navigation
