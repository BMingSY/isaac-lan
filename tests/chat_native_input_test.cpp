#include "engine/chat_input.h"
#include "engine/lua_api.h"
#include "test_support.h"
#include <map>
#include <string>

// Exercise the public Lua bindings and Windows event boundary without a game.
struct lua_State {
    std::map<std::string, isaac::lua::Function> functions;
    std::map<std::string, bool> booleans;
    isaac::lua::Function function = nullptr;
    bool boolean = false;
};
extern "C" {
__declspec(dllexport) void lua_pushcclosure(lua_State* L, isaac::lua::Function fn, int) {
    L->function = fn;
}
__declspec(dllexport) void lua_setfield(lua_State* L, int, const char* name) {
    if (L->function) {
        L->functions[name] = L->function;
        L->function = nullptr;
    } else
        L->booleans[name] = L->boolean;
}
__declspec(dllexport) void lua_createtable(lua_State*, int, int) {}
__declspec(dllexport) void lua_pushboolean(lua_State* L, int value) {
    L->boolean = value;
}
__declspec(dllexport) int lua_toboolean(lua_State* L, int) {
    return L->boolean;
}
__declspec(dllexport) void lua_pushinteger(lua_State*, long long) {}
__declspec(dllexport) void lua_pushnumber(lua_State*, double) {}
__declspec(dllexport) const char* lua_pushlstring(lua_State*, const char* text, std::size_t) {
    return text;
}
__declspec(dllexport) const char* luaL_checklstring(lua_State*, int, std::size_t* size) {
    *size = 0;
    return "";
}
__declspec(dllexport) double luaL_checknumber(lua_State*, int) {
    return 0;
}
__declspec(dllexport) long long luaL_checkinteger(lua_State*, int) {
    return 0;
}
}
namespace isaac::emotes {
void reset() {}
} // namespace isaac::emotes

int main() {
    namespace chat = isaac::chat_input;
    lua_State state;
    require(chat::bind(&state, GetModuleHandleW(nullptr)), "Chat bindings did not load");
    auto call = [&](const char* name, bool value = false) {
        state.boolean = value;
        state.functions.at(name)(&state);
    };
    // No foreground window or actual user's input context is touched.
    auto event = [&](UINT message, WPARAM key = 0, LPARAM data = 0) {
        return chat::event(nullptr, message, key, data);
    };
    chat::reset();
    call("chat_ui_available", true);
    event(WM_KEYDOWN, VK_OEM_3);
    require(chat::capturesInput(), "Toggle did not open chat");
    event(WM_KEYUP, VK_OEM_3);
    event(WM_IME_STARTCOMPOSITION);
    call("chat_ui_state");
    require(state.booleans.at("composing"), "IME composition did not start");
    event(WM_KEYDOWN, VK_OEM_3);
    require(!chat::capturesInput(), "IME composition prevented the close toggle");
    call("chat_ui_state");
    require(!state.booleans.at("composing"), "Closing retained the IME composition");
    event(WM_KEYDOWN, VK_OEM_3, 1ll << 30);
    require(!chat::capturesInput(), "Held toggle reopened chat");
    require(event(WM_CHAR, '~').has_value(), "Closing leaked its character to the game");
    event(WM_KEYUP, VK_OEM_3);
    event(WM_KEYDOWN, VK_OEM_3);
    require(chat::capturesInput(), "Toggle could not reopen chat");
    event(WM_KEYUP, VK_OEM_3);
    event(WM_KILLFOCUS);
    require(!chat::capturesInput(), "Focus loss retained chat input capture");
    call("chat_ui_available", false);
    require(!event(WM_KEYDOWN, VK_OEM_3), "Inactive chat consumed a game key");
    chat::reset();
}
