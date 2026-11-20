#include "engine/versions/common/entity_pose.h"
#include "engine/versions/common/entity_pose_bindings.h"
#include "engine/versions/common/sprite_state.h"
#include "engine/lua_api.h"
#include "compat/game_ids.h"
#include "core/occurrence_mapping.h"
#include "core/animation_pose.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <bit>
#include <cmath>

namespace isaac::engine::native_entity_pose {
namespace {
using Address = std::uintptr_t;
isaac::lua::API lua{};
template <class T> T& at(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
Address entity(lua_State* L) {
    const auto wrapper = static_cast<const Address*>(lua.toUserdata(L, 1));
    if (!wrapper || lua.rawLength(L, 1) != 8 || wrapper[1] < bindings.entity.sprite)
        throw std::runtime_error("Entity pose requires a borrowed entity Sprite");
    const auto result = wrapper[1] - bindings.entity.sprite;
    if (!result || !at<unsigned>(result, bindings.entity.type))
        throw std::runtime_error("Entity pose requires a native entity");
    return result;
}
unsigned number(lan::Reader& reader) {
    const auto value = reader.u32();
    if (!std::isfinite(std::bit_cast<float>(value)))
        throw std::runtime_error("Invalid entity pose number");
    return value;
}
bool boolean(lan::Reader& reader) {
    const auto value = reader.u8();
    if (value > 1)
        throw std::runtime_error("Invalid entity pose flag");
    return value;
}
std::vector<std::string_view> costumes(Address player) {
    const auto& b = bindings.player;
    const auto first = at<Address>(player, b.costumesBegin);
    const auto last = at<Address>(player, b.costumesEnd);
    if (last < first || (last && !first) || (last - first) % b.costumeStride ||
        (last - first) / b.costumeStride > maxCostumes)
        throw std::runtime_error("Invalid costume array");
    std::vector<std::string_view> paths;
    paths.reserve((last - first) / b.costumeStride);
    for (auto p = first; p < last; p += b.costumeStride)
        paths.push_back(native_sprite::path(p + b.costumePath));
    return paths;
}
struct Weapon {
    bool present = false;
    unsigned kind = 0, modifiers = 0;
    std::array<unsigned, chargeValues> charge{};
};
struct Layer {
    int costume = -1, id = 0;
    unsigned priority = 0;
    bool body = false;
};
struct Pose {
    std::array<bool, 2> flags{};
    unsigned blinkTime = 0, damageCooldown = 0, nightLightAngle = 0;
    std::array<Weapon, weaponSlots> weapons{};
    std::vector<std::string_view> paths;
    std::array<Layer, costumeLayers> layers{};
};
Pose decode(lan::Reader& reader) {
    Pose value;
    for (auto& flag : value.flags)
        flag = boolean(reader);
    value.blinkTime = reader.u32();
    value.damageCooldown = reader.u32();
    value.nightLightAngle = number(reader);
    for (auto& weapon : value.weapons) {
        weapon.present = boolean(reader);
        if (!weapon.present)
            continue;
        weapon.kind = reader.u32();
        for (auto& charge : weapon.charge)
            charge = number(reader);
        number(reader); // The native maximum is read-only prediction metadata.
        weapon.modifiers = reader.u32();
    }
    const auto count = reader.u16();
    if (count > maxCostumes)
        throw std::runtime_error("Too many costumes");
    value.paths.reserve(count);
    for (unsigned i = 0; i < count; ++i) {
        const auto path = reader.stringView();
        if (path.size() > maxPath)
            throw std::runtime_error("Invalid costume path");
        value.paths.push_back(path);
    }
    for (auto& layer : value.layers) {
        layer.costume = std::bit_cast<int>(reader.u32());
        layer.id = std::bit_cast<int>(reader.u32());
        layer.priority = reader.u32();
        layer.body = boolean(reader);
    }
    reader.finish();
    return value;
}
int actorPose(lua_State* L) {
    try {
        const auto player = entity(L);
        if (at<unsigned>(player, bindings.entity.type) != compat::ids::entity::player)
            throw std::runtime_error("Actor visual state requires a player");
        const auto& b = bindings.player;
        const auto current = costumes(player);
        if (lua.getTop(L) == 1) {
            constexpr unsigned captureReserve = 512;
            lan::Writer writer(lan::Message::world, captureReserve);
            for (auto offset : b.poseFlags)
                writer.u8(at<bool>(player, offset));
            writer.u32(at<unsigned>(player, b.blinkTime));
            writer.u32(at<unsigned>(player, b.damageCooldown));
            writer.u32(at<unsigned>(player, b.nightLightAngle));
            for (unsigned slot = 0; slot < weaponSlots; ++slot) {
                const auto weapon = at<Address>(player, b.weapons + slot * sizeof(Address));
                writer.u8(weapon != 0);
                if (!weapon)
                    continue;
                writer.u32(at<unsigned>(weapon, bindings.weapon.kind));
                for (auto offset : bindings.weapon.charge)
                    writer.u32(at<unsigned>(weapon, offset));
                using MaxCharge = float(__attribute__((thiscall))*)(void*);
                const auto vtable = at<Address>(weapon, 0);
                if (!vtable)
                    throw std::runtime_error("Missing native weapon methods");
                const auto query =
                    at<MaxCharge>(vtable, bindings.weapon.maxChargeMethod * sizeof(Address));
                if (!query)
                    throw std::runtime_error("Missing native weapon charge query");
                const auto maximum = query(reinterpret_cast<void*>(weapon));
                if (!std::isfinite(maximum))
                    throw std::runtime_error("Invalid native weapon charge limit");
                writer.u32(std::bit_cast<unsigned>(maximum));
                writer.u32(at<unsigned>(weapon, bindings.weapon.modifiers));
            }
            writer.u16(current.size());
            for (auto path : current)
                writer.string(path);
            for (unsigned i = 0; i < costumeLayers; ++i) {
                const auto layer = player + b.layers + i * b.layerStride;
                writer.u32(at<unsigned>(layer, b.costumeIndex));
                writer.u32(at<unsigned>(layer, b.layerId));
                writer.u32(at<unsigned>(layer, b.priority));
                writer.u8(at<bool>(layer, b.body));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(writer.bytes.data() + 1),
                            writer.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas apply actor pose");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto value = decode(reader);
        const auto mapping = core::mapOccurrences(current, value.paths);
        auto layers = value.layers;
        for (unsigned i = 0; i < costumeLayers; ++i) {
            auto& layer = layers[i];
            layer.costume =
                layer.costume >= 0 && static_cast<unsigned>(layer.costume) < mapping.size()
                    ? mapping[layer.costume]
                    : -1;
            if (layer.costume < 0)
                layer.id = static_cast<int>(i);
            else if (layer.id < 0 ||
                     static_cast<unsigned>(layer.id) >= core::animation_pose::maxLayers)
                throw std::runtime_error("Invalid costume layer ID");
        }
        // Decode and resolve the whole pose before touching the native object.
        // Costume strings and weapon objects remain owned by this player.
        for (unsigned i = 0; i < value.flags.size(); ++i)
            at<bool>(player, b.poseFlags[i]) = value.flags[i];
        at<unsigned>(player, b.blinkTime) = value.blinkTime;
        at<unsigned>(player, b.damageCooldown) = value.damageCooldown;
        at<unsigned>(player, b.nightLightAngle) = value.nightLightAngle;
        for (unsigned i = 0; i < weaponSlots; ++i) {
            const auto& pose = value.weapons[i];
            if (!pose.present)
                continue;
            const auto weapon = at<Address>(player, b.weapons + i * sizeof(Address));
            if (!weapon || at<unsigned>(weapon, bindings.weapon.kind) != pose.kind)
                continue;
            for (unsigned j = 0; j < chargeValues; ++j)
                at<unsigned>(weapon, bindings.weapon.charge[j]) = pose.charge[j];
            at<unsigned>(weapon, bindings.weapon.modifiers) = pose.modifiers;
        }
        for (unsigned i = 0; i < costumeLayers; ++i) {
            const auto& layer = layers[i];
            const auto target = player + b.layers + i * b.layerStride;
            at<int>(target, b.costumeIndex) = layer.costume;
            at<int>(target, b.layerId) = layer.id;
            at<unsigned>(target, b.priority) = layer.priority;
            at<bool>(target, b.body) = layer.body;
        }
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int entityShadow(lua_State* L) {
    try {
        const auto object = entity(L);
        if (lua.getTop(L) == 1) {
            lan::Writer writer(lan::Message::world, 1 + shadowValues * sizeof(unsigned));
            for (auto offset : bindings.entity.shadow)
                writer.u32(at<unsigned>(object, offset));
            lua.pushLString(L, reinterpret_cast<const char*>(writer.bytes.data() + 1),
                            writer.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas apply entity shadows");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        std::array<unsigned, shadowValues> values{};
        for (auto& value : values)
            value = number(reader);
        reader.finish();
        for (unsigned i = 0; i < shadowValues; ++i)
            at<unsigned>(object, bindings.entity.shadow[i]) = values[i];
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    lua.pushClosure(L, actorPose, 0);
    lua.setField(L, -2, "actor_pose");
    lua.pushClosure(L, entityShadow, 0);
    lua.setField(L, -2, "entity_shadow");
    return true;
}
} // namespace isaac::engine::native_entity_pose
