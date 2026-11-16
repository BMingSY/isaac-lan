#include "engine/player_opacity.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>
#include <array>
#include <unordered_map>

namespace isaac::presentation::player_opacity {
namespace {
namespace j460 = engine::j460;
namespace layout = j460::layout;
using Address = std::uintptr_t;
using Factors = std::unordered_map<Address, float>;
constexpr unsigned maximum = 100;
unsigned defaultOthers = maximum;
std::array<unsigned, 4> percentages{maximum, maximum, maximum, maximum};
const Factors* activeSprites = nullptr;
const Factors* activePlayers = nullptr;
Address image = 0;
enum Pass : unsigned { sprite, tear, laser, laserShadow };
struct Boundary {
    Address gate, draw;
    void* original = nullptr;
};
std::array<Boundary, 4> boundaries{{
    {j460::entry::spriteRenderColor, 0},
    {j460::entry::tearOpacityGate, j460::entry::tearOpacityDraw},
    {j460::entry::laserOpacityGate, j460::entry::laserOpacityDraw},
    {j460::entry::laserShadowOpacityGate, j460::entry::laserShadowOpacityDraw},
}};
lua::API api{};
template <class T> T read(Address address, std::ptrdiff_t offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
int settings(lua_State* L) {
    if (api.getTop(L) == 0) {
        api.pushInteger(L, defaultOthers);
        return 1;
    }
    auto next = percentages;
    bool valid = api.getTop(L) == static_cast<int>(next.size());
    for (unsigned i = 0; valid && i < next.size(); ++i) {
        // Do not coerce strings, fractions, infinities or values outside 0..100.
        valid = api.isInteger(L, i + 1);
        if (valid) {
            const auto value = api.toInteger(L, i + 1, nullptr);
            valid = value >= 0 && value <= maximum;
            if (valid)
                next[i] = static_cast<unsigned>(value);
        }
    }
    if (valid)
        percentages = next;
    api.pushBoolean(L, valid);
    return 1;
}
} // namespace
extern "C" {
__attribute__((used,
               force_align_arg_pointer)) void __cdecl isaac_lan_opacity_prepare(Address* registers,
                                                                                unsigned pass) {
    // pushad: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, flags, continuation.
    enum Register : unsigned {
        entity = 1,
        frame = 2,
        tearOwner = 5,
        laserOwner = 7,
        continuation = 9
    };
    const auto& boundary = boundaries[pass];
    registers[continuation] = reinterpret_cast<Address>(boundary.original);
    if (pass != sprite) {
        if (!activePlayers)
            return;
        // The native renderer has already resolved the owning player. Match
        // against this render's roster without retaining or dereferencing it.
        const auto found = activePlayers->find(registers[pass == tear ? tearOwner : laserOwner]);
        if (found == activePlayers->end())
            return;
        if (pass == tear) {
            // Native Tear::Render saved this color before the online gate and
            // restores it after drawing, before MC_POST_TEAR_RENDER. Use that
            // same temporary modulation, retaining all tint/fade channels.
            auto& alpha = *reinterpret_cast<float*>(registers[entity] + layout::entity::sprite +
                                                    layout::sprite::color + layout::color::alpha);
            alpha *= found->second;
        } else {
            // Both laser passes consume a stack-local multiplier, including
            // native beam segments/rings that do not use Sprite::RenderColor.
            const auto offset = pass == laser ? layout::laserRenderFrame::opacity
                                              : layout::laserRenderFrame::shadowOpacity;
            *reinterpret_cast<float*>(registers[frame] + offset) = found->second;
        }
        registers[continuation] = image + boundary.draw;
        return;
    }
    if (!activeSprites || activeSprites->empty())
        return;
    const auto stack = registers[frame];
    const auto sprite = read<Address>(stack, layout::spriteRenderFrame::sprite);
    const auto found = activeSprites->find(sprite);
    if (found == activeSprites->end())
        return;
    auto& alpha =
        *reinterpret_cast<float*>(stack + layout::spriteRenderFrame::color + layout::color::alpha);
    alpha *= found->second;
}
#define OPACITY_BOUNDARY(NAME, PASS)                                                               \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__("pushl $0\n\tpushfl\n\tpushal\n\tsubl $128, %esp\n\t"                 \
                             "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"                 \
                             "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"                \
                             "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"                \
                             "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"               \
                             "leal 128(%esp), %eax\n\tpushl $" #PASS "\n\tpushl %eax\n\t"          \
                             "call _isaac_lan_opacity_prepare\n\taddl $8, %esp\n\t"                \
                             "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"                 \
                             "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"                \
                             "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"                \
                             "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"               \
                             "addl $128, %esp\n\tpopal\n\tpopfl\n\tret");                          \
    }
OPACITY_BOUNDARY(isaac_lan_opacity_color, 0)
OPACITY_BOUNDARY(isaac_lan_opacity_tear, 1)
OPACITY_BOUNDARY(isaac_lan_opacity_laser, 2)
OPACITY_BOUNDARY(isaac_lan_opacity_laser_shadow, 3)
#undef OPACITY_BOUNDARY
}
void configure(unsigned others) {
    defaultOthers = others <= maximum ? others : maximum;
}
bool bind(lua_State* L, lua::Module module) {
    if (!api.load(module, {lua::Symbol::getTop, lua::Symbol::isInteger, lua::Symbol::toInteger,
                           lua::Symbol::pushInteger, lua::Symbol::pushBoolean,
                           lua::Symbol::pushClosure, lua::Symbol::setField}))
        return false;
    api.pushClosure(L, settings, 0);
    api.setField(L, -2, "player_opacity");
    return true;
}
bool install(Address base) {
    image = base;
    const std::array<void (*)(), 4> detours{isaac_lan_opacity_color, isaac_lan_opacity_tear,
                                            isaac_lan_opacity_laser,
                                            isaac_lan_opacity_laser_shadow};
    for (unsigned i = 0; i < boundaries.size(); ++i)
        if (MH_CreateHook(reinterpret_cast<void*>(image + boundaries[i].gate),
                          reinterpret_cast<void*>(detours[i]), &boundaries[i].original) != MH_OK)
            return false;
    for (const auto& boundary : boundaries)
        if (MH_EnableHook(reinterpret_cast<void*>(image + boundary.gate)) != MH_OK)
            return false;
    return true;
}
void withPlayers(std::span<const Address> players, unsigned connected,
                 const std::function<void()>& render) {
    Factors sprites, owners;
    for (const auto player : players) {
        if (!player)
            continue;
        const auto controller = read<int>(player, layout::player::controller);
        if (controller < 1 || controller > static_cast<int>(percentages.size()) ||
            !(connected & (1u << (controller - 1))))
            continue;
        const auto percent = percentages[controller - 1];
        const auto factor = static_cast<float>(percent) / maximum;
        owners.emplace(player, factor);
        if (percent == maximum)
            continue;
        for (const auto offset : {layout::entity::sprite, layout::player::extraSprite,
                                  layout::player::ghostSprite, layout::player::auxiliarySprite})
            sprites.emplace(player + offset, factor);
        const auto costumes = player + layout::player::costumes;
        const auto begin = read<Address>(costumes, layout::vector::begin);
        const auto end = read<Address>(costumes, layout::vector::end);
        if (end < begin || (end - begin) % layout::player::costumeStride ||
            (end - begin) / layout::player::costumeStride > layout::player::maximumCostumes)
            continue;
        for (auto sprite = begin; sprite < end; sprite += layout::player::costumeStride)
            sprites.emplace(sprite, factor);
    }
    struct Restore {
        const Factors* previous = activeSprites;
        const Factors* players = activePlayers;
        ~Restore() {
            activeSprites = previous;
            activePlayers = players;
        }
    } restore;
    activeSprites = &sprites;
    activePlayers = &owners;
    render();
}
} // namespace isaac::presentation::player_opacity
