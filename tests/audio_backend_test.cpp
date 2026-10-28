#include "test_support.h"
#include "engine/versions/common/audio.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#else
#include "engine/versions/j460/entrypoints.h"
#endif
#include <limits>

struct lua_State {
    int top = 0;
    long long integer = 0;
    std::string input, output;
    bool success = false;
};
namespace {
namespace audio = isaac::audio;
namespace lan = isaac::lan;
#ifdef ISAAC_LAN_TEST_J835
namespace backend = isaac::engine::j835;
constexpr unsigned roomOffset = 0x18190, indexOffset = 0x18194, dimensionOffset = 0x1819c;
constexpr unsigned musicOffset = 0x29a78, volumeOffset = 0x29e10;
#else
namespace backend = isaac::engine::j460;
constexpr unsigned roomOffset = 0x18300, indexOffset = 0x18304, dimensionOffset = 0x1830c;
constexpr unsigned musicOffset = 0x29fbc, volumeOffset = 0x2a354;
#endif
constexpr unsigned currentOffset = 0x30c, queuedOffset = 0x310, imageSize = 0x890000;
using Address = std::uintptr_t;
using Music = void(__attribute__((thiscall)) *)(void*, int, float);
using Sound = void(__attribute__((thiscall)) *)(void*, int, float, int, bool, float, float);
unsigned char* image;
std::array<unsigned char, 0x18400> game{};
std::array<unsigned char, 0x2a400> manager{};
std::array<unsigned char, 8> room{}, sfx{};
bool replica = false, failSelector = false;
unsigned tick = 100, epoch = 1, audience = 1, selectorCalls = 0;
int localSlot = 0;
std::string lastError;
struct SoundCall {
    int id;
    float volume;
    int delay;
    bool loop;
    float pitch, pan;
};
struct MusicCall {
    bool fade;
    int id;
    float parameter;
};
std::vector<SoundCall> soundCalls;
std::vector<MusicCall> musicCalls;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void* musicManager() {
    return manager.data() + musicOffset;
}
unsigned& current() {
    return field<unsigned>(musicManager(), currentOffset);
}
unsigned& queued() {
    return field<unsigned>(musicManager(), queuedOffset);
}
void setRoom(int index, int dimension = 0) {
    field<int>(game.data(), indexOffset) = index;
    field<int>(game.data(), dimensionOffset) = dimension;
}
void playMusic(int id, float parameter = 0.4f, bool fade = false) {
    reinterpret_cast<Music>(
        image + (fade ? backend::entry::musicCrossfade : backend::entry::musicPlay))(musicManager(),
                                                                                     id, parameter);
}
void playSound(int id = 12, float volume = 0.6f) {
    reinterpret_cast<Sound>(image + backend::entry::audioPlay)(sfx.data(), id, volume, 7, true,
                                                               1.2f, -0.25f);
}
void __attribute__((thiscall)) nativeSound(void* receiver, int id, float volume, int delay,
                                           bool loop, float pitch, float pan) {
    require(receiver == sfx.data(), "Sound receiver changed");
    soundCalls.push_back({id, volume, delay, loop, pitch, pan});
}
void __attribute__((thiscall)) nativeMusic(void* receiver, int id, float parameter) {
    require(receiver == musicManager(), "Music receiver changed");
    musicCalls.push_back({false, id, parameter});
    current() = id;
    queued() = 0;
}
void __attribute__((thiscall)) nativeFade(void* receiver, int id, float parameter) {
    require(receiver == musicManager(), "Music crossfade receiver changed");
    musicCalls.push_back({true, id, parameter});
    current() = id;
    queued() = 0;
}
void __attribute__((thiscall)) nativeSelector(void* receiver) {
    require(receiver == room.data() && current() == 0 && queued() == 0,
            "Room selector borrowed another room's music or wrong object");
    ++selectorCalls;
    if (failSelector) {
        current() = 99;
        queued() = 88;
        throw std::runtime_error("selector failed");
    }
    playMusic(10);
    queued() = 11; // Native Queue writes this field directly without a hook.
}
void patch(unsigned rva, auto function) {
    image[rva] = 0xe9;
    field<unsigned>(image, rva + 1) =
        reinterpret_cast<Address>(function) - reinterpret_cast<Address>(image + rva + 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void setup() {
    require(!audio::install(0), "Missing image installed native hooks");
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Allocate isolated audio fixture");
    patch(backend::entry::audioPlay, nativeSound);
    patch(backend::entry::musicPlay, nativeMusic);
    patch(backend::entry::musicCrossfade, nativeFade);
    patch(backend::entry::roomUpdateMusic, nativeSelector);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(image, backend::globals::manager) = reinterpret_cast<Address>(manager.data());
    field<Address>(game.data(), roomOffset) = reinterpret_cast<Address>(room.data());
    field<float>(manager.data(), volumeOffset) = 0.75f;
    // Guard the options fields adjacent to the native music volume.
    field<float>(manager.data(), volumeOffset - 4) = 0.125f;
    field<float>(manager.data(), volumeOffset + 4) = 0.25f;
    auto* foreign = image + backend::entry::musicCrossfade;
    require(MH_CreateHook(foreign, reinterpret_cast<void*>(nativeFade), nullptr) == MH_OK,
            "Create foreign audio conflict");
    require(!audio::install(reinterpret_cast<Address>(image)), "Partial audio install succeeded");
    for (unsigned rva : {backend::entry::audioPlay, backend::entry::musicPlay}) {
        require(MH_CreateHook(image + rva, reinterpret_cast<void*>(nativeSound), nullptr) == MH_OK,
                "Failed audio install retained a hook");
        require(MH_RemoveHook(image + rva) == MH_OK, "Remove rollback probe");
    }
    require(MH_CreateHook(foreign, reinterpret_cast<void*>(nativeFade), nullptr) ==
                MH_ERROR_ALREADY_CREATED,
            "Rollback removed a foreign audio hook");
    require(MH_RemoveHook(foreign) == MH_OK && audio::install(reinterpret_cast<Address>(image)),
            "Audio installation did not recover");
    require(!audio::install(reinterpret_cast<Address>(image)),
            "Duplicate audio installation succeeded");
    audio::lua.getTop = [](lua_State* L) { return L->top; };
    audio::lua.checkInteger = [](lua_State* L, int) { return L->integer; };
    audio::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    audio::lua.pushLString = [](lua_State* L, const char* data, std::size_t size) {
        L->output.assign(data, size);
        return L->output.c_str();
    };
    audio::lua.pushBoolean = [](lua_State* L, int result) { L->success = result != 0; };
}
void reset() {
    audio::reset();
    replica = false;
    tick = 100;
    epoch = 1;
    audience = 1;
    localSlot = 0;
    selectorCalls = 0;
    failSelector = false;
    soundCalls.clear();
    musicCalls.clear();
    lastError.clear();
    current() = 41;
    queued() = 43;
    setRoom(70);
}
std::string soundEvents(int slot) {
    lua_State L;
    L.integer = slot;
    require(audio::capture(&L) == 1, "Capture sounds result count");
    return L.output;
}
struct Request {
    unsigned mode, id;
    float parameter;
    unsigned queue;
};
std::string encode(Request value) {
    lan::Writer w(lan::Message::world);
    w.u8(value.mode);
    w.u32(value.id);
    w.u32(std::bit_cast<unsigned>(value.parameter));
    w.u32(value.queue);
    return {reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1};
}
std::string captureMusic() {
    lua_State L;
    require(audio::musicState(&L) == 1, "Capture music result count");
    return L.output;
}
bool applyMusic(const std::string& bytes) {
    lua_State L;
    L.top = 1;
    L.input = bytes;
    require(audio::musicState(&L) == 1, "Apply music result count");
    return L.success;
}
void soundRouting() {
    reset();
    audience = 0;
    playSound();
    require(soundCalls.size() == 1 && soundCalls.back().volume == 0.6f && soundEvents(0).empty(),
            "Unscoped sound was intercepted or sent");
    audience = 2;
    playSound();
    const auto& native = soundCalls.back();
    require(native.volume == 0 && native.id == 12 && native.delay == 7 && native.loop &&
                native.pitch == 1.2f && native.pan == -0.25f,
            "Background sound changed native metadata");
    lan::Writer expected(lan::Message::world);
    expected.u32(1);
    expected.u32(100);
    expected.u32(12);
    expected.u32(std::bit_cast<unsigned>(0.6f));
    expected.u32(7);
    expected.u8(1);
    expected.u32(std::bit_cast<unsigned>(1.2f));
    expected.u32(std::bit_cast<unsigned>(-0.25f));
    require(soundEvents(1) == std::string(reinterpret_cast<const char*>(expected.bytes.data() + 1),
                                          expected.bytes.size() - 1) &&
                soundEvents(0).empty(),
            "Sound wire bytes or audience changed");
    require(soundEvents(-1).empty() && soundEvents(4).empty(), "Invalid slot captured sounds");
    tick = 130;
    require(!soundEvents(1).empty(), "Boundary-aged sound expired too early");
    tick = 131;
    require(soundEvents(1).empty(), "Expired sound was resent");
    replica = true;
    const auto calls = soundCalls.size();
    playSound();
    require(soundCalls.size() == calls, "Replica played another room's sound");
    audience = 1;
    playSound();
    require(soundCalls.size() == calls + 1 && soundCalls.back().volume == 0.6f &&
                soundEvents(0).empty(),
            "Replica dropped local sound or retransmitted it");
    reset();
    audience = 1;
    for (unsigned i = 0; i < 520; ++i)
        playSound(i);
    const auto bytes = soundEvents(0);
    require(bytes.size() == 512 * 29, "Sound queue was not bounded");
    lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size()});
    require(reader.u32() == 9 && reader.u32() == tick && reader.u32() == 8,
            "Sound eviction lost serial ordering");
    audio::reset();
    require(soundEvents(0).empty(), "Session reset retained sound events");
}
void roomMusic() {
    reset();
    {
        audio::RoomScope outer;
        require(current() == 0 && queued() == 0, "Unknown room borrowed physical music");
        playMusic(10);
        queued() = 11;
        require(musicCalls.empty() && captureMusic() == encode({1, 10, 0.4f, 11}),
                "Scoped selection became audible or lost queued track");
        setRoom(71, 1);
        {
            audio::RoomScope nested;
            require(current() == 0 && queued() == 0, "Different dimension inherited outer music");
            playMusic(20, 0.2f, true);
            queued() = 21;
            require(captureMusic() == encode({2, 20, 0.2f, 21}), "Nested room music was lost");
        }
        setRoom(70);
        require(current() == 10 && queued() == 11 && musicCalls.empty(),
                "Nested scope corrupted outer IDs");
    }
    require(current() == 41 && queued() == 43, "Leaving room did not restore physical IDs");
    {
        audio::RoomScope scope;
        audio::present();
        require(musicCalls.size() == 1 && musicCalls.back().id == 11 &&
                    musicCalls.back().parameter == 0.75f && !musicCalls.back().fade,
                "Room entry did not select queued track at native options volume");
        require(current() == 10 && queued() == 11, "Presentation overwrote virtual IDs");
        audio::present();
        require(musicCalls.size() == 1, "Repeated snapshot restarted music");
    }
    require(current() == 11 && queued() == 0, "Room exit restored obsolete physical IDs");
    {
        audio::RoomScope scope;
        playMusic(12, 0.05f, true);
        queued() = 13;
    }
    // Native update exits its room scope before the subsequent render scope.
    {
        audio::RoomScope scope;
        audio::present();
        require(musicCalls.size() == 2 && musicCalls.back().fade && musicCalls.back().id == 12 &&
                    musicCalls.back().parameter == 0.05f,
                "Same-room change lost native fading");
    }
    require(current() == 12 && queued() == 13, "Same-room queue was lost");
    // Queue finishes physically outside room scopes. A matching authoritative state is not a
    // restart.
    playMusic(13, 0.75f);
    const auto calls = musicCalls.size();
    {
        audio::RoomScope scope;
        audio::present();
    }
    require(musicCalls.size() == calls && current() == 13, "Completed queue restarted its track");
    setRoom(72);
    {
        audio::RoomScope scope;
        playMusic(13);
        audio::present();
    }
    require(musicCalls.size() == calls, "Same track restarted across rooms");
    ++epoch;
    {
        audio::RoomScope scope;
        playMusic(13);
        audio::present();
    }
    require(musicCalls.size() == calls + 1, "New floor reused stale track ownership");
}
void selectorCleanup() {
    reset();
    {
        audio::RoomScope scope;
        current() = 7;
        queued() = 8;
        failSelector = true;
        require(captureMusic().empty() && lastError == "selector failed" && current() == 7 &&
                    queued() == 8,
                "Failed selector leaked temporary native IDs");
        failSelector = false;
        require(captureMusic() == encode({1, 10, 0.4f, 11}) && current() == 7 && queued() == 8 &&
                    musicCalls.empty() && selectorCalls == 2,
                "Selector failed to retry or played physical music");
        require(captureMusic() == encode({1, 10, 0.4f, 11}) && selectorCalls == 2,
                "Known room reran native selection");
    }
    require(current() == 41 && queued() == 43, "Selector scope leaked its borrowed IDs");
}
void replicaMusic() {
    reset();
    replica = true;
    const auto first = encode({2, 30, 0.1f, 31});
    require(applyMusic(first), "Replica rejected valid music");
    {
        audio::RoomScope scope;
        playMusic(99);
        require(captureMusic() == first && musicCalls.empty(),
                "Native initialization replaced authority");
        audio::present();
    }
    require(current() == 31 && queued() == 0 && musicCalls.size() == 1,
            "Replica room entry did not use authoritative queued track");
    require(applyMusic(first), "Repeated snapshot failed");
    {
        audio::RoomScope scope;
        audio::present();
    }
    require(musicCalls.size() == 1, "Repeated replica snapshot restarted music");
    require(applyMusic(encode({2, 32, 0.07f, 33})), "Replica rejected same-room change");
    {
        audio::RoomScope scope;
        audio::present();
    }
    require(musicCalls.back().fade && musicCalls.back().id == 32 && queued() == 33,
            "Replica same-room queue lost crossfade");
    playMusic(33, 0.75f);
    const auto calls = musicCalls.size();
    require(captureMusic() == encode({2, 32, 0.07f, 33}),
            "Physical queue completion rewrote authority");
    require(applyMusic(encode({1, 33, 0.75f, 0})), "Replica rejected queue completion");
    {
        audio::RoomScope scope;
        audio::present();
    }
    require(musicCalls.size() == calls, "Confirmed queue completion restarted music");
    for (const auto& bad : {encode({3, 1, 0, 0}), encode({1, ~0u, 0, 0}), encode({1, 1, 0, ~0u}),
                            encode({1, 1, std::numeric_limits<float>::infinity(), 0}),
                            std::string(12, '\0'), first + 'x'}) {
        require(!applyMusic(bad) && !lastError.empty(), "Malformed music reached native playback");
    }
    require(captureMusic() == encode({1, 33, 0.75f, 0}), "Rejected snapshot changed music state");
    replica = false;
    require(!applyMusic(first), "Authority accepted replica-only state");
    audio::reset();
    replica = true;
    require(captureMusic() == encode({0, 0, 0, 0}), "Session reset retained prior music");
    require(applyMusic(first), "Rejoined session rejected music");
    {
        audio::RoomScope scope;
        audio::present();
    }
    require(musicCalls.size() == calls + 1, "Rejoined session retained played snapshot cache");
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
int localViewSlot() {
    return localSlot;
}
std::uint32_t tick() {
    return ::tick;
}
std::uint32_t worldEpoch() {
    return epoch;
}
void abort(const std::string& reason) {
    lastError = reason;
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned soundAudience() {
    return audience;
}
} // namespace isaac::rooms
int main() {
    try {
        setup();
        soundRouting();
        roomMusic();
        selectorCleanup();
        replicaMusic();
        require(field<float>(manager.data(), volumeOffset - 4) == 0.125f &&
                    field<float>(manager.data(), volumeOffset + 4) == 0.25f,
                "Audio modified adjacent options");
        require(MH_Uninitialize() == MH_OK, "Remove audio fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS native audio ABI, room ownership, queues, wire bytes and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
