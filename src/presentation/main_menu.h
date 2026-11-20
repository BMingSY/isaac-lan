#pragma once
#include <array>

namespace isaac::presentation::main_menu {
// Printed order on the original Repentance menu. The stock selector uses all seven rows.
inline constexpr int online = 2;
inline constexpr std::array<int, 6> nativeCursorX{168, 171, 172, 176, 182, 187};
inline constexpr std::array<int, 6> nativeCursorY{68, 94, 122, 152, 181, 211};
inline constexpr std::array<int, 7> cursorX{168, 170, 172, 174, 178, 182, 187};
inline constexpr std::array<int, 7> cursorY{60, 83, 107, 131, 155, 179, 203};
inline constexpr int labelX = 183, labelY = 96;
struct Position {
    float x, y;
};

constexpr int displayRow(int nativeRow) {
    return nativeRow < online ? nativeRow : nativeRow + 1;
}
constexpr int rowOffset(int native) {
    return cursorY[displayRow(native)] - nativeCursorY[native];
}
inline bool hitsOnline(Position paper, float mouseX, float mouseY) {
    // The printed rows slope up toward the right edge of the main menu paper.
    const float x = mouseX - paper.x, y = mouseY - paper.y;
    if (x < 160 || x > 307)
        return false;
    const float baseline = y + (x - labelX) * 0.268f; // 15-degree paper lettering
    return baseline >= cursorY[online] - 13 && baseline < cursorY[online] + 10;
}
inline bool labelVisible(Position paper, float width, float height) {
    return paper.x + labelX < width && paper.x + 307 > 0 && paper.y + labelY - 20 < height &&
           paper.y + labelY + 20 > 0;
}
} // namespace isaac::presentation::main_menu
