#include "engine/state_codec.h"
#include "engine/lua_capture_arrays.h"
#include <lua.hpp>
#include <dlfcn.h>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <array>
#include <cstdio>

namespace {
isaac::lua::API captureApi;
int captureArray(lua_State* state) {
    char error[192]{};
    try {
        luaL_checktype(state, 1, LUA_TTABLE);
        const auto count = lua_rawlen(state, 1);
        std::array<float, 7> values{};
        if (count > values.size())
            return luaL_error(state, "Capture test array is too large");
        for (std::size_t i = 0; i < count; ++i) {
            lua_rawgeti(state, 1, i + 1);
            values[i] = static_cast<float>(luaL_checknumber(state, -1));
            lua_pop(state, 1);
        }
        isaac::lua::pushCaptureArray(state, captureApi, std::span<const float>(values).first(count),
                                     lua_istable(state, 2) ? 2 : 0);
        return 1;
    } catch (const std::exception& exception) {
        std::snprintf(error, sizeof(error), "%s", exception.what());
    }
    return luaL_error(state, "%s", error);
}
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
    using S = isaac::lua::Symbol;
    if (!captureApi.load(nullptr,
                         {S::pushLString, S::rawGet, S::setTop, S::createTable, S::pushNumber,
                          S::rawSetI, S::rawLength, S::getTop, S::pushValue, S::rawSet},
                         resolve)) {
        std::cerr << "Cannot load Lua 5.3 capture ABI\n";
        lua_close(state);
        return 2;
    }
    lua_pushcfunction(state, captureArray);
    lua_setfield(state, -2, "capture_array");
    lua_pushinteger(state, isaac::lua::maxCaptureArrays);
    lua_setfield(state, -2, "capture_array_limit");
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
