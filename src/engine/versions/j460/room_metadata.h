#pragma once
#include "net/protocol.h"
#include "runtime/room_map.h"
#include <cstring>
#include <map>
#include <string>

namespace isaac::engine::j460::room_metadata {
inline constexpr unsigned cellsPerDimension = 169, dimensions = 3;
inline constexpr unsigned configBytes = 0x5c, configType = 8, configShape = 0x48;
inline constexpr unsigned configWidth = 0x46, configHeight = 0x47, configStringCapacity = 0x28;
inline constexpr std::array<unsigned, 10> configWords{0,    4,    8,    12,   16,
                                                      0x2c, 0x38, 0x3c, 0x48, 0x4c};
struct Layout {
    int dimension = 0, index = 0, gridIndex = 0, listIndex = 0;
    std::array<std::uint8_t, configBytes> config{};
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
        for (const auto offset : configWords) {
            const auto value = r.u32();
            std::memcpy(next.config.data() + offset, &value, sizeof(value));
        }
        next.config[configWidth] = r.u8();
        next.config[configHeight] = r.u8();
        const unsigned emptyStringCapacity = 15;
        std::memcpy(next.config.data() + configStringCapacity, &emptyStringCapacity,
                    sizeof(emptyStringCapacity));
        next.allowed = r.u32();
        for (auto& door : next.doors)
            door = r.u32();
        for (auto& seed : next.seeds)
            seed = r.u32();
        r.finish();
        if (!rooms::validLayoutIndices(next.dimension, next.index, next.gridIndex,
                                       next.listIndex) ||
            (next.index >= 0 &&
             std::find(next.cells.begin(), next.cells.end(), next.index) == next.cells.end()) ||
            std::any_of(next.cells.begin(), next.cells.end(),
                        [](auto cell) { return cell >= cellsPerDimension; }) ||
            next.word(configShape) < 1 || next.word(configShape) > 12 ||
            next.word(configType) < 1 || next.word(configType) > 32 || !next.config[configWidth] ||
            next.config[configWidth] > 26 || !next.config[configHeight] ||
            next.config[configHeight] > 14)
            throw std::runtime_error("Invalid authoritative room layout");
        next.bytes.assign(wire);
        *this = std::move(next);
        return true;
    }
};

inline constexpr std::array<unsigned, 6> pickupFields{0, 4, 8, 0x14, 0x28, 0x2c};
inline constexpr unsigned pickupBytes = 0x78, maxPickups = 4096;
using MapEntity = std::array<std::uint32_t, pickupBytes / sizeof(std::uint32_t)>;
struct Pickups {
    std::vector<MapEntity> entities;
    std::string bytes;
    bool update(std::span<const std::uint8_t> source) {
        constexpr auto headerBytes = 2 * sizeof(std::uint32_t);
        constexpr auto recordBytes = pickupFields.size() * sizeof(std::uint32_t);
        if (source.size() < headerBytes || (source.size() - headerBytes) % recordBytes ||
            source.size() > headerBytes + maxPickups * recordBytes)
            throw std::runtime_error("Invalid map pickups");
        const std::string_view wire(reinterpret_cast<const char*>(source.data()), source.size());
        if (!bytes.empty() && bytes == wire)
            return false;
        lan::Reader r(source);
        const int dimension = r.u32(), index = r.u32();
        if (dimension < 0 || dimension >= static_cast<int>(dimensions) || index < -20 ||
            index >= static_cast<int>(cellsPerDimension))
            throw std::runtime_error("Invalid map room");
        std::vector<MapEntity> next((source.size() - headerBytes) / recordBytes);
        for (auto& entity : next) {
            for (const auto offset : pickupFields)
                entity[offset / sizeof(std::uint32_t)] = r.u32();
            if (entity[0] != 5 && entity[0] != 6)
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
} // namespace isaac::engine::j460::room_metadata
