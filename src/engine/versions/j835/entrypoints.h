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
inline constexpr std::uint32_t managerSave = 0x4b3850;
inline constexpr std::uint32_t managerDeleteSave = 0x4b3b70;
inline constexpr std::uint32_t managerSaveRerun = 0x4b3bb0;
inline constexpr std::uint32_t managerExecuteMenu = 0x4b43d0;
inline constexpr std::uint32_t managerExecuteStart = 0x4b3fd0;
inline constexpr std::uint32_t progressSerialize = 0x4836a0;
inline constexpr std::uint32_t progressPersist = 0x4848f0;
inline constexpr std::uint32_t gameStart = 0x2c97e0;
inline constexpr std::uint32_t gameUpdate = 0x2cdcf0;
inline constexpr std::uint32_t gameControls = 0x2cda60;
inline constexpr std::uint32_t consoleUpdate = 0x263550;
inline constexpr std::uint32_t consoleRunCommand = 0x2655c0;
inline constexpr std::uint32_t consolePrint = 0x26aec0;
inline constexpr std::uint32_t runtimeNetExecuteStart = 0x515b50;
inline constexpr std::uint32_t frontendAssign = 0x7c80;
inline constexpr std::uint32_t frontendMenuUpdate = 0x7be0;
inline constexpr std::uint32_t runtimeNetParseSeed = 0x53e080;
inline constexpr std::uint32_t runtimeNetSeedConstructor = 0x53bc50;
inline constexpr std::uint32_t runtimeNetSetSeed = 0x53e220;
inline constexpr std::uint32_t runtimeNetStartGame = 0x4b3470;
inline constexpr std::uint32_t inputPressed = 0x56a520;
inline constexpr std::uint32_t inputTriggered = 0x56a5e0;
inline constexpr std::uint32_t inputValue = 0x56a6c0;
} // namespace entry
namespace globals {
inline constexpr std::uint32_t characterMenuPages = 0x60d698;
inline constexpr std::uint32_t characterMenuEntries = 0x60d6b0;
inline constexpr std::uint32_t game = 0x7fd65c;
inline constexpr std::uint32_t manager = 0x7fd680;
} // namespace globals
} // namespace isaac::engine::j835
