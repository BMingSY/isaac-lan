#include "engine/versions/common/laser_state.h"
#include "engine/versions/common/laser_state_bindings.h"
#include "engine/lua_api.h"
#include "runtime/session.h"
#include "core/laser_state.h"
#include "compat/game_ids.h"
#include <algorithm>
#include <cstring>
#include <new>
namespace isaac::engine::native_laser_state {
namespace {
using Address = std::uintptr_t;
constexpr unsigned pointBytes = 8;
constexpr unsigned alignedThreshold = 4096, alignment = 32, allocationPadding = alignment + 3;
Address image = 0;
isaac::lua::API lua;
struct Vector {
    Address begin = 0, end = 0, capacity = 0;
};
template <class T> T& at(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
template <class T> T engine(unsigned rva) {
    return reinterpret_cast<T>(image + rva);
}
using Allocate = void*(__cdecl*)(std::size_t);
using Delete = void(__cdecl*)(void*, std::size_t);
void validate(const Vector& value) {
    if (value.end < value.begin || value.end > value.capacity || (!value.begin && value.capacity) ||
        (value.end - value.begin) % pointBytes || (value.capacity - value.begin) % pointBytes ||
        value.end - value.begin > presentation::maxLaserPoints * pointBytes)
        throw std::runtime_error("Invalid native laser path");
    const auto bytes = value.capacity - value.begin;
    if (bytes >= alignedThreshold) {
        if (value.begin % alignment || bytes > UINT32_MAX - allocationPadding)
            throw std::runtime_error("Invalid native laser allocation");
        const auto allocation = *reinterpret_cast<const Address*>(value.begin - sizeof(Address));
        if (!allocation || allocation >= value.begin ||
            value.begin - allocation < sizeof(Address) ||
            value.begin - allocation > allocationPadding)
            throw std::runtime_error("Invalid native laser allocation header");
    }
}
void release(const Vector& value) {
    if (!value.begin)
        return;
    auto pointer = value.begin;
    auto bytes = value.capacity - value.begin;
    if (bytes >= alignedThreshold) {
        pointer = *reinterpret_cast<const Address*>(pointer - sizeof(Address));
        bytes += allocationPadding;
    }
    engine<Delete>(bindings.release)(reinterpret_cast<void*>(pointer), bytes);
}
struct PreparedPath {
    Vector replacement;
    ~PreparedPath() {
        release(replacement);
    }
    void prepare(const Vector& previous, const std::vector<std::uint32_t>& words) {
        validate(previous);
        const auto needed = words.size() * sizeof(std::uint32_t);
        if (needed <= previous.capacity - previous.begin)
            return;
        const auto capacity = std::max<std::size_t>(needed * 2, 128);
        const auto bytes = capacity < alignedThreshold ? capacity : capacity + allocationPadding;
        const auto allocation =
            reinterpret_cast<Address>(engine<Allocate>(bindings.allocate)(bytes));
        if (!allocation)
            throw std::bad_alloc();
        auto pointer = allocation;
        if (capacity >= alignedThreshold) {
            pointer = (allocation + allocationPadding) & ~(alignment - 1);
            *reinterpret_cast<Address*>(pointer - sizeof(Address)) = allocation;
        }
        replacement = {pointer, pointer, pointer + capacity};
    }
    void commit(Vector& destination, const std::vector<std::uint32_t>& words) {
        if (replacement.begin) {
            release(destination);
            destination = replacement;
            replacement = {};
        }
        const auto bytes = words.size() * sizeof(std::uint32_t);
        if (bytes)
            std::memcpy(reinterpret_cast<void*>(destination.begin), words.data(), bytes);
        destination.end = destination.begin + bytes;
    }
};
int laserPath(lua_State* L) {
    auto sprite = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!sprite || lua.rawLength(L, 1) != 8 || sprite[1] <= bindings.sprite ||
        at<unsigned>(sprite[1] - bindings.sprite, bindings.type) != compat::ids::entity::laser) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto entity = sprite[1] - bindings.sprite;
    try {
        if (lua.getTop(L) == 1) {
            lan::Writer bytes(lan::Message::world);
            bytes.u8(at<std::uint8_t>(entity, bindings.sampleState));
            for (auto offset : bindings.values)
                bytes.u32(at<std::uint32_t>(entity, offset));
            bytes.u32(at<unsigned>(entity, bindings.samples));
            for (auto offset : bindings.paths) {
                const auto points = at<Vector>(entity, offset);
                validate(points);
                bytes.u16((points.end - points.begin) / 8);
                for (auto p = points.begin; p < points.end; p += 4)
                    bytes.u32(at<std::uint32_t>(p, 0));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(bytes.bytes.data() + 1),
                            bytes.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica()) {
            lua.pushBoolean(L, false);
            return 1;
        }
        std::size_t size = 0;
        const auto data = lua.checkString(L, 2, &size);
        lan::Reader bytes({reinterpret_cast<const std::uint8_t*>(data), size});
        auto path = presentation::readLaserPath(bytes);
        if (lua.getTop(L) > 2) {
            if (lua.getTop(L) != 4)
                throw std::runtime_error("Laser render offset requires two coordinates");
            presentation::translateLaserPath(path, static_cast<float>(lua.checkNumber(L, 3)),
                                             static_cast<float>(lua.checkNumber(L, 4)));
        }
        // Validate both native owners and reserve all storage before committing
        // either path or scalar. Allocation failure leaves the old snapshot intact.
        std::array<PreparedPath, 2> prepared;
        for (unsigned i = 0; i < prepared.size(); ++i)
            prepared[i].prepare(at<Vector>(entity, bindings.paths[i]), path.paths[i]);
        for (unsigned i = 0; i < prepared.size(); ++i)
            prepared[i].commit(at<Vector>(entity, bindings.paths[i]), path.paths[i]);
        at<std::uint8_t>(entity, bindings.sampleState) = path.sampleState;
        for (unsigned i = 0; i < bindings.values.size(); ++i)
            at<std::uint32_t>(entity, bindings.values[i]) = path.values[i];
        at<unsigned>(entity, bindings.samples) = path.samples;
        lua.pushBoolean(L, true);
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module, Address base) {
    if (!base ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::checkNumber, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    image = base;
    lua.pushClosure(L, laserPath, 0);
    lua.setField(L, -2, "laser_path");
    return true;
}
} // namespace isaac::engine::native_laser_state
