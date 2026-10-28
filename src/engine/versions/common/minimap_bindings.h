#pragma once
#include <cstdint>
namespace isaac::engine::native_minimap {
struct Bindings {
    unsigned game, renderer;
    struct Entry {
        unsigned update, render, cache, flush;
    } entry;
    struct Game {
        unsigned minimap, roomIndex, dimension;
    } gameLayout;
    struct Minimap {
        unsigned small, large;
    } minimapLayout;
    struct Config {
        unsigned texture, cellWidth, cellHeight, cellSpacing, anchorX, anchorY;
    } mapConfigLayout;
    struct Texture {
        unsigned width, height;
    } textureLayout;
};
extern const Bindings bindings;
bool ensureTextureHook(std::uintptr_t image, std::uintptr_t texture);
} // namespace isaac::engine::native_minimap
