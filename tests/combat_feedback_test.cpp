// Private x86 memory and synthetic native callees only. No game is loaded.
#include "test_support.h"
#include "engine/versions/common/combat_feedback.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
namespace native = isaac::engine::j835;
constexpr unsigned seedOffset = 0x344, spriteOffset = 0x3c;
constexpr unsigned roomOffset = 0x18194, dimensionOffset = 0x1819c;
#else
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
namespace native = isaac::engine::j511;
constexpr unsigned seedOffset = 0x3ec, spriteOffset = 0x48;
constexpr unsigned roomOffset = 0x18304, dimensionOffset = 0x1830c;
#endif
// Independent fixture layouts, checked against each executable. Neither the
// native queues nor render array belong to the extension.
constexpr unsigned queueOffset = 8, recordSize = 0x38, typeOffset = 0x28, indexOffset = 0x20;
constexpr unsigned roomEntities = 0x1218, renderArray = 0x40, arrayData = 4, arrayCount = 0xc;
constexpr unsigned colorOffset = 0xa8, referenceEntity = 0x24;
#include <map>
#include <tuple>

struct lua_State {
    std::intptr_t argument = 0;
    long long integer = 0;
    bool boolean = false;
    int count = 0;
    std::size_t length = 8;
    std::array<std::uintptr_t, 2> wrapper{};
    std::vector<std::uint8_t> bytes;
    isaac::lua::Function pushed = nullptr;
    std::map<std::string, isaac::lua::Function> functions;
};
extern "C" {
__declspec(dllexport) long long luaL_checkinteger(lua_State* L, int) {
    return L->argument;
}
__declspec(dllexport) void lua_pushinteger(lua_State* L, long long value) {
    L->integer = value;
}
__declspec(dllexport) void lua_pushboolean(lua_State* L, int value) {
    L->boolean = value;
}
__declspec(dllexport) void lua_pushcclosure(lua_State* L, isaac::lua::Function fn, int) {
    L->pushed = fn;
}
__declspec(dllexport) void lua_setfield(lua_State* L, int, const char* name) {
    L->functions[name] = L->pushed;
}
__declspec(dllexport) const char* lua_pushlstring(lua_State* L, const char* value,
                                                  std::size_t size) {
    L->bytes.assign(value, value + size);
    return value;
}
__declspec(dllexport) int lua_gettop(lua_State* L) {
    return L->count;
}
__declspec(dllexport) void* lua_touserdata(lua_State* L, int) {
    return L->wrapper[1] ? L->wrapper.data() : nullptr;
}
__declspec(dllexport) std::size_t lua_rawlen(lua_State* L, int) {
    return L->length;
}

void* combatDrainEntry = nullptr;
void* combatDrainObject = nullptr;
unsigned combatDrainFlags = 0, combatDrainECX = 0, combatDrainSSE = 0;
double combatDrainX87 = 0;
__attribute__((naked)) void nativeDrain() {
    __asm__ __volatile__("pushfl\n\tpopl _combatDrainFlags\n\tmovl %ecx, _combatDrainECX\n\t"
                         "movd %xmm7, _combatDrainSSE\n\tfstpl _combatDrainX87\n\t"
                         "movl 8(%edi), %eax\n\tmovl %eax, 12(%edi)\n\tret");
}
__attribute__((naked)) void invokeDrain() {
    __asm__ __volatile__("pushl %edi\n\tmovl _combatDrainObject, %edi\n\t"
                         "movl $0x87654321, %ecx\n\tpcmpeqd %xmm7, %xmm7\n\tfld1\n\t"
                         "cmpl %eax, %eax\n\tstc\n\tcall *_combatDrainEntry\n\tpopl %edi\n\tret");
}
}

#include "support/native_entity_types.h"
#include <array>

namespace isaac::runtime {
std::uint32_t testTick = 10, testEpoch = 2;
bool testReplica = false;
std::vector<std::string> errors;
bool replica() {
    return testReplica;
}
std::uint32_t tick() {
    return testTick;
}
std::uint32_t worldEpoch() {
    return testEpoch;
}
void abort(const std::string& error) {
    errors.push_back(error);
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned testAudience = 3;
unsigned soundAudience() {
    return testAudience;
}
} // namespace isaac::rooms

namespace {
namespace feedback = isaac::combat_feedback;
using Address = std::uintptr_t;
enum class Result {
    contactOnly,
    ignored,
    flash,
    rejected,
    nested,
    nestedSame,
    throws,
    retiresSource
};
Result behavior = Result::contactOnly;
std::array<unsigned char, 0x1000> other{};
std::array<unsigned char, 16 * recordSize> otherQueue{};
std::tuple<void*, float, std::uint64_t, void*, int> damageArguments;
bool __attribute__((thiscall)) nativeDamage(void* object, float amount, std::uint64_t flags,
                                            void* source, int countdown) {
    damageArguments = {object, amount, flags, source, countdown};
    const auto target = reinterpret_cast<Address>(object);
    if (behavior == Result::throws)
        throw std::runtime_error("fixture damage callback failure");
    if (behavior == Result::retiresSource && source) {
        const auto entity =
            feedback::at<Address>(reinterpret_cast<Address>(source), referenceEntity);
        feedback::at<unsigned>(entity, seedOffset) += 10;
        feedback::at<Address>(reinterpret_cast<Address>(source), referenceEntity) = 0;
    }
    if (behavior == Result::nested || behavior == Result::nestedSame) {
        const auto enclosing = behavior;
        behavior = Result::flash;
        feedback::damage(enclosing == Result::nestedSame ? object : other.data(), nullptr, 30, 0,
                         nullptr, 0);
        behavior = enclosing;
    }
    if (behavior != Result::rejected && behavior != Result::ignored) {
        auto& end = feedback::at<Address>(target, queueOffset + 4);
        feedback::at<float>(end, 0) = 3.5f;
        end += recordSize;
    }
    return behavior != Result::rejected;
}
unsigned colorCalls = 0;
std::tuple<void*, const feedback::Color*, int, int, bool, bool> colorArguments;
void __attribute__((thiscall)) nativeColor(void* object, const feedback::Color* color, int frames,
                                           int priority, bool fade, bool share) {
    ++colorCalls;
    colorArguments = {object, color, frames, priority, fade, share};
}
struct Fixture {
    lua_State lua;
    unsigned char* image =
        static_cast<unsigned char*>(VirtualAlloc(nullptr, native::globals::game + sizeof(Address),
                                                 MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    isaac::test::NativeEntityTypes types{reinterpret_cast<Address>(image)};
    std::array<unsigned char, 0x20000> game{};
    std::array<unsigned char, 0x1000> target{};
    std::array<unsigned char, 16 * recordSize> queue{};
    Fixture() {
        require(image != nullptr, "Private ABI image allocation failed");
        other.fill(0);
        otherQueue.fill(0);
        feedback::image = reinterpret_cast<Address>(image);
        feedback::at<Address>(feedback::image, native::globals::game) =
            reinterpret_cast<Address>(game.data());
        feedback::originalDamage = nativeDamage;
        for (const auto& [object, records] : std::array<std::pair<Address, Address>, 2>{
                 {{reinterpret_cast<Address>(target.data()),
                   reinterpret_cast<Address>(queue.data())},
                  {reinterpret_cast<Address>(other.data()),
                   reinterpret_cast<Address>(otherQueue.data())}}}) {
            feedback::at<unsigned>(object, typeOffset) = 10;
            feedback::at<bool>(object, native::layout::entity::active) = true;
            types.npc(object);
            feedback::at<Address>(object, queueOffset + 0) = records;
            feedback::at<Address>(object, queueOffset + 4) = records;
        }
        feedback::events.clear();
        feedback::flashes.clear();
        feedback::pending.clear();
        feedback::pendingCount = 0;
        feedback::identities.clear();
        feedback::serial = feedback::nextIdentity = 0;
        isaac::runtime::testTick = 10;
        isaac::runtime::testEpoch = 2;
        isaac::runtime::testReplica = false;
        isaac::runtime::errors.clear();
        isaac::rooms::testAudience = 3;
        feedback::at<int>(reinterpret_cast<Address>(game.data()), roomOffset) = 17;
        feedback::at<int>(reinterpret_cast<Address>(game.data()), dimensionOffset) = 1;
        feedback::originalSetColor = nativeColor;
        colorCalls = 0;
        require(feedback::bind(&lua, GetModuleHandleW(nullptr)) && lua.functions.size() == 4,
                "Combat Lua registration or symbol lookup failed");
    }
    ~Fixture() {
        feedback::reset(&lua);
        feedback::api = {};
        feedback::image = 0;
        feedback::installed = false;
        feedback::originalDamage = nullptr;
        feedback::originalSetColor = nullptr;
        feedback::isaac_lan_damage_drain_original = nullptr;
        VirtualFree(image, 0, MEM_RELEASE);
    }
    bool hit(Result result) {
        behavior = result;
        const auto accepted = feedback::damage(target.data(), nullptr, 30, 0, nullptr, 0);
        require(!feedback::observingDamage, "Damage observation leaked outside its call");
        return accepted;
    }
};
void flash(Address object, unsigned record, int frames) {
    const auto begin = feedback::at<Address>(object, queueOffset);
    feedback::setColor(reinterpret_cast<void*>(object), begin + record * recordSize,
                       feedback::image + native::entry::entityDamageColorReturn, nullptr, frames, 0,
                       false, false);
}
void contacts() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    require(f.hit(Result::ignored) && feedback::events.back().duration == 0,
            "Ignored contact acquired feedback");
    feedback::events.clear();
    require(f.hit(Result::contactOnly), "Native contact result changed");
    require(feedback::events.empty(), "Provisional queued damage was published early");
    feedback::drain(target); // NPC Update discarded the positive queued amount.
    require(feedback::events.size() == 1 && feedback::events.back().accepted &&
                feedback::events.back().duration == 0,
            "Immune contact invented a native hurt flash");
    require(f.hit(Result::flash), "Native damage return changed");
    flash(target, 1, 2); // Deferred native SetColor chooses the actual duration.
    feedback::drain(target);
    require(feedback::events.back().duration == 2,
            "Confirmed feedback ignored the actual native presentation");
    require(f.hit(Result::contactOnly), "No-flash contact return changed");
    feedback::drain(target);
    require(feedback::events.back().duration == 0, "Previous flash leaked into later damage");
    require(!f.hit(Result::rejected) && !feedback::events.back().accepted &&
                feedback::events.back().duration == 0,
            "A rejected hit acquired feedback");
    require(feedback::pending.empty() && feedback::pendingCount == 0,
            "Drained observations were retained");
}
void nested() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    const auto otherTarget = reinterpret_cast<Address>(other.data());
    require(f.hit(Result::nested), "Nested native damage result changed");
    require(feedback::events.empty(), "Nested queue was confirmed before Update");
    flash(otherTarget, 0, 2);
    feedback::drain(otherTarget);
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::events[0].duration == 2 &&
                feedback::events[1].duration == 0,
            "Nested damage assigned its flash to the enclosing target");
    require(feedback::events[0].target != feedback::events[1].target,
            "Nested target identities were conflated");
    feedback::events.clear();
    require(f.hit(Result::nestedSame), "Nested same-target result changed");
    flash(target, 1, 3);
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::events[0].duration == 3 &&
                feedback::events[1].duration == 0,
            "Nested damage was attributed to a contact-only enclosing call");
}
void relocationAndLifetime() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    require(f.hit(Result::flash), "Queued damage failed");
    auto relocated = f.queue;
    feedback::at<Address>(target, queueOffset) = reinterpret_cast<Address>(relocated.data());
    flash(target, 0, 4);
    // A later rejected contact may be published before deferred native damage.
    require(!f.hit(Result::rejected), "Rejection changed");
    feedback::drain(target);
    require(feedback::events.size() == 2 && !feedback::events[0].accepted &&
                feedback::events[1].duration == 4 &&
                feedback::events[0].serial < feedback::events[1].serial,
            "Relocation or delayed publication lost the source confirmation");
    feedback::at<Address>(target, queueOffset) = reinterpret_cast<Address>(f.queue.data());
    require(f.hit(Result::flash), "Second queued damage failed");
    ++isaac::runtime::testEpoch;
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::pendingCount == 0,
            "A previous world published a late confirmation");
    require(f.hit(Result::flash), "Expiring damage failed");
    isaac::runtime::testTick += feedback::retentionTicks + 1;
    feedback::prune();
    require(feedback::pending.empty() && feedback::pendingCount == 0,
            "Removed/frozen entities retained unbounded observations");
}
void sourceIdentityAndFailure() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    const auto source = reinterpret_cast<Address>(other.data());
    std::array<unsigned char, 0x28> reference{};
    feedback::at<Address>(reinterpret_cast<Address>(reference.data()), referenceEntity) = source;
    behavior = Result::retiresSource;
    require(feedback::damage(f.target.data(), nullptr, 30, 0, reference.data(), 0),
            "Native source-removing callback return changed");
    feedback::drain(target);
    const auto event = feedback::events.back();
    require(event.target == 1 && event.source == 2 && feedback::identify(source) == 3,
            "Damage looked up its source after a callback replaced it");
    const auto count = feedback::events.size();
    require(f.hit(Result::flash), "Replacement target fixture failed");
    ++feedback::at<unsigned>(target, seedOffset);
    feedback::drain(target);
    require(feedback::events.size() == count,
            "Recycled target confirmed the retired object's damage");
    require(feedback::identify(target) == 4, "Recycled address reused its old combat identity");
    rejects([&] { f.hit(Result::throws); }, "Native damage exception was swallowed");
    require(!feedback::observingDamage && feedback::events.size() == count,
            "Failed native callback leaked observation state or an event");
    require(!f.hit(Result::rejected) && feedback::events.back().target == 4,
            "Failed callback poisoned a later native observation");
}
void luaWireAndAudience() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    const auto source = reinterpret_cast<Address>(other.data());
    std::array<unsigned char, 0x28> reference{};
    feedback::at<Address>(reinterpret_cast<Address>(reference.data()), referenceEntity) = source;
    behavior = Result::flash;
    feedback::damage(f.target.data(), nullptr, 30, 0, reference.data(), 0);
    flash(target, 0, 3);
    feedback::drain(target);
    f.lua.functions.at("combat_events")(&f.lua);
    const std::vector<std::uint8_t> expected{0, 0, 0, 1, 0, 0, 0,  1, 0, 0, 0, 10, 0, 0, 0, 2, 0,
                                             0, 0, 1, 0, 0, 0, 17, 0, 0, 0, 2, 0,  0, 0, 1, 1, 3};
    require(f.lua.bytes == expected, "Combat event changed the fixed big-endian wire bytes");
    f.lua.argument = 1;
    f.lua.functions.at("combat_events")(&f.lua);
    require(f.lua.bytes == expected, "Same-room audience lost an event");
    f.lua.argument = 2;
    f.lua.functions.at("combat_events")(&f.lua);
    require(f.lua.bytes == std::vector<std::uint8_t>{0, 0, 0, 0},
            "Another room received a combat event");
    f.lua.wrapper[1] = target + spriteOffset;
    f.lua.functions.at("combat_identity")(&f.lua);
    require(f.lua.integer == 1, "Combat Sprite identity differs from damage event identity");
    f.lua.argument = 4;
    f.lua.functions.at("combat_events")(&f.lua);
    require(!f.lua.boolean && isaac::runtime::errors.size() == 1,
            "Invalid event audience escaped its Lua failure boundary");
    f.lua.length = 0x11c;
    f.lua.functions.at("combat_identity")(&f.lua);
    require(!f.lua.boolean && isaac::runtime::errors.size() == 2,
            "Owned Sprite was treated as a live combat entity");
    f.lua.length = 8;
    isaac::runtime::testReplica = true;
    f.lua.functions.at("combat_identity")(&f.lua);
    require(!f.lua.boolean && isaac::runtime::errors.size() == 3,
            "Replica assigned authoritative combat identity");
    f.lua.count = 1;
    f.lua.functions.at("combat_present")(&f.lua);
    require(f.lua.boolean && feedback::flashes.at(target).local,
            "Replica could not select local hit presentation");
    f.lua.count = 0;
    f.lua.functions.at("combat_present")(&f.lua);
    require(f.lua.boolean && feedback::flashes.empty(), "New view retained old hit presentation");
    f.lua.functions.at("combat_reset")(&f.lua);
    require(f.lua.boolean && feedback::events.empty() && feedback::identities.empty() &&
                feedback::pending.empty() && !feedback::serial && !feedback::nextIdentity,
            "Session reset retained old identities or events");
}
void temporaryPresentation() {
    Fixture f;
    std::array<unsigned char, 0x1300> room{};
    const auto target = reinterpret_cast<Address>(f.target.data());
    std::array<Address, 3> renderList{0, target, reinterpret_cast<Address>(other.data())};
    const auto list = reinterpret_cast<Address>(room.data()) + roomEntities + renderArray;
    feedback::at<Address>(list, arrayData) = reinterpret_cast<Address>(renderList.data());
    feedback::at<unsigned>(list, arrayCount) = renderList.size();
    auto& color = feedback::at<feedback::Color>(target, spriteOffset + colorOffset);
    for (unsigned i = 0; i < color.size(); ++i)
        color[i] = static_cast<float>(i) / 8;
    const auto originalColor = color;
    for (unsigned type : {10, 407, 951}) {
        feedback::at<unsigned>(target, typeOffset) = type;
        const auto before = f.target;
        flash(target, 0, 2);
        const auto draw = [&] {
            require(color[0] == .5f && color[1] == .5f && color[3] == 1 &&
                        color[2] == (type == 10 ? .5f : .33f) &&
                        color[8] == (type == 10 ? 200.f / 255.f : 100.f / 255.f) && color[4] == 0 &&
                        color[5] == 0 && color[6] == 0 && color[7] == 0 && color[9] == 0 &&
                        color[10] == 0,
                    "Temporary hit style changed native ColorMod channels");
        };
        feedback::withPresentation(reinterpret_cast<Address>(room.data()), [&] {
            draw();
            feedback::withPresentation(reinterpret_cast<Address>(room.data()), draw);
            draw();
        });
        require(f.target == before, "Hit rendering wrote persistent entity or Sprite state");
        rejects(
            [&] {
                feedback::withPresentation(reinterpret_cast<Address>(room.data()), [&] {
                    draw();
                    throw std::runtime_error("fixture interrupted render");
                });
            },
            "Render exception was swallowed");
        require(f.target == before, "Render failure retained temporary hit color");
    }
    isaac::runtime::testTick += 2;
    feedback::withPresentation(reinterpret_cast<Address>(room.data()), [&] {
        require(color == originalColor, "Expired hit flash remained visible");
    });
    flash(target, 0, 2);
    ++feedback::at<unsigned>(target, indexOffset);
    feedback::withPresentation(reinterpret_cast<Address>(room.data()), [&] {
        require(color == originalColor, "Reused entity index inherited old presentation");
    });
    unsigned calls = 0;
    feedback::withPresentation(0, [&] { ++calls; });
    feedback::at<Address>(list, arrayData) = 0;
    feedback::withPresentation(reinterpret_cast<Address>(room.data()), [&] { ++calls; });
    require(calls == 2 && color == originalColor,
            "Missing room or render array suppressed normal drawing or mutated colors");
}
void passiveAndBounded() {
    Fixture f;
    isaac::runtime::testReplica = true;
    require(f.hit(Result::flash) && feedback::events.empty() && feedback::pending.empty(),
            "Replica synthesized authoritative damage events");
    isaac::runtime::testReplica = false;
    isaac::rooms::testAudience = 0;
    require(f.hit(Result::flash) && feedback::events.empty() && feedback::pending.empty(),
            "Single-player damage was observed as LAN damage");
    isaac::rooms::testAudience = 3;
    auto& game = feedback::at<Address>(feedback::image, native::globals::game);
    const auto saved = game;
    game = 0;
    require(f.hit(Result::flash) && feedback::events.empty(),
            "Missing Game synthesized a room event");
    game = saved;
    for (unsigned i = 0; i < feedback::maxEvents + 8; ++i)
        require(!f.hit(Result::rejected), "Rejected damage became accepted");
    f.lua.functions.at("combat_events")(&f.lua);
    require(feedback::events.size() == feedback::maxEvents,
            "Combat event retention exceeded its bounded window");
    ++isaac::runtime::testEpoch;
    f.lua.functions.at("combat_events")(&f.lua);
    require(feedback::events.empty() && f.lua.bytes == std::vector<std::uint8_t>{0, 0, 0, 0},
            "New floor retained previous-floor combat events");
}
void patch(Fixture& f, unsigned rva, auto target) {
    std::fill_n(f.image + rva, 16, 0x90);
    f.image[rva] = 0xe9;
    feedback::at<std::uint32_t>(reinterpret_cast<Address>(f.image), rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(target) -
                                   reinterpret_cast<Address>(f.image + rva + 5));
}
void hookABIAndOwnership() {
    Fixture f;
    struct Hooks {
        Hooks() {
            require(MH_Initialize() == MH_OK, "Cannot initialize fixture MinHook");
        }
        ~Hooks() {
            MH_Uninitialize();
        }
    } hooks;
    patch(f, native::entry::npcTakeDamage, nativeDamage);
    patch(f, native::entry::entitySetColor, nativeColor);
    patch(f, native::entry::entityDamageDrain, nativeDrain);
    const auto base = reinterpret_cast<Address>(f.image);
    const std::array<unsigned, 3> entries{native::entry::npcTakeDamage,
                                          native::entry::entitySetColor,
                                          native::entry::entityDamageDrain};
    require(!feedback::install(0), "Zero image installed combat hooks");
    for (unsigned conflict = 0; conflict < entries.size(); ++conflict) {
        auto* foreign = f.image + entries[conflict];
        require(MH_CreateHook(foreign, reinterpret_cast<void*>(nativeDrain), nullptr) == MH_OK,
                "Cannot prepare foreign combat hook");
        require(!feedback::install(base) && !feedback::image && !feedback::originalDamage &&
                    !feedback::originalSetColor && !feedback::isaac_lan_damage_drain_original,
                "Failed combat installation retained partial hooks or bypasses");
        for (unsigned i = 0; i < conflict; ++i) {
            auto* target = f.image + entries[i];
            require(MH_CreateHook(target, reinterpret_cast<void*>(nativeDrain), nullptr) == MH_OK &&
                        MH_RemoveHook(target) == MH_OK,
                    "Combat rollback leaked an earlier hook");
        }
        require(MH_CreateHook(foreign, reinterpret_cast<void*>(nativeDrain), nullptr) ==
                        MH_ERROR_ALREADY_CREATED &&
                    MH_RemoveHook(foreign) == MH_OK,
                "Combat rollback removed a foreign hook");
    }
    // Synthetic thiscall site: EDX carries the queue record into ESI. Copy
    // five original stack arguments and return at the audited native RVA.
    const auto site = native::entry::entityDamageColorReturn - 28;
    std::array<std::uint8_t, 32> caller{0x56, 0x8b, 0xf2,       // push ESI; mov ESI,EDX
                                        0xff, 0x74, 0x24, 0x18, // push [ESP+24], five arguments
                                        0xff, 0x74, 0x24, 0x18, 0xff, 0x74, 0x24,
                                        0x18, 0xff, 0x74, 0x24, 0x18, 0xff, 0x74,
                                        0x24, 0x18, 0xe8, 0,    0,    0,    0, // call SetColor
                                        0x5e, 0xc2, 0x14, 0};                  // pop ESI; ret 20
    const auto relative = static_cast<std::uint32_t>(native::entry::entitySetColor -
                                                     native::entry::entityDamageColorReturn);
    for (unsigned i = 0; i < 4; ++i)
        caller[24 + i] = static_cast<std::uint8_t>(relative >> (i * 8));
    std::copy(caller.begin(), caller.end(), f.image + site);
    require(FlushInstructionCache(GetCurrentProcess(), f.image, native::globals::game) != 0 &&
                feedback::install(base) && !feedback::install(base),
            "Combat retry failed or duplicate install replaced live trampolines");
    behavior = Result::flash;
    constexpr std::uint64_t flags = 0x123456789abcdef0ull;
    std::array<unsigned char, 0x28> reference{};
    feedback::at<Address>(reinterpret_cast<Address>(reference.data()), referenceEntity) =
        reinterpret_cast<Address>(other.data());
    auto hit = reinterpret_cast<feedback::Damage>(base + native::entry::npcTakeDamage);
    require(hit(f.target.data(), 30, flags, reference.data(), 9) &&
                damageArguments ==
                    std::tuple<void*, float, std::uint64_t, void*, int>{f.target.data(), 30, flags,
                                                                        reference.data(), 9} &&
                feedback::events.empty(),
            "NPC damage hook changed receiver, 64-bit flags, stack arguments or deferred result");
    feedback::Color color{};
    auto colorCall = reinterpret_cast<feedback::SetColor>(base + native::entry::entitySetColor);
    colorCall(f.target.data(), &color, 14, 255, true, false);
    require(colorCalls == 1 && colorArguments ==
                                   std::tuple<void*, const feedback::Color*, int, int, bool, bool>{
                                       f.target.data(), &color, 14, 255, true, false},
            "Unrelated native SetColor was intercepted or its thiscall ABI changed");
    using NativeColorSite = void(__attribute__((fastcall))*)(void*, void*, const feedback::Color*,
                                                             int, int, bool, bool);
    reinterpret_cast<NativeColorSite>(base + site)(f.target.data(), f.queue.data(), &color, 99, 0,
                                                   false, false);
    require(colorCalls == 1 && feedback::events.empty(),
            "Native hit flash became persistent or published before queue drain");
    combatDrainEntry = f.image + native::entry::entityDamageDrain;
    combatDrainObject = f.target.data();
    invokeDrain();
    require(feedback::events.size() == 1 && feedback::events[0].accepted &&
                feedback::events[0].duration == 6 && feedback::events[0].source == 2 &&
                feedback::events[0].target == 1 && feedback::pending.empty() &&
                feedback::queuedDamage(reinterpret_cast<Address>(f.target.data())) == 0,
            "Native queue drain changed ownership, duration bounds or original queue cleanup");
    require(combatDrainECX == 0x87654321 && combatDrainSSE == 0xffffffff && combatDrainX87 == 1 &&
                (combatDrainFlags & 0x41) == 0x41,
            "Queue-drain hook corrupted native registers, flags or floating-point state");
}
void customTypes() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    for (const auto kind : {6617u, 6621u}) {
        feedback::at<unsigned>(target, native::layout::entity::type) = kind;
        require(f.hit(Result::flash), "Custom NPC damage failed");
        flash(target, static_cast<unsigned>(feedback::events.size()), 3);
        feedback::drain(target);
        require(feedback::events.back().duration == 3 && feedback::flashes.contains(target),
                "Custom NPC lost its confirmed hurt flash");
    }
    const std::array<Address, 2> sprite{0, target + native::layout::entity::sprite};
    feedback::api.getTop = [](lua_State*) { return 1; };
    // The Lua ABI borrows the wrapper only for this synchronous call.
    static const Address* wrapper;
    wrapper = sprite.data();
    feedback::api.toUserdata = [](lua_State*, int) -> void* {
        return const_cast<Address*>(wrapper);
    };
    feedback::api.rawLength = [](lua_State*, int) -> std::size_t { return 8; };
    feedback::api.pushBoolean = [](lua_State*, int value) {
        require(value == 1, "Local hit presentation failed");
    };
    isaac::runtime::testReplica = true;
    require(feedback::present(nullptr) == 1 && feedback::flashes.at(target).local,
            "Custom NPC rejected local hit presentation");
    feedback::flashes.clear();
    f.types.effect(target);
    for (const auto kind : {10u, 6617u}) {
        feedback::at<unsigned>(target, native::layout::entity::type) = kind;
        rejects([] { feedback::present(nullptr); }, "Non-NPC accepted hit presentation");
        require(feedback::flashes.empty(), "Rejected native class retained a hurt flash");
    }
    f.types.npc(target);
    feedback::at<bool>(target, native::layout::entity::active) = false;
    rejects([] { feedback::present(nullptr); }, "Inactive NPC accepted hit presentation");
    require(feedback::flashes.empty(), "Inactive NPC retained hit presentation");
    isaac::runtime::testReplica = false;
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"contacts", contacts},
                     {"nested", nested},
                     {"relocation-and-lifetime", relocationAndLifetime},
                     {"source-identity-failure", sourceIdentityAndFailure},
                     {"lua-wire-audience", luaWireAndAudience},
                     {"temporary-presentation", temporaryPresentation},
                     {"passive-bounded", passiveAndBounded},
                     {"hook-abi-ownership", hookABIAndOwnership},
                     {"custom-types", customTypes}});
}
