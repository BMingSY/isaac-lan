#include "engine/lua_api.h"
#include "core/occurrence_mapping.h"
#include "core/animation_pose.h"
#include "engine/versions/j460/layout.h"
#include "engine/visuals.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include "presentation/ambient_effects.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <vector>

#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/entity_links.h"
#include "engine/versions/j460/held_bombs.h"
#include "engine/versions/j460/rails.h"
namespace j460 = isaac::engine::j460;

namespace isaac::visuals {
namespace {
using Address = std::uintptr_t;
namespace pose = core::animation_pose;
namespace animation = j460::layout::animationState;
namespace animationData = j460::layout::animationData;
namespace animationLayer = j460::layout::animationLayer;
constexpr unsigned spriteFormat = 2;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
isaac::lua::API lua{};
Address sprite(lua_State* L) {
    auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
    const auto size = lua.rawLength(L, 1);
    if (!wrapper || (size != 8 && size != 0x11c))
        throw std::runtime_error("Invalid native Sprite wrapper");
    return wrapper[1];
}
int roomRails(lua_State* L) {
    try {
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        const auto game = at<Address>(image, j460::globals::game);
        const auto room = game ? at<Address>(game, 0x18300) : 0;
        if (!lua.getTop(L)) {
            const auto value = j460::rails::grid(room);
            lua.pushLString(L, reinterpret_cast<const char*>(value.data()), value.size());
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 1)
            throw std::runtime_error("Only replicas restore room rails");
        std::size_t size = 0;
        const auto data = lua.checkString(L, 1, &size);
        j460::rails::restore(room, {reinterpret_cast<const std::uint8_t*>(data), size});
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
Address entitySprite(lua_State* L, int index) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, index));
    if (!sample || lua.rawLength(L, index) != 8 || sample[1] < 0x48)
        throw std::runtime_error("Invalid entity Sprite wrapper");
    return sample[1] - 0x48;
}
int entityMinecart(lua_State* L) {
    try {
        const auto entity = entitySprite(L, 1);
        if (lua.getTop(L) == 1) {
            lua.pushInteger(L, j460::entity_links::index(entity));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore minecart links");
        const auto cart = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::entity_links::restore(entity, cart,
                                    reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int actorHeldEntity(lua_State* L) {
    try {
        const auto player = entitySprite(L, 1);
        if (lua.getTop(L) == 1) {
            lua.pushInteger(L, j460::entity_links::heldIndex(player));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore player held entity links");
        const auto held = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::entity_links::restoreHeld(
            player, held, reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int bossHeldBombs(lua_State* L) {
    try {
        const auto entity = entitySprite(L, 1);
        const auto count = j460::held_bombs::slotCount(entity);
        if (lua.getTop(L) == 1) {
            const auto indices = j460::held_bombs::indices(entity);
            for (unsigned i = 0; i < count; ++i)
                lua.pushInteger(L, indices[i]);
            return count;
        }
        if (!runtime::replica() || lua.getTop(L) != static_cast<int>(count + 1))
            throw std::runtime_error("Only replicas restore Boss held bombs");
        std::array<Address, 3> bombs{};
        for (unsigned i = 0; i < count; ++i)
            if (lua.type(L, i + 2) != 1 || lua.toBoolean(L, i + 2))
                bombs[i] = entitySprite(L, i + 2);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Resize = void(__attribute__((thiscall))*)(void*, unsigned);
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::held_bombs::restore(
            entity, bombs, reinterpret_cast<Resize>(image + j460::entry::bossHeldBombsResize),
            reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int prepareEntity(lua_State* L) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (runtime::replica() || !sample || lua.rawLength(L, 1) != 8 || sample[1] < 0x48) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto entity = sample[1] - 0x48;
    if (at<unsigned>(entity, 0x28) == 881) {
        using Prepare = void(__attribute__((thiscall))*)(void*);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        // Background authoritative rooms never render in the host viewport.
        // Compute their Needle body layer poses before capturing the sprite.
        reinterpret_cast<Prepare>(image + j460::entry::nPCNeedlePrepareVisual)(
            reinterpret_cast<void*>(entity));
    }
    lua.pushBoolean(L, true);
    return 1;
}
int localAmbientEffect(lua_State* L) {
    // Share one portable classification with the replica update hook. This
    // query accepts ordinary IDs and never borrows or changes a game object.
    lua.pushBoolean(L, presentation::localAmbientEffect(
                           lua.checkInteger(L, 1), lua.checkInteger(L, 2), lua.checkInteger(L, 3)));
    return 1;
}
int doorSprite(lua_State* L) {
    // ExtraSprite's Lua property returns an owning copy in J460. Expose the
    // door-owned ANM2 through the same non-owning wrapper as GetSprite().
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!sample || lua.rawLength(L, 1) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = sample[1] - 0x40 + 0x27c;
    lua.getMetatable(L, 1);
    lua.setMetatable(L, -2);
    return 1;
}
int gridVariant(lua_State* L) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!runtime::replica() || !sample || lua.rawLength(L, 1) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    at<int>(sample[1] - 0x40, 8) = static_cast<int>(lua.checkInteger(L, 2));
    lua.pushBoolean(L, true);
    return 1;
}
int removeGrid(lua_State* L) {
    const auto index = lua.checkInteger(L, 1);
    if (!runtime::replica() || index < 0 || index >= 448) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    const auto room = at<Address>(at<Address>(image, j460::globals::game), 0x18300);
    using Remove = void(__attribute__((thiscall))*)(void*, int, int, bool);
    // Lua RemoveGridEntity queues removal for a later Room::Update. That
    // pending index would delete a replacement installed by this snapshot.
    reinterpret_cast<Remove>(image + j460::entry::roomRemoveGridEntityImmediate)(
        reinterpret_cast<void*>(room), static_cast<int>(index), 0, false);
    lua.pushBoolean(L, true);
    return 1;
}
int doorSlot(lua_State* L) {
    if (!runtime::replica()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    const auto room = at<Address>(at<Address>(image, j460::globals::game), 0x18300);
    const auto slot = lua.checkInteger(L, 1);
    if (slot == -1) {
        for (unsigned i = 0; i < 8; ++i)
            at<Address>(room, 0x724 + i * 4) = 0;
    } else {
        const auto index = lua.checkInteger(L, 2);
        if (slot < 0 || slot > 7 || index < 0 || index >= 448) {
            lua.pushBoolean(L, false);
            return 1;
        }
        at<unsigned>(room, 0x744 + slot * 4) = static_cast<unsigned>(index);
        if (lua.getTop(L) < 3) {
            using MakeDoor = bool(__attribute__((thiscall))*)(void*, int);
            lua.pushBoolean(L, reinterpret_cast<MakeDoor>(image + j460::entry::roomMakeDoor)(
                                   reinterpret_cast<void*>(room), static_cast<int>(slot)));
            return 1;
        }
        auto sample = static_cast<Address*>(lua.toUserdata(L, 3));
        if (!sample || lua.rawLength(L, 3) != 8) {
            lua.pushBoolean(L, false);
            return 1;
        }
        // The room grid vector owns the door; Room::GetDoor/Render use a
        // separate borrowed slot table. Late Devil/Angel doors need both.
        at<Address>(room, 0x724 + slot * 4) = sample[1] - 0x40;
    }
    lua.pushBoolean(L, true);
    return 1;
}
std::string_view string(Address p) {
    const auto length = at<unsigned>(p, 0x10), capacity = at<unsigned>(p, 0x14);
    if (length > capacity || length > 1024)
        throw std::runtime_error("Invalid sprite path");
    return {reinterpret_cast<const char*>(capacity < 16 ? p : at<Address>(p, 0)), length};
}
unsigned count(Address p, unsigned offset, unsigned limit = 64) {
    const auto n = at<unsigned>(p, offset);
    if (n > limit)
        throw std::runtime_error("Invalid native visual array");
    return n;
}
unsigned number(lan::Reader& r) {
    const auto bits = r.u32();
    if (!std::isfinite(std::bit_cast<float>(bits)))
        throw std::runtime_error("Invalid visual number");
    return bits;
}
unsigned boolean(lan::Reader& r) {
    const auto v = r.u8();
    if (v > 1)
        throw std::runtime_error("Invalid visual flag");
    return v;
}
Address layer(Address s, unsigned id) {
    const auto begin = at<Address>(s, 0x7c);
    for (unsigned i = 0; i < count(s, 0x80); ++i) {
        const auto p = begin + i * 0xa0;
        if (at<unsigned>(at<Address>(p, 0), 0) == id)
            return p;
    }
    return 0;
}
void captureAnimation(lan::Writer& w, Address state) {
    pose::State value;
    const auto data = at<Address>(state, animation::data);
    value.present = data != 0;
    if (data) {
        value.frame = at<unsigned>(state, animation::frame);
        value.playing = at<bool>(state, animation::playing);
        value.events = at<unsigned>(state, animation::events);
        value.previousEvents = at<unsigned>(state, animation::previousEvents);
        value.layerCount = count(data, animationData::layerCount, pose::maxLayers);
        value.nullCount = count(data, animationData::nullCount, pose::maxNullLayers);
        if ((value.layerCount && (!at<Address>(data, animationData::layers) ||
                                  !at<Address>(state, animation::layerFrames))) ||
            (value.nullCount && (!at<Address>(data, animationData::nulls) ||
                                 !at<Address>(state, animation::nullFrames))))
            throw std::runtime_error("Missing native animation frame array");
        for (unsigned i = 0; i < value.layerCount; ++i) {
            const auto entry =
                at<Address>(data, animationData::layers) + i * animationLayer::stride;
            const auto id = at<unsigned>(entry, animationLayer::id);
            if (id >= pose::maxLayers)
                throw std::runtime_error("Invalid native animation layer ID");
            value.layers[i] = {
                static_cast<std::uint16_t>(id),
                at<int>(at<Address>(state, animation::layerFrames), i * sizeof(int))};
        }
        for (unsigned i = 0; i < value.nullCount; ++i) {
            const auto entry = at<Address>(data, animationData::nulls) + i * animationLayer::stride;
            const auto id = at<unsigned>(entry, animationLayer::id);
            if (id >= pose::maxNullLayers)
                throw std::runtime_error("Invalid native attachment layer ID");
            value.nulls[i] = {static_cast<std::uint16_t>(id),
                              at<int>(at<Address>(state, animation::nullFrames), i * sizeof(int))};
        }
    }
    pose::write(w, value);
}
void applyAnimation(lan::Reader& r, Address state) {
    const auto value = pose::read(r);
    const auto data = at<Address>(state, animation::data);
    if (!value.present) {
        if (data) {
            using Reset = void(__attribute__((thiscall))*)(void*, void*);
            reinterpret_cast<Reset>(reinterpret_cast<Address>(GetModuleHandleW(nullptr)) +
                                    j460::entry::animationStateReset)(
                reinterpret_cast<void*>(state), nullptr);
        }
        return;
    }
    if (!data)
        return;
    at<unsigned>(state, animation::frame) = value.frame;
    at<bool>(state, animation::playing) = value.playing;
    at<unsigned>(state, animation::events) = value.events;
    at<unsigned>(state, animation::previousEvents) = value.previousEvents;
    for (unsigned i = 0; i < value.layerCount; ++i) {
        const auto [id, frameIndex] = value.layers[i];
        const int order = at<int>(data, animationData::layerMap + id * sizeof(int));
        if (order < 0 || static_cast<unsigned>(order) >= count(data, animationData::layerCount))
            continue;
        const auto frames =
            count(at<Address>(data, animationData::layers) + order * animationLayer::stride,
                  animationLayer::frameCount, pose::maxFrames);
        if (pose::validCursor(frameIndex, frames))
            at<int>(at<Address>(state, animation::layerFrames), order * sizeof(int)) = frameIndex;
    }
    const auto nulls = at<Address>(data, animationData::nulls);
    const auto frames = at<Address>(state, animation::nullFrames);
    const auto localCount = count(data, animationData::nullCount, pose::maxNullLayers);
    if (localCount && (!nulls || !frames))
        throw std::runtime_error("Missing native attachment frame array");
    for (unsigned i = 0; i < localCount; ++i)
        at<int>(frames, i * sizeof(int)) = -1;
    for (unsigned i = 0; i < value.nullCount; ++i) {
        const auto [id, frameIndex] = value.nulls[i];
        unsigned order = i;
        if (order >= localCount ||
            at<unsigned>(nulls + order * animationLayer::stride, animationLayer::id) != id) {
            for (order = 0; order < localCount; ++order)
                if (at<unsigned>(nulls + order * animationLayer::stride, animationLayer::id) == id)
                    break;
        }
        if (order == localCount)
            continue;
        const auto limit = count(nulls + order * animationLayer::stride,
                                 animationLayer::nullFrameCount, pose::maxFrames);
        if (pose::validCursor(frameIndex, limit))
            at<int>(frames, order * sizeof(int)) = frameIndex;
    }
}
constexpr std::array<unsigned, 18> layerNumbers = {0x34, 0x38, 0x3c, 0x40, 0x44, 0x48,
                                                   0x4c, 0x50, 0x54, 0x58, 0x5c, 0x60,
                                                   0x64, 0x68, 0x6c, 0x70, 0x90, 0x94};
int spriteAnimationLength(lua_State* L) {
    try {
        const auto data = at<Address>(sprite(L) + j460::layout::sprite::animation, animation::data);
        lua.pushInteger(L, data ? count(data, animationData::totalFrames, pose::maxFrames) : 0);
        return 1;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int spriteState(lua_State* L) {
    try {
        const auto s = sprite(L);
        if (lua.getTop(L) == 1) {
            const auto n = count(s, 0x80);
            // Reserve typical header/layer payloads once; longer paths still
            // grow normally. This changes allocation, never the wire layout.
            constexpr std::size_t headerReserve = 256, layerReserve = 256;
            lan::Writer w(lan::Message::world, headerReserve + n * layerReserve);
            w.u8(spriteFormat);
            captureAnimation(w, s + 0x30);
            captureAnimation(w, s + 0x50);
            w.u32(at<unsigned>(s, 0x10c));
            // Colorize/champion colors and rendering flags are not exposed by
            // the seven Lua Color channels. They affect blood/floor decals.
            for (unsigned offset = 0xa8; offset < 0x100; offset += 4)
                w.u32(at<unsigned>(s, offset));
            w.u32(at<unsigned>(s, 0x104));
            w.u32(at<unsigned>(s, 0x110));
            w.u8(at<bool>(s, 0x70));
            w.u16(n);
            for (unsigned i = 0; i < n; ++i) {
                const auto p = at<Address>(s, 0x7c) + i * 0xa0;
                w.u16(at<unsigned>(at<Address>(p, 0), 0));
                w.string(string(p + 8));
                for (auto offset : {0x32u, 0x33u, 0x74u})
                    w.u8(at<bool>(p, offset));
                for (auto offset : layerNumbers)
                    w.u32(at<unsigned>(p, offset));
                for (unsigned offset = 0x78; offset < 0x8c; offset += 4)
                    w.u32(at<unsigned>(p, offset));
                w.u32(at<unsigned>(p, 0x8c));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply visual state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        if (r.u8() != spriteFormat)
            throw std::runtime_error("Invalid native Sprite format");
        applyAnimation(r, s + 0x30);
        applyAnimation(r, s + 0x50);
        const int shadowLayer = static_cast<int>(r.u32());
        if (shadowLayer < -1 || shadowLayer >= 64)
            throw std::runtime_error("Invalid shadow layer");
        at<int>(s, 0x10c) = shadowLayer >= 0 && !layer(s, shadowLayer) ? -1 : shadowLayer;
        for (unsigned offset = 0xa8; offset < 0x100; offset += 4)
            at<unsigned>(s, offset) = number(r);
        at<unsigned>(s, 0x104) = number(r);
        at<unsigned>(s, 0x110) = r.u32();
        at<bool>(s, 0x70) = boolean(r);
        const auto n = r.u16();
        if (n > 64)
            throw std::runtime_error("Too many sprite layers");
        unsigned changed = 0;
        for (unsigned i = 0; i < n; ++i) {
            const auto id = r.u16();
            const auto path = r.stringView();
            const auto p = layer(s, id);
            if (p && path != string(p + 8)) {
                if (!changed)
                    lua.createTable(L, 0, 0);
                lua.createTable(L, 2, 0);
                lua.pushInteger(L, id);
                lua.rawSetI(L, -2, 1);
                lua.pushLString(L, path.data(), path.size());
                lua.rawSetI(L, -2, 2);
                lua.rawSetI(L, -2, ++changed);
            }
            for (auto offset : {0x32u, 0x33u, 0x74u}) {
                const auto v = boolean(r);
                if (p)
                    at<bool>(p, offset) = v;
            }
            for (auto offset : layerNumbers) {
                const auto v = number(r);
                if (p)
                    at<unsigned>(p, offset) = v;
            }
            for (unsigned offset = 0x78; offset < 0x8c; offset += 4) {
                const auto v = r.u32();
                if (v > 32)
                    throw std::runtime_error("Invalid sprite blend mode");
                if (p)
                    at<unsigned>(p, offset) = v;
            }
            const auto flags = r.u32();
            if (p)
                at<unsigned>(p, 0x8c) = flags;
        }
        r.finish();
        if (!changed)
            lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
std::vector<Address> costumes(Address player) {
    const auto first = at<Address>(player, 0x1220), last = at<Address>(player, 0x1224);
    if (last < first || (last - first) % 0x130 || last - first > 4096 * 0x130)
        throw std::runtime_error("Invalid costume array");
    std::vector<Address> result;
    for (auto p = first; p < last; p += 0x130)
        result.push_back(p);
    return result;
}
int entityShadow(lua_State* L) {
    try {
        // EntityList::RenderShadows and Entity::RenderShadowLayer read these
        // three shadow floats and native altitude in J460. Update initializes them;
        // replicas must receive them instead of drawing constructor shadows.
        const auto entity = sprite(L) - 0x48;
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world, 1 + 4 * sizeof(std::uint32_t));
            for (auto offset : {0x15cu, 0x160u, 0x164u, 0x350u})
                w.u32(at<unsigned>(entity, offset));
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply entity shadows");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        for (auto offset : {0x15cu, 0x160u, 0x164u, 0x350u})
            at<unsigned>(entity, offset) = number(r);
        r.finish();
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int familiarBody(lua_State* L) {
    try {
        namespace body = j460::layout::familiarBody;
        const auto familiar = entitySprite(L, 1);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Body sprites require a familiar");
        const auto data = at<Address>(familiar, body::extraData);
        if (!data || at<Address>(data, 0) != image + body::dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        if (lua.getTop(L) != 1) {
            if (!runtime::replica() || lua.getTop(L) != 2)
                throw std::runtime_error("Only replicas restore familiar body layers");
            std::size_t size = 0;
            const auto bytes = lua.checkString(L, 2, &size);
            lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
            std::array<int, body::layerCount> layers{};
            for (unsigned i = 0; i < layers.size(); ++i) {
                layers[i] = std::bit_cast<int>(r.u32());
                const auto s = data + body::sprites + (i + 1) * j460::layout::sprite::size;
                if (layers[i] < -1 || (layers[i] >= 0 && !layer(s, layers[i])))
                    throw std::runtime_error("Invalid familiar body layer");
            }
            r.finish();
            for (unsigned i = 0; i < layers.size(); ++i)
                at<int>(data, body::layers + i * sizeof(int)) = layers[i];
            lua.pushBoolean(L, true);
            return 1;
        }
        lan::Writer w(lan::Message::world);
        for (unsigned i = 0; i < body::layerCount; ++i)
            w.u32(at<unsigned>(data, body::layers + i * sizeof(int)));
        lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
        lua.createTable(L, body::spriteCount, 0);
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        for (unsigned i = 0; i < body::spriteCount; ++i) {
            const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
            wrapper[0] = source[0];
            wrapper[1] = data + body::sprites + i * j460::layout::sprite::size;
            lua.getMetatable(L, 1);
            lua.setMetatable(L, -2);
            lua.rawSetI(L, -2, i + 1);
        }
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int familiarTether(lua_State* L) {
    try {
        namespace tether = j460::layout::tether;
        const auto familiar = entitySprite(L, 1);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Tether capture requires a familiar");
        const auto data = at<Address>(familiar, tether::extraData);
        if (!data || at<Address>(data, 0) != image + tether::dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        const auto count = at<unsigned>(data, tether::count);
        const auto capacity = at<unsigned>(data, tether::capacity);
        const auto first = at<unsigned>(data, tether::first);
        if (count > tether::maxPoints || count > capacity || capacity > 4096 ||
            (count && (!capacity || (capacity & (capacity - 1)))))
            throw std::runtime_error("Invalid native tether points");
        lan::Writer w(lan::Message::world);
        w.u16(count);
        const auto points = at<Address>(data, tether::points);
        for (unsigned i = 0; i < count; ++i) {
            const auto point =
                at<Address>(points, ((first + i) & (capacity - 1)) * sizeof(Address));
            for (unsigned axis = 0; axis < 3; ++axis) {
                const auto value = at<float>(point, axis * sizeof(float));
                if (!std::isfinite(value))
                    throw std::runtime_error("Invalid tether coordinate");
                w.u32(std::bit_cast<unsigned>(value));
            }
        }
        lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = source[0];
        wrapper[1] = data + tether::sprite;
        lua.getMetatable(L, 1);
        lua.setMetatable(L, -2);
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int renderTether(lua_State* L) {
    try {
        namespace tether = j460::layout::tether;
        if (!runtime::replica())
            throw std::runtime_error("Only replicas draw tether snapshots");
        const auto familiar = entitySprite(L, 1);
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Tether rendering requires a familiar");
        const auto spriteSize = lua.rawLength(L, 2);
        const auto spriteWrapper = static_cast<const Address*>(lua.toUserdata(L, 2));
        if (!spriteWrapper || (spriteSize != 8 && spriteSize != j460::layout::sprite::size + 8))
            throw std::runtime_error("Invalid tether Sprite");
        std::size_t length = 0;
        const auto bytes = lua.checkString(L, 3, &length);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), length});
        const auto count = r.u16();
        if (count > tether::maxPoints)
            throw std::runtime_error("Too many tether points");
        std::array<std::array<float, 3>, tether::maxPoints> points{};
        std::array<Address, tether::maxPoints> map{};
        for (unsigned i = 0; i < count; ++i) {
            for (auto& axis : points[i])
                axis = std::bit_cast<float>(number(r));
            map[i] = reinterpret_cast<Address>(points[i].data());
        }
        r.finish();
        if (count > 1) {
            const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
            alignas(Address) std::array<std::byte, tether::size> storage{};
            const auto data = reinterpret_cast<Address>(storage.data());
            at<Address>(data, 0) = image + tether::dataVtable;
            at<Address>(data, tether::points) = reinterpret_cast<Address>(map.data());
            at<unsigned>(data, tether::capacity) = tether::maxPoints;
            at<unsigned>(data, tether::count) = count;
            // The render routine only borrows this ANM2 and point deque. Neither
            // the stack view nor its shallow Sprite copy is ever destroyed as
            // a native owner, and no update/weapon gameplay is invoked.
            std::memcpy(storage.data() + tether::sprite, reinterpret_cast<void*>(spriteWrapper[1]),
                        j460::layout::sprite::size);
            struct Borrow {
                Address& target;
                Address saved;
                ~Borrow() {
                    target = saved;
                }
            } borrow{at<Address>(familiar, tether::extraData),
                     at<Address>(familiar, tether::extraData)};
            borrow.target = data;
            const std::array<float, 2> offset{};
            using Render = void(__attribute__((thiscall))*)(void*, const void*, int);
            reinterpret_cast<Render>(image + j460::entry::familiarRenderTether)(
                reinterpret_cast<void*>(familiar), offset.data(), 0);
        }
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int actorPose(lua_State* L) {
    try {
        const auto player = sprite(L) - 0x48;
        if (at<unsigned>(player, 0x28) != 1)
            throw std::runtime_error("Actor visual state requires a player");
        const auto current = costumes(player);
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world);
            w.u8(at<bool>(player, 0x1398));
            w.u8(at<bool>(player, 0x139a));
            w.u32(at<unsigned>(player, 0x1338));
            // J460 Render reads damageCooldown modulo six to hide the body.
            // Replica Update is suppressed, so an arrival cooldown otherwise
            // stays on the same invisible frame until the next floor reload.
            w.u32(at<unsigned>(player, 0x13bc));
            // Night Light smooths its beam angle in Player::Update.
            w.u32(at<unsigned>(player, j460::layout::player::nightLightAngle));
            for (unsigned slot = 0; slot < 5; ++slot) {
                const auto weapon = at<Address>(player, j460::layout::player::weapons + slot * 4);
                w.u8(weapon != 0);
                if (weapon) {
                    w.u32(at<unsigned>(weapon, 0x30));
                    for (auto offset : {0xcu, 0x10u, 0x14u})
                        w.u32(at<unsigned>(weapon, offset));
                    using MaxCharge = float(__attribute__((thiscall))*)(void*);
                    const auto query =
                        at<MaxCharge>(at<Address>(weapon, 0),
                                      j460::layout::weapon::maxChargeMethod * sizeof(Address));
                    const auto maximum = query(reinterpret_cast<void*>(weapon));
                    // Native item combinations can return a negative limit.
                    // It is read-only metadata: preview requires a positive
                    // limit, while gameplay and cooldowns remain authoritative.
                    if (!std::isfinite(maximum))
                        throw std::runtime_error("Invalid native weapon charge limit");
                    w.u32(std::bit_cast<unsigned>(maximum));
                    w.u32(at<unsigned>(weapon, j460::layout::weapon::modifiers));
                }
            }
            w.u16(current.size());
            for (auto p : current)
                w.string(string(p));
            for (unsigned i = 0; i < 15; ++i) {
                const auto p = player + 0x122c + i * 0x10;
                for (auto offset : {0u, 4u, 8u})
                    w.u32(at<unsigned>(p, offset));
                w.u8(at<bool>(p, 0xc));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply actor pose");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        at<bool>(player, 0x1398) = boolean(r);
        at<bool>(player, 0x139a) = boolean(r);
        at<unsigned>(player, 0x1338) = r.u32();
        at<unsigned>(player, 0x13bc) = r.u32();
        at<unsigned>(player, j460::layout::player::nightLightAngle) = number(r);
        for (unsigned slot = 0; slot < 5; ++slot)
            if (boolean(r)) {
                const auto type = r.u32();
                std::array<unsigned, 3> values{};
                for (auto& value : values)
                    value = number(r);
                number(r); // Native charge limit is read-only prediction metadata.
                const auto modifiers = r.u32();
                const auto weapon = at<Address>(player, 0x13dc + slot * 4);
                if (weapon && at<unsigned>(weapon, 0x30) == type) {
                    at<unsigned>(weapon, 0xc) = values[0];
                    at<unsigned>(weapon, 0x10) = values[1];
                    at<unsigned>(weapon, 0x14) = values[2];
                    at<unsigned>(weapon, j460::layout::weapon::modifiers) = modifiers;
                }
            }
        const auto n = r.u16();
        if (n > 4096)
            throw std::runtime_error("Too many costumes");
        std::vector<std::string_view> localPaths, remotePaths;
        localPaths.reserve(current.size());
        remotePaths.reserve(n);
        for (const auto costume : current)
            localPaths.push_back(string(costume));
        for (unsigned i = 0; i < n; ++i)
            remotePaths.push_back(r.stringView());
        const auto mapping = core::mapOccurrences(localPaths, remotePaths);
        for (unsigned i = 0; i < 15; ++i) {
            const int remote = static_cast<int>(r.u32()), layerID = static_cast<int>(r.u32());
            const auto priority = r.u32(), body = boolean(r);
            const auto p = player + 0x122c + i * 0x10;
            const int local =
                remote >= 0 && static_cast<unsigned>(remote) < n ? mapping[remote] : -1;
            // A cosmetic Mod absent on this peer must not leave a dangling
            // costume index. The native base layer remains a valid fallback.
            at<int>(p, 0) = local;
            at<int>(p, 4) = local >= 0 ? layerID : static_cast<int>(i);
            at<unsigned>(p, 8) = priority;
            at<bool>(p, 0xc) = body;
        }
        r.finish();
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}

} // namespace
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::type,
                           isaac::lua::Symbol::toBoolean, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::newUserdata,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushInteger, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    lua.pushClosure(L, spriteState, 0);
    lua.setField(L, -2, "sprite_state");
    lua.pushClosure(L, spriteAnimationLength, 0);
    lua.setField(L, -2, "sprite_animation_length");
    lua.pushClosure(L, bossHeldBombs, 0);
    lua.setField(L, -2, "boss_held_bombs");
    lua.pushClosure(L, entityMinecart, 0);
    lua.setField(L, -2, "entity_minecart");
    lua.pushClosure(L, actorHeldEntity, 0);
    lua.setField(L, -2, "actor_held_entity");
    lua.pushClosure(L, roomRails, 0);
    lua.setField(L, -2, "room_rails");
    lua.pushClosure(L, actorPose, 0);
    lua.setField(L, -2, "actor_pose");
    lua.pushClosure(L, familiarTether, 0);
    lua.setField(L, -2, "familiar_tether");
    lua.pushClosure(L, familiarBody, 0);
    lua.setField(L, -2, "familiar_body");
    lua.pushClosure(L, renderTether, 0);
    lua.setField(L, -2, "familiar_tether_render");
    lua.pushClosure(L, entityShadow, 0);
    lua.setField(L, -2, "entity_shadow");
    lua.pushClosure(L, prepareEntity, 0);
    lua.setField(L, -2, "entity_prepare");
    lua.pushClosure(L, localAmbientEffect, 0);
    lua.setField(L, -2, "presentation_local_effect");
    lua.pushClosure(L, gridVariant, 0);
    lua.setField(L, -2, "grid_variant");
    lua.pushClosure(L, removeGrid, 0);
    lua.setField(L, -2, "grid_remove");
    lua.pushClosure(L, doorSprite, 0);
    lua.setField(L, -2, "door_sprite");
    lua.pushClosure(L, doorSlot, 0);
    lua.setField(L, -2, "door_slot");
    return true;
}
} // namespace isaac::visuals
