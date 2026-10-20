#include "engine/lua_api.h"
#include "engine/audio.h"
#include "core/audio_ownership.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include <MinHook.h>
#include <bit>
#include <deque>
#include <cstring>
#include <map>
#include <optional>
#include <cmath>
#include <climits>

#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
namespace j460 = isaac::engine::j460;
namespace musicLayout = j460::layout::music;

namespace isaac::audio {
namespace {
struct Event {
    std::uint32_t serial, tick;
    unsigned audience;
    int id;
    float volume;
    int delay;
    bool loop;
    float pitch, pan;
};
std::deque<Event> events;
std::uint32_t serial = 0;
std::uintptr_t image = 0;
template <class T> T& at(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
using Key = RoomKey;
Key roomKey() {
    const auto g = at<std::uintptr_t>(image, j460::globals::game);
    return audioRoomKey(runtime::worldEpoch(), at<int>(g, 0x1830c), at<int>(g, 0x18304));
}
struct MusicState {
    unsigned mode = 0;
    int id = 0;
    float parameter = 0;
    unsigned queued = 0;
    bool operator==(const MusicState&) const = default;
};
std::map<Key, MusicState> music;
std::optional<std::pair<Key, MusicState>> played;
using MusicCall = void(__attribute__((thiscall)) *)(void*, int, float);
MusicCall originalMusicPlay = nullptr, originalMusicFade = nullptr;
unsigned scopeDepth = 0;
std::array<unsigned, 2> audibleIDs{};
unsigned playedSounds = 0, filteredSounds = 0;
unsigned playedMusic = 0, fadedMusic = 0;
int lastSoundID = 0;
std::map<int, unsigned> playedSoundIDs;
void captureQueuedMusic(std::uintptr_t manager) {
    if (runtime::replica())
        return;
    const auto found = music.find(roomKey());
    if (found != music.end() &&
        at<unsigned>(manager, musicLayout::currentId) == static_cast<unsigned>(found->second.id))
        found->second.queued = at<unsigned>(manager, musicLayout::queuedId);
}
void musicCall(void* manager, int id, float parameter, unsigned mode, MusicCall original) {
    const auto audience = rooms::soundAudience();
    if (audience) {
        if (runtime::replica() && !audible(audience, runtime::localViewSlot()))
            return;
        if (runtime::replica()) {
            // Room initialization cannot replace the authoritative selection.
            // Physical queue completion runs outside room scopes; let it play,
            // without turning a repeated snapshot into a fresh jingle request.
            if (!scopeDepth)
                original(manager, id, parameter);
            return;
        }
        music[roomKey()] = {mode, id, parameter};
        if (scopeDepth) {
            // Native room music selection reads these IDs directly. Give it
            // its own request, without making a background room audible.
            at<unsigned>(reinterpret_cast<std::uintptr_t>(manager), musicLayout::currentId) = id;
            at<unsigned>(reinterpret_cast<std::uintptr_t>(manager), musicLayout::queuedId) = 0;
            return;
        }
        if (!audible(audience, runtime::localViewSlot()))
            return;
        played = std::pair{roomKey(), music[roomKey()]};
    }
    (mode == 1 ? playedMusic : fadedMusic)++;
    original(manager, id, parameter);
}
void __attribute__((fastcall)) musicPlay(void* manager, void*, int id, float volume) {
    musicCall(manager, id, volume, 1, originalMusicPlay);
}
void __attribute__((fastcall)) musicFade(void* manager, void*, int id, float rate) {
    musicCall(manager, id, rate, 2, originalMusicFade);
}
using Play = void(__attribute__((thiscall)) *)(void*, int, float, int, bool, float, float);
Play originalPlay = nullptr;
void __attribute__((fastcall)) play(void* manager, void*, int id, float volume, int delay,
                                    bool loop, float pitch, float pan) {
    const auto audience = rooms::soundAudience();
    if (runtime::replica() && !audible(audience, runtime::localViewSlot())) {
        ++filteredSounds;
        return;
    }
    if (audience && !runtime::replica()) {
        events.push_back(
            {++serial, runtime::tick(), audience, id, volume, delay, loop, pitch, pan});
        while (events.size() > 512)
            events.pop_front();
        // Background rooms retain gameplay and send their sounds to occupants.
        if (!audible(audience, runtime::localViewSlot()))
            volume = 0;
    }
    if (volume > 0) {
        ++playedSounds;
        lastSoundID = id;
        ++playedSoundIDs[id];
    }
    originalPlay(manager, id, volume, delay, loop, pitch, pan);
}
isaac::lua::API lua{};
void ensureRoomMusic() {
    if (runtime::replica() || music.contains(roomKey()))
        return;
    // StartGame selects its first track before room virtualization starts.
    // A later room can also request the already selected track and skip Play.
    // Evaluate that room once with empty virtual IDs, without changing the
    // physical channels. Its native selector supplies the correct room track.
    const auto manager =
        at<std::uintptr_t>(image, j460::globals::manager) + j460::layout::manager::music;
    const auto previous = std::array{at<unsigned>(manager, musicLayout::currentId),
                                     at<unsigned>(manager, musicLayout::queuedId)};
    at<unsigned>(manager, musicLayout::currentId) = at<unsigned>(manager, musicLayout::queuedId) =
        0;
    const auto g = at<std::uintptr_t>(image, j460::globals::game);
    using RoomMusic = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<RoomMusic>(image + j460::entry::roomUpdateMusic)(
        reinterpret_cast<void*>(at<std::uintptr_t>(g, 0x18300)));
    if (!music.contains(roomKey()))
        music[roomKey()] = {0, 0, 0};
    captureQueuedMusic(manager);
    at<unsigned>(manager, musicLayout::currentId) = previous[0];
    at<unsigned>(manager, musicLayout::queuedId) = previous[1];
}
int status(lua_State* L) {
    const auto manager =
        at<std::uintptr_t>(image, j460::globals::manager) + j460::layout::manager::music;
    lan::Writer w(lan::Message::world);
    for (auto value : {scopeDepth ? audibleIDs[0] : at<unsigned>(manager, musicLayout::currentId),
                       at<unsigned>(manager, musicLayout::currentId), playedSounds, filteredSounds,
                       static_cast<unsigned>(lastSoundID)})
        w.u32(value);
    if (lua.getTop(L)) {
        const auto id = static_cast<int>(lua.checkInteger(L, 1));
        const auto found = playedSoundIDs.find(id);
        w.u32(found == playedSoundIDs.end() ? 0 : found->second);
    }
    w.u32(playedMusic);
    w.u32(fadedMusic);
    lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
    return 1;
}
int musicState(lua_State* L) {
    try {
        const auto key = roomKey();
        if (lua.getTop(L) == 0) {
            ensureRoomMusic();
            if (scopeDepth)
                captureQueuedMusic(at<std::uintptr_t>(image, j460::globals::manager) +
                                   j460::layout::manager::music);
            const auto found = music.find(key);
            const auto value = found == music.end() ? MusicState{} : found->second;
            lan::Writer w(lan::Message::world);
            w.u8(value.mode);
            w.u32(value.id);
            w.u32(std::bit_cast<unsigned>(value.parameter));
            w.u32(value.queued);
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply room music");
        std::size_t size = 0;
        const auto data = lua.checkString(L, 1, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(data), size});
        MusicState value;
        value.mode = r.u8();
        value.id = r.u32();
        value.parameter = std::bit_cast<float>(r.u32());
        value.queued = r.u32();
        r.finish();
        if (value.mode > 2 || value.id < 0 || value.queued > INT_MAX ||
            !std::isfinite(value.parameter))
            throw std::runtime_error("Invalid room music");
        music[key] = value;
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int capture(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto tick = runtime::tick();
    lan::Writer bytes(lan::Message::world);
    if (slot >= 0 && slot < 4)
        for (const auto& event : events) {
            if (!(event.audience & (1u << slot)) || tick - event.tick > 30)
                continue;
            bytes.u32(event.serial);
            bytes.u32(event.tick);
            bytes.u32(event.id);
            bytes.u32(std::bit_cast<std::uint32_t>(event.volume));
            bytes.u32(event.delay);
            bytes.u8(event.loop);
            bytes.u32(std::bit_cast<std::uint32_t>(event.pitch));
            bytes.u32(std::bit_cast<std::uint32_t>(event.pan));
        }
    lua.pushLString(L, reinterpret_cast<const char*>(bytes.bytes.data() + 1),
                    bytes.bytes.size() - 1);
    return 1;
}
int resetLua(lua_State*) {
    reset();
    return 0;
}
} // namespace
bool install(std::uintptr_t base) {
    image = base;
    return MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::audioPlay),
                         reinterpret_cast<void*>(play),
                         reinterpret_cast<void**>(&originalPlay)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::audioPlay)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::musicPlay),
                         reinterpret_cast<void*>(musicPlay),
                         reinterpret_cast<void**>(&originalMusicPlay)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::musicPlay)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::musicCrossfade),
                         reinterpret_cast<void*>(musicFade),
                         reinterpret_cast<void**>(&originalMusicFade)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::musicCrossfade)) == MH_OK;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField,
                           isaac::lua::Symbol::checkInteger, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::getTop,
                           isaac::lua::Symbol::pushBoolean}))
        return false;
    lua.pushClosure(L, capture, 0);
    lua.setField(L, -2, "sound_events");
    lua.pushClosure(L, musicState, 0);
    lua.setField(L, -2, "music_state");
    lua.pushClosure(L, resetLua, 0);
    lua.setField(L, -2, "sound_reset");
    lua.pushClosure(L, status, 0);
    lua.setField(L, -2, "audio_state");
    return true;
}
void reset() {
    events.clear();
    serial = 0;
    music.clear();
    played.reset();
    playedSounds = filteredSounds = 0;
    playedMusic = fadedMusic = 0;
    lastSoundID = 0;
    playedSoundIDs.clear();
}
RoomScope::RoomScope() {
    if (!image)
        return;
    manager = at<std::uintptr_t>(image, j460::globals::manager) + j460::layout::manager::music;
    previous = {at<unsigned>(manager, musicLayout::currentId),
                at<unsigned>(manager, musicLayout::queuedId)};
    if (!scopeDepth)
        audibleIDs = previous;
    if (const auto found = music.find(roomKey()); found != music.end() && found->second.mode) {
        at<unsigned>(manager, musicLayout::currentId) = found->second.id;
        at<unsigned>(manager, musicLayout::queuedId) = found->second.queued;
    } else {
        at<unsigned>(manager, musicLayout::currentId) =
            at<unsigned>(manager, musicLayout::queuedId) = 0;
    }
    ++scopeDepth;
}
RoomScope::~RoomScope() {
    if (!manager)
        return;
    // Queue() and native room transitions write the next track directly,
    // bypassing Play/Crossfade. Preserve it before restoring another room.
    captureQueuedMusic(manager);
    const auto ids = scopeDepth == 1 ? audibleIDs : previous;
    at<unsigned>(manager, musicLayout::currentId) = ids[0];
    at<unsigned>(manager, musicLayout::queuedId) = ids[1];
    --scopeDepth;
}
void present() {
    const auto key = roomKey();
    const auto found = music.find(key);
    if (found == music.end() || !found->second.mode)
        return;
    const auto next = std::pair{key, found->second};
    if (played == next)
        return;
    const auto manager =
        at<std::uintptr_t>(image, j460::globals::manager) + j460::layout::manager::music;
    const auto& m = found->second;
    const std::array virtualIDs = {at<unsigned>(manager, musicLayout::currentId),
                                   at<unsigned>(manager, musicLayout::queuedId)};
    const auto channels = scopeDepth ? audibleIDs : virtualIDs;
    if (played &&
        continueRoomTrack(played->first, key, {static_cast<unsigned>(m.id), m.queued}, channels)) {
        played = next;
        return;
    }
    if (played && played->first == key &&
        completedQueuedTrack({static_cast<unsigned>(played->second.id), played->second.queued},
                             {static_cast<unsigned>(m.id), m.queued}, channels)) {
        played = next;
        return;
    }
    if (scopeDepth) {
        at<unsigned>(manager, musicLayout::currentId) = audibleIDs[0];
        at<unsigned>(manager, musicLayout::queuedId) = audibleIDs[1];
    }
    // Entering another room must not wait for the preceding room's queued
    // jingle/crossfade. Changes within one room retain native fading.
    const bool entering = !played || played->first != key;
    if (entering) {
        ++playedMusic;
        originalMusicPlay(reinterpret_cast<void*>(manager),
                          roomEntryTrack({static_cast<unsigned>(m.id), m.queued}),
                          at<float>(manager, musicLayout::volume));
    } else {
        (m.mode == 1 ? playedMusic : fadedMusic)++;
        (m.mode == 1 ? originalMusicPlay : originalMusicFade)(reinterpret_cast<void*>(manager),
                                                              m.id, m.parameter);
    }
    at<unsigned>(manager, musicLayout::queuedId) = entering ? 0 : m.queued;
    if (scopeDepth) {
        audibleIDs = {at<unsigned>(manager, musicLayout::currentId),
                      at<unsigned>(manager, musicLayout::queuedId)};
        at<unsigned>(manager, musicLayout::currentId) = virtualIDs[0];
        at<unsigned>(manager, musicLayout::queuedId) = virtualIDs[1];
    }
    played = next;
}
} // namespace isaac::audio
