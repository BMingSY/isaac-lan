#include "engine/state_codec.h"
#include "core/state_codec.h"
#include "core/laser_projection.h"
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

struct LeafCache {
    int table = 0;
    unsigned entries = 0;
    static constexpr unsigned maxEntries = 4096, maxFields = 16;
};

// View leaves are immutable value tuples. Share identical numeric/boolean
// leaves within this decode only; mutable containers and separate views never
// alias. The ordinary codec keeps its independent-table contract.
bool scalarLeaf(Reader& reader, unsigned size) {
    if (!size || size > LeafCache::maxFields)
        return false;
    bool integerPair = size <= 2;
    for (unsigned i = 0; i < size; ++i) {
        switch (reader.tag()) {
        case Tag::falseValue:
        case Tag::trueValue:
            integerPair = false;
            break;
        case Tag::int32:
            reader.integer(4);
            break;
        case Tag::int64:
            reader.integer(8);
            break;
        case Tag::float32:
            integerPair = false;
            reader.number();
            break;
        default:
            return false;
        }
    }
    // Short integer tuples (notably item ID/count pairs) are usually unique.
    // Their hash keys would cost more than the small tables they might save.
    return !integerPair;
}

void get(lua_State* L, Reader& reader, Budget& budget, std::size_t depth, LeafCache& cache) {
    budget.visit(depth);
    const auto first = reader.position();
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
        auto end = reader;
        const bool leaf = cache.table && scalarLeaf(end, size);
        const auto key = leaf ? end.slice(first) : std::string_view{};
        if (leaf) {
            api.pushLString(L, key.data(), key.size());
            if (api.rawGet(L, cache.table) == LuaType::table) {
                budget.visit(depth + 1, size);
                reader = end;
                return;
            }
            pop(L);
        }
        api.createTable(L, size, 0);
        for (int i = 1; i <= size; ++i) {
            get(L, reader, budget, depth + 1, cache);
            api.rawSetI(L, -2, i);
        }
        if (leaf && cache.entries < LeafCache::maxEntries) {
            const auto value = api.getTop(L);
            api.pushLString(L, key.data(), key.size());
            api.pushValue(L, value);
            api.rawSet(L, cache.table);
            ++cache.entries;
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
template <bool packing> int laserSamples(lua_State* L) {
    // Release the vector before calling Lua, whose allocator can longjmp on OOM.
    constexpr std::size_t maxBytes = 33 + 2 * presentation::maxLaserPoints * 2 * sizeof(float);
    std::array<char, maxBytes> storage;
    std::size_t size = 0;
    bool refined = false, encoded = false;
    presentation::laser_projection::Point endpoint{}, origin{};
    char error[256]{};
    try {
        const auto raw = bytes(L, 1);
        const auto input = std::span(reinterpret_cast<const std::uint8_t*>(raw.data()), raw.size());
        if (raw.empty() || raw.size() > maxBytes)
            throw std::runtime_error("Invalid laser payload size");
        refined = input.front() == presentation::laser_projection::projectedTag;
        if (!packing && !refined && input.front() != presentation::laser_projection::exactTag) {
            api.pushValue(L, 1);
            return 1;
        }
        lan::Writer out(lan::Message::world);
        if constexpr (packing)
            refined =
                presentation::laser_projection::project(input, out, api.toBoolean(L, 2), endpoint);
        else
            presentation::laser_projection::expand(input, out, endpoint);
        encoded = !packing || out.bytes.front() == presentation::laser_projection::projectedTag ||
                  out.bytes.front() == presentation::laser_projection::exactTag;
        if (encoded) {
            // Both representations are derived from the already validated native path.
            const auto original = packing ? input : std::span<const std::uint8_t>(out.bytes);
            lan::Reader coordinates(original.subspan(1));
            origin = {coordinates.u32(), coordinates.u32()};
        }
        size = out.bytes.size();
        if (size > storage.size())
            throw std::runtime_error("Laser payload overflow");
        std::memcpy(storage.data(), out.bytes.data(), size);
    } catch (const std::exception& exception) {
        std::snprintf(error, sizeof(error), "%s", exception.what());
    }
    if (*error) {
        api.pushString(L, error);
        return api.error(L);
    }
    api.pushLString(L, storage.data(), size);
    api.pushBoolean(L, refined);
    if (!encoded)
        return 2;
    for (const auto word : endpoint)
        api.pushNumber(L, std::bit_cast<float>(word));
    for (const auto word : origin)
        api.pushNumber(L, std::bit_cast<float>(word));
    return 6;
}

template <bool view> int decode(lua_State* L) {
    char error[256]{};
    try {
        if (!api.checkStack(L, static_cast<int>(state_codec::maxDepth) + 4))
            throw std::runtime_error("Cannot reserve state codec stack");
        const auto value = bytes(L, 1);
        Reader reader({reinterpret_cast<const std::uint8_t*>(value.data()), value.size()});
        Budget budget;
        LeafCache cache;
        if constexpr (view) {
            api.createTable(L, 0, 0);
            cache.table = api.getTop(L);
        }
        get(L, reader, budget, 0, cache);
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
    api.pushClosure(L, laserSamples<true>, 0);
    api.setField(L, -2, "laser_project");
    api.pushClosure(L, laserSamples<false>, 0);
    api.setField(L, -2, "laser_expand");
    api.pushClosure(L, encode, 0);
    api.setField(L, -2, "state_encode");
    api.pushClosure(L, decode<false>, 0);
    api.setField(L, -2, "state_decode");
    api.pushClosure(L, decode<true>, 0);
    api.setField(L, -2, "state_decode_view");
    return true;
}
} // namespace isaac::lua_state_codec
