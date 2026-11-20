#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/animation_skip.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned nightmareOffset = 0x211bc, stageOffset = 0x1ba0c;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
constexpr unsigned nightmareOffset = 0x21778, stageOffset = 0x1ba78;
#endif
#include <cstring>

struct lua_State {
    std::array<long long, 3> args{};
    bool result = false, floorReady = false;
};
namespace {
namespace animation = isaac::presentation::animation;
using Address = std::uintptr_t;
std::array<unsigned char, 0x23000> manager{};
std::array<unsigned char, 0x1c000> game{};
unsigned char* image = nullptr;
int localSlot = -1, confirm = -1;
bool ending = false, guest = false, intro = false, captureInput = false;
bool triggered = false, ready = true, throwUpdate = false;
unsigned updates = 0, renders = 0, overlays = 0, shows = 0, skipped = 0;
unsigned epoch = 37, introId = 49;
template <class T> T& field(void* object, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void patch(unsigned rva, auto function) {
    image[rva] = 0xe9;
    field<std::int32_t>(image, rva + 1) =
        reinterpret_cast<Address>(function) - reinterpret_cast<Address>(image + rva + 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void __attribute__((fastcall)) update(void* scene, void*) {
    require(scene == manager.data() + nightmareOffset, "Nightmare update receiver");
    ++updates;
    if (throwUpdate)
        throw std::runtime_error("Fixture nightmare update failure");
}
void __attribute__((fastcall)) render(void* scene, void*) {
    require(scene == manager.data() + nightmareOffset, "Nightmare render receiver");
    ++renders;
}
void __attribute__((fastcall)) show(void* scene, void*, bool value) {
    require(scene == manager.data() + nightmareOffset && value, "Nightmare show ABI");
    ++shows;
}
void install() {
    require(!animation::install(0), "Missing image accepted");
    constexpr unsigned imageSize = 0x900000;
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize nightmare fixture");
    patch(backend::entry::nightmareSceneUpdate, update);
    patch(backend::entry::nightmareSceneRender, render);
    patch(backend::entry::nightmareSceneShow, show);
    field<void*>(image, backend::globals::manager) = manager.data();
    field<void*>(image, backend::globals::game) = game.data();
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    const auto base = reinterpret_cast<Address>(image);
    const std::array entries{backend::entry::nightmareSceneRender,
                             backend::entry::nightmareSceneUpdate,
                             backend::entry::nightmareSceneShow};
    for (auto collision : entries) {
        require(MH_CreateHook(image + collision, reinterpret_cast<void*>(render), nullptr) == MH_OK,
                "Prepare conflicting hook");
        require(!animation::install(base) && !animation::image, "Failed install retained state");
        for (auto entry : entries) {
            const auto result =
                MH_CreateHook(image + entry, reinterpret_cast<void*>(render), nullptr);
            require(result == (entry == collision ? MH_ERROR_ALREADY_CREATED : MH_OK),
                    "Rollback removed a foreign hook or retained an owned hook");
            if (entry != collision)
                MH_RemoveHook(image + entry);
        }
        require(MH_RemoveHook(image + collision) == MH_OK, "Remove conflicting fixture");
    }
    require(animation::install(base) && !animation::install(base), "Install once after rollback");
    animation::lua.checkInteger = [](lua_State* L, int index) { return L->args[index - 1]; };
    animation::lua.pushBoolean = [](lua_State* L, int value) { L->result = value; };
    animation::lua.pushInteger = [](lua_State*, long long) {};
    animation::lua.createTable = [](lua_State*, int, int) {};
    animation::lua.rawSetI = [](lua_State*, int, long long) {};
    animation::lua.setField = [](lua_State* L, int, const char* name) {
        if (std::strcmp(name, "floorReady") == 0)
            L->floorReady = L->result;
    };
}
void native(unsigned entry, std::initializer_list<std::uint32_t> arguments = {}) {
    const auto result =
        native_fixture::call(image + entry, manager.data() + nightmareOffset, arguments);
    require(result.balanced && result.preserved, "Nightmare wrapper changed native ABI");
}
void behavior() {
    using Kind = animation::Kind;
    lua_State L;
    field<int>(manager.data(), 8) = 5;
    field<unsigned>(manager.data(), nightmareOffset) = 1;
    require(!animation::active(), "Single-player nightmare became a network event");
    native(backend::entry::nightmareSceneUpdate);
    native(backend::entry::nightmareSceneRender);
    require(updates == 1 && renders == 1 && overlays == 0 && confirm == -1,
            "Single-player forwarding");
    localSlot = 0;
    require(animation::kind() == Kind::floor, "Shared floor dream was not selected");
    field<bool>(manager.data(), nightmareOffset + 0x5e8) = true;
    require(animation::kind() == Kind::personal, "Home dream lost personal ownership");
    field<bool>(manager.data(), nightmareOffset + 0x5e8) = false;
    L.args = {static_cast<long long>(Kind::floor), epoch, epoch};
    animation::skip(&L);
    require(L.result && animation::approved, "Valid floor consent rejected");
    native(backend::entry::nightmareSceneUpdate);
    native(backend::entry::nightmareSceneRender);
    require(updates == 2 && renders == 2 && overlays == 1 && confirm == -1,
            "Network nightmare forwarding or input restoration");
    native(backend::entry::nightmareSceneShow, {1});
    require(shows == 1 && !animation::approved, "New dream retained previous consent");
    L.args[2] = epoch - 1;
    animation::skip(&L);
    require(!L.result && !animation::approved, "Stale epoch approved a dream");
    L.args[2] = epoch;
    L.args[1] = epoch + 1;
    animation::skip(&L);
    require(!L.result, "Wrong dream identity accepted");
    triggered = true;
    animation::request(&L);
    require(L.result, "Normal confirmation did not request consent");
    captureInput = true;
    animation::request(&L);
    require(!L.result, "Chat input triggered an animation vote");
    captureInput = false;
    field<unsigned>(manager.data(), nightmareOffset) = 0;
    field<int>(manager.data(), 8) = 2;
    intro = true;
    require(animation::kind() == Kind::boss, "Boss intro selection");
    L.args = {static_cast<long long>(Kind::boss), introId, epoch};
    animation::skip(&L);
    require(L.result && skipped == 1, "Boss consent did not use native intro completion");
    animation::view(&L);
    require(L.floorReady, "Settled game did not finish floor barrier");
    field<unsigned>(game.data(), stageOffset) = 1;
    animation::view(&L);
    require(!L.floorReady, "Active native stage transition finished barrier early");
    ending = true;
    require(!animation::active(), "Ending entered animation voting");
    animation::skip(&L);
    require(!L.result && skipped == 1, "Ending allowed skip");
    ending = false;
    throwUpdate = true;
    rejects([&] { animation::update(manager.data() + nightmareOffset, nullptr); },
            "Native update exception was lost");
    require(confirm == -1, "Exceptional native update leaked confirmation scope");
    animation::approved = true;
    animation::reset();
    require(!animation::approved, "Disconnect retained consent");
}
} // namespace
namespace isaac::runtime {
int localViewSlot() {
    return localSlot;
}
bool replica() {
    return guest;
}
bool ending() {
    return ::ending;
}
std::uint32_t worldEpoch() {
    return epoch;
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned connected() {
    return 3;
}
bool stateReady() {
    return ready;
}
} // namespace isaac::rooms
namespace isaac::frontend {
bool capturesInput() {
    return captureInput;
}
void render() {
    ++overlays;
}
} // namespace isaac::frontend
namespace isaac::presentation {
unsigned playedIntro() {
    return introId;
}
bool introActive() {
    return intro;
}
std::vector<std::pair<unsigned, unsigned>> introAudiences() {
    return {{introId, 3}};
}
bool skipIntro(unsigned serial) {
    if (serial != introId)
        return false;
    ++skipped;
    return true;
}
} // namespace isaac::presentation
namespace isaac::input {
AnimationConfirmScope::AnimationConfirmScope(bool approved) : previous(confirm) {
    confirm = approved ? 1 : 0;
}
AnimationConfirmScope::~AnimationConfirmScope() {
    confirm = previous;
}
bool menuTriggered(int action, bool) {
    require(action == action::menuConfirm, "Unexpected animation input");
    return triggered;
}
} // namespace isaac::input
int main() {
    install();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release nightmare fixture");
}
