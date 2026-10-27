#pragma once
#include "engine/versions/common/progress.h"
#include <array>

namespace isaac::engine::j835::layout {
namespace manager {
inline constexpr unsigned progress = 0x14, scene = 0x8;
inline constexpr unsigned stringTable = 0x4a234;
inline constexpr unsigned characterConfigs = 0x29f90;
inline constexpr unsigned saveState = 0xf34;
inline constexpr unsigned saveSlot = 0x10, continueAvailable = 0x209c4;
inline constexpr unsigned continueRequested = 0x1ea6c1, deleteSaveRequested = 0x1ea814;
inline constexpr unsigned cinematicActive = 0x1ea830;
inline constexpr unsigned menuRequested = 0x1ea818, requestedMenu = 0x1ea81c;
} // namespace manager
namespace progress {
inline constexpr unsigned dirty = 0, readOnly = 1;
inline constexpr unsigned achievements = 0x38, counters = 0x2b8;
inline constexpr unsigned achievementCount = 638, counterCount = 496;
inline constexpr native_progress::Layout fields{achievements, achievementCount, counters,
                                                counterCount};
} // namespace progress
namespace gameState {
inline constexpr unsigned stream = 0x1fac8;
// Local primary/backup and Steam primary/backup MSVC strings. Native Clear
// preserves these; Read consults them only for logging and failure deletion.
inline constexpr std::array<unsigned, 4> fileNames{0x1fa60, 0x1fa78, 0x1fa98, 0x1fab0};
} // namespace gameState
namespace game {
inline constexpr unsigned stage = 0, stageType = 4;
inline constexpr unsigned floorSeeds = 0x1bb1c, stateFlags = 0x1c3168;
inline constexpr unsigned pauseMenu = 0x10203c, console = 0x1bb60;
inline constexpr unsigned fadeAlpha = 0x1c31a8, fadeAction = 0x1c31b0;
inline constexpr unsigned restartHeldFrames = 0x1c31b4;
} // namespace game
namespace console {
inline constexpr unsigned state = 0x20;
} // namespace console
namespace luaEngine {
inline constexpr unsigned state = 0x18;
} // namespace luaEngine
} // namespace isaac::engine::j835::layout
