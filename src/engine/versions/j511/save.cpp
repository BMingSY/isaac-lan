#include "engine/save.h"
#include "engine/versions/common/save_stream.h"
#include "engine/versions/common/save_file_names.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::save {
namespace {
namespace backend = engine::j511;
namespace stream = engine::native_save;
std::uintptr_t state(std::uintptr_t image) {
    return *reinterpret_cast<std::uintptr_t*>(image + backend::globals::manager) +
           backend::layout::manager::saveState;
}
std::uintptr_t& streamField(std::uintptr_t gameState) {
    return *reinterpret_cast<std::uintptr_t*>(gameState + backend::layout::gameState::stream);
}
} // namespace
std::vector<std::uint8_t> encode(std::uintptr_t image) {
    return encodeAt(image, state(image));
}
std::vector<std::uint8_t> encodeAt(std::uintptr_t image, std::uintptr_t gameState) {
    using Write = bool(__attribute__((thiscall))*)(void*, stream::Context*);
    const auto write = reinterpret_cast<Write>(image + backend::entry::engineSaveWrite);
    return stream::encode(streamField(gameState), [&](stream::Context& context) {
        return write(reinterpret_cast<void*>(gameState), &context);
    });
}
bool decode(std::uintptr_t image, std::span<const std::uint8_t> bytes) {
    return decodeAt(image, state(image), bytes);
}
bool decodeAt(std::uintptr_t image, std::uintptr_t gameState, std::span<const std::uint8_t> bytes) {
    using Clear = void(__attribute__((thiscall))*)(void*);
    using Read = bool(__attribute__((thiscall))*)(void*, stream::Context*, bool);
    const auto clear = reinterpret_cast<Clear>(image + backend::entry::runtimeNetClear);
    const auto read = reinterpret_cast<Read>(image + backend::entry::engineSaveRead);
    return stream::decode(
        streamField(gameState), bytes, [&] { clear(reinterpret_cast<void*>(gameState)); },
        [&](stream::Context& context) {
            const stream::FileNames names(gameState, backend::layout::gameState::fileNames);
            return read(reinterpret_cast<void*>(gameState), &context, false);
        });
}
std::vector<std::uint8_t> capture(std::uintptr_t image) {
    using Capture = void(__attribute__((thiscall))*)(void*, void*);
    const auto game = *reinterpret_cast<void**>(image + backend::globals::game);
    reinterpret_cast<Capture>(image + backend::entry::runtimeNetCapture)(
        game, reinterpret_cast<void*>(state(image)));
    return encode(image);
}
} // namespace isaac::save
