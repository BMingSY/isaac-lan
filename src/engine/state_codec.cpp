#include "engine/state_codec.h"
#include "core/state_codec.h"
#include <algorithm>
#include <array>
#include <cstdio>

namespace isaac::lua_state_codec {
namespace {
lua::API api;
constexpr int registry = -1001000;
enum LuaType { boolean = 1, number = 3, string = 4, table = 5 };
constexpr auto bufferMetatable = "IsaacLAN.StateCodec.Buffer";
using state_codec::Budget;
using state_codec::Reader;
using state_codec::Tag;
using state_codec::Writer;

void pop(lua_State* L, int count = 1) {
    api.setTop(L, api.getTop(L) - count);
}
void field(lua_State* L, int index, const char* name) {
    api.pushString(L, name);
    api.rawGet(L, index);
}
std::string_view bytes(lua_State* L, int index) {
    if (api.type(L, index) != LuaType::string)
        throw std::runtime_error("Expected state bytes");
    std::size_t size = 0;
    const auto value = api.toString(L, index, &size);
    return {value, size};
}
std::size_t metadata(lua_State* L, int index, const char* name, std::size_t limit) {
    field(L, index, name);
    const auto value = api.toInteger(L, -1, nullptr);
    if (!api.isInteger(L, -1) || value < 0 || static_cast<std::uint64_t>(value) >= limit)
        throw std::runtime_error("Invalid state fragment metadata");
    pop(L);
    return static_cast<std::size_t>(value);
}
void setInteger(lua_State* L, const char* name, std::size_t value) {
    api.pushInteger(L, static_cast<long long>(value));
    api.setField(L, -2, name);
}

struct Encoder {
    lua_State* L;
    Writer& writer;
    int memo;
    Budget budget;
    std::array<std::size_t, state_codec::maxDepth> path{};

    std::size_t put(int index, std::size_t depth) {
        budget.visit(depth);
        auto deepest = depth;
        switch (api.type(L, index)) {
        case LuaType::boolean:
            writer.boolean(api.toBoolean(L, index) != 0);
            break;
        case LuaType::number:
            if (api.isInteger(L, index))
                writer.number(static_cast<std::int64_t>(api.toInteger(L, index, nullptr)));
            else
                writer.number(api.toNumber(L, index, nullptr));
            break;
        case LuaType::string:
            writer.string(bytes(L, index));
            break;
        case LuaType::table: {
            bool cache = false;
            if (memo) {
                api.pushValue(L, index);
                const auto kind = api.rawGet(L, memo);
                const auto entry = api.getTop(L);
                if (kind == LuaType::table) {
                    const auto count = metadata(L, entry, "nodes", state_codec::maxNodes);
                    const auto relativeDepth = metadata(L, entry, "depth", state_codec::maxDepth);
                    if (!count)
                        throw std::runtime_error("Invalid state fragment nodes");
                    budget.visit(depth + relativeDepth, count - 1);
                    field(L, entry, "bytes");
                    const auto value = bytes(L, -1);
                    writer.append(
                        {reinterpret_cast<const std::uint8_t*>(value.data()), value.size()});
                    pop(L, 2);
                    return depth + relativeDepth;
                }
                cache = kind == LuaType::boolean && !api.toBoolean(L, -1);
                pop(L);
            }
            const auto first = writer.data().size(), firstNode = budget.nodes;
            const auto size = api.rawLength(L, index);
            writer.array(size);
            for (std::size_t i = 1; i <= size; ++i) {
                path[depth] = i;
                api.rawGetI(L, index, static_cast<long long>(i));
                deepest = std::max(deepest, put(api.getTop(L), depth + 1));
                pop(L);
                path[depth] = 0;
            }
            if (cache) {
                api.pushValue(L, index);
                api.createTable(L, 0, 3);
                const auto value = writer.data().subspan(first);
                api.pushLString(L, reinterpret_cast<const char*>(value.data()), value.size());
                api.setField(L, -2, "bytes");
                setInteger(L, "depth", deepest - depth);
                setInteger(L, "nodes", budget.nodes - firstNode + 1);
                api.rawSet(L, memo);
            }
            break;
        }
        default:
            throw std::runtime_error("Unsupported state value");
        }
        return deepest;
    }
};

void get(lua_State* L, Reader& reader, Budget& budget, std::size_t depth) {
    budget.visit(depth);
    switch (reader.tag()) {
    case Tag::falseValue:
        api.pushBoolean(L, false);
        break;
    case Tag::trueValue:
        api.pushBoolean(L, true);
        break;
    case Tag::int32:
        api.pushInteger(L,
                        std::bit_cast<std::int32_t>(static_cast<std::uint32_t>(reader.integer(4))));
        break;
    case Tag::int64:
        api.pushInteger(L, std::bit_cast<std::int64_t>(reader.integer(8)));
        break;
    case Tag::float32:
        api.pushNumber(L, reader.number());
        break;
    case Tag::string: {
        const auto value = reader.string();
        api.pushLString(L, value.data(), value.size());
        break;
    }
    case Tag::array: {
        const auto size = static_cast<int>(reader.integer(2));
        api.createTable(L, size, 0);
        for (int i = 1; i <= size; ++i) {
            get(L, reader, budget, depth + 1);
            api.rawSetI(L, -2, i);
        }
        break;
    }
    }
}

int releaseBuffer(lua_State* L) {
    const auto owner = static_cast<Writer**>(api.toUserdata(L, 1));
    delete *owner;
    *owner = nullptr;
    return 0;
}
int encode(lua_State* L) {
    if (!api.checkStack(L, static_cast<int>(state_codec::maxDepth) + 16)) {
        api.pushString(L, "Cannot reserve state codec stack");
        return api.error(L);
    }
    const auto memo = api.type(L, 2) == LuaType::table ? 2 : 0;
    // Lua owns this guard before any C++ allocation. A Lua allocation failure
    // longjmps past C++ frames; __gc still releases the buffer in that case.
    const auto owner = static_cast<Writer**>(api.newUserdata(L, sizeof(Writer*)));
    *owner = nullptr;
    api.getField(L, registry, bufferMetatable);
    api.setMetatable(L, -2);
    char error[256]{};
    try {
        *owner = new Writer;
        Encoder encoder{L, **owner, memo, {}, {}};
        try {
            encoder.put(1, 0);
        } catch (const std::exception& exception) {
            // Construct the field path only on failure, with no additional Lua calls.
            auto used = std::snprintf(error, sizeof(error), "%s at", exception.what());
            for (const auto index : encoder.path) {
                if (!index || used < 0 || static_cast<std::size_t>(used) >= sizeof(error))
                    break;
                used += std::snprintf(error + used, sizeof(error) - used, " [%zu]", index);
            }
            throw;
        }
        const auto value = (*owner)->data();
        api.pushLString(L, reinterpret_cast<const char*>(value.data()), value.size());
        delete *owner;
        *owner = nullptr;
        return 1;
    } catch (const std::exception& exception) {
        if (!error[0])
            std::snprintf(error, sizeof(error), "%s", exception.what());
    }
    delete *owner;
    *owner = nullptr;
    api.pushString(L, error);
    return api.error(L); // No owning C++ objects remain across Lua's longjmp.
}
int decode(lua_State* L) {
    char error[256]{};
    try {
        if (!api.checkStack(L, static_cast<int>(state_codec::maxDepth) + 4))
            throw std::runtime_error("Cannot reserve state codec stack");
        const auto value = bytes(L, 1);
        Reader reader({reinterpret_cast<const std::uint8_t*>(value.data()), value.size()});
        Budget budget;
        get(L, reader, budget, 0);
        reader.finish();
        return 1;
    } catch (const std::exception& exception) {
        std::snprintf(error, sizeof(error), "%s", exception.what());
    }
    api.pushString(L, error);
    return api.error(L);
}
} // namespace

bool bind(lua_State* L, lua::Module module, lua::Resolver resolver) {
    using S = lua::Symbol;
    if (!api.load(module,
                  {S::type,         S::isInteger,   S::toInteger,   S::toNumber,    S::toBoolean,
                   S::toString,     S::rawLength,   S::rawGetI,     S::rawSetI,     S::rawGet,
                   S::rawSet,       S::getTop,      S::setTop,      S::pushValue,   S::pushString,
                   S::pushLString,  S::pushInteger, S::pushNumber,  S::pushBoolean, S::createTable,
                   S::setField,     S::getField,    S::pushClosure, S::newUserdata, S::toUserdata,
                   S::setMetatable, S::error,       S::checkStack},
                  resolver))
        return false;
    api.createTable(L, 0, 1);
    api.pushClosure(L, releaseBuffer, 0);
    api.setField(L, -2, "__gc");
    api.setField(L, registry, bufferMetatable);
    api.pushClosure(L, encode, 0);
    api.setField(L, -2, "state_encode");
    api.pushClosure(L, decode, 0);
    api.setField(L, -2, "state_decode");
    return true;
}
} // namespace isaac::lua_state_codec
