#include "engine/bootstrap.h"
#include "engine/versions/common/bootstrap_bindings.h"
#include "engine/rooms.h"
#include "engine/input.h"
#include "engine/frontend.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>
#include <bit>
#include <cstdio>

namespace isaac::engine::native_bootstrap {
namespace {
template <class T> T& field(Address base, std::size_t offset) {
    return *reinterpret_cast<T*>(base + offset);
}
} // namespace
void restoreRoomPositions(Address room) {
    if (!room)
        return;
    const auto& layout = bindings.layout;
    const auto list = room + layout.room.entities + layout.entityList.renderArray;
    const auto data = field<Address>(list, layout.entityList.data);
    if (!data)
        return;
    for (unsigned i = 0; i < field<unsigned>(list, layout.entityList.count); ++i) {
        const auto entity = field<Address>(data, i * sizeof(Address));
        if (entity && field<bool>(entity, layout.entity.interpolated)) {
            field<float>(entity, layout.entity.positionX) =
                field<float>(entity, layout.entity.previousX);
            field<float>(entity, layout.entity.positionY) =
                field<float>(entity, layout.entity.previousY);
            field<bool>(entity, layout.entity.interpolated) = false;
        }
    }
}
} // namespace isaac::engine::native_bootstrap
namespace isaac::engine::bootstrap {
namespace {
using native_bootstrap::Address;
using native_bootstrap::bindings;
using native_bootstrap::field;
Address image;
native_bootstrap::Logger log;
rooms::RoomCall originalRoomUpdate, originalGameRender;
native_bootstrap::HalfUpdate originalHalfUpdate;
bool updatesInstalled = false, renderingInstalled = false;
constexpr auto roomUpdateFailure = startup::Code::roomUpdate;
constexpr auto halfUpdateFailure = startup::Code::halfUpdate;
constexpr auto renderingFailure = startup::Code::rendering;
lua::API lua;
template <class T> bool read(std::uintptr_t address, T& value) {
    SIZE_T count = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(address), &value,
                             sizeof(T), &count) &&
           count == sizeof(T);
}
void __attribute__((fastcall)) updateForeground(void* room, void*) {
    if (rooms::update(room, originalRoomUpdate))
        return;
    if (bindings.probe && bindings.probe->update(room, originalRoomUpdate))
        return;
    originalRoomUpdate(room);
}
void __attribute__((fastcall)) renderLocalRoom(void* game, void*) {
    input::ViewScope inputView(runtime::localViewSlot());
    runtime::present();
    frontend::prepareView();
    if (!rooms::render(game, originalGameRender, runtime::localViewSlot()) &&
        !(bindings.probe &&
          bindings.probe->render(game, originalGameRender, runtime::localViewSlot())))
        originalGameRender(game);
    frontend::render();
}
void __cdecl updateHalfFrames() {
    if (!runtime::halfAllowed())
        return;
    runtime::halfStarted();
    if (!rooms::half(originalHalfUpdate)) {
        originalHalfUpdate();
        if (bindings.probe)
            bindings.probe->half(originalHalfUpdate);
    }
    // Completion publishes authoritative state: never report it if update threw.
    runtime::halfCompleted();
}
int traceCallback(lua_State* L) {
    const int who = static_cast<int>(lua.checkInteger(L, 1));
    static unsigned counts[3] = {};
    if (who < 1 || who > 2 || counts[who]++ >= 2)
        return 0;
    void* frames[48] = {};
    auto size = CaptureStackBackTrace(0, 48, frames, nullptr);
    std::string result = "player_callback_stack=" + std::to_string(who);
    for (unsigned i = 0; i < size; ++i) {
        auto pc = reinterpret_cast<std::uintptr_t>(frames[i]);
        if (pc >= image && pc < image + bindings.diagnosticImageSpan) {
            char address[24];
            snprintf(address, sizeof(address), " %08lx",
                     static_cast<unsigned long>(pc - image + bindings.preferredImageBase));
            result += address;
        }
    }
    log(result);
    return 0;
}
int audit(lua_State* L) {
    std::uintptr_t game = 0, room = 0, begin = 0, end = 0;
    int stage = 0, index = 0, gameFrame = 0, enteredFrame = 0;
    bool valid = image && read(image + bindings.game, game) && game &&
                 read(game + bindings.layout.game.room, room) && room && read(game, stage) &&
                 read(game + bindings.layout.game.roomIndex, index) &&
                 read(game + bindings.layout.game.frame, gameFrame) &&
                 read(room + bindings.layout.room.enteredFrame, enteredFrame) &&
                 read(game + bindings.layout.game.players, begin) &&
                 read(game + bindings.layout.game.players + bindings.layout.vector.end, end) &&
                 end >= begin && end - begin <= 32;
    const int roomFrame =
        std::bit_cast<int>(static_cast<unsigned>(gameFrame) - static_cast<unsigned>(enteredFrame));
    int players = static_cast<int>((end - begin) / sizeof(std::uintptr_t));
    if (valid)
        valid = stage == lua.checkInteger(L, 1) && index == lua.checkInteger(L, 2) &&
                roomFrame == lua.checkInteger(L, 3) && players == lua.checkInteger(L, 4);
    char line[384];
    snprintf(line, sizeof(line),
             "audit=%s game=%08lx room=%08lx stage=%d index=%d room_frame=%d players=%d",
             valid ? "PASS" : "FAIL", static_cast<unsigned long>(game),
             static_cast<unsigned long>(room), stage, index, roomFrame, players);
    log(line);
    lua.pushBoolean(L, valid);
    return 1;
}
} // namespace
startup::Code installUpdates(Address base, native_bootstrap::Logger logger) {
    if (!base || updatesInstalled)
        return roomUpdateFailure;
    image = base;
    log = logger;
    const std::array<void*, 2> targets{
        reinterpret_cast<void*>(image + bindings.entry.roomUpdate),
        reinterpret_cast<void*>(image + bindings.entry.gameUpdateHalf)};
    const std::array<void*, 2> detours{reinterpret_cast<void*>(updateForeground),
                                       reinterpret_cast<void*>(updateHalfFrames)};
    const std::array<void**, 2> originals{reinterpret_cast<void**>(&originalRoomUpdate),
                                          reinterpret_cast<void**>(&originalHalfUpdate)};
    unsigned created = 0;
    auto error = startup::Code::success;
    for (unsigned i = 0; i < targets.size(); ++i) {
        if (MH_CreateHook(targets[i], detours[i], originals[i]) != MH_OK) {
            error = i == 0 ? roomUpdateFailure : halfUpdateFailure;
            break;
        }
        ++created;
    }
    if (error == startup::Code::success)
        for (unsigned i = 0; i < targets.size(); ++i)
            if (MH_EnableHook(targets[i]) != MH_OK) {
                error = i == 0 ? roomUpdateFailure : halfUpdateFailure;
                break;
            }
    if (error != startup::Code::success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        originalRoomUpdate = nullptr;
        originalHalfUpdate = nullptr;
        image = 0;
        log = nullptr;
        return error;
    }
    updatesInstalled = true;
    if (bindings.probe)
        bindings.probe->initialize(image, log);
    return startup::Code::success;
}
startup::Code installRendering() {
    if (!updatesInstalled || renderingInstalled)
        return renderingFailure;
    auto* target = reinterpret_cast<void*>(image + bindings.entry.gameRender);
    if (MH_CreateHook(target, reinterpret_cast<void*>(renderLocalRoom),
                      reinterpret_cast<void**>(&originalGameRender)) != MH_OK)
        return renderingFailure;
    if (MH_EnableHook(target) != MH_OK) {
        MH_RemoveHook(target);
        originalGameRender = nullptr;
        return renderingFailure;
    }
    renderingInstalled = true;
    return startup::Code::success;
}
void halfUpdate() {
    if (updatesInstalled)
        updateHalfFrames();
}
void restorePositions() {
    if (!image)
        return;
    const auto game = field<Address>(image, bindings.game);
    if (game)
        native_bootstrap::restoreRoomPositions(field<Address>(game, bindings.layout.game.room));
}
bool scopeActive() {
    return bindings.probe && bindings.probe->active();
}
bool bind(lua_State* L, lua::Module module) {
    using S = lua::Symbol;
    if (!lua.load(module, {S::checkInteger, S::pushBoolean, S::pushClosure, S::setField}))
        return false;
    for (const auto& [name, fn] : std::array<std::pair<const char*, lua::Function>, 2>{
             {{"audit", audit}, {"trace_callback", traceCallback}}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    return !bindings.probe || bindings.probe->bind(L, module);
}
} // namespace isaac::engine::bootstrap
