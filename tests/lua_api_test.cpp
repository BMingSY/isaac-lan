#include "engine/lua_api.h"
#include <bit>
#include <iostream>
#include <stdexcept>

namespace {
int __cdecl top(lua_State*) {
    return 7;
}
void __cdecl push(lua_State*, long long) {}
FARPROC WINAPI resolve(HMODULE, LPCSTR name) {
    if (std::strcmp(name, "lua_gettop") == 0)
        return std::bit_cast<FARPROC>(&top);
    if (std::strcmp(name, "lua_pushinteger") == 0)
        return std::bit_cast<FARPROC>(&push);
    return nullptr;
}
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
} // namespace
int main() {
    try {
        using namespace isaac::lua;
        API api;
        require(api.load(nullptr, {Symbol::getTop}, resolve), "Required export was not loaded");
        require(api.getTop(nullptr) == 7 && !api.pushInteger, "Optional exports were required");
        require(!api.load(nullptr, {Symbol::pushInteger, Symbol::setTop}, resolve),
                "Missing export was accepted");
        require(api.getTop(nullptr) == 7 && !api.pushInteger && !api.setTop,
                "Failed load changed callable ABI table");
        require(api.load(nullptr, {Symbol::pushInteger}, resolve), "Failed load prevented retry");
        api.pushInteger(nullptr, 42);
        std::cout << "PASS Lua ABI subset loading, atomic failure and retry\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
