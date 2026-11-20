#include "engine/versions/common/sprite_state.h"
#include "engine/versions/common/sprite_state_bindings.h"
#include "engine/lua_api.h"
#include "core/animation_pose.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <bit>
#include <bitset>
#include <cmath>

namespace isaac::engine::native_sprite {
namespace {
using Address = std::uintptr_t;
namespace pose = core::animation_pose;
constexpr unsigned format = 2, maxPath = 1024, maxBlend = 32;
Address image = 0;
isaac::lua::API lua{};
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
unsigned count(Address object, unsigned offset, unsigned limit = pose::maxLayers) {
    const auto value = at<unsigned>(object, offset);
    if (value > limit)
        throw std::runtime_error("Invalid native visual array");
    return value;
}
Address sprite(lua_State* L) {
    const auto wrapper = static_cast<const Address*>(lua.toUserdata(L, 1));
    const auto size = lua.rawLength(L, 1);
    if (!wrapper || (size != 8 && size != bindings.sprite.size + 8) || !wrapper[1])
        throw std::runtime_error("Invalid native Sprite wrapper");
    return wrapper[1];
}
unsigned number(lan::Reader& reader) {
    const auto value = reader.u32();
    if (!std::isfinite(std::bit_cast<float>(value)))
        throw std::runtime_error("Invalid visual number");
    return value;
}
bool boolean(lan::Reader& reader) {
    const auto value = reader.u8();
    if (value > 1)
        throw std::runtime_error("Invalid visual flag");
    return value;
}
Address layerAt(Address sprite, unsigned order) {
    const auto first = at<Address>(sprite, bindings.sprite.layers);
    if (!first)
        throw std::runtime_error("Missing native Sprite layers");
    return first + order * bindings.layer.stride;
}
unsigned layerId(Address layer) {
    const auto data = at<Address>(layer, bindings.layer.data);
    if (!data)
        throw std::runtime_error("Missing native Sprite layer data");
    const auto id = at<unsigned>(data, bindings.layer.id);
    if (id >= pose::maxLayers)
        throw std::runtime_error("Invalid native Sprite layer ID");
    return id;
}
void captureAnimation(lan::Writer& w, Address state) {
    pose::State value;
    const auto data = at<Address>(state, bindings.animation.data);
    value.present = data != 0;
    if (data) {
        value.frame = at<unsigned>(state, bindings.animation.frame);
        value.playing = at<bool>(state, bindings.animation.playing);
        value.events = at<unsigned>(state, bindings.animation.events);
        value.previousEvents = at<unsigned>(state, bindings.animation.previousEvents);
        value.layerCount = count(data, bindings.data.layerCount, pose::maxLayers);
        value.nullCount = count(data, bindings.data.nullCount, pose::maxNullLayers);
        if ((value.layerCount && (!at<Address>(data, bindings.data.layers) ||
                                  !at<Address>(state, bindings.animation.layerFrames))) ||
            (value.nullCount && (!at<Address>(data, bindings.data.nulls) ||
                                 !at<Address>(state, bindings.animation.nullFrames))))
            throw std::runtime_error("Missing native animation frame array");
        for (unsigned i = 0; i < value.layerCount; ++i) {
            const auto entry =
                at<Address>(data, bindings.data.layers) + i * bindings.animationLayer.stride;
            const auto id = at<unsigned>(entry, bindings.animationLayer.id);
            if (id >= pose::maxLayers)
                throw std::runtime_error("Invalid native animation layer ID");
            value.layers[i] = {
                static_cast<std::uint16_t>(id),
                at<int>(at<Address>(state, bindings.animation.layerFrames), i * sizeof(int))};
        }
        for (unsigned i = 0; i < value.nullCount; ++i) {
            const auto entry =
                at<Address>(data, bindings.data.nulls) + i * bindings.animationLayer.stride;
            const auto id = at<unsigned>(entry, bindings.animationLayer.id);
            if (id >= pose::maxNullLayers)
                throw std::runtime_error("Invalid native attachment layer ID");
            value.nulls[i] = {
                static_cast<std::uint16_t>(id),
                at<int>(at<Address>(state, bindings.animation.nullFrames), i * sizeof(int))};
        }
    }
    pose::write(w, value);
}
void applyAnimation(const pose::State& value, Address state) {
    const auto data = at<Address>(state, bindings.animation.data);
    if (!value.present) {
        if (data) {
            using Reset = void(__attribute__((thiscall))*)(void*, void*);
            reinterpret_cast<Reset>(image + bindings.resetAnimation)(reinterpret_cast<void*>(state),
                                                                     nullptr);
        }
        return;
    }
    if (!data)
        return;
    at<unsigned>(state, bindings.animation.frame) = value.frame;
    at<bool>(state, bindings.animation.playing) = value.playing;
    at<unsigned>(state, bindings.animation.events) = value.events;
    at<unsigned>(state, bindings.animation.previousEvents) = value.previousEvents;
    for (unsigned i = 0; i < value.layerCount; ++i) {
        const auto [id, frameIndex] = value.layers[i];
        const int order = at<int>(data, bindings.data.layerMap + id * sizeof(int));
        if (order < 0 || static_cast<unsigned>(order) >= count(data, bindings.data.layerCount))
            continue;
        const auto frames =
            count(at<Address>(data, bindings.data.layers) + order * bindings.animationLayer.stride,
                  bindings.animationLayer.frameCount, pose::maxFrames);
        if (pose::validCursor(frameIndex, frames))
            at<int>(at<Address>(state, bindings.animation.layerFrames), order * sizeof(int)) =
                frameIndex;
    }
    const auto nulls = at<Address>(data, bindings.data.nulls);
    const auto frames = at<Address>(state, bindings.animation.nullFrames);
    const auto localCount = count(data, bindings.data.nullCount, pose::maxNullLayers);
    if (localCount && (!nulls || !frames))
        throw std::runtime_error("Missing native attachment frame array");
    for (unsigned i = 0; i < localCount; ++i)
        at<int>(frames, i * sizeof(int)) = -1;
    for (unsigned i = 0; i < value.nullCount; ++i) {
        const auto [id, frameIndex] = value.nulls[i];
        unsigned order = i;
        if (order >= localCount || at<unsigned>(nulls + order * bindings.animationLayer.stride,
                                                bindings.animationLayer.id) != id) {
            for (order = 0; order < localCount; ++order)
                if (at<unsigned>(nulls + order * bindings.animationLayer.stride,
                                 bindings.animationLayer.id) == id)
                    break;
        }
        if (order == localCount)
            continue;
        const auto limit = count(nulls + order * bindings.animationLayer.stride,
                                 bindings.animationLayer.nullFrameCount, pose::maxFrames);
        if (pose::validCursor(frameIndex, limit))
            at<int>(frames, order * sizeof(int)) = frameIndex;
    }
}

struct Layer {
    unsigned id = 0;
    std::string_view path;
    std::array<bool, layerFlags> booleans{};
    std::array<unsigned, layerValues> numbers{};
    std::array<unsigned, blendValues> blend{};
    unsigned flags = 0;
};
struct State {
    pose::State animation, overlay;
    int shadow = -1;
    std::array<unsigned, colorValues> colors{};
    unsigned speed = 0, flags = 0;
    bool overlayFirst = false;
    unsigned count = 0;
    std::array<Layer, pose::maxLayers> layers{};
};
State decode(lan::Reader& reader) {
    if (reader.u8() != format)
        throw std::runtime_error("Invalid native Sprite format");
    State state;
    state.animation = pose::read(reader);
    state.overlay = pose::read(reader);
    state.shadow = std::bit_cast<int>(reader.u32());
    if (state.shadow < -1 || state.shadow >= static_cast<int>(pose::maxLayers))
        throw std::runtime_error("Invalid shadow layer");
    for (auto& value : state.colors)
        value = number(reader);
    state.speed = number(reader);
    state.flags = reader.u32();
    state.overlayFirst = boolean(reader);
    state.count = reader.u16();
    if (state.count > state.layers.size())
        throw std::runtime_error("Too many sprite layers");
    std::bitset<pose::maxLayers> used;
    for (unsigned i = 0; i < state.count; ++i) {
        auto& layer = state.layers[i];
        layer.id = reader.u16();
        layer.path = reader.stringView();
        if (layer.id >= used.size() || used[layer.id] || layer.path.size() > maxPath)
            throw std::runtime_error("Invalid sprite layer");
        used[layer.id] = true;
        for (auto& value : layer.booleans)
            value = boolean(reader);
        for (auto& value : layer.numbers)
            value = number(reader);
        for (unsigned j = 0; j < layer.blend.size(); ++j) {
            layer.blend[j] = reader.u32();
            if (layer.blend[j] > maxBlend || (!bindings.layer.blend[j] && layer.blend[j]))
                throw std::runtime_error("Invalid sprite blend mode");
        }
        layer.flags = reader.u32();
    }
    reader.finish();
    return state;
}
// Validate native containers before any scalar write or native Reset. Borrowed
// frame arrays remain owned by AnimationState throughout this synchronous call.
void validateAnimation(Address state, const pose::State& value) {
    const auto data = at<Address>(state, bindings.animation.data);
    if (!data || !value.present)
        return;
    const auto layers = count(data, bindings.data.layerCount);
    const auto nulls = count(data, bindings.data.nullCount, pose::maxNullLayers);
    const auto layerData = at<Address>(data, bindings.data.layers);
    const auto nullData = at<Address>(data, bindings.data.nulls);
    if ((layers && (!layerData || !at<Address>(state, bindings.animation.layerFrames))) ||
        (nulls && (!nullData || !at<Address>(state, bindings.animation.nullFrames))))
        throw std::runtime_error("Missing native animation frame array");
    for (unsigned i = 0; i < layers; ++i)
        count(layerData + i * bindings.animationLayer.stride, bindings.animationLayer.frameCount,
              pose::maxFrames);
    for (unsigned i = 0; i < nulls; ++i)
        count(nullData + i * bindings.animationLayer.stride, bindings.animationLayer.nullFrameCount,
              pose::maxFrames);
}
int animationLength(lua_State* L) {
    try {
        const auto data =
            at<Address>(sprite(L) + bindings.sprite.animation, bindings.animation.data);
        lua.pushInteger(L, data ? count(data, bindings.data.totalFrames, pose::maxFrames) : 0);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int state(lua_State* L) {
    try {
        const auto s = sprite(L);
        if (lua.getTop(L) == 1) {
            const auto n = count(s, bindings.sprite.layerCount);
            constexpr std::size_t headerReserve = 256, layerReserve = 256;
            lan::Writer writer(lan::Message::world, headerReserve + n * layerReserve);
            writer.u8(format);
            captureAnimation(writer, s + bindings.sprite.animation);
            captureAnimation(writer, s + bindings.sprite.overlay);
            writer.u32(at<unsigned>(s, bindings.sprite.shadow));
            for (unsigned i = 0; i < colorValues; ++i)
                writer.u32(at<unsigned>(s, bindings.sprite.colors + i * sizeof(unsigned)));
            writer.u32(at<unsigned>(s, bindings.sprite.speed));
            writer.u32(at<unsigned>(s, bindings.sprite.flags));
            writer.u8(at<bool>(s, bindings.sprite.overlayFirst));
            writer.u16(n);
            for (unsigned i = 0; i < n; ++i) {
                const auto p = layerAt(s, i);
                writer.u16(layerId(p));
                writer.string(path(p + bindings.layer.path));
                for (auto offset : bindings.layer.booleans)
                    writer.u8(at<bool>(p, offset));
                for (auto offset : bindings.layer.numbers)
                    writer.u32(at<unsigned>(p, offset));
                for (auto offset : bindings.layer.blend)
                    writer.u32(offset ? at<unsigned>(p, *offset) : 0);
                writer.u32(at<unsigned>(p, bindings.layer.flags));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(writer.bytes.data() + 1),
                            writer.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas apply visual state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto value = decode(reader);
        validateAnimation(s + bindings.sprite.animation, value.animation);
        validateAnimation(s + bindings.sprite.overlay, value.overlay);
        const auto shadow = value.shadow >= 0 && !findLayer(s, value.shadow) ? -1 : value.shadow;
        std::array<Address, pose::maxLayers> local{};
        std::bitset<pose::maxLayers> changed;
        for (unsigned i = 0; i < value.count; ++i) {
            local[i] = findLayer(s, value.layers[i].id);
            if (local[i])
                changed[i] = value.layers[i].path != path(local[i] + bindings.layer.path);
        }
        applyAnimation(value.animation, s + bindings.sprite.animation);
        applyAnimation(value.overlay, s + bindings.sprite.overlay);
        at<int>(s, bindings.sprite.shadow) = shadow;
        for (unsigned i = 0; i < colorValues; ++i)
            at<unsigned>(s, bindings.sprite.colors + i * sizeof(unsigned)) = value.colors[i];
        at<unsigned>(s, bindings.sprite.speed) = value.speed;
        at<unsigned>(s, bindings.sprite.flags) = value.flags;
        at<bool>(s, bindings.sprite.overlayFirst) = value.overlayFirst;
        if (changed.any())
            lua.createTable(L, 0, 0);
        unsigned changedCount = 0;
        for (unsigned i = 0; i < value.count; ++i) {
            const auto p = local[i];
            if (!p)
                continue;
            const auto& layer = value.layers[i];
            if (changed[i]) {
                lua.createTable(L, 2, 0);
                lua.pushInteger(L, layer.id);
                lua.rawSetI(L, -2, 1);
                lua.pushLString(L, layer.path.data(), layer.path.size());
                lua.rawSetI(L, -2, 2);
                lua.rawSetI(L, -2, ++changedCount);
            }
            for (unsigned j = 0; j < layerFlags; ++j)
                at<bool>(p, bindings.layer.booleans[j]) = layer.booleans[j];
            for (unsigned j = 0; j < layerValues; ++j)
                at<unsigned>(p, bindings.layer.numbers[j]) = layer.numbers[j];
            for (unsigned j = 0; j < blendValues; ++j)
                if (bindings.layer.blend[j])
                    at<unsigned>(p, *bindings.layer.blend[j]) = layer.blend[j];
            at<unsigned>(p, bindings.layer.flags) = layer.flags;
        }
        if (!changed.any())
            lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
Address findLayer(Address sprite, unsigned id) {
    for (unsigned i = 0; i < count(sprite, bindings.sprite.layerCount); ++i) {
        const auto p = layerAt(sprite, i);
        if (layerId(p) == id)
            return p;
    }
    return 0;
}
std::string_view path(Address nativeString) {
    const auto length = at<unsigned>(nativeString, bindings.string.length);
    const auto capacity = at<unsigned>(nativeString, bindings.string.capacity);
    if (length > capacity || length > maxPath)
        throw std::runtime_error("Invalid sprite path");
    const auto address =
        capacity <= bindings.string.inlineCapacity ? nativeString : at<Address>(nativeString, 0);
    if (length && !address)
        throw std::runtime_error("Missing native sprite path");
    return {reinterpret_cast<const char*>(address), length};
}
bool bind(lua_State* L, HMODULE module, Address base) {
    if (!base ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::pushInteger,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    image = base;
    lua.pushClosure(L, state, 0);
    lua.setField(L, -2, "sprite_state");
    lua.pushClosure(L, animationLength, 0);
    lua.setField(L, -2, "sprite_animation_length");
    return true;
}
} // namespace isaac::engine::native_sprite
