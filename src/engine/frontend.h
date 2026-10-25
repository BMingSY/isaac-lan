#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include "core/chat.h"
#include "presentation/chat_background.h"
#include "presentation/minimap.h"
#include <filesystem>
#include <vector>
struct lua_State;
namespace isaac::frontend {
void prepareView();
const std::vector<presentation::MinimapView>& minimapViews();
void render();
void returnToLobby();
bool capturesInput();
void configureConnection(const std::filesystem::path& path);
void configureChat(const chat::Appearance& appearance,
                   const presentation::ChatBackground& background);
bool install(std::uintptr_t image, const std::wstring& root, void (*log)(const std::string&),
             int(__cdecl* bind)(lua_State*), bool installed = false);
} // namespace isaac::frontend
