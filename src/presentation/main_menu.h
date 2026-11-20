#pragma once
#include <array>

namespace isaac::presentation::main_menu {
// The extra row follows Continue. The six original selections retain their
// native indices, actions and enabled states.
inline constexpr int online = 2;
inline constexpr std::array<int, 6> nativeCursorY{68, 94, 122, 152, 181, 211};
inline constexpr std::array<int, 7> cursorY{60, 83, 107, 131, 155, 179, 203};
inline constexpr int labelX = 184, labelY = 97;
struct Position {
    float x, y;
};

constexpr int displayRow(int nativeRow) {
    return nativeRow < online ? nativeRow : nativeRow + 1;
}
constexpr int rowOffset(int native) {
    return cursorY[displayRow(native)] - nativeCursorY[native];
}
constexpr bool crossesOnline(int before, int after, bool up, bool down) {
    return (down && before < online && after >= online) ||
           (up && before >= online && after < online);
}
inline bool hitsOnline(Position paper, float mouseX, float mouseY) {
    // The printed rows slope up toward the right edge of the main menu paper.
    const float x = mouseX - paper.x, y = mouseY - paper.y;
    if (x < 160 || x > 307)
        return false;
    const float baseline = y + (x - labelX) * 0.16f;
    return baseline >= cursorY[online] - 13 && baseline < cursorY[online] + 10;
}
inline bool labelVisible(Position paper, float width, float height) {
    return paper.x + labelX < width && paper.x + 307 > 0 && paper.y + labelY - 20 < height &&
           paper.y + labelY + 20 > 0;
}
} // namespace isaac::presentation::main_menu
