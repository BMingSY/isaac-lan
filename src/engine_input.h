#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include "net_protocol.h"
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
void install(std::uintptr_t image, void (*logger)(const std::string&), bool installed = false);
FARPROC resolve(HMODULE module, LPCSTR name, FARPROC original);
bool bind(lua_State*, HMODULE);
void apply(const lan::Frame& frame);
void finishUpdate();
void reset();
// Latch one-render-frame button edges until the next 30 Hz network sample.
void pollPhysicalInput();
// Read held bindings for local prediction without consuming latched button edges.
lan::InputFrame previewPhysicalInput();
unsigned menuOwner();
void setMenuOwner(unsigned slot);
bool menuTriggered(int action);
void confirmOriginalMenu(void* menu, void(__attribute__((thiscall)) * update)(void*));
void leaveLan();
} // namespace isaac::input
