#include "engine/animation_skip.h"
#include "engine/frontend.h"
#include "engine/input.h"
#include "engine/lua_api.h"
#include "engine/presentation.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"
#include "runtime/session.h"
#include <MinHook.h>

namespace isaac::presentation::animation {
namespace {
namespace j460 = engine::j460;
namespace layout = j460::layout;
enum class Kind { none, boss, floor, personal };
std::uintptr_t image;
lua::API lua{};
bool approved = false;
using Update = void(__attribute__((thiscall)) *)(void*);
using Show = void(__attribute__((thiscall)) *)(void*, bool);
Update originalUpdate;
Update originalRender;
Show originalShow;
template <class T> T& at(std::uintptr_t address, unsigned offset) {
    return *reinterpret_cast<T*>(address + offset);
}
std::uintptr_t manager() {
    return image ? at<std::uintptr_t>(image, j460::globals::manager) : 0;
}
std::uintptr_t game() {
    return image ? at<std::uintptr_t>(image, j460::globals::game) : 0;
}
bool network() {
    return runtime::localViewSlot() >= 0 && !runtime::ending();
}
Kind kind() {
    if (!network() || !game() || !manager())
        return Kind::none;
    if (at<int>(manager(), layout::manager::scene) == layout::nightmare::scene &&
        at<unsigned>(manager() + layout::manager::nightmare, layout::nightmare::active))
        return at<bool>(manager(), layout::manager::dreamHome) ? Kind::personal : Kind::floor;
    return introActive() ? Kind::boss : Kind::none;
}
void __attribute__((fastcall)) update(void* scene, void*) {
    if (!network()) {
        originalUpdate(scene);
        return;
    }
    const input::AnimationConfirmScope consent(approved);
    originalUpdate(scene);
}
void __attribute__((fastcall)) show(void* scene, void*, bool value) {
    approved = false;
    originalShow(scene, value);
}
void __attribute__((fastcall)) render(void* scene, void*) {
    originalRender(scene);
    // NightmareScene bypasses Game::Render, which normally draws the LAN HUD.
    if (network())
        frontend::render();
}
int view(lua_State* L) {
    const auto local = kind();
    lua.createTable(L, 0, 5);
    const auto integer = [&](const char* name, unsigned value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, name);
    };
    integer("kind", static_cast<unsigned>(local));
    integer("id", local == Kind::boss ? playedIntro() : runtime::worldEpoch());
    integer("epoch", runtime::worldEpoch());
    lua.pushBoolean(L, network() && game() && manager() &&
                           at<int>(manager(), layout::manager::scene) == j460::scene::game &&
                           !at<unsigned>(game(), layout::game::stageTransition) &&
                           rooms::stateReady());
    lua.setField(L, -2, "floorReady");
    lua.createTable(L, 0, 0);
    unsigned index = 0;
    const auto event = [&](Kind type, unsigned id, unsigned members) {
        lua.createTable(L, 0, 3);
        integer("kind", static_cast<unsigned>(type));
        integer("id", id);
        integer("members", members);
        lua.rawSetI(L, -2, ++index);
    };
    if (network() && !runtime::replica()) {
        for (const auto& [id, audience] : introAudiences())
            event(Kind::boss, id, audience);
        if (local == Kind::floor)
            event(Kind::floor, runtime::worldEpoch(), rooms::connected());
    }
    lua.setField(L, -2, "events");
    return 1;
}
int request(lua_State* L) {
    lua.pushBoolean(L, active() && !frontend::capturesInput() &&
                           input::menuTriggered(input::action::menuConfirm));
    return 1;
}
int kinds(lua_State* L) {
    lua.createTable(L, 0, 4);
    for (const auto& [name, value] : {std::pair{"none", Kind::none},
                                      {"boss", Kind::boss},
                                      {"floor", Kind::floor},
                                      {"personal", Kind::personal}}) {
        lua.pushInteger(L, static_cast<unsigned>(value));
        lua.setField(L, -2, name);
    }
    return 1;
}
int skip(lua_State* L) {
    const auto type = lua.checkInteger(L, 1), id = lua.checkInteger(L, 2),
               epoch = lua.checkInteger(L, 3);
    bool ok = false;
    if (network() && id >= 0 && epoch == runtime::worldEpoch()) {
        if (type == static_cast<unsigned>(Kind::boss))
            ok = skipIntro(static_cast<unsigned>(id));
        else if ((type == static_cast<unsigned>(Kind::floor) ||
                  type == static_cast<unsigned>(Kind::personal)) &&
                 type == static_cast<unsigned>(kind()) && id == runtime::worldEpoch())
            ok = approved = true;
    }
    lua.pushBoolean(L, ok);
    return 1;
}
} // namespace
bool install(std::uintptr_t base) {
    image = base;
    const auto hook = [](unsigned entry, auto callback, auto& original) {
        const auto address = reinterpret_cast<void*>(image + entry);
        return MH_CreateHook(address, reinterpret_cast<void*>(callback),
                             reinterpret_cast<void**>(&original)) == MH_OK &&
               MH_EnableHook(address) == MH_OK;
    };
    return hook(j460::entry::nightmareSceneRender, render, originalRender) &&
           hook(j460::entry::nightmareSceneUpdate, update, originalUpdate) &&
           hook(j460::entry::nightmareSceneShow, show, originalShow);
}
bool bind(lua_State* L, HMODULE module) {
    using isaac::lua::Symbol;
    if (!lua.load(module,
                  {Symbol::checkInteger, Symbol::pushBoolean, Symbol::pushInteger,
                   Symbol::createTable, Symbol::rawSetI, Symbol::pushClosure, Symbol::setField}))
        return false;
    for (const auto& [name, callback] : {std::pair{"animation_skip_view", &view},
                                         {"animation_skip_request", request},
                                         {"animation_skip", skip},
                                         {"animation_skip_kinds", kinds}}) {
        lua.pushClosure(L, callback, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
void reset() {
    approved = false;
}
bool active() {
    return kind() != Kind::none;
}
} // namespace isaac::presentation::animation
