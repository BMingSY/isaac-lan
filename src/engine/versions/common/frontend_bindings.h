#pragma once
#include "engine/versions/common/menu_context.h"
namespace isaac::engine::native_frontend {
struct Bindings {
    unsigned luaInit, menuUpdate, menuRender;
    unsigned luaState, logicalWidth, logicalHeight;
    native_menu::Layout menu;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_frontend
