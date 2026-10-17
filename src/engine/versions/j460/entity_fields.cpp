#include "engine/entity_fields.h"
#include "engine/versions/j460/entity_fields.h"
#include "engine/versions/j460/entrypoints.h"
#include "runtime/session.h"
#include <bit>
#include <cmath>
#include <cstdio>
#include <limits>
#include <new>
#include <stdexcept>

namespace isaac::entity_fields {
namespace {
namespace j460 = engine::j460;
namespace properties = j460::entity_fields;
using properties::Kind;
using properties::Write;
using Address = std::uintptr_t;
lua::API api;
Address image = 0;
constexpr unsigned maxNodes = 128, maxDepth = 3;
constexpr std::uint32_t planMagic = 0x45465031;
enum LuaType { boolean = 1, number = 3, string = 4, table = 5, userdata = 7 };
struct Node {
    const properties::Field* field = nullptr;
    unsigned count = 0, next = 0;
    bool array = false;
};
struct Plan {
    std::uint32_t magic = planMagic;
    unsigned type = 0, used = 0;
    std::array<Node, maxNodes> nodes{};
};
template <class T> T& at(Address address, unsigned offset) {
    return *reinterpret_cast<T*>(address + offset);
}
void pop(lua_State* L) {
    api.setTop(L, api.getTop(L) - 1);
}
unsigned compile(lua_State* L, int value, Plan& plan, unsigned depth) {
    if (depth > maxDepth || plan.used == maxNodes)
        throw std::runtime_error("Entity field plan exceeded");
    const auto index = plan.used++;
    auto& node = plan.nodes[index];
    switch (api.type(L, value)) {
    case LuaType::boolean:
        if (api.toBoolean(L, value))
            throw std::runtime_error("Entity field placeholders must be false");
        break;
    case LuaType::string: {
        std::size_t length = 0;
        const auto name = api.toString(L, value, &length);
        node.field = properties::find(plan.type, {name, length});
        if (!node.field)
            throw std::runtime_error("Unsupported native entity property");
        break;
    }
    case LuaType::table:
        node.array = true;
        node.count = api.rawLength(L, value);
        if (node.count >= maxNodes)
            throw std::runtime_error("Entity field array exceeded");
        for (unsigned i = 1; i <= node.count; ++i) {
            api.rawGetI(L, value, i);
            compile(L, api.getTop(L), plan, depth + 1);
            pop(L);
        }
        break;
    default:
        throw std::runtime_error("Invalid entity field plan");
    }
    node.next = plan.used;
    return index;
}
const Plan& checkedPlan(lua_State* L, int index) {
    if (api.type(L, index) != LuaType::userdata || api.rawLength(L, index) != sizeof(Plan))
        throw std::runtime_error("Invalid entity field plan handle");
    const auto& plan = *static_cast<const Plan*>(api.toUserdata(L, index));
    if (plan.magic != planMagic || !plan.used || plan.used > maxNodes || !plan.nodes[0].array ||
        (plan.type != properties::spriteType && !properties::supported(plan.type)))
        throw std::runtime_error("Invalid entity field plan handle");
    return plan;
}
Address checkedEntity(lua_State* L, const Plan& plan) {
    if (api.type(L, 1) != LuaType::userdata || api.rawLength(L, 1) != 8)
        throw std::runtime_error("Expected borrowed entity Sprite");
    const auto wrapper = static_cast<const Address*>(api.toUserdata(L, 1));
    if (wrapper[1] < j460::layout::entity::sprite)
        throw std::runtime_error("Invalid entity Sprite");
    const auto entity = wrapper[1] - j460::layout::entity::sprite;
    if (at<unsigned>(entity, j460::layout::entity::type) != plan.type ||
        !at<bool>(entity, j460::layout::entity::active))
        throw std::runtime_error("Entity field plan type or lifetime mismatch");
    return entity;
}
Address checkedSprite(lua_State* L) {
    const auto size = api.rawLength(L, 1);
    if (api.type(L, 1) != LuaType::userdata ||
        (size != 8 && size != j460::layout::sprite::size + 8))
        throw std::runtime_error("Expected a native Sprite");
    const auto value = static_cast<const Address*>(api.toUserdata(L, 1))[1];
    if (!value)
        throw std::runtime_error("Invalid native Sprite");
    return value;
}
void captureText(lua_State* L, Address value) {
    if (!value) {
        api.pushLString(L, "", 0);
        return;
    }
    const auto size = at<unsigned>(value, j460::layout::string::size);
    const auto capacity = at<unsigned>(value, j460::layout::string::capacity);
    if (size > capacity || size > 1024)
        throw std::runtime_error("Invalid native Sprite string");
    const auto address =
        capacity <= j460::layout::string::inlineCapacity ? value : at<Address>(value, 0);
    api.pushLString(L, reinterpret_cast<const char*>(address), size);
}
void capture(lua_State* L, const Plan& plan, unsigned index, Address entity, unsigned frame) {
    const auto& node = plan.nodes[index];
    if (node.array) {
        api.createTable(L, node.count, 0);
        auto child = index + 1;
        for (unsigned i = 1; i <= node.count; ++i) {
            capture(L, plan, child, entity, frame);
            api.rawSetI(L, -2, i);
            child = plan.nodes[child].next;
        }
    } else if (!node.field) {
        api.pushBoolean(L, false);
    } else {
        const auto& field = *node.field;
        switch (field.kind) {
        case Kind::real:
            api.pushNumber(L, at<float>(entity, field.offset));
            break;
        case Kind::integer:
            api.pushInteger(L, at<std::int32_t>(entity, field.offset));
            break;
        case Kind::unsignedInteger:
            api.pushInteger(L, at<std::uint32_t>(entity, field.offset));
            break;
        case Kind::boolean:
            api.pushBoolean(L, at<bool>(entity, field.offset));
            break;
        case Kind::vector:
            api.createTable(L, 2, 0);
            for (unsigned i = 0; i < 2; ++i) {
                api.pushNumber(L, at<float>(entity, field.offset + i * sizeof(float)));
                api.rawSetI(L, -2, i + 1);
            }
            break;
        case Kind::flags:
            api.pushInteger(L,
                            std::bit_cast<std::int64_t>(at<std::uint64_t>(entity, field.offset)));
            break;
        case Kind::frame:
            api.pushInteger(
                L, std::bit_cast<std::int32_t>(frame - at<unsigned>(entity, field.offset)));
            break;
        case Kind::color:
            api.createTable(L, std::size(properties::colorOffsets), 0);
            for (unsigned i = 0; i < std::size(properties::colorOffsets); ++i) {
                api.pushNumber(L, at<float>(entity, field.offset + properties::colorOffsets[i]));
                api.rawSetI(L, -2, i + 1);
            }
            break;
        case Kind::text:
            captureText(L, entity + field.offset);
            break;
        case Kind::animationName:
            captureText(L, at<Address>(entity + field.offset, j460::layout::animationState::data));
            break;
        case Kind::animationFrame:
        case Kind::overlayFrame: {
            const auto state = entity + field.offset;
            if (!at<Address>(state, j460::layout::animationState::data)) {
                api.pushInteger(L, -1);
                break;
            }
            const auto frame = at<float>(state, j460::layout::animationState::frame);
            if (!std::isfinite(frame) || frame < INT32_MIN ||
                static_cast<double>(frame) > INT32_MAX)
                throw std::runtime_error("Invalid native Sprite frame");
            api.pushInteger(L, static_cast<int>(
                                   field.kind == Kind::animationFrame ? std::floor(frame) : frame));
            break;
        }
        }
    }
}
float real(lua_State* L, int index) {
    const auto value = static_cast<float>(api.toNumber(L, index, nullptr));
    if (api.type(L, index) != LuaType::number || !std::isfinite(value))
        throw std::runtime_error("Invalid entity number");
    return value;
}
void writeReal(Address entity, const properties::Field& field, float value) {
    using SetFloat = void(__attribute__((thiscall))*)(void*, float);
    switch (field.write) {
    case Write::direct:
        at<float>(entity, field.offset) = value;
        break;
    case Write::size: {
        using SetSize = void(__cdecl*)(void*, float);
        reinterpret_cast<SetSize>(image + j460::entry::entityLuaSetSize)(
            reinterpret_cast<void*>(entity), value);
        break;
    }
    case Write::damage:
        reinterpret_cast<SetFloat>(
            at<Address>(at<Address>(entity, 0), j460::layout::entity::damageVtableSlot))(
            reinterpret_cast<void*>(entity), value);
        break;
    case Write::tearHeight:
    case Write::tearScale:
        reinterpret_cast<SetFloat>(image + (field.write == Write::tearHeight
                                                ? j460::entry::tearSetHeight
                                                : j460::entry::tearSetScale))(
            reinterpret_cast<void*>(entity), value);
        break;
    case Write::readOnly:
        break;
    }
}
using Values = std::array<std::array<std::uint32_t, std::size(properties::colorOffsets)>, maxNodes>;
void validate(lua_State* L, const Plan& plan, unsigned index, int value, Values& values) {
    const auto& node = plan.nodes[index];
    if (node.array) {
        if (api.type(L, value) != LuaType::table || api.rawLength(L, value) != node.count)
            throw std::runtime_error("Entity field shape mismatch");
        auto child = index + 1;
        for (unsigned i = 1; i <= node.count; ++i) {
            api.rawGetI(L, value, i);
            validate(L, plan, child, api.getTop(L), values);
            pop(L);
            child = plan.nodes[child].next;
        }
        return;
    }
    if (!node.field)
        return;
    const auto& field = *node.field;
    switch (field.kind) {
    case Kind::real: {
        const auto number = real(L, value);
        values[index][0] = std::bit_cast<std::uint32_t>(number);
        break;
    }
    case Kind::integer:
    case Kind::unsignedInteger:
    case Kind::frame:
    case Kind::flags: {
        const auto number = api.toInteger(L, value, nullptr);
        if (!api.isInteger(L, value) ||
            (field.kind == Kind::unsignedInteger && (number < 0 || number > UINT32_MAX)) ||
            ((field.kind == Kind::integer || field.kind == Kind::frame) &&
             (number < INT32_MIN || number > INT32_MAX)))
            throw std::runtime_error("Invalid entity integer");
        values[index][0] = static_cast<std::uint32_t>(number);
        break;
    }
    case Kind::animationFrame:
    case Kind::overlayFrame:
        if (!api.isInteger(L, value))
            throw std::runtime_error("Invalid Sprite frame");
        break;
    case Kind::text:
    case Kind::animationName:
        if (api.type(L, value) != LuaType::string || api.rawLength(L, value) > 1024)
            throw std::runtime_error("Invalid Sprite string");
        break;
    case Kind::boolean:
        if (api.type(L, value) != LuaType::boolean)
            throw std::runtime_error("Invalid entity boolean");
        values[index][0] = api.toBoolean(L, value) != 0;
        break;
    case Kind::color:
    case Kind::vector: {
        const unsigned count = field.kind == Kind::color ? std::size(properties::colorOffsets) : 2;
        if (api.type(L, value) != LuaType::table || api.rawLength(L, value) != count)
            throw std::runtime_error("Invalid entity vector");
        for (unsigned i = 0; i < count; ++i) {
            api.rawGetI(L, value, i + 1);
            const auto number = real(L, api.getTop(L));
            values[index][i] = std::bit_cast<std::uint32_t>(number);
            pop(L);
        }
        break;
    }
    }
}
void apply(const Plan& plan, Address entity, const Values& values) {
    // Validation resolves Lua values once. This pass neither enters Lua nor
    // retains Lua references, and starts only after the complete shape is valid.
    for (unsigned index = 0; index < plan.used; ++index) {
        const auto* field = plan.nodes[index].field;
        if (!field || field->write == Write::readOnly)
            continue;
        const auto& value = values[index];
        switch (field->kind) {
        case Kind::real:
            writeReal(entity, *field, std::bit_cast<float>(value[0]));
            break;
        case Kind::integer:
        case Kind::unsignedInteger:
            at<std::uint32_t>(entity, field->offset) = value[0];
            break;
        case Kind::boolean:
            at<bool>(entity, field->offset) = value[0] != 0;
            break;
        case Kind::vector:
        case Kind::color: {
            const unsigned count =
                field->kind == Kind::color ? std::size(properties::colorOffsets) : 2;
            for (unsigned i = 0; i < count; ++i) {
                const auto offset =
                    field->kind == Kind::color ? properties::colorOffsets[i] : i * sizeof(float);
                at<float>(entity, field->offset + offset) = std::bit_cast<float>(value[i]);
            }
            if (field->kind == Kind::color)
                for (unsigned i = 0; i < j460::layout::color::colorizeChannels; ++i)
                    at<float>(entity, field->offset + j460::layout::color::colorize +
                                          i * sizeof(float)) = 0;
            break;
        }
        default:
            throw std::runtime_error("Unsupported writable entity property");
        }
    }
}
template <int Operation> int run(lua_State* L) {
    char error[192]{};
    try {
        if (!api.checkStack(L, maxDepth + 16))
            throw std::runtime_error("Cannot reserve entity field stack");
        constexpr bool sprite = Operation >= 3;
        if constexpr (Operation == 0 || Operation == 3) {
            const auto type =
                sprite ? properties::spriteType : static_cast<unsigned>(api.checkInteger(L, 1));
            if (!sprite && !properties::supported(type)) {
                api.pushBoolean(L, false);
                return 1;
            }
            auto* plan = new (api.newUserdata(L, sizeof(Plan))) Plan{};
            plan->type = type;
            compile(L, sprite ? 1 : 2, *plan, 0);
            if (!plan->nodes[0].array)
                throw std::runtime_error("Entity field root must be an array");
        } else {
            const auto& plan = checkedPlan(L, 2);
            if (sprite != (plan.type == properties::spriteType))
                throw std::runtime_error("Native field plan domain mismatch");
            const auto entity = sprite ? checkedSprite(L) : checkedEntity(L, plan);
            if constexpr (Operation == 1 || Operation == 4) {
                unsigned frame = 0;
                if constexpr (!sprite) {
                    const auto game = at<Address>(image, j460::globals::game);
                    if (!game)
                        throw std::runtime_error("Entity capture requires an active game");
                    frame = at<unsigned>(game, j460::layout::game::frame);
                }
                capture(L, plan, 0, entity, frame);
            } else {
                if (!runtime::replica())
                    throw std::runtime_error("Only replicas restore entity fields");
                // Validation fills every writable component before apply reads it.
                Values values;
                validate(L, plan, 0, 3, values);
                apply(plan, entity, values);
                api.pushBoolean(L, true);
            }
        }
        return 1;
    } catch (const std::exception& exception) {
        std::snprintf(error, sizeof(error), "%s", exception.what());
    }
    api.pushString(L, error);
    return api.error(L);
}
} // namespace

bool bind(lua_State* L, lua::Module module) {
    using S = lua::Symbol;
    if (!api.load(module,
                  {S::type,        S::toBoolean,    S::toString,    S::toNumber,    S::toInteger,
                   S::isInteger,   S::rawLength,    S::rawGetI,     S::rawSetI,     S::getTop,
                   S::setTop,      S::createTable,  S::newUserdata, S::toUserdata,  S::pushBoolean,
                   S::pushInteger, S::pushNumber,   S::pushString,  S::pushClosure, S::setField,
                   S::error,       S::checkInteger, S::checkStack,  S::pushLString}))
        return false;
    image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    api.pushClosure(L, run<0>, 0);
    api.setField(L, -2, "entity_fields_plan");
    api.pushClosure(L, run<1>, 0);
    api.setField(L, -2, "entity_fields_capture");
    api.pushClosure(L, run<2>, 0);
    api.setField(L, -2, "entity_fields_apply");
    api.pushClosure(L, run<3>, 0);
    api.setField(L, -2, "sprite_fields_plan");
    api.pushClosure(L, run<4>, 0);
    api.setField(L, -2, "sprite_fields_capture");
    api.pushClosure(L, run<5>, 0);
    api.setField(L, -2, "sprite_fields_apply");
    return true;
}
} // namespace isaac::entity_fields
