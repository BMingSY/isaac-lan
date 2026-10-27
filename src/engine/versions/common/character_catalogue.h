#pragma once
#include "engine/characters.h"
#include "engine/versions/common/progress.h"

namespace isaac::engine::native_characters {
using Available = bool(__attribute__((thiscall)) *)(const void*, int);
using Lookup = const char*(__attribute__((thiscall)) *)(void*, const char*, int, const char*,
                                                        bool*);
// Native ownership stays with the game. All pointers are borrowed for a single
// synchronous query; returned catalogue entries contain copied strings only.
struct Directory {
    std::uintptr_t manager, pages, entries;
    unsigned configs, stringTable, progressOffset, scene;
    native_progress::Layout progress;
    Available available;
    Lookup lookup;
};
characters::Catalogue catalogue(const Directory& directory, const lan::Progress& personal);
} // namespace isaac::engine::native_characters
