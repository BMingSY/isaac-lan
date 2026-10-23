#include "engine/versions/j460/mouse_input.h"
#include "test_support.h"
#include <array>
#include <limits>

namespace {
namespace mouse = isaac::engine::j460::mouse_input;
namespace layout = isaac::engine::j460::layout;
static_assert(sizeof(void*) == 4);
alignas(4) std::array<std::byte, 0x1620> player{}, companion{};
bool down = true, detached = false;
mouse::Vector direction{12.5f, -20.0f};
template <class T> T& at(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(reinterpret_cast<std::uintptr_t>(object) + offset);
}
void* __attribute__((thiscall)) anchor(void* object) {
    require(object == player.data(), "Wrong player queried");
    return detached ? companion.data() : nullptr;
}
bool __attribute__((thiscall)) physical(void* object, mouse::Vector* result, bool raw) {
    require(object == player.data() && at<int>(object, layout::player::controller) == 0 && !raw,
            "Physical capture did not borrow keyboard identity");
    *result = direction;
    return down;
}
} // namespace
int main() {
    at<float>(player.data(), layout::entity::positionX) = 320;
    at<float>(player.data(), layout::entity::positionY) = 280;
    at<float>(companion.data(), layout::entity::positionX) = 100;
    at<float>(companion.data(), layout::entity::positionY) = 120;
    for (int controller = 1; controller <= 4; ++controller) {
        at<int>(player.data(), layout::player::controller) = controller;
        for (const bool split : {false, true}) {
            detached = split;
            const auto before = player;
            const auto pointer = mouse::capture(player.data(), physical, anchor);
            require(player == before && pointer.active, "Capture changed native actor state");
            mouse::Vector output;
            require(mouse::replay(player.data(), pointer, &output, anchor) &&
                        std::abs(output.x - direction.x) < 0.0001f &&
                        std::abs(output.y - direction.y) < 0.0001f,
                    "Mouse aim/anchor changed during network replay");
            const auto held = output;
            require(!mouse::replay(player.data(), {}, &output, anchor) && output.x == held.x &&
                        output.y == held.y,
                    "Inactive pointer overwrote keyboard/controller aim");
        }
        down = false;
        const auto before = player;
        require(!mouse::capture(player.data(), physical, anchor).active && player == before,
                "Mouse release changed the controller or retained held fire");
        down = true;
    }
    direction.x = std::numeric_limits<float>::quiet_NaN();
    require(!mouse::capture(player.data(), physical, anchor).active,
            "Invalid native pointer was transmitted");
    std::puts("PASS J460 mouse ABI, four controllers, shooting anchors and ownership restoration");
}
