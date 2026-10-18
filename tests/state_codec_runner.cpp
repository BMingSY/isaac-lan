#include "engine/state_codec.h"
#include <lua.hpp>
#include <dlfcn.h>
#include <cstring>
#include <cstdlib>
#include <iostream>

namespace {
int allocationBudget = -1;
void* allocate(void*, void* pointer, std::size_t previous, std::size_t size) {
    if (!size) {
        std::free(pointer);
        return nullptr;
    }
    // Lua's allocator contract requires shrinking allocations to succeed.
    if (!pointer || size > previous) {
        if (allocationBudget == 0)
            return nullptr;
        if (allocationBudget > 0)
            --allocationBudget;
    }
    return std::realloc(pointer, size);
}
int withAllocationBudget(lua_State* state) {
    const auto limit = static_cast<int>(luaL_checkinteger(state, 1));
    const auto arguments = lua_gettop(state) - 2;
    luaL_checkstack(state, 32, "allocation probe stack");
    lua_remove(state, 1);
    allocationBudget = limit;
    const auto status = lua_pcall(state, arguments, LUA_MULTRET, 0);
    allocationBudget = -1;
    lua_pushboolean(state, status == LUA_OK);
    lua_insert(state, 1);
    return lua_gettop(state);
}
isaac::lua::Procedure resolve(isaac::lua::Module, const char* name) {
    const auto address = dlsym(RTLD_DEFAULT, name);
    isaac::lua::Procedure result;
    static_assert(sizeof(result) == sizeof(address));
    std::memcpy(&result, &address, sizeof(result));
    return result;
}
} // namespace

int main(int argc, char** argv) {
    if (argc < 2)
        return 2;
    const auto state = lua_newstate(allocate, nullptr);
    if (!state)
        return 2;
    luaL_openlibs(state);
    lua_newtable(state);
    if (!isaac::lua_state_codec::bind(state, nullptr, resolve)) {
        std::cerr << "Cannot load Lua 5.3 state codec ABI\n";
        lua_close(state);
        return 2;
    }
    lua_pushcfunction(state, withAllocationBudget);
    lua_setfield(state, -2, "with_allocation_limit");
    lua_setglobal(state, "_IsaacLanCodec");
    lua_createtable(state, argc - 2, 0);
    for (int i = 1; i < argc; ++i) {
        lua_pushstring(state, argv[i]);
        lua_rawseti(state, -2, i - 1);
    }
    lua_setglobal(state, "arg");
    const auto status = luaL_dofile(state, argv[1]);
    if (status != LUA_OK)
        std::cerr << lua_tostring(state, -1) << '\n';
    lua_close(state);
    return status == LUA_OK ? 0 : 1;
}
