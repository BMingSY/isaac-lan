#pragma once
#include <cstdint>

namespace isaac::engine::native_crafting_hud {
struct PocketLayout {
    float x, y, scale;
};
enum class PocketAbi { stackLayoutAlpha, registerScaleAlpha };
struct Bindings {
    std::uint32_t bag, pocket, activeItem, width, height;
    struct PlayerHud {
        unsigned player, root, stride;
    } playerHud;
    unsigned controller, coopGhost;
    PocketAbi pocketAbi;
    bool (*placePocket)(std::uintptr_t image, std::uintptr_t hud, std::uintptr_t root, float width,
                        float height, PocketLayout&);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_crafting_hud
