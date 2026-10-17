#pragma once
#include <array>
#include <bit>
#include <bitset>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace isaac::core::animation_pose {
inline constexpr unsigned maxLayers = 64, maxNullLayers = 256, maxFrames = 65535;
struct Layer {
    std::uint16_t id;
    std::int32_t frame;
};
struct State {
    bool present = false, playing = false;
    std::uint32_t frame = 0, events = 0, previousEvents = 0;
    unsigned layerCount = 0, nullCount = 0;
    std::array<Layer, maxLayers> layers{};
    std::array<Layer, maxNullLayers> nulls{};
};
template <std::size_t N> void validate(const std::array<Layer, N>& layers, unsigned count) {
    if (count > N)
        throw std::runtime_error("Too many animation layers");
    std::bitset<N> used;
    for (unsigned i = 0; i < count; ++i) {
        const auto& layer = layers[i];
        if (layer.id >= N || used[layer.id] || layer.frame < -1 ||
            layer.frame >= static_cast<int>(maxFrames))
            throw std::runtime_error("Invalid animation layer");
        used[layer.id] = true;
    }
}
template <class Writer, std::size_t N>
void writeLayers(Writer& writer, const std::array<Layer, N>& layers, unsigned count) {
    validate(layers, count);
    writer.u16(count);
    for (unsigned i = 0; i < count; ++i) {
        writer.u16(layers[i].id);
        writer.u32(std::bit_cast<std::uint32_t>(layers[i].frame));
    }
}
template <class Writer> void write(Writer& writer, const State& state) {
    writer.u8(state.present);
    if (!state.present)
        return;
    if (!std::isfinite(std::bit_cast<float>(state.frame)))
        throw std::runtime_error("Invalid animation frame");
    writer.u32(state.frame);
    writer.u8(state.playing);
    writer.u32(state.events);
    writer.u32(state.previousEvents);
    writeLayers(writer, state.layers, state.layerCount);
    writeLayers(writer, state.nulls, state.nullCount);
}
template <class Reader, std::size_t N>
unsigned readLayers(Reader& reader, std::array<Layer, N>& layers) {
    const auto count = reader.u16();
    if (count > N)
        throw std::runtime_error("Too many animation layers");
    for (unsigned i = 0; i < count; ++i)
        layers[i] = {reader.u16(), std::bit_cast<std::int32_t>(reader.u32())};
    validate(layers, count);
    return count;
}
template <class Reader> State read(Reader& reader) {
    State state;
    const auto present = reader.u8();
    if (present > 1)
        throw std::runtime_error("Invalid animation presence");
    state.present = present;
    if (!present)
        return state;
    state.frame = reader.u32();
    const auto playing = reader.u8();
    if (!std::isfinite(std::bit_cast<float>(state.frame)) || playing > 1)
        throw std::runtime_error("Invalid animation state");
    state.playing = playing;
    state.events = reader.u32();
    state.previousEvents = reader.u32();
    state.layerCount = readLayers(reader, state.layers);
    state.nullCount = readLayers(reader, state.nulls);
    return state;
}
} // namespace isaac::core::animation_pose
