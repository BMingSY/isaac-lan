#pragma once
#ifdef _WIN32
#include <windows.h>
#define ISAAC_LUA_CALL __cdecl
#else
#define ISAAC_LUA_CALL
#endif
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>

struct lua_State;
namespace isaac::lua {
using Function = int(ISAAC_LUA_CALL*)(lua_State*);
using Continuation = int(ISAAC_LUA_CALL*)(lua_State*, int, std::intptr_t);
#ifdef _WIN32
using Module = HMODULE;
using Procedure = FARPROC;
using Resolver = FARPROC(WINAPI*)(HMODULE, LPCSTR);
inline constexpr Resolver defaultResolver = GetProcAddress;
#else
using Module = void*;
using Procedure = void (*)();
using Resolver = Procedure (*)(Module, const char*);
inline constexpr Resolver defaultResolver = nullptr;
#endif
enum class Symbol {
    createTable,
    pushClosure,
    setField,
    pushString,
    checkInteger,
    checkString,
    checkNumber,
    pushBoolean,
    pushValue,
    pcall,
    pushInteger,
    pushLString,
    toString,
    getTop,
    getGlobal,
    setTop,
    type,
    ref,
    unref,
    rawGetI,
    rawSetI,
    toBoolean,
    pushNumber,
    toUserdata,
    newUserdata,
    rawLength,
    getMetatable,
    setMetatable,
    error,
    isInteger,
    toInteger,
    toNumber,
    rawGet,
    rawSet,
    getField,
    checkStack,
};
struct API {
    void(ISAAC_LUA_CALL* createTable)(lua_State*, int, int) = nullptr;
    void(ISAAC_LUA_CALL* pushClosure)(lua_State*, Function, int) = nullptr;
    void(ISAAC_LUA_CALL* setField)(lua_State*, int, const char*) = nullptr;
    const char*(ISAAC_LUA_CALL* pushString)(lua_State*, const char*) = nullptr;
    long long(ISAAC_LUA_CALL* checkInteger)(lua_State*, int) = nullptr;
    const char*(ISAAC_LUA_CALL* checkString)(lua_State*, int, std::size_t*) = nullptr;
    double(ISAAC_LUA_CALL* checkNumber)(lua_State*, int) = nullptr;
    void(ISAAC_LUA_CALL* pushBoolean)(lua_State*, int) = nullptr;
    void(ISAAC_LUA_CALL* pushValue)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* pcall)(lua_State*, int, int, int, std::intptr_t, Continuation) = nullptr;
    void(ISAAC_LUA_CALL* pushInteger)(lua_State*, long long) = nullptr;
    const char*(ISAAC_LUA_CALL* pushLString)(lua_State*, const char*, std::size_t) = nullptr;
    const char*(ISAAC_LUA_CALL* toString)(lua_State*, int, std::size_t*) = nullptr;
    int(ISAAC_LUA_CALL* getTop)(lua_State*) = nullptr;
    int(ISAAC_LUA_CALL* getGlobal)(lua_State*, const char*) = nullptr;
    void(ISAAC_LUA_CALL* setTop)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* type)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* ref)(lua_State*, int) = nullptr;
    void(ISAAC_LUA_CALL* unref)(lua_State*, int, int) = nullptr;
    int(ISAAC_LUA_CALL* rawGetI)(lua_State*, int, long long) = nullptr;
    void(ISAAC_LUA_CALL* rawSetI)(lua_State*, int, long long) = nullptr;
    int(ISAAC_LUA_CALL* toBoolean)(lua_State*, int) = nullptr;
    void(ISAAC_LUA_CALL* pushNumber)(lua_State*, double) = nullptr;
    void*(ISAAC_LUA_CALL* toUserdata)(lua_State*, int) = nullptr;
    void*(ISAAC_LUA_CALL* newUserdata)(lua_State*, std::size_t) = nullptr;
    std::size_t(ISAAC_LUA_CALL* rawLength)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* getMetatable)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* setMetatable)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* error)(lua_State*) = nullptr;
    int(ISAAC_LUA_CALL* isInteger)(lua_State*, int) = nullptr;
    long long(ISAAC_LUA_CALL* toInteger)(lua_State*, int, int*) = nullptr;
    double(ISAAC_LUA_CALL* toNumber)(lua_State*, int, int*) = nullptr;
    int(ISAAC_LUA_CALL* rawGet)(lua_State*, int) = nullptr;
    void(ISAAC_LUA_CALL* rawSet)(lua_State*, int) = nullptr;
    int(ISAAC_LUA_CALL* getField)(lua_State*, int, const char*) = nullptr;
    int(ISAAC_LUA_CALL* checkStack)(lua_State*, int) = nullptr;
    bool load(Module module, std::initializer_list<Symbol> required,
              Resolver resolve = defaultResolver) {
        if (!resolve)
            return false;
        API next = *this;
        for (auto symbol : required) {
            switch (symbol) {
            case Symbol::createTable:
                if (!bind(next.createTable, resolve(module, "lua_createtable")))
                    return false;
                break;
            case Symbol::pushClosure:
                if (!bind(next.pushClosure, resolve(module, "lua_pushcclosure")))
                    return false;
                break;
            case Symbol::setField:
                if (!bind(next.setField, resolve(module, "lua_setfield")))
                    return false;
                break;
            case Symbol::pushString:
                if (!bind(next.pushString, resolve(module, "lua_pushstring")))
                    return false;
                break;
            case Symbol::checkInteger:
                if (!bind(next.checkInteger, resolve(module, "luaL_checkinteger")))
                    return false;
                break;
            case Symbol::checkString:
                if (!bind(next.checkString, resolve(module, "luaL_checklstring")))
                    return false;
                break;
            case Symbol::checkNumber:
                if (!bind(next.checkNumber, resolve(module, "luaL_checknumber")))
                    return false;
                break;
            case Symbol::pushBoolean:
                if (!bind(next.pushBoolean, resolve(module, "lua_pushboolean")))
                    return false;
                break;
            case Symbol::pushValue:
                if (!bind(next.pushValue, resolve(module, "lua_pushvalue")))
                    return false;
                break;
            case Symbol::pcall:
                if (!bind(next.pcall, resolve(module, "lua_pcallk")))
                    return false;
                break;
            case Symbol::pushInteger:
                if (!bind(next.pushInteger, resolve(module, "lua_pushinteger")))
                    return false;
                break;
            case Symbol::pushLString:
                if (!bind(next.pushLString, resolve(module, "lua_pushlstring")))
                    return false;
                break;
            case Symbol::toString:
                if (!bind(next.toString, resolve(module, "lua_tolstring")))
                    return false;
                break;
            case Symbol::getTop:
                if (!bind(next.getTop, resolve(module, "lua_gettop")))
                    return false;
                break;
            case Symbol::getGlobal:
                if (!bind(next.getGlobal, resolve(module, "lua_getglobal")))
                    return false;
                break;
            case Symbol::setTop:
                if (!bind(next.setTop, resolve(module, "lua_settop")))
                    return false;
                break;
            case Symbol::type:
                if (!bind(next.type, resolve(module, "lua_type")))
                    return false;
                break;
            case Symbol::ref:
                if (!bind(next.ref, resolve(module, "luaL_ref")))
                    return false;
                break;
            case Symbol::unref:
                if (!bind(next.unref, resolve(module, "luaL_unref")))
                    return false;
                break;
            case Symbol::rawGetI:
                if (!bind(next.rawGetI, resolve(module, "lua_rawgeti")))
                    return false;
                break;
            case Symbol::rawSetI:
                if (!bind(next.rawSetI, resolve(module, "lua_rawseti")))
                    return false;
                break;
            case Symbol::toBoolean:
                if (!bind(next.toBoolean, resolve(module, "lua_toboolean")))
                    return false;
                break;
            case Symbol::pushNumber:
                if (!bind(next.pushNumber, resolve(module, "lua_pushnumber")))
                    return false;
                break;
            case Symbol::toUserdata:
                if (!bind(next.toUserdata, resolve(module, "lua_touserdata")))
                    return false;
                break;
            case Symbol::newUserdata:
                if (!bind(next.newUserdata, resolve(module, "lua_newuserdata")))
                    return false;
                break;
            case Symbol::rawLength:
                if (!bind(next.rawLength, resolve(module, "lua_rawlen")))
                    return false;
                break;
            case Symbol::getMetatable:
                if (!bind(next.getMetatable, resolve(module, "lua_getmetatable")))
                    return false;
                break;
            case Symbol::setMetatable:
                if (!bind(next.setMetatable, resolve(module, "lua_setmetatable")))
                    return false;
                break;
            case Symbol::isInteger:
                if (!bind(next.isInteger, resolve(module, "lua_isinteger")))
                    return false;
                break;
            case Symbol::toInteger:
                if (!bind(next.toInteger, resolve(module, "lua_tointegerx")))
                    return false;
                break;
            case Symbol::toNumber:
                if (!bind(next.toNumber, resolve(module, "lua_tonumberx")))
                    return false;
                break;
            case Symbol::rawGet:
                if (!bind(next.rawGet, resolve(module, "lua_rawget")))
                    return false;
                break;
            case Symbol::rawSet:
                if (!bind(next.rawSet, resolve(module, "lua_rawset")))
                    return false;
                break;
            case Symbol::getField:
                if (!bind(next.getField, resolve(module, "lua_getfield")))
                    return false;
                break;
            case Symbol::checkStack:
                if (!bind(next.checkStack, resolve(module, "lua_checkstack")))
                    return false;
                break;
            case Symbol::error:
                if (!bind(next.error, resolve(module, "lua_error")))
                    return false;
                break;
            }
        }
        *this = next;
        return true;
    }

  private:
    template <class T> static bool bind(T& target, Procedure address) {
        static_assert(sizeof(target) == sizeof(address));
        if (!address)
            return false;
        std::memcpy(&target, &address, sizeof(target));
        return true;
    }
};
} // namespace isaac::lua
#undef ISAAC_LUA_CALL
