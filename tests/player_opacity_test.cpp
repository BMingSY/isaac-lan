// Exercise the production x86 color boundary with private players and stack frames.
#include "test_support.h"
#include "engine/versions/j460/player_opacity.cpp"
#include <climits>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace opacity = isaac::presentation::player_opacity;
namespace layout = isaac::engine::j460::layout;
using Address = std::uintptr_t;
extern "C" {
unsigned char opacityFrame[512]{};
unsigned opacityECX = 0, opacityFlags = 0;
float opacitySSE = 0;
__attribute__((naked)) void opacityOriginal() {
    __asm__ __volatile__("pushfl\n\tpopl _opacityFlags\n\tmovl %ecx, _opacityECX\n\t"
                         "movss %xmm7, _opacitySSE\n\tret");
}
__attribute__((naked)) void invokeOpacity() {
    __asm__ __volatile__("pushl %ebp\n\tleal _opacityFrame+256, %ebp\n\t"
                         "movl $0x87654321, %ecx\n\tmovl $0x3f400000, %eax\n\t"
                         "movd %eax, %xmm7\n\tstc\n\tcall _isaac_lan_opacity_color\n\t"
                         "popl %ebp\n\tret");
}
}
namespace {
template <class T> T& at(Address address, std::ptrdiff_t offset) {
    return *reinterpret_cast<T*>(address + offset);
}
struct Player {
    std::array<unsigned char, layout::player::controller + sizeof(int)> bytes{};
    std::array<unsigned char, layout::player::costumeStride * 2> costumes{};
    explicit Player(int controller) {
        at<int>(address(), layout::player::controller) = controller;
        const auto vector = address() + layout::player::costumes;
        at<Address>(vector, layout::vector::begin) = reinterpret_cast<Address>(costumes.data());
        at<Address>(vector, layout::vector::end) =
            reinterpret_cast<Address>(costumes.data() + costumes.size());
    }
    Address address() {
        return reinterpret_cast<Address>(bytes.data());
    }
};
void draw(Address sprite, float source, float expected) {
    const auto frame = reinterpret_cast<Address>(opacityFrame + 256);
    at<Address>(frame, layout::spriteRenderFrame::sprite) = sprite;
    using Color = std::array<float, layout::color::size / sizeof(float)>;
    auto& color = at<Color>(frame, layout::spriteRenderFrame::color);
    color = {0.3f, 0.8f, 0.4f, source, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.7f};
    auto expectedColor = color;
    expectedColor[layout::color::alpha / sizeof(float)] = expected;
    invokeOpacity();
    require(color == expectedColor, "Final draw color lost its alpha multiplier or other channels");
    require(opacityECX == 0x87654321 && (opacityFlags & 1) && opacitySSE == 0.75f,
            "Opacity boundary corrupted registers or flags");
}
void rendering() {
    opacity::original = reinterpret_cast<void*>(opacityOriginal);
    opacity::percentages = {100, 50, 0, 25};
    Player host(1), guest(2), twin(2), third(3), fourth(4), unowned(0);
    std::array<Address, 6> players{guest.address(), fourth.address(),  twin.address(),
                                   host.address(),  unowned.address(), third.address()};
    const auto snapshot = guest.bytes;
    draw(guest.address() + layout::entity::sprite, 0.8f, 0.8f);
    opacity::withPlayers(players, 15, [&] {
        for (auto offset : {layout::entity::sprite, layout::player::extraSprite,
                            layout::player::ghostSprite, layout::player::auxiliarySprite}) {
            draw(host.address() + offset, 0.8f, 0.8f);
            draw(guest.address() + offset, 0.8f, 0.4f);
            draw(twin.address() + offset, 0.8f, 0.4f);
            draw(third.address() + offset, 0.8f, 0);
            draw(fourth.address() + offset, 0.8f, 0.2f);
            draw(unowned.address() + offset, 0.8f, 0.8f);
        }
        for (unsigned i = 0; i < 2; ++i)
            draw(reinterpret_cast<Address>(guest.costumes.data()) +
                     i * layout::player::costumeStride,
                 0.6f, 0.3f);
        // The same boundary sees an ordinary tint, an overriding outline color,
        // a hologram and repeated layers. Each fresh temporary color scales once.
        for (float alpha : {1.f, 0.8f, 0.2f, 0.f, 1.f})
            draw(guest.address() + layout::entity::sprite, alpha, alpha * 0.5f);
        draw(guest.address() + 0x758, 1, 1); // Native charge UI is independent.
        draw(1234, 1, 1);                    // Tears, familiars, other entities and unrelated UI.
        opacity::withPlayers(players, 1,
                             [&] { draw(guest.address() + layout::entity::sprite, 1, 1); });
        draw(guest.address() + layout::entity::sprite, 1, 0.5f);
        try {
            opacity::withPlayers({}, 15, [&] {
                draw(guest.address() + layout::entity::sprite, 1, 1);
                throw std::runtime_error("interrupted render");
            });
        } catch (const std::runtime_error&) {
        }
        draw(guest.address() + layout::entity::sprite, 1, 0.5f);
    });
    require(!opacity::activeSprites && guest.bytes == snapshot,
            "Draw changed player state or retained sprite addresses");
    draw(guest.address() + layout::entity::sprite, 1, 1);
    for (int controller : {-1, INT_MIN, 5, INT_MAX}) {
        at<int>(guest.address(), layout::player::controller) = controller;
        opacity::withPlayers(players, 15,
                             [&] { draw(guest.address() + layout::entity::sprite, 1, 1); });
    }
    at<int>(guest.address(), layout::player::controller) = 2;
    const auto vector = guest.address() + layout::player::costumes;
    const auto begin = at<Address>(vector, layout::vector::begin);
    for (const auto end :
         {begin - 1, begin + 1,
          begin + layout::player::costumeStride * (layout::player::maximumCostumes + 1)}) {
        at<Address>(vector, layout::vector::end) = end;
        opacity::withPlayers(players, 15, [&] {
            draw(begin, 1, 1);
            draw(guest.address() + layout::entity::sprite, 1, 0.5f);
        });
    }
}
int argumentCount = 0;
std::array<long long, 4> arguments{};
std::array<bool, 4> integers{};
bool accepted = false;
long long returned = -1;
void settings() {
    opacity::api.getTop = [](lua_State*) { return argumentCount; };
    opacity::api.isInteger = [](lua_State*, int i) { return int(integers[i - 1]); };
    opacity::api.toInteger = [](lua_State*, int i, int*) { return arguments[i - 1]; };
    opacity::api.pushBoolean = [](lua_State*, int value) { accepted = value; };
    opacity::api.pushInteger = [](lua_State*, long long value) { returned = value; };
    opacity::configure(35);
    opacity::settings(nullptr);
    require(returned == 35, "Default others opacity was not exposed");
    argumentCount = 4;
    arguments = {0, 50, 100, 25};
    integers.fill(true);
    opacity::settings(nullptr);
    require(accepted && opacity::percentages == std::array<unsigned, 4>{0, 50, 100, 25},
            "Valid opacity values were rejected");
    const auto before = opacity::percentages;
    for (auto invalid : {-1LL, 101LL, LLONG_MAX}) {
        arguments[3] = invalid;
        opacity::settings(nullptr);
        require(!accepted && opacity::percentages == before, "Partial/invalid preference commit");
    }
    arguments[3] = 25;
    integers[2] = false;
    opacity::settings(nullptr);
    require(!accepted && opacity::percentages == before, "Non-integer opacity was accepted");
    for (int count : {1, 3, 5}) {
        argumentCount = count;
        opacity::settings(nullptr);
        require(!accepted && opacity::percentages == before, "Wrong arity changed opacity");
    }
}
} // namespace
int main() {
    try {
        rendering();
        settings();
        std::puts(
            "PASS player opacity x86 colors, body/costume ownership, nested cleanup and bounds");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
