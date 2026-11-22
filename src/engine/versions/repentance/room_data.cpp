#include "engine/versions/common/room_data_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
namespace isaac::engine::native_room_data {
namespace backend = repentance;
namespace g = backend::layout::game;
namespace r = backend::layout::room;
namespace d = backend::layout::roomDescriptor;
namespace c = backend::layout::roomConfig;
namespace e = backend::layout::savedEntity;
const Bindings bindings{backend::globals::game,
                        backend::entry::engineRoomsDesc,
                        backend::entry::minimapCache,
                        d::minimumRoom,
                        {g::room, g::roomIndex, g::dimension, g::descriptors, g::mapOffsets,
                         g::roomCount, g::frame, g::mapCaches, g::mapState, g::mapTimer},
                        {r::descriptor, r::waterX, r::waterY},
                        {d::size, d::gridIndex, d::safeGridIndex, d::listIndex, d::dimension,
                         d::data, d::overrideData, d::allowedDoors, d::doors, d::doorCount,
                         d::seeds, d::savedEntities},
                        {c::size, c::scalarFields, c::width, c::height, c::stringCapacity,
                         backend::layout::string::inlineCapacity, c::shape, c::type},
                        {e::size, e::mapFields}};
} // namespace isaac::engine::native_room_data
