#include "engine/versions/j460/room_metadata.h"
#include "test_support.h"
#include <numeric>

using namespace isaac::engine::j460::room_metadata;
using isaac::lan::Message;
using isaac::lan::Writer;
std::vector<std::uint8_t> layout(int dimension = 0, int index = 84, unsigned seed = 1) {
    Writer w(Message::world);
    w.u32(dimension);
    w.u32(index);
    w.u32(index);
    w.u32(index < 0 ? index : 0);
    w.u8(index < 0 ? 0 : 1);
    if (index >= 0)
        w.u8(index);
    for (const auto offset : configWords)
        w.u32(offset == configType || offset == configShape ? 1 : 0);
    w.u8(13);
    w.u8(7);
    w.u32(15);
    for (unsigned i = 0; i < 8; ++i)
        w.u32(i);
    for (unsigned i = 0; i < 4; ++i)
        w.u32(seed);
    return {w.bytes.begin() + 1, w.bytes.end()};
}
std::vector<std::uint8_t> pickups(unsigned kind = 5, unsigned variant = 10) {
    Writer w(Message::world);
    w.u32(0);
    w.u32(84);
    for (unsigned i = 0; i < pickupFields.size(); ++i)
        w.u32(i == 0 ? kind : variant);
    return {w.bytes.begin() + 1, w.bytes.end()};
}
template <class F> void rejects(F fn) {
    bool rejected = false;
    try {
        fn();
    } catch (const std::runtime_error&) {
        rejected = true;
    }
    require(rejected, "Invalid metadata accepted");
}
int main() {
    Layout value;
    const auto first = layout();
    require(value.update(first), "First layout not decoded");
    const auto pointer = value.config.data();
    const auto cells = value.cells.data();
    for (int i = 0; i < 100; ++i)
        require(!value.update(first), "Repeated layout rebuilt");
    require(value.config.data() == pointer && value.cells.data() == cells,
            "Repeated layout allocated");
    require(value.word(configStringCapacity) == 15 && value.word(configType) == 1,
            "Native layout differs");
    require(value.update(layout(0, 84, 2)) && value.seeds[0] == 2,
            "Same-sized layout change missed");
    require(value.config.data() == pointer, "Borrowed configuration address changed");
    auto bad = first;
    bad.pop_back();
    rejects([&] { value.update(bad); });
    rejects([&] { value.update(layout(3)); });
    rejects([&] { value.update(layout(0, 169)); });
    require(value.seeds[0] == 2, "Invalid layout mutated committed data");
    require(value.update(layout(1, -12)) && value.cells.empty(), "Off-map layout lost");

    Pickups metadata;
    auto bytes = pickups();
    require(metadata.update(bytes), "First pickups not restored");
    const auto entries = metadata.entities.data();
    for (int i = 0; i < 100; ++i)
        require(!metadata.update(bytes), "Identical pickups changed");
    require(metadata.entities.data() == entries, "Identical pickups reallocated");
    require(metadata.update(pickups(6, 20)), "Same-sized pickup replacement missed");
    rejects([&] { metadata.update(pickups(10)); });
    require(metadata.entities[0][0] == 6, "Invalid pickup replaced prior data");
    bytes.resize(8);
    require(metadata.update(bytes) && metadata.entities.empty(), "Empty room retained pickups");
    metadata = {};
    require(metadata.update(pickups()), "Reset did not restore pickups");

    CellIndex index;
    std::array<int, cellsPerDimension> offsets;
    offsets.fill(-1);
    offsets[84] = offsets[85] = 7;
    require(index.get(0, 7, offsets) == std::vector<unsigned>({84, 85}), "Large room cells differ");
    const auto cached = index.get(0, 7, offsets).data();
    for (int i = 0; i < 100; ++i)
        require(index.get(0, 7, offsets).data() == cached, "Unchanged cells rebuilt");
    offsets[85] = 8;
    require(index.get(0, 7, offsets) == std::vector<unsigned>({84}), "Red-room remap missed");
    require(index.get(0, 8, offsets) == std::vector<unsigned>({85}), "New room missing");
    offsets[84] = 8;
    require(index.get(1, 8, offsets).size() == 2, "Dimension alias changed");
    index.reset();
    offsets.fill(-1);
    offsets[10] = 7;
    require(index.get(0, 7, offsets) == std::vector<unsigned>({10}),
            "Floor/rewind reset retained cells");
}
