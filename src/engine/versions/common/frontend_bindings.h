#pragma once
#include "engine/versions/common/menu_context.h"
#include "presentation/main_menu.h"
namespace isaac::engine::native_frontend {
using DrawMainMenu = void(__attribute__((thiscall)) *)(void*);
struct InsertedRow {
    unsigned drawMainMenu;
    // Lend the original paper for this draw only and return its screen origin.
    std::optional<presentation::main_menu::Position> (*draw)(std::uintptr_t image, void* menu,
                                                             bool selected, DrawMainMenu original);
};
struct Bindings {
    unsigned luaInit, menuUpdate, menuRender;
    unsigned luaState, logicalWidth, logicalHeight;
    native_menu::Layout menu;
    std::optional<InsertedRow> insertedRow = std::nullopt;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_frontend
