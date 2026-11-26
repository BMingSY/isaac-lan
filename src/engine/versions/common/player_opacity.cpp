#include "engine/versions/common/player_seats.h"
#include "engine/player_opacity.h"
#include "engine/versions/common/player_opacity_bindings.h"
#include <array>
#include <unordered_map>

namespace isaac::presentation::player_opacity {
namespace {
using Address = std::uintptr_t;
using Factors = std::unordered_map<Address, float>;
constexpr unsigned maximum = 100;
unsigned defaultOthers = maximum;
std::array<unsigned, party::maxPlayers> percentages = [] {
    std::array<unsigned, party::maxPlayers> result;
    result.fill(maximum);
    return result;
}();
const Factors* activeSprites = nullptr;
const Factors* activePlayers = nullptr;
Address additionalSprite = 0;
float additionalFactor = 1;
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
    const auto count = api.getTop(L);
    bool valid =
        count == engine::player_seats::nativeGamepads || count == static_cast<int>(next.size());
    for (int i = 0; valid && i < count; ++i) {
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
bool playersActive() {
    return activePlayers && !activePlayers->empty();
}
std::optional<float> spriteFactor(Address sprite) {
    if (sprite && sprite == additionalSprite)
        return additionalFactor;
    if (activeSprites) {
        const auto found = activeSprites->find(sprite);
        if (found != activeSprites->end())
            return found->second;
    }
    return std::nullopt;
}
std::optional<float> playerFactor(Address player) {
    if (activePlayers) {
        const auto found = activePlayers->find(player);
        if (found != activePlayers->end())
            return found->second;
    }
    return std::nullopt;
}
void withSprite(Address sprite, float factor, const std::function<void()>& render) {
    struct Restore {
        Address sprite = additionalSprite;
        float factor = additionalFactor;
        ~Restore() {
            additionalSprite = sprite;
            additionalFactor = factor;
        }
    } restore;
    additionalSprite = sprite;
    additionalFactor = factor;
    render();
}
void withPlayers(std::span<const Address> players, unsigned connected,
                 const std::function<void()>& render) {
    Factors sprites, owners;
    for (const auto player : players) {
        if (!player)
            continue;
        const auto controller =
            isaac::engine::player_seats::owner(player, read<int>(player, layoutFields.controller));
        if (controller < 1 || controller > static_cast<int>(percentages.size()) ||
            !(connected & (1u << (controller - 1))))
            continue;
        const auto percent = percentages[controller - 1];
        const auto factor = static_cast<float>(percent) / maximum;
        owners.emplace(player, factor);
        if (percent == maximum)
            continue;
        for (const auto offset : layoutFields.sprites)
            sprites.emplace(player + offset, factor);
        const auto begin = read<Address>(player, layoutFields.costumesBegin);
        const auto end = read<Address>(player, layoutFields.costumesEnd);
        if (end < begin || (end - begin) % layoutFields.costumeStride ||
            (end - begin) / layoutFields.costumeStride > layoutFields.maximumCostumes)
            continue;
        for (auto sprite = begin; sprite < end; sprite += layoutFields.costumeStride)
            sprites.emplace(sprite, factor);
    }
    struct Restore {
        const Factors* previous = activeSprites;
        const Factors* players = activePlayers;
        Address sprite = additionalSprite;
        float factor = additionalFactor;
        ~Restore() {
            activeSprites = previous;
            activePlayers = players;
            additionalSprite = sprite;
            additionalFactor = factor;
        }
    } restore;
    additionalSprite = 0;
    additionalFactor = 1;
    activeSprites = &sprites;
    activePlayers = &owners;
    render();
}
} // namespace isaac::presentation::player_opacity
