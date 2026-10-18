#pragma once
#include "net/protocol.h"
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
    w.blob(std::span(value.rewind)
               .subspan(offset, std::min<std::size_t>(3000, value.rewind.size() - offset)));
    return w;
}
} // namespace isaac::lan
