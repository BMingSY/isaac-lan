#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include "core/chat.h"
struct lua_State;
namespace isaac::frontend {
void prepareView();
void render();
void returnToLobby();
bool capturesInput();
void configureChat(const chat::Appearance& appearance);
bool install(std::uintptr_t image, const std::wstring& root, void (*log)(const std::string&),
             int(__cdecl* bind)(lua_State*), bool installed = false);
} // namespace isaac::frontend
