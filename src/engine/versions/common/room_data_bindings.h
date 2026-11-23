#pragma once
#include <array>
namespace isaac::engine::native_room_data {
struct Bindings {
    unsigned globalGame, descriptor, cache, backdropInit;
    int minimumRoom;
    struct Game {
        unsigned room, roomIndex, dimension, descriptors, mapOffsets, roomCount, frame;
        std::array<unsigned, 2> mapCaches;
        unsigned mapState, mapTimer;
    } game;
    struct Room {
        unsigned descriptor, waterX, waterY, backdrop, backdropType, backdropCount, floorSprite,
            spriteLoaded;
    } room;
    struct Descriptor {
        unsigned size, gridIndex, safeGridIndex, listIndex, dimension, data, overrideData;
        unsigned allowedDoors, doors, doorCount, seeds, savedEntities;
    } roomDescriptor;
    struct Config {
        unsigned size;
        std::array<unsigned, 10> fields;
        unsigned width, height, stringCapacity, inlineCapacity, shape, type;
    } config;
    struct SavedEntity {
        unsigned size;
        std::array<unsigned, 6> fields;
    } savedEntity;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_room_data
