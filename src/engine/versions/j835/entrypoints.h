#pragma once
#include <cstdint>

// J835 entries audited against the original executable. This is not a complete
// backend: there is no sources.cmake and builds must reject selection.
namespace isaac::engine::j835 {
namespace entry {
inline constexpr std::uint32_t menuCharacterAvailable = 0x4a1ea0;
inline constexpr std::uint32_t stringTableLookup = 0x56b880;
inline constexpr std::uint32_t luaEngineInit = 0x3fcb00;
inline constexpr std::uint32_t runtimeNetCapture = 0x2cc850;
inline constexpr std::uint32_t runtimeNetClear = 0x520160;
inline constexpr std::uint32_t engineSaveWrite = 0x521a00;
inline constexpr std::uint32_t engineSaveRead = 0x524320;
} // namespace entry
namespace globals {
inline constexpr std::uint32_t characterMenuPages = 0x60d698;
inline constexpr std::uint32_t characterMenuEntries = 0x60d6b0;
inline constexpr std::uint32_t game = 0x7fd65c;
inline constexpr std::uint32_t manager = 0x7fd680;
} // namespace globals
} // namespace isaac::engine::j835
