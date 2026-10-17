#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include "net/protocol.h"
#include "engine/pause_menu.h"
struct lua_State;
namespace isaac::input {
// Read the local physical bindings while drawing native/Mod interfaces. This
// scope never changes the authoritative inputs used to simulate combat.
class ViewScope {
    int previous;

  public:
    explicit ViewScope(int slot);
    ~ViewScope();
    ViewScope(const ViewScope&) = delete;
};
// Supply the current local preview to native per-actor movement queries. The
// borrowed input lives through this scope; accepted simulation input is untouched.
class MovementPreviewScope {
    const lan::InputFrame* previous;
    int previousController;

  public:
    MovementPreviewScope(const lan::InputFrame& input, int controller);
    ~MovementPreviewScope();
    MovementPreviewScope(const MovementPreviewScope&) = delete;
};
class PauseScope {
    ViewScope view;
    bool previous;
    pause_menu::Intent previousIntent;

  public:
    explicit PauseScope(int slot);
    ~PauseScope();
    pause_menu::Intent intent() const;
    PauseScope(const PauseScope&) = delete;
};
void install(std::uintptr_t image, void (*logger)(const std::string&), bool installed = false);
FARPROC resolve(HMODULE module, LPCSTR name, FARPROC original);
bool bind(lua_State*, HMODULE);
void apply(const lan::Frame& frame);
void finishUpdate();
void reset();
// Clear native menu prompts after the menu has handed off to a LAN game.
void resetMenuPrompts();
void prepareControllers();
void clearAutomation();
// Latch button edges until the next input capture.
void pollPhysicalInput();
// Identity of the native input/render frame, shared by all polls in that frame.
unsigned physicalFrame();
// Read held bindings for local prediction without consuming latched button edges.
lan::InputFrame previewPhysicalInput();
unsigned menuOwner();
void setMenuOwner(unsigned slot);
bool menuTriggered(int action);
// Modal authority controls use the host's latched simulation-step edges.
bool hostMenuTriggered(int action);
void confirmOriginalMenu(void* menu, void(__attribute__((thiscall)) * update)(void*));
void leaveLan();
} // namespace isaac::input
