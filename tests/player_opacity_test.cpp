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
unsigned char projectileFrame[1024]{};
Address projectileOwner = 0, projectileEntity = 0;
void (*projectileBoundary)() = nullptr;
unsigned projectileHandled = 0;
std::array<Address, 4> projectileRegisters{};
float projectileSSE = 0;
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
__attribute__((naked)) void projectileCapture() {
    __asm__ __volatile__("movl %eax, _projectileRegisters\n\t"
                         "movl %edx, _projectileRegisters+4\n\t"
                         "movl %esi, _projectileRegisters+8\n\t"
                         "movl %edi, _projectileRegisters+12\n\t"
                         "movss %xmm0, _projectileSSE\n\tjmp _opacityOriginal");
}
__attribute__((naked)) void projectileOriginal() {
    __asm__ __volatile__("movl $0, _projectileHandled\n\tjmp _projectileCapture");
}
__attribute__((naked)) void projectileDraw() {
    __asm__ __volatile__("movl $1, _projectileHandled\n\tjmp _projectileCapture");
}
__attribute__((naked)) void invokeProjectile() {
    __asm__ __volatile__("pushl %ebp\n\tpushl %esi\n\tpushl %edi\n\t"
                         "leal _projectileFrame+512, %ebp\n\t"
                         "movl $0x3f400000, %eax\n\tmovd %eax, %xmm7\n\t"
                         "movl $0x3e800000, %eax\n\tmovd %eax, %xmm0\n\t"
                         "movl _projectileOwner, %eax\n\tmovl %eax, %edx\n\t"
                         "movl _projectileEntity, %esi\n\tmovl $0x12345678, %edi\n\t"
                         "movl $0x87654321, %ecx\n\tstc\n\t"
                         "call *_projectileBoundary\n\tpopl %edi\n\tpopl %esi\n\tpopl %ebp\n\tret");
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
    opacity::boundaries[opacity::sprite].original = reinterpret_cast<void*>(opacityOriginal);
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
        draw(1234, 1, 1);                    // Unlisted sprites and unrelated UI.
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
    require(!opacity::activeSprites && !opacity::activePlayers && guest.bytes == snapshot,
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
void projectiles() {
    Player host(1), guest(2), twin(2), third(3), fourth(4), unowned(0);
    const std::array<Address, 7> players{guest.address(),
                                         fourth.address(),
                                         twin.address(),
                                         host.address(),
                                         unowned.address(),
                                         third.address(),
                                         0};
    const auto playerBefore = guest.bytes;
    opacity::percentages = {100, 50, 0, 25};
    std::array<unsigned char, 1024> entity{};
    projectileEntity = reinterpret_cast<Address>(entity.data());
    const auto frame = reinterpret_cast<Address>(projectileFrame + 512);
    using Color = std::array<float, layout::color::size / sizeof(float)>;
    auto& color = at<Color>(projectileEntity, layout::entity::sprite + layout::sprite::color);
    const Color source{0.3f, 0.8f, 0.4f, 0.8f, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.7f};
    const std::array<void (*)(), 3> callbacks{opacity::isaac_lan_opacity_tear,
                                              opacity::isaac_lan_opacity_laser,
                                              opacity::isaac_lan_opacity_laser_shadow};
    auto draw = [&](Address owner, float factor, bool handled) {
        for (unsigned index = 0; index < callbacks.size(); ++index) {
            const auto pass = index + opacity::tear;
            opacity::boundaries[pass].original = reinterpret_cast<void*>(projectileOriginal);
            opacity::boundaries[pass].draw = reinterpret_cast<Address>(projectileDraw);
            projectileBoundary = callbacks[index];
            projectileOwner = owner;
            color = source;
            at<float>(frame, layout::laserRenderFrame::opacity) = 1;
            at<float>(frame, layout::laserRenderFrame::shadowOpacity) = 1;
            invokeProjectile();
            auto expected = source;
            if (pass == opacity::tear)
                expected[layout::color::alpha / sizeof(float)] *= factor;
            require(color == expected, "Tear opacity changed tint or used the wrong owner");
            require(at<float>(frame, layout::laserRenderFrame::opacity) ==
                            (pass == opacity::laser ? factor : 1) &&
                        at<float>(frame, layout::laserRenderFrame::shadowOpacity) ==
                            (pass == opacity::laserShadow ? factor : 1),
                    "Laser pass used the wrong opacity or stack local");
            require(projectileHandled == unsigned(handled), "Wrong native opacity continuation");
            require(projectileRegisters ==
                            std::array<Address, 4>{owner, owner, projectileEntity, 0x12345678} &&
                        projectileSSE == 0.25f && opacityECX == 0x87654321 && (opacityFlags & 1) &&
                        opacitySSE == 0.75f,
                    "Projectile opacity boundary corrupted registers or flags");
        }
    };
    draw(guest.address(), 1, false);
    opacity::withPlayers(players, 15, [&] {
        for (unsigned repeat = 0; repeat < 3; ++repeat) {
            draw(host.address(), 1, true);
            draw(guest.address(), 0.5f, true);
            draw(twin.address(), 0.5f, true);
            draw(third.address(), 0, true);
            draw(fourth.address(), 0.25f, true);
            draw(unowned.address(), 1, false);
            draw(0, 1, false);    // Enemy/unowned attacks retain the native path.
            draw(1234, 1, false); // Never dereference an owner outside the roster.
        }
        opacity::withPlayers(players, 1, [&] { draw(guest.address(), 1, false); });
        draw(guest.address(), 0.5f, true);
        try {
            opacity::withPlayers({}, 15, [&] {
                draw(guest.address(), 1, false);
                throw std::runtime_error("interrupted projectile render");
            });
        } catch (const std::runtime_error&) {
        }
        draw(guest.address(), 0.5f, true);
    });
    draw(guest.address(), 1, false);
    require(!opacity::activePlayers && guest.bytes == playerBefore,
            "Projectile render retained owners or changed player state");
    opacity::percentages.fill(100);
    opacity::withPlayers(players, 15, [&] { draw(guest.address(), 1, true); });
    Player replacement(2);
    const std::array<Address, 1> replaced{replacement.address()};
    opacity::percentages[1] = 25;
    opacity::withPlayers(replaced, 2, [&] {
        draw(guest.address(), 1, false);
        draw(replacement.address(), 0.25f, true);
    });
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
        projectiles();
        settings();
        std::puts(
            "PASS player opacity x86 colors, tears/lasers, ownership, nested cleanup and bounds");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
