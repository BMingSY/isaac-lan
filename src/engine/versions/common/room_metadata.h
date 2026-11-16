#pragma once
#include "net/protocol.h"
#include "engine/versions/common/room_data_bindings.h"
#include "runtime/room_map.h"
#include <cstring>
#include <map>
#include <string>

namespace isaac::engine::native_room_data::metadata {
inline constexpr unsigned cellsPerDimension = 169, dimensions = 3;
struct Layout {
    int dimension = 0, index = 0, gridIndex = 0, listIndex = 0;
    std::vector<std::uint8_t> config = std::vector<std::uint8_t>(bindings.config.size);
    std::vector<unsigned> cells;
    unsigned allowed = 0;
    std::array<unsigned, 8> doors{};
    std::array<unsigned, 4> seeds{};
    std::string bytes;

    unsigned word(unsigned offset) const {
        unsigned value;
        std::memcpy(&value, config.data() + offset, sizeof(value));
        return value;
    }
    bool update(std::span<const std::uint8_t> source) {
        const std::string_view wire(reinterpret_cast<const char*>(source.data()), source.size());
        if (!bytes.empty() && bytes == wire)
            return false;
        Layout next;
        lan::Reader r(source);
        next.dimension = static_cast<int>(r.u32());
        next.index = static_cast<int>(r.u32());
        next.gridIndex = static_cast<int>(r.u32());
        next.listIndex = static_cast<int>(r.u32());
        next.cells.resize(r.u8());
        for (auto& cell : next.cells)
            cell = r.u8();
        for (const auto offset : bindings.config.fields) {
            const auto value = r.u32();
            std::memcpy(next.config.data() + offset, &value, sizeof(value));
        }
        next.config[bindings.config.width] = r.u8();
        next.config[bindings.config.height] = r.u8();
        const unsigned emptyStringCapacity = bindings.config.inlineCapacity;
        std::memcpy(next.config.data() + bindings.config.stringCapacity, &emptyStringCapacity,
                    sizeof(emptyStringCapacity));
        next.allowed = r.u32();
        for (auto& door : next.doors)
            door = r.u32();
        for (auto& seed : next.seeds)
            seed = r.u32();
        r.finish();
        if (!rooms::validLayoutIndices(next.dimension, next.index, next.gridIndex,
                                       next.listIndex) ||
            next.index < bindings.minimumRoom || next.gridIndex < bindings.minimumRoom ||
            next.listIndex >=
                static_cast<int>(dimensions * cellsPerDimension) - bindings.minimumRoom ||
            (next.index >= 0 &&
             std::find(next.cells.begin(), next.cells.end(), next.index) == next.cells.end()) ||
            std::any_of(next.cells.begin(), next.cells.end(),
                        [](auto cell) { return cell >= cellsPerDimension; }) ||
            next.word(bindings.config.shape) < 1 || next.word(bindings.config.shape) > 12 ||
            next.word(bindings.config.type) < 1 || next.word(bindings.config.type) > 32 ||
            !next.config[bindings.config.width] || next.config[bindings.config.width] > 26 ||
            !next.config[bindings.config.height] || next.config[bindings.config.height] > 14)
            throw std::runtime_error("Invalid authoritative room layout");
        next.bytes.assign(wire);
        // Keep the configuration address stable while native descriptors borrow it.
        std::copy(next.config.begin(), next.config.end(), config.begin());
        next.config = std::move(config);
        *this = std::move(next);
        return true;
    }
};

inline constexpr unsigned maxPickups = 4096;
struct Pickups {
    std::vector<std::uint8_t> entities;
    std::string bytes;
    bool update(std::span<const std::uint8_t> source) {
        constexpr auto headerBytes = 2 * sizeof(std::uint32_t);
        const auto recordBytes = bindings.savedEntity.fields.size() * sizeof(std::uint32_t);
        if (source.size() < headerBytes || (source.size() - headerBytes) % recordBytes ||
            source.size() > headerBytes + maxPickups * recordBytes)
            throw std::runtime_error("Invalid map pickups");
        const std::string_view wire(reinterpret_cast<const char*>(source.data()), source.size());
        if (!bytes.empty() && bytes == wire)
            return false;
        lan::Reader r(source);
        const int dimension = r.u32(), index = r.u32();
        if (dimension < 0 || dimension >= static_cast<int>(dimensions) ||
            index < bindings.minimumRoom || index >= static_cast<int>(cellsPerDimension))
            throw std::runtime_error("Invalid map room");
        std::vector<std::uint8_t> next((source.size() - headerBytes) / recordBytes *
                                       bindings.savedEntity.size);
        for (unsigned i = 0; i < next.size(); i += bindings.savedEntity.size) {
            unsigned kind = 0;
            for (const auto offset : bindings.savedEntity.fields) {
                const auto value = r.u32();
                std::memcpy(next.data() + i + offset, &value, sizeof(value));
                if (!offset)
                    kind = value;
            }
            if (kind != 5 && kind != 6)
                throw std::runtime_error("Invalid map entity");
        }
        r.finish();
        const bool changed = next != entities;
        bytes.assign(wire);
        entities = std::move(next);
        return changed;
    }
};

// Cache only copied cell identities, never descriptors or native pointers.
// Compare the live table on every query, including changes of the same size.
class CellIndex {
    struct Dimension {
        bool valid = false;
        std::array<int, cellsPerDimension> offsets{};
        std::map<int, std::vector<unsigned>> rooms;
    };
    std::array<Dimension, dimensions> entries;

  public:
    const std::vector<unsigned>& get(unsigned dimension, int listIndex,
                                     std::span<const int, cellsPerDimension> offsets) {
        auto& entry = entries.at(dimension);
        if (!entry.valid || !std::equal(offsets.begin(), offsets.end(), entry.offsets.begin())) {
            entry.rooms.clear();
            std::copy(offsets.begin(), offsets.end(), entry.offsets.begin());
            for (unsigned cell = 0; cell < offsets.size(); ++cell)
                if (offsets[cell] >= 0)
                    entry.rooms[offsets[cell]].push_back(cell);
            entry.valid = true;
        }
        const auto found = entry.rooms.find(listIndex);
        static const std::vector<unsigned> empty;
        return found == entry.rooms.end() ? empty : found->second;
    }
    void reset() {
        for (auto& entry : entries) {
            entry.valid = false;
            entry.rooms.clear();
        }
    }
};
} // namespace isaac::engine::native_room_data::metadata
