#include "engine/characters.h"
#include "engine/versions/common/character_catalogue.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/completion_marks.h"

namespace isaac::characters {
namespace backend = engine::j460;
std::uint32_t completionPreview(unsigned character, const lan::Progress& personal) {
    return backend::completion::preview(character, personal);
}
std::optional<std::array<std::uint8_t, 12>> completionLayers(std::uint32_t preview) {
    return backend::completion::layers(preview);
}
Catalogue catalogue(std::uintptr_t image, const lan::Progress& personal) {
    if (!image)
        return {};
    namespace native = engine::native_characters;
    const native::Directory directory{
        *reinterpret_cast<std::uintptr_t*>(image + backend::globals::manager),
        image + backend::globals::characterMenuPages,
        image + backend::globals::characterMenuEntries,
        backend::layout::manager::characterConfigs,
        backend::layout::manager::stringTable,
        backend::layout::manager::progress,
        backend::layout::manager::scene,
        backend::layout::progress::fields,
        reinterpret_cast<native::Available>(image + backend::entry::menuCharacterAvailable),
        reinterpret_cast<native::Lookup>(image + backend::entry::stringTableLookup)};
    return native::catalogue(directory, personal);
}
} // namespace isaac::characters
