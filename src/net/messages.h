#pragma once
#include "net/protocol.h"
#include <algorithm>
namespace isaac::lan {
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
