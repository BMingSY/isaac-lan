#pragma once
#include <windows.h>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <initializer_list>

struct lua_State;
namespace isaac::lua {
using Function = int(__cdecl*)(lua_State*);
using Continuation = int(__cdecl*)(lua_State*, int, std::intptr_t);
using Resolver = FARPROC(WINAPI*)(HMODULE, LPCSTR);
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
};
struct API {
    void(__cdecl* createTable)(lua_State*, int, int) = nullptr;
    void(__cdecl* pushClosure)(lua_State*, Function, int) = nullptr;
    void(__cdecl* setField)(lua_State*, int, const char*) = nullptr;
    const char*(__cdecl* pushString)(lua_State*, const char*) = nullptr;
    long long(__cdecl* checkInteger)(lua_State*, int) = nullptr;
    const char*(__cdecl* checkString)(lua_State*, int, std::size_t*) = nullptr;
    double(__cdecl* checkNumber)(lua_State*, int) = nullptr;
    void(__cdecl* pushBoolean)(lua_State*, int) = nullptr;
    void(__cdecl* pushValue)(lua_State*, int) = nullptr;
    int(__cdecl* pcall)(lua_State*, int, int, int, std::intptr_t, Continuation) = nullptr;
    void(__cdecl* pushInteger)(lua_State*, long long) = nullptr;
    const char*(__cdecl* pushLString)(lua_State*, const char*, std::size_t) = nullptr;
    const char*(__cdecl* toString)(lua_State*, int, std::size_t*) = nullptr;
    int(__cdecl* getTop)(lua_State*) = nullptr;
    int(__cdecl* getGlobal)(lua_State*, const char*) = nullptr;
    void(__cdecl* setTop)(lua_State*, int) = nullptr;
    int(__cdecl* type)(lua_State*, int) = nullptr;
    int(__cdecl* ref)(lua_State*, int) = nullptr;
    void(__cdecl* unref)(lua_State*, int, int) = nullptr;
    int(__cdecl* rawGetI)(lua_State*, int, long long) = nullptr;
    void(__cdecl* rawSetI)(lua_State*, int, long long) = nullptr;
    int(__cdecl* toBoolean)(lua_State*, int) = nullptr;
    void(__cdecl* pushNumber)(lua_State*, double) = nullptr;
    void*(__cdecl* toUserdata)(lua_State*, int) = nullptr;
    void*(__cdecl* newUserdata)(lua_State*, std::size_t) = nullptr;
    std::size_t(__cdecl* rawLength)(lua_State*, int) = nullptr;
    int(__cdecl* getMetatable)(lua_State*, int) = nullptr;
    int(__cdecl* setMetatable)(lua_State*, int) = nullptr;
    int(__cdecl* error)(lua_State*) = nullptr;
    bool load(HMODULE module, std::initializer_list<Symbol> required,
              Resolver resolve = GetProcAddress) {
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
    template <class T> static bool bind(T& target, FARPROC address) {
        static_assert(sizeof(target) == sizeof(address));
        if (!address)
            return false;
        std::memcpy(&target, &address, sizeof(target));
        return true;
    }
};
} // namespace isaac::lua
