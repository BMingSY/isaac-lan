#include "engine/lua_api.h"
#include "engine/rewind.h"
#include "compat/items/rewind_targets.h"
#include "compat/routes/home.h"
#include "compat/routes/hourglass.h"
#include "engine/save.h"
#include "engine/versions/common/rewind_bindings.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <optional>

namespace isaac::rewind {
namespace {
using Address = std::uintptr_t;
using engine::native_rewind::bindings;
constexpr int rewindAnimation = 12, homeAnimation = 6;
constexpr int minimumRoomIndex = -20, roomIndexLimit = 169;
constexpr int minimumDirection = -1, directionLimit = 8;
constexpr int maximumAnimation = 22, maximumDimension = 2;
bool installed;
Address image;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
Address game() {
    return image ? at<Address>(image, bindings.game) : 0;
}
struct Checkpoint {
    std::vector<std::uint8_t> game;
    std::vector<rooms::SavedLocation> locations;
    decltype(lan::Progress::counters) counters{};
    unsigned door = 0, tick = 0;
};
struct NativeTransition {
    int index, direction, animation, dimension;
};
bool valid(const NativeTransition& value) {
    return value.index >= minimumRoomIndex && value.index < roomIndexLimit &&
           value.direction >= minimumDirection && value.direction < directionLimit &&
           value.animation >= 0 && value.animation <= maximumAnimation && value.dimension >= 0 &&
           value.dimension <= maximumDimension;
}
std::optional<NativeTransition> selectedTransition() {
    const auto transition = game() + bindings.gameLayout.transition;
    if (at<int>(transition, bindings.transition.state) == 0)
        return std::nullopt;
    NativeTransition result{at<int>(transition, bindings.transition.index),
                            at<int>(transition, bindings.transition.direction),
                            at<int>(transition, bindings.transition.animation),
                            at<int>(transition, bindings.transition.dimension)};
    if (!valid(result))
        throw std::runtime_error("Invalid native hourglass transition");
    return result;
}
compat::items::RewindTargets<Checkpoint, lan::maxPlayers> targets;
bool* nativeHome = nullptr;
struct RouteScope {
    bool* previous;
    explicit RouteScope(bool& home) : previous(nativeHome) {
        nativeHome = &home;
    }
    ~RouteScope() {
        nativeHome = previous;
    }
    RouteScope(const RouteScope&) = delete;
};
using Store = void(__stdcall*)(int);
Store originalStore;
void storeCheckpoint(int door) {
    auto& flags = at<std::uint64_t>(game(), bindings.gameLayout.stateFlags);
    const auto checkpointFlags = compat::routes::hourglassCheckpointFlags(
        at<int>(game(), bindings.gameLayout.stage), at<int>(game(), bindings.gameLayout.stageType),
        flags);
    struct Restore {
        std::uint64_t& field;
        std::uint64_t value, mask;
        ~Restore() {
            field = (field & ~mask) | (value & mask);
        }
    } restore{flags, flags, flags ^ checkpointFlags};
    flags = checkpointFlags;
    originalStore(door);
}
void __stdcall store(int door) {
    // Native room entry uses two process-wide buffers. LAN keeps one last
    // entry per controller, so background entries cannot replace another
    // player's rewind target. Native loading/restoration retains its own work.
    if (!rooms::virtualized())
        originalStore(door);
}
Address actor(unsigned slot) {
    const auto current = game();
    if (!current)
        return 0;
    const auto roster = current + bindings.gameLayout.players;
    const auto first = at<Address>(roster, 0), last = at<Address>(roster, sizeof(Address));
    if (!first || last < first || (last - first) % sizeof(Address))
        return 0;
    for (auto p = first; p < last; p += sizeof(Address)) {
        const auto player = at<Address>(p, 0);
        if (player && at<int>(player, bindings.player.controller) == static_cast<int>(slot + 1) &&
            at<unsigned>(player, bindings.player.variant) == 0)
            return player;
    }
    return 0;
}
std::vector<std::uint8_t> encode(const Checkpoint& checkpoint, unsigned slot,
                                 const std::optional<NativeTransition>& transition = std::nullopt) {
    const auto user = actor(slot);
    if (!user)
        throw std::runtime_error("Hourglass user is missing");
    lan::Writer w(lan::Message::stage);
    w.u8(slot);
    w.u32(at<unsigned>(user, bindings.player.uses));
    w.u32(at<unsigned>(user, bindings.player.floorUses));
    w.u32(checkpoint.door);
    w.u32(checkpoint.tick);
    for (auto value : checkpoint.counters)
        w.u32(value);
    w.u8(checkpoint.locations.size());
    for (auto p : checkpoint.locations) {
        w.u32(p.dimension);
        w.u32(p.index);
        w.u32(std::bit_cast<unsigned>(p.x));
        w.u32(std::bit_cast<unsigned>(p.y));
    }
    w.blob(checkpoint.game);
    w.u8(transition.has_value());
    if (transition) {
        w.u32(transition->index);
        w.u32(transition->direction);
        w.u32(transition->animation);
        w.u32(transition->dimension);
    }
    w.u64(lan::snapshotHash(w.bytes));
    return w.bytes;
}
bool startRewind(std::span<const std::uint8_t> bytes) {
    if (bytes.size() < 8)
        return false;
    lan::Reader checksum(bytes.last(8));
    if (checksum.u64() != lan::snapshotHash(bytes.first(bytes.size() - 8)))
        return false;
    lan::Reader r(bytes.first(bytes.size() - 8));
    if (r.u8() != static_cast<unsigned>(lan::Message::stage))
        return false;
    const auto slot = r.u8();
    if (slot >= lan::maxPlayers)
        return false;
    const auto uses = r.u32(), floorUses = r.u32();
    Checkpoint checkpoint;
    checkpoint.door = r.u32();
    checkpoint.tick = r.u32();
    for (auto& value : checkpoint.counters)
        value = r.u32();
    const auto count = r.u8();
    if (count < 2 || count > lan::maxPlayers || slot >= count)
        return false;
    for (unsigned i = 0; i < count; ++i) {
        rooms::SavedLocation p{static_cast<int>(r.u32()), static_cast<int>(r.u32()),
                               std::bit_cast<float>(r.u32()), std::bit_cast<float>(r.u32())};
        if (p.dimension < 0 || p.dimension > maximumDimension || p.index < minimumRoomIndex ||
            p.index >= roomIndexLimit || !std::isfinite(p.x) || !std::isfinite(p.y))
            return false;
        checkpoint.locations.push_back(p);
    }
    checkpoint.game = r.blob();
    const auto hasTransition = r.u8();
    if (hasTransition > 1)
        return false;
    std::optional<NativeTransition> selected;
    if (hasTransition) {
        selected = NativeTransition{static_cast<int>(r.u32()), static_cast<int>(r.u32()),
                                    static_cast<int>(r.u32()), static_cast<int>(r.u32())};
        if (!valid(*selected))
            return false;
    }
    r.finish();
    // The shared wire keeps its existing counter count. A smaller native
    // progress array supplies a zero tail, never adjacent object memory.
    for (unsigned i = bindings.buffer.counterCount; i < checkpoint.counters.size(); ++i)
        if (checkpoint.counters[i] != 0)
            return false;
    if (!game())
        return false;
    // Rejoin the native complete roster before GameState restoration. The
    // original hourglass transition owns entities, inventory, RNG and effects.
    if (runtime::replica())
        rooms::beforeStart();
    else if (!rooms::prepareRewind(slot))
        return false;
    const auto buffer = game() + bindings.gameLayout.buffers;
    if (!save::decodeAt(image, buffer + bindings.buffer.state, checkpoint.game))
        return false;
    at<bool>(buffer, bindings.buffer.valid) = true;
    at<bool>(buffer + bindings.buffer.stride, bindings.buffer.valid) = false;
    at<unsigned>(buffer, bindings.buffer.door) = checkpoint.door;
    at<unsigned>(buffer, bindings.buffer.tick) = checkpoint.tick;
    for (unsigned i = 0; i < bindings.buffer.counterCount; ++i)
        at<unsigned>(buffer, bindings.buffer.counters + i * sizeof(unsigned)) =
            checkpoint.counters[i];
    at<int>(game(), bindings.gameLayout.selectedBuffer) = 0;
    const auto user = actor(slot);
    if (!user)
        return false;
    at<unsigned>(user, bindings.player.uses) = uses;
    at<unsigned>(user, bindings.player.floorUses) = floorUses;
    using Transition = void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
    const auto location = checkpoint.locations[slot];
    bool home = false;
    if (!runtime::replica()) {
        RouteScope route(home);
        reinterpret_cast<Transition>(image + bindings.roomTransition)(
            reinterpret_cast<void*>(game()), location.index, 0, rewindAnimation,
            reinterpret_cast<void*>(user), location.dimension);
    }
    if (home && !runtime::replica()) {
        // Publish only the native-selected Home transaction. No rewind event
        // or old-floor player locations may precede this global departure.
        runtime::beginStage(false, homeAnimation);
        using Stage = void(__attribute__((thiscall))*)(void*, bool, int, void*);
        reinterpret_cast<Stage>(image + bindings.stageTransition)(reinterpret_cast<void*>(game()),
                                                                  false, homeAnimation, nullptr);
        rooms::resumeAfterTransition({});
        return true;
    }
    if (!runtime::replica())
        selected = selectedTransition();
    if (runtime::replica() && selected) {
        // Replay the authority's actual native choice, including Greed's
        // starting-room teleport. A local viewport cannot select another route.
        const auto transition = game() + bindings.gameLayout.transition;
        reinterpret_cast<Transition>(image + bindings.replayTransition)(
            reinterpret_cast<void*>(transition), selected->index, selected->direction,
            selected->animation, reinterpret_cast<void*>(user), selected->dimension);
        if (bindings.finishReplay)
            bindings.finishReplay(game());
    }
    if (!runtime::replica())
        runtime::beginRewind(encode(checkpoint, slot, selected));
    // Only native animation 12 restores GameState. Greed's error-room
    // teleport and native early returns must keep their actual landing.
    if (selected && selected->animation == rewindAnimation)
        rooms::resumeAfterTransition(std::move(checkpoint.locations));
    else
        rooms::resumeAfterTransition({});
    return true;
}
isaac::lua::API lua{};
int beginLua(lua_State* L) {
    try {
        std::size_t size;
        const auto bytes = lua.checkString(L, 1, &size);
        lua.pushBoolean(L, runtime::replica() &&
                               startRewind({reinterpret_cast<const std::uint8_t*>(bytes), size}));
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int resetLua(lua_State*) {
    reset();
    return 0;
}
} // namespace
void remember(unsigned slot, int door, const std::vector<rooms::SavedLocation>& locations) {
    if (runtime::replica() || slot >= lan::maxPlayers || locations.empty() || !game() ||
        !originalStore)
        return;
    at<int>(game(), bindings.gameLayout.selectedBuffer) = -1;
    storeCheckpoint(door);
    const auto buffer = game() + bindings.gameLayout.buffers;
    at<bool>(buffer + bindings.buffer.stride, bindings.buffer.valid) = false;
    if (!at<bool>(buffer, bindings.buffer.valid))
        return;
    Checkpoint checkpoint;
    checkpoint.game = save::encodeAt(image, buffer + bindings.buffer.state);
    if (checkpoint.game.empty())
        throw std::runtime_error("Cannot capture native hourglass state");
    checkpoint.locations = locations;
    checkpoint.door = at<unsigned>(buffer, bindings.buffer.door);
    checkpoint.tick = at<unsigned>(buffer, bindings.buffer.tick);
    for (unsigned i = 0; i < bindings.buffer.counterCount; ++i)
        checkpoint.counters[i] =
            at<unsigned>(buffer, bindings.buffer.counters + i * sizeof(unsigned));
    targets.remember(slot, std::move(checkpoint));
}
bool request(unsigned slot) {
    return targets.request(slot);
}
void cancelPending() {
    targets.take();
}
bool executePending() {
    const auto pending = targets.take();
    if (!pending)
        return false;
    const auto slot = *pending;
    const auto bytes = encode(targets.at(slot), slot);
    if (!startRewind(bytes))
        throw std::runtime_error("Native hourglass rewind failed");
    return true;
}
bool captureStage(bool same, int animation) {
    if (!nativeHome || !compat::routes::homeTransition(same, animation))
        return false;
    *nativeHome = true;
    return true;
}
void reset() {
    targets.reset();
}
bool install(Address base) {
    if (!base || installed)
        return false;
    image = base;
    const auto target = reinterpret_cast<void*>(image + bindings.store);
    if (MH_CreateHook(target, reinterpret_cast<void*>(store),
                      reinterpret_cast<void**>(&originalStore)) == MH_OK) {
        if (MH_EnableHook(target) == MH_OK) {
            installed = true;
            return true;
        }
        MH_RemoveHook(target);
    }
    image = 0;
    originalStore = nullptr;
    return false;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    lua.pushClosure(L, beginLua, 0);
    lua.setField(L, -2, "rewind_begin");
    lua.pushClosure(L, resetLua, 0);
    lua.setField(L, -2, "rewind_reset");
    return true;
}
} // namespace isaac::rewind
