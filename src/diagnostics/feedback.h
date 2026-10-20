#pragma once
#include <windows.h>
#include <filesystem>
#include <string>

struct lua_State;

// /feedback: a worker thread collects recent logs, packs them and uploads the
// zip to the feedback receiver; Lua submits and polls for the result.
namespace isaac::feedback {
struct Environment {
    std::filesystem::path config;
    // UTF-8 endpoint; empty disables uploads.
    std::string endpoint;
    std::string client, game;
};
// Returns false and disables uploads when the endpoint is not acceptable.
bool configure(Environment environment);
bool bind(lua_State* L, HMODULE module);
} // namespace isaac::feedback
