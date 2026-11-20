#include "engine/profile.h"
#include "selected_game_profile.h"

namespace isaac::engine {
const Profile& profile() {
    return selectedProfile;
}
} // namespace isaac::engine
