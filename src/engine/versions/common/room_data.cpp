#include "engine/versions/common/room_data.h"
#include "engine/versions/common/room_metadata.h"
#include "engine/versions/common/room_data_bindings.h"
#include "engine/lua_api.h"
#include "runtime/session.h"
#include "runtime/room_map.h"
#include "net/protocol.h"
#include "core/level_grid.h"
#include <cmath>
#include <map>
#include <memory>
#include <compare>
namespace isaac::engine::native_room_data {
namespace {
using Address = std::uintptr_t;
using RoomCall = void(__attribute__((thiscall)) *)(void*);
constexpr unsigned maxMapEntities = 4096;
constexpr unsigned dimensionCount = 3, roomsPerDimension = level_grid::cellCount;
constexpr unsigned floorRoomCount = dimensionCount * roomsPerDimension;
constexpr unsigned doorCount = 8, seedCount = 4;
struct Key {
    int dimension, index;
    auto operator<=>(const Key&) const = default;
};
struct Vector {
    Address begin, end, capacity;
};
Address image = 0;
Callbacks context;
isaac::lua::API lua;
template <class T> T& at(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
template <class T> T engine(unsigned rva) {
    return reinterpret_cast<T>(image + rva);
}
Address game() {
    return image ? at<Address>(image, bindings.globalGame) : 0;
}
bool validKey(long long dimension, long long index) {
    return dimension >= 0 && dimension < dimensionCount && index >= bindings.minimumRoom &&
           index < roomsPerDimension;
}
Key queryKey(lua_State* L) {
    const auto index = lua.checkInteger(L, 1), dimension = lua.checkInteger(L, 2);
    if (!validKey(dimension, index))
        throw std::runtime_error("Invalid map room query");
    return {static_cast<int>(dimension), static_cast<int>(index)};
}
// Replica room initialization uses an explicit layout from the authority.
// Special rooms are created lazily by gameplay (Devil/Angel, Error, etc.);
// generating the floor from the same seed does not create these descriptors.
// No process pointers, STL containers or spawn configuration cross the wire.
// Descriptors borrow these scalar-only configurations. Keep stable storage
// through floor/game cleanup; replacing a key copies into its existing block.
std::map<Key, std::vector<std::uint8_t>> replicaLayouts;
std::map<Key, metadata::Layout> decodedLayouts;
std::map<Key, metadata::Pickups> decodedPickups;
metadata::CellIndex roomCells;
// The native minimap reads saved entities, which replicas never simulate or
// save. Supply pickup metadata only while caching the map; room loading and
// saving must retain their original owned vectors.
using MapStorage = std::vector<std::uint8_t>;
std::map<Key, std::shared_ptr<const MapStorage>> replicaMapEntities;
int mapPickups(lua_State* L) {
    try {
        if (!game())
            throw std::runtime_error("Map Game is unavailable");
        if (lua.getTop(L) == 2) {
            const auto [dimension, index] = queryKey(L);
            using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
            const auto desc = reinterpret_cast<Address>(engine<Desc>(bindings.descriptor)(
                reinterpret_cast<void*>(game()), index, dimension));
            if (!desc || !at<Address>(desc, bindings.roomDescriptor.data))
                throw std::runtime_error("Map descriptor is unavailable");
            lan::Writer w(lan::Message::world);
            w.u32(dimension);
            w.u32(index);
            const auto received = replicaMapEntities.find({dimension, index});
            if (runtime::replica() && received != replicaMapEntities.end()) {
                const auto& records = *received->second;
                for (unsigned i = 0; i < records.size(); i += bindings.savedEntity.size)
                    for (auto offset : bindings.savedEntity.fields)
                        w.u32(at<unsigned>(reinterpret_cast<Address>(records.data()) + i, offset));
            } else {
                const auto saved = at<Vector>(desc, bindings.roomDescriptor.savedEntities);
                if (saved.end < saved.begin || saved.end > saved.capacity ||
                    (!saved.begin && saved.capacity) ||
                    (saved.end - saved.begin) % bindings.savedEntity.size ||
                    saved.end - saved.begin > maxMapEntities * bindings.savedEntity.size)
                    throw std::runtime_error("Invalid saved map entities");
                for (auto entity = saved.begin; entity < saved.end;
                     entity += bindings.savedEntity.size)
                    if (at<unsigned>(entity, 0) == 5 || at<unsigned>(entity, 0) == 6)
                        for (auto offset : bindings.savedEntity.fields)
                            w.u32(at<unsigned>(entity, offset));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas receive map pickups");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        Key key{static_cast<int>(r.u32()), static_cast<int>(r.u32())};
        if (!validKey(key.dimension, key.index))
            throw std::runtime_error("Invalid map room");
        auto& decoded = decodedPickups[key];
        const bool changed = decoded.update({reinterpret_cast<const std::uint8_t*>(bytes), size});
        auto& previous = replicaMapEntities[key];
        if (!previous || changed)
            previous = std::make_shared<MapStorage>(decoded.entities);
        lua.pushBoolean(L, true);
        lua.pushBoolean(L, changed);
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int roomBackdrop(lua_State* L) {
    const auto id = lua.checkInteger(L, 1);
    const auto room = context.writableRoom();
    const bool valid = runtime::replica() && room && id >= 0 && id < bindings.room.backdropCount;
    if (valid) {
        const auto backdrop = room + bindings.room.backdrop;
        if (at<unsigned>(backdrop, bindings.room.backdropType) != static_cast<unsigned>(id)) {
            using Init = void(__attribute__((thiscall))*)(void*, unsigned, bool);
            engine<Init>(bindings.backdropInit)(reinterpret_cast<void*>(backdrop), id, true);
        }
    }
    lua.pushBoolean(L, valid);
    return 1;
}
int roomWaterCurrent(lua_State* L) {
    const auto x = lua.checkNumber(L, 1), y = lua.checkNumber(L, 2);
    const auto room = context.writableRoom();
    const bool valid = runtime::replica() && room && std::isfinite(x) && std::isfinite(y) &&
                       x * x + y * y <= 1.000001;
    if (valid) {
        // Replica layouts omit the spawn marker that initializes this vector.
        // Restore the room vector before its native ambient-effect update.
        at<float>(room, bindings.room.waterX) = static_cast<float>(x);
        at<float>(room, bindings.room.waterY) = static_cast<float>(y);
    }
    lua.pushBoolean(L, valid);
    return 1;
}
Address mainRoomDescriptor(int index) {
    using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
    return reinterpret_cast<Address>(
        engine<Desc>(bindings.descriptor)(reinterpret_cast<void*>(game()), index, 0));
}
int roomConnections(lua_State* L) {
    const auto& descriptor = bindings.roomDescriptor;
    const auto index = lua.checkInteger(L, 1);
    const auto desc = game() && context.enabled() && !runtime::replica() && context.idle() &&
                              index >= 0 && index < roomsPerDimension
                          ? mainRoomDescriptor(static_cast<int>(index))
                          : 0;
    if (!desc || !at<Address>(desc, descriptor.data)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lua.createTable(L, descriptor.doorCount, 0);
    for (unsigned slot = 0; slot < descriptor.doorCount; ++slot) {
        const auto target = at<int>(desc, descriptor.doors + slot * sizeof(int));
        int canonical = -1;
        if ((at<unsigned>(desc, descriptor.allowedDoors) & (1u << slot)) && target >= 0 &&
            target < static_cast<int>(roomsPerDimension)) {
            const auto neighbor = mainRoomDescriptor(target);
            if (neighbor && at<Address>(neighbor, descriptor.data))
                canonical = at<int>(neighbor, descriptor.safeGridIndex);
        }
        lua.pushInteger(L, canonical);
        lua.rawSetI(L, -2, slot + 1);
    }
    return 1;
}
int roomLayout(lua_State* L) {
    try {
        if (!game())
            throw std::runtime_error("Layout Game is unavailable");
        if (lua.getTop(L) == 0 || lua.getTop(L) == 2) {
            using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
            const auto key = lua.getTop(L) ? queryKey(L)
                                           : Key{at<int>(game(), bindings.game.dimension),
                                                 at<int>(game(), bindings.game.roomIndex)};
            const auto [dimension, index] = key;
            if (!validKey(dimension, index) ||
                (!lua.getTop(L) && !at<Address>(game(), bindings.game.room)))
                throw std::runtime_error("Current native room is unavailable");
            const auto desc = lua.getTop(L)
                                  ? reinterpret_cast<Address>(engine<Desc>(bindings.descriptor)(
                                        reinterpret_cast<void*>(game()), index, dimension))
                                  : at<Address>(at<Address>(game(), bindings.game.room),
                                                bindings.room.descriptor);
            if (!desc)
                throw std::runtime_error("Layout descriptor is unavailable");
            const auto override = at<Address>(desc, bindings.roomDescriptor.overrideData);
            const auto config =
                override ? override : at<Address>(desc, bindings.roomDescriptor.data);
            if (!config)
                throw std::runtime_error("Room configuration is unavailable");
            lan::Writer w(lan::Message::world);
            w.u32(dimension);
            w.u32(index < 0 ? index : at<int>(desc, bindings.roomDescriptor.safeGridIndex));
            w.u32(at<int>(desc, bindings.roomDescriptor.gridIndex));
            w.u32(at<int>(desc, bindings.roomDescriptor.listIndex));
            // Large rooms occupy several cells; the minimap uses this native
            // cell-to-descriptor table rather than GetRoomByIdx's fallback.
            const auto& cells =
                index < 0
                    ? std::vector<unsigned>{}
                    : roomCells.get(
                          dimension, at<int>(desc, bindings.roomDescriptor.listIndex),
                          std::span<const int, roomsPerDimension>(
                              reinterpret_cast<const int*>(game() + bindings.game.mapOffsets) +
                                  dimension * roomsPerDimension,
                              roomsPerDimension));
            w.u8(cells.size());
            for (auto cell : cells)
                w.u8(cell);
            for (auto offset : bindings.config.fields)
                w.u32(at<unsigned>(config, offset));
            w.u8(at<unsigned char>(config, bindings.config.width));
            w.u8(at<unsigned char>(config, bindings.config.height));
            w.u32(at<unsigned>(desc, bindings.roomDescriptor.allowedDoors));
            for (unsigned offset = bindings.roomDescriptor.doors;
                 offset < bindings.roomDescriptor.doors + doorCount * sizeof(unsigned); offset += 4)
                w.u32(at<unsigned>(desc, offset));
            for (unsigned offset = bindings.roomDescriptor.seeds;
                 offset < bindings.roomDescriptor.seeds + seedCount * sizeof(unsigned); offset += 4)
                w.u32(at<unsigned>(desc, offset));
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas receive room layouts");
        std::size_t size;
        const auto data = lua.checkString(L, 1, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(data), size});
        Key key{static_cast<int>(r.u32()), static_cast<int>(r.u32())};
        if (!validKey(key.dimension, key.index))
            throw std::runtime_error("Invalid layout room");
        auto& decoded = decodedLayouts[key];
        decoded.update({reinterpret_cast<const std::uint8_t*>(data), size});
        const auto gridIndex = decoded.gridIndex, listIndex = decoded.listIndex;
        const auto& cells = decoded.cells;
        const auto& config = decoded.config;
        const auto allowed = decoded.allowed;
        const auto& doors = decoded.doors;
        const auto& seeds = decoded.seeds;
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        // All floor descriptors are constructed by the game at startup. A new
        // red room has no replica index yet: GetRoomByIdx returns a shared
        // sentinel in that case, which must never be populated as a real room.
        const auto desc =
            key.index >= 0
                ? game() + bindings.game.descriptors + listIndex * bindings.roomDescriptor.size
                : reinterpret_cast<Address>(engine<Desc>(bindings.descriptor)(
                      reinterpret_cast<void*>(game()), key.index, key.dimension));
        if (!desc)
            throw std::runtime_error("Replica descriptor is unavailable");
        {
            auto& stored = replicaLayouts[key];
            if (stored.empty())
                stored.resize(bindings.config.size);
            std::copy(config.begin(), config.end(), stored.begin());
            at<Address>(desc, bindings.roomDescriptor.data) =
                reinterpret_cast<Address>(stored.data());
            at<Address>(desc, bindings.roomDescriptor.overrideData) = 0;
            at<int>(desc, bindings.roomDescriptor.gridIndex) = gridIndex;
            at<int>(desc, bindings.roomDescriptor.safeGridIndex) = key.index;
            at<int>(desc, bindings.roomDescriptor.listIndex) = listIndex;
            at<int>(desc, bindings.roomDescriptor.dimension) = key.dimension;
            if (key.index >= 0) {
                rooms::registerMapRoom(
                    std::span<int, floorRoomCount>(
                        reinterpret_cast<int*>(game() + bindings.game.mapOffsets), 507),
                    at<unsigned>(game(), bindings.game.roomCount), key.dimension, key.index,
                    listIndex, cells);
            }
            at<unsigned>(desc, bindings.roomDescriptor.allowedDoors) = allowed;
            for (unsigned i = 0; i < doors.size(); ++i)
                at<unsigned>(desc, bindings.roomDescriptor.doors + 4 * i) = doors[i];
            for (unsigned i = 0; i < seeds.size(); ++i)
                at<unsigned>(desc, bindings.roomDescriptor.seeds + 4 * i) = seeds[i];
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int stateClock(lua_State* L) {
    if (runtime::replica() && game()) {
        const auto frame = lua.checkInteger(L, 1);
        if (frame < 0 || frame > UINT32_MAX)
            runtime::abort("Invalid room state clock");
        else
            at<unsigned>(game(), bindings.game.frame) = static_cast<unsigned>(frame);
    }
    return 0;
}
int refreshMap(lua_State* L) {
    if (!context.enabled() || !game()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    // Game::UpdateVisibility ends by refreshing these two map caches.
    // Use that display-only step after applying authoritative DisplayFlags;
    // its preceding door walk would recompute visibility from replica doors.
    const auto g = game();
    for (auto offset : bindings.game.mapCaches)
        engine<RoomCall>(bindings.cache)(reinterpret_cast<void*>(g + offset));
    if (at<int>(g, bindings.game.mapState) != 2) {
        at<int>(g, bindings.game.mapState) = 1;
        at<int>(g, bindings.game.mapTimer) = 2;
    }
    lua.pushBoolean(L, true);
    return 1;
}
void borrowMapPickups(const std::function<void()>& cache) {
    if (!runtime::replica() || !game()) {
        cache();
        return;
    }
    struct Restore {
        struct Borrowed {
            Address descriptor;
            Vector original;
            std::shared_ptr<const MapStorage> storage;
        };
        std::vector<Borrowed> vectors;
        ~Restore() {
            // Multiple map cells/dimensions may resolve to the same native
            // descriptor. Unwind the borrowing order, including nested caches.
            for (auto it = vectors.rbegin(); it != vectors.rend(); ++it)
                at<Vector>(it->descriptor, bindings.roomDescriptor.savedEntities) = it->original;
        }
    } restore;
    using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
    for (const auto& [key, entities] : replicaMapEntities) {
        const auto descriptor = reinterpret_cast<Address>(engine<Desc>(bindings.descriptor)(
            reinterpret_cast<void*>(game()), key.index, key.dimension));
        if (!descriptor || !at<Address>(descriptor, bindings.roomDescriptor.data))
            continue;
        restore.vectors.push_back(
            {descriptor, at<Vector>(descriptor, bindings.roomDescriptor.savedEntities), entities});
        const auto begin = reinterpret_cast<Address>(entities->data());
        const auto end = begin + entities->size();
        at<Vector>(descriptor, bindings.roomDescriptor.savedEntities) = {begin, end, end};
    }
    cache();
}
} // namespace
void resetMap() {
    replicaMapEntities.clear();
    decodedLayouts.clear();
    decodedPickups.clear();
    roomCells.reset();
}
void withMapPickups(const std::function<void()>& cache) {
    borrowMapPickups(cache);
}
bool bind(lua_State* L, HMODULE module, Address base, const Callbacks& callbacks) {
    if (!base || !callbacks.enabled || !callbacks.idle || !callbacks.writableRoom ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::checkNumber, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushInteger, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    image = base;
    context = callbacks;
    for (const auto& [name, fn] : {std::pair{"room_layout", &roomLayout},
                                   {"map_pickups", mapPickups},
                                   {"room_water_current", roomWaterCurrent},
                                   {"room_backdrop", roomBackdrop},
                                   {"room_connections", roomConnections},
                                   {"state_clock", stateClock},
                                   {"map_refresh", refreshMap}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::engine::native_room_data
