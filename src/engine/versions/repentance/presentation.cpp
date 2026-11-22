#include "engine/versions/common/presentation_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/boss_intro.h"
#include "engine/versions/repentance/player_hud.h"

namespace isaac::engine::native_presentation {
namespace {
namespace backend = repentance;
namespace layout = backend::layout;
template <class T> T& at(Address address, unsigned offset) {
    return *reinterpret_cast<T*>(address + offset);
}
void finishIntro(Address image, Address transition) {
    using Update = void(__attribute__((thiscall))*)(void*);
    backend::finishBossIntro(transition, [&] {
        reinterpret_cast<Update>(image + backend::entry::roomTransitionUpdate)(
            reinterpret_cast<void*>(transition));
    });
}
void prepareActor(Address image, Address game, Address transition) {
    const auto roster = at<Address>(game, layout::game::players);
    if (roster != at<Address>(game, layout::game::players + layout::vector::end)) {
        // RoomTransition::Start registers this EntityPtr with the actor. Use
        // that same native assignment so removal clears the live reference.
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        reinterpret_cast<Assign>(image + backend::entry::entityPtrAssign)(
            reinterpret_cast<void*>(transition + layout::roomTransition::actor),
            reinterpret_cast<void*>(at<Address>(roster, 0)));
    }
}
bool introMarker(Address transition) {
    return at<bool>(transition, layout::roomTransition::bossIntro);
}
bool canRestoreControls(Address) {
    // Repentance+'s extra native control-state object does not exist in Repentance.
    // The shared caller still checks the room identity and LAN ending state.
    return true;
}
std::optional<native_player_hud::Anchor> hudAnchor(Address image, Address game, unsigned index,
                                                   float width, float height) {
    const auto manager = at<Address>(image, backend::globals::manager);
    if (!manager)
        return {};
    return backend::player_hud::anchor(
        game + layout::game::hud, index, width, height,
        at<float>(manager, layout::manager::options + layout::options::hudOffset));
}
} // namespace
const Bindings bindings{
    {backend::entry::playerHasCollectible, backend::entry::roomNightLightQuery + 5,
     backend::entry::roomTransitionStartBossIntro, backend::entry::roomTransitionUpdate,
     backend::entry::playerManagerSetControlsEnabled},
    backend::globals::game,
    backend::globals::manager,
    backend::globals::logicalWidth,
    backend::globals::logicalHeight,
    {layout::manager::scene,
     layout::player::controller,
     {layout::game::stage, layout::game::stageType, layout::game::roomIndex,
      layout::game::dimension, layout::game::roomTransition, layout::game::pauseMenu,
      layout::game::playerManager},
     {layout::roomTransition::state, layout::roomTransition::index,
      layout::roomTransition::dimension},
     {layout::room::firstBoss, layout::room::secondBoss, layout::room::enemies,
      layout::room::delayedEnemies, layout::room::descriptor},
     {layout::roomDescriptor::data, layout::roomDescriptor::flags},
     {layout::roomConfig::stage, layout::roomConfig::type, layout::roomConfig::variant}},
    finishIntro,
    prepareActor,
    introMarker,
    canRestoreControls,
    hudAnchor};
} // namespace isaac::engine::native_presentation
