#include "engine/player_outlines.h"
#include "engine/versions/common/player_outlines.h"
namespace isaac::presentation::outlines {
void withPlayers(unsigned connected, const std::function<void()>& render) {
    struct Restore {
        unsigned previous = participants;
        ~Restore() {
            participants = previous;
        }
    } restore;
    participants = connected;
    render();
}
} // namespace isaac::presentation::outlines
