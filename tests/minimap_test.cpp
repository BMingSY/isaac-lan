#include "presentation/minimap.h"
#include "test_support.h"
#include <limits>

int main() {
    using namespace isaac::presentation;
    // A cropped map around cell (6, 6), rendered at twice its texture scale.
    const auto small = projectMinimap({40, 30, 80, 70}, {300, 20, 380, 100}, 4, -6, 10, 10, .5f, 0);
    require(small && small->x + 6 * small->cellWidth == 348, "Cropped horizontal anchor");
    require(small->y + 6 * small->cellHeight == 68 && small->alpha == .5f,
            "Cropped vertical anchor and fade");
    require(small->clip.left == 300 && small->clip.bottom == 100, "Native viewport bounds");
    const auto large = projectMinimap({0, 0, 200, 160}, {50, 10, 250, 170}, 4, 6, 10, 8, 1.2f, 2);
    require(large && large->x == 54 && large->y == 16 && large->cellHeight == 8,
            "Expanded map transform");
    require(large->alpha == 1 && large->dimension == 2, "Clamped opacity and dimension");
    require(!projectMinimap({0, 0, 0, 10}, {0, 0, 100, 100}, 0, 0, 1, 1, 1, 0),
            "Empty texture crop");
    require(!projectMinimap({0, 0, 10, 10}, {0, 0, 100, 100}, 0, 0, 1, 1, 0, 0), "Hidden map");
    require(!projectMinimap({0, 0, 10, 10}, {0, 0, 100, 100}, 0, 0, -1, 1, 1, 0), "Invalid pitch");
    require(!projectMinimap({0, 0, 10, 10}, {0, 0, 100, 100},
                            std::numeric_limits<float>::quiet_NaN(), 0, 1, 1, 1, 0),
            "Non-finite projection");
}
