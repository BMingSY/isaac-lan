#pragma once

namespace isaac::compat::characters {
inline constexpr int lazarusLiving = 29;
inline constexpr int lazarusDead = 38;
inline constexpr unsigned darkEsau = 866;
inline bool lazarus(int kind) {
    return kind == lazarusLiving || kind == lazarusDead;
}
inline bool taintedJacob(int kind) {
    return kind == 37 || kind == 39;
}
} // namespace isaac::compat::characters
