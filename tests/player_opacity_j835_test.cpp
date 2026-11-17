#include "test_support.h"
#include "native_branch.h"
#include "engine/versions/j835/player_opacity.cpp"
#include "engine/versions/common/player_opacity.cpp"
#include <cstring>
#include <vector>

namespace opacity = isaac::presentation::player_opacity;
namespace backend = isaac::engine::j835;
namespace layout = backend::layout;
using Address = std::uintptr_t;
namespace {
constexpr unsigned imageSize = 0x600000, stubBase = 0x10000, stubStride = 32;
unsigned char* image = nullptr;
std::array<unsigned char, 1024> frame{}, projectile{}, intermediary{};
std::array<unsigned char, layout::player::controller + sizeof(int)> player{};
using Color = std::array<float, 11>;
Color drawColor{};
std::optional<float> expectedFactor;
unsigned draws = 0;
const auto sprite = reinterpret_cast<Address>(projectile.data()) + layout::entity::sprite;
const auto frameBase = reinterpret_cast<Address>(frame.data() + frame.size() / 2);
template <class T> T& at(Address object, std::ptrdiff_t offset) {
    return *reinterpret_cast<T*>(object + offset);
}
void jump(unsigned rva, Address target) {
    image[rva] = 0xe9;
    at<std::int32_t>(reinterpret_cast<Address>(image), rva + 1) =
        target - reinterpret_cast<Address>(image + rva + 5);
}
void __attribute__((thiscall)) draw(void* self, void* position, void* topLeft, void* bottomRight) {
    require(reinterpret_cast<Address>(self) == sprite && position == reinterpret_cast<void*>(1) &&
                topLeft == reinterpret_cast<void*>(2) && bottomRight == reinterpret_cast<void*>(3),
            "Original sprite renderer lost its thiscall arguments");
    require(opacity::spriteFactor(sprite) == expectedFactor,
            "Sprite factor escaped its native caller or missed the owning player");
    ++draws;
}
void __attribute__((thiscall)) drawLayer(void* self, int layer, void* position, void* topLeft,
                                         void* bottomRight) {
    require(layer == 7, "Sprite layer adapter lost the layer argument");
    draw(self, position, topLeft, bottomRight);
}
unsigned caller(unsigned after, unsigned entry, unsigned arguments) {
    const auto start = after - 5 - arguments * 4;
    auto* code = image + start;
    for (unsigned argument = 0; argument < arguments; ++argument) {
        *code++ = 0xff;
        *code++ = 0x74;
        *code++ = 0x24;
        *code++ = arguments * sizeof(Address);
    }
    *code++ = 0xe8;
    at<std::int32_t>(reinterpret_cast<Address>(code), 0) = entry - after;
    code += 4;
    *code++ = 0xc2;
    *code++ = arguments * sizeof(Address);
    *code = 0;
    return start;
}
void prepare() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize opacity fixture");
    for (unsigned pass = 0; pass < opacity::entries.size(); ++pass) {
        const auto entry = opacity::entries[pass];
        std::memset(image + entry, 0x90, 5);
        auto* code = image + entry + 5;
        if (pass != opacity::sprite) {
            const unsigned char cleanup[]{0x8d, 0x64, 0x24, 12};
            std::memcpy(code, cleanup, sizeof(cleanup));
            code += sizeof(cleanup);
        }
        *code = 0xc3;
        const auto start = stubBase + pass * stubStride;
        code = image + start;
        if (pass != opacity::sprite) {
            *code++ = 0x68;
            at<Address>(reinterpret_cast<Address>(code), 0) =
                reinterpret_cast<Address>(drawColor.data());
            code += sizeof(Address);
            *code++ = 0x6a;
            *code++ = 0;
            *code++ = 0x6a;
            *code++ = 0;
        }
        jump(static_cast<unsigned>(code - image), reinterpret_cast<Address>(image + entry));
    }
    jump(backend::entry::spriteRender, reinterpret_cast<Address>(draw));
    jump(backend::entry::spriteRenderLayer, reinterpret_cast<Address>(drawLayer));
    caller(backend::entry::entitySpriteRenderReturn, backend::entry::spriteRender, 3);
    caller(backend::entry::laserSpriteRenderReturn, backend::entry::spriteRender, 3);
    caller(backend::entry::laserLayerRenderReturn, backend::entry::spriteRenderLayer, 4);
    caller(0x300000, backend::entry::spriteRender, 3);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    at<int>(reinterpret_cast<Address>(player.data()), layout::player::controller) = 2;
    at<Address>(reinterpret_cast<Address>(projectile.data()), layout::entity::spawner) =
        reinterpret_cast<Address>(intermediary.data());
    at<Address>(reinterpret_cast<Address>(intermediary.data()), layout::entity::spawner) =
        reinterpret_cast<Address>(player.data());
    at<Address>(frameBase, layout::spriteRenderFrame::sprite) = sprite;
    at<Address>(frameBase, layout::laserRenderFrame::segmentEntity) =
        reinterpret_cast<Address>(projectile.data());
    at<Address>(frameBase, layout::laserRenderFrame::shadowEntity) =
        reinterpret_cast<Address>(projectile.data());
    opacity::percentages = {100, 25, 0, 50};
}
void install() {
    std::vector<unsigned> targets(opacity::entries.begin(), opacity::entries.end());
    targets.push_back(backend::entry::spriteRender);
    targets.push_back(backend::entry::spriteRenderLayer);
    const auto base = reinterpret_cast<Address>(image);
    require(!opacity::install(0), "Missing opacity image accepted");
    for (auto collision : targets) {
        require(MH_CreateHook(image + collision, reinterpret_cast<void*>(draw), nullptr) == MH_OK &&
                    !opacity::install(base),
                "Partial opacity install succeeded");
        for (auto target : targets) {
            const auto result =
                MH_CreateHook(image + target, reinterpret_cast<void*>(draw), nullptr);
            require(result == (target == collision ? MH_ERROR_ALREADY_CREATED : MH_OK),
                    "Opacity rollback retained own hooks or removed a foreign hook");
            if (target != collision)
                MH_RemoveHook(image + target);
        }
        require(MH_RemoveHook(image + collision) == MH_OK, "Remove conflicting opacity hook");
    }
    require(opacity::install(base) && opacity::install(base) && !opacity::install(base + 1),
            "Opacity install did not recover or accepted a different image");
}
void boundary(unsigned pass, float expected) {
    const Color source{0.3f, 0.7f, 0.9f, 0.8f, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.7f};
    auto& color = pass == opacity::sprite ? at<Color>(frameBase, layout::spriteRenderFrame::color)
                                          : drawColor;
    color = source;
    auto wanted = source;
    wanted[3] = expected;
    const auto snapshot = projectile;
    native_fixture::Registers registers{sprite,     sprite,     frameBase,  0,
                                        0x44445555, 0x55556666, 0x66667777, 0x77778888};
    const auto result = native_fixture::branch(image + stubBase + pass * stubStride, registers);
    require(result.balanced && result.floatingPreserved && color == wanted &&
                projectile == snapshot,
            "Opacity boundary changed source state, tint channels, stack or floating state");
    for (unsigned i = 0; i < registers.size(); ++i)
        if (i != 3)
            require(result.registers[i] == registers[i], "Opacity boundary corrupted a register");
    static unsigned flags = result.flags;
    require(result.flags == flags, "Opacity boundary corrupted flags");
}
void sprites(unsigned returnAddress, bool layer, std::optional<float> factor) {
    expectedFactor = factor;
    const auto start = returnAddress - 5 - (layer ? 4u : 3u) * 4;
    if (layer)
        reinterpret_cast<opacity::RenderLayer>(image + start)(
            reinterpret_cast<void*>(sprite), 7, reinterpret_cast<void*>(1),
            reinterpret_cast<void*>(2), reinterpret_cast<void*>(3));
    else
        reinterpret_cast<opacity::Render>(image + start)(
            reinterpret_cast<void*>(sprite), reinterpret_cast<void*>(1), reinterpret_cast<void*>(2),
            reinterpret_cast<void*>(3));
    require(!opacity::spriteFactor(sprite), "Projectile sprite factor outlived the native draw");
}
void behavior() {
    for (unsigned pass = 0; pass < opacity::entries.size(); ++pass)
        boundary(pass, 0.8f);
    install();
    const std::array players{reinterpret_cast<Address>(player.data())};
    opacity::withPlayers(players, 2, [&] {
        for (unsigned pass = 1; pass < opacity::entries.size(); ++pass)
            boundary(pass, 0.2f);
        opacity::withSprite(sprite, 0.25f, [&] {
            boundary(opacity::sprite, 0.2f);
            opacity::withPlayers({}, 0, [&] { boundary(opacity::sprite, 0.8f); });
            boundary(opacity::sprite, 0.2f);
        });
        sprites(backend::entry::laserSpriteRenderReturn, false, 0.25f);
        sprites(backend::entry::laserLayerRenderReturn, true, 0.25f);
        sprites(0x300000, false, std::nullopt);
        at<unsigned>(reinterpret_cast<Address>(projectile.data()), layout::entity::type) = 2;
        sprites(backend::entry::entitySpriteRenderReturn, false, std::nullopt);
        at<Address>(reinterpret_cast<Address>(projectile.data()), layout::entity::spawner) =
            players[0];
        sprites(backend::entry::entitySpriteRenderReturn, false, 0.25f);
        at<unsigned>(reinterpret_cast<Address>(projectile.data()), layout::entity::type) = 3;
        sprites(backend::entry::entitySpriteRenderReturn, false, std::nullopt);
        at<Address>(reinterpret_cast<Address>(projectile.data()), layout::entity::spawner) =
            reinterpret_cast<Address>(projectile.data());
        for (unsigned pass = 1; pass < opacity::entries.size(); ++pass)
            boundary(pass, 0.8f);
        at<Address>(reinterpret_cast<Address>(projectile.data()), layout::entity::spawner) =
            players[0];
        opacity::withPlayers(players, 1, [&] {
            for (unsigned pass = 1; pass < opacity::entries.size(); ++pass)
                boundary(pass, 0.8f);
        });
        try {
            opacity::withSprite(sprite, 0.5f,
                                [] { throw std::runtime_error("Fixture render failure"); });
        } catch (const std::runtime_error&) {
        }
        require(!opacity::spriteFactor(sprite), "Failed render retained a borrowed sprite");
        for (unsigned percent : {0u, 100u, 50u}) {
            opacity::percentages[1] = percent;
            opacity::withPlayers(players, 2, [&] {
                for (unsigned pass = 1; pass < opacity::entries.size(); ++pass)
                    boundary(pass, 0.8f * percent / 100);
            });
        }
    });
    require(draws == 6 && !opacity::playerFactor(players[0]),
            "Render scope retained player addresses");
    for (unsigned pass = 0; pass < opacity::entries.size(); ++pass)
        boundary(pass, 0.8f);
}
} // namespace
int main() {
    prepare();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release opacity fixture");
}
