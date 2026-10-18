#pragma once
#include "net/protocol.h"
#include "net/bulk_transfer.h"
#include "net/compression.h"
#include <algorithm>
namespace isaac::lan {
struct InputSample {
    std::uint32_t sequence;
    InputFrame input;
    std::optional<InputRoom> room;
};
inline InputSample readInput(Reader& r) {
    InputSample sample{r.u32(), r.input(), {}};
    const auto hasRoom = r.u8();
    if (hasRoom > 1)
        throw std::runtime_error("Invalid input room flag");
    if (hasRoom) {
        sample.room = InputRoom{r.u32(), static_cast<std::int16_t>(r.u16()), r.u8()};
        auto& room = *sample.room;
        room.introSerial = r.u32();
        const auto active = r.u8();
        if (active > 1)
            throw std::runtime_error("Invalid intro state");
        room.introActive = active != 0;
        if (room.index < -20 || room.index >= 169 || room.dimension > 2)
            throw std::runtime_error("Invalid input room");
    }
    return sample;
}
inline Writer inputMessage(const InputSample& sample) {
    Writer w(Message::input);
    w.u32(sample.sequence);
    w.input(sample.input);
    w.u8(sample.room.has_value());
    if (sample.room) {
        const auto& room = *sample.room;
        w.u32(room.epoch);
        w.u16(static_cast<std::uint16_t>(room.index));
        w.u8(room.dimension);
        w.u32(room.introSerial);
        w.u8(room.introActive);
    }
    return w;
}
inline std::uint16_t retainedInputEdges(const InputFrame& previous,
                                        const std::optional<InputRoom>& before,
                                        const std::optional<InputRoom>& after) {
    const bool sameRoom = before && after ? before->sameRoom(*after) : before == after;
    return previous.triggered & (sameRoom ? 0xffffu : menuActionMask);
}
inline void writeRules(Writer& w, const RunRules& rules) {
    w.u16(rules.id);
    w.u16(rules.version);
    w.u16(rules.character);
    w.u8(rules.difficulty);
    w.u8(rules.transient);
}
inline RunRules readRules(Reader& r) {
    RunRules value;
    value.id = r.u16();
    value.version = r.u16();
    value.character = r.u16();
    value.difficulty = r.u8();
    const auto transient = r.u8();
    value.transient = transient != 0;
    if (transient > 1 || !value.valid())
        throw std::runtime_error("Invalid run rules");
    return value;
}
struct StartEnvelope {
    Start settings;
    std::string run;
    std::uint32_t epoch = 0;
    std::size_t size = 0;
    std::uint64_t checksum = 0;
};
inline StartEnvelope readStart(Reader& r) {
    StartEnvelope value;
    value.settings.rules = readRules(r);
    value.settings.seed = r.string();
    value.settings.difficulty = r.u8();
    for (auto& character : value.settings.characters)
        character = r.u16();
    value.settings.progress = r.progress();
    value.run = r.string();
    value.epoch = r.u32();
    value.settings.firstTick = r.u32();
    value.settings.connected = r.u8();
    value.size = r.u32();
    value.checksum = r.u64();
    if (value.run.size() != 32)
        throw std::runtime_error("Invalid integration run identity");
    if (value.size > maxSnapshotSize + StateCompression::headerSize)
        throw std::runtime_error("Invalid start state");
    return value;
}
struct StageChunk {
    Stage settings;
    std::size_t total, offset;
    std::vector<std::uint8_t> bytes;
};
inline StageChunk readStageChunk(Reader& r) {
    StageChunk chunk;
    auto& value = chunk.settings;
    value.epoch = r.u32();
    value.level = r.u8();
    value.type = r.u8();
    value.animation = r.u8();
    const auto same = r.u8();
    for (auto& seed : value.seeds)
        seed = r.u32();
    for (auto& flags : value.stateFlags)
        flags = r.u32();
    value.restart = r.u8();
    value.cinematic = r.u8();
    value.sourceRoom = static_cast<std::int16_t>(r.u16());
    chunk.total = r.u32();
    chunk.offset = r.u32();
    chunk.bytes = r.blob(bulkChunkSize);
    if (!value.epoch || value.level < 1 || value.level > 13 || value.type > 5 || same > 1 ||
        chunk.total > maxSnapshotSize + StateCompression::headerSize || value.restart > 2 ||
        value.sourceRoom < -20 || value.sourceRoom >= 169 ||
        (value.cinematic && (value.cinematic != 25 || value.level != 13 || value.type != 1 ||
                             value.animation != 1 || same || value.restart || chunk.total)) ||
        (value.restart &&
         (chunk.total || value.animation || same || value.level != 1 || value.type)) ||
        (chunk.total ? value.animation != 12 : value.animation > 6))
        throw std::runtime_error("Invalid floor transition");
    value.same = same != 0;
    return chunk;
}
inline Writer stageMessage(const Stage& value, std::size_t offset = 0) {
    Writer w(Message::stage);
    w.u32(value.epoch);
    w.u8(value.level);
    w.u8(value.type);
    w.u8(value.animation);
    w.u8(value.same);
    for (auto seed : value.seeds)
        w.u32(seed);
    for (auto flags : value.stateFlags)
        w.u32(flags);
    w.u8(value.restart);
    w.u8(value.cinematic);
    w.u16(static_cast<std::uint16_t>(value.sourceRoom));
    w.u32(value.rewind.size());
    w.u32(offset);
    w.blob(bulkChunk(value.rewind, offset));
    return w;
}
} // namespace isaac::lan
