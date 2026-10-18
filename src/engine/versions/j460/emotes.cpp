#include "engine/emotes.h"
#include "engine/input.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>
#include <array>

namespace isaac::emotes {
namespace {
namespace j460 = engine::j460;
namespace layout = j460::layout;
std::uintptr_t image;
lua::API lua;
using Method = void(__attribute__((thiscall)) *)(void*);
using LocalParticipant = void*(__attribute__((thiscall)) *)(void*);
LocalParticipant originalParticipant;
void* scopedParticipant = nullptr;
template <class T> T& at(std::uintptr_t base, unsigned offset = 0) {
    return *reinterpret_cast<T*>(base + offset);
}
std::uintptr_t wheel() {
    const auto game = at<std::uintptr_t>(image, j460::globals::game);
    return game && rooms::stateReady() ? game + layout::game::emoteWheel : 0;
}
void* __attribute__((fastcall)) localParticipant(void* object, void*) {
    return scopedParticipant ? scopedParticipant : originalParticipant(object);
}
int poll(lua_State* L) {
    const auto controller = lua.checkInteger(L, 1);
    const bool allowed = lua.toBoolean(L, 2);
    const auto object = wheel();
    int selected = -1;
    if (!allowed || !object || controller < 0 || controller > 4) {
        reset();
    } else {
        // The original wheel needs only the local participant's controller.
        // Supply that view within this call, without inserting an official peer
        // or enabling Steam networking. Native wheel input/draw stays intact.
        std::array<unsigned char, layout::emoteWheel::participantBytes> participant{};
        std::array<int, 4> device{};
        device[layout::emoteWheel::controllerId / sizeof(int)] = static_cast<int>(controller);
        at<void*>(reinterpret_cast<std::uintptr_t>(participant.data()),
                  layout::emoteWheel::participantDevice) = device.data();
        const auto manager = at<std::uintptr_t>(image, j460::globals::manager);
        auto& pending = at<int>(manager, layout::manager::pendingEmote);
        const auto previousPending = pending;
        pending = -1;
        scopedParticipant = participant.data();
        {
            input::ViewScope scope(0);
            reinterpret_cast<Method>(image + j460::entry::emoteWheelUpdate)(
                reinterpret_cast<void*>(object));
        }
        scopedParticipant = nullptr;
        selected = pending;
        pending = previousPending;
    }
    lua.createTable(L, 0, 2);
    lua.pushBoolean(L, object && at<int>(object, layout::emoteWheel::state) != 0);
    lua.setField(L, -2, "open");
    lua.pushInteger(L, selected >= 0 && selected <= layout::emote::lastId ? selected + 1 : 0);
    lua.setField(L, -2, "selected");
    return 1;
}
int show(lua_State* L) {
    const auto owner = lua.checkInteger(L, 1), id = lua.checkInteger(L, 2);
    bool shown = false;
    if (owner >= 0 && owner < 4 && id >= 1 && id <= layout::emote::lastId + 1 &&
        (rooms::connected() & (1u << owner))) {
        shown = rooms::withPlayer(owner, [&] {
            const auto player = rooms::presentationPlayer();
            if (!player)
                return;
            const auto object = player + layout::player::emote;
            at<int>(object, layout::emote::id) = -1;
            using Show = void(__attribute__((thiscall))*)(void*, int, unsigned);
            reinterpret_cast<Show>(image + j460::entry::emoteShow)(reinterpret_cast<void*>(object),
                                                                   id - 1, layout::emote::duration);
        });
    }
    lua.pushBoolean(L, shown);
    return 1;
}
int count(lua_State* L) {
    lua.pushInteger(L, layout::emote::lastId + 1);
    return 1;
}
} // namespace
void reset() {
    if (const auto object = wheel()) {
        at<int>(object, layout::emoteWheel::state) = 0;
        at<float>(object, layout::emoteWheel::radius) = 0;
    }
}
bool install(std::uintptr_t base) {
    image = base;
    auto target = reinterpret_cast<void*>(image + j460::entry::emoteLocalParticipant);
    return MH_CreateHook(target, reinterpret_cast<void*>(localParticipant),
                         reinterpret_cast<void**>(&originalParticipant)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module,
                  {lua::Symbol::pushClosure, lua::Symbol::setField, lua::Symbol::createTable,
                   lua::Symbol::pushBoolean, lua::Symbol::pushInteger, lua::Symbol::checkInteger,
                   lua::Symbol::toBoolean}))
        return false;
    for (const auto& [name, function] : {std::pair<const char*, lua::Function>{"emote_poll", poll},
                                         {"emote_show", show},
                                         {"emote_count", count}}) {
        lua.pushClosure(L, function, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::emotes
