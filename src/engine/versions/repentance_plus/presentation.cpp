#include "engine/versions/common/presentation_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/boss_intro.h"
#include "engine/versions/repentance_plus/player_hud.h"

namespace isaac::engine::native_presentation {
namespace {
namespace backend = repentance_plus;
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
void prepareActor(Address, Address game, Address) {
    const auto roster = at<Address>(game, layout::game::players);
    if (roster != at<Address>(game, layout::game::players + layout::vector::end))
        at<Address>(game, layout::game::introPlayer) = at<Address>(roster, 0);
}
bool introMarker(Address transition) {
    // This is a full boss ID, not the byte used by the original game.
    return at<unsigned>(transition, layout::roomTransition::active) != 0;
}
bool canRestoreControls(Address game) {
    constexpr int nativeControlLock = 2;
    return at<int>(game, layout::game::controlRestoreGuard) < nativeControlLock;
}
std::optional<native_player_hud::Anchor> hudAnchor(Address image, Address game, unsigned index,
                                                   float width, float height, unsigned audience) {
    using Layout = int(__attribute__((thiscall))*)(void*, int, void*);
    using Position = float*(__attribute__((thiscall))*)(void*, float*, int, int);
    return backend::player_hud::anchor(
        game + layout::game::hud, index, width, height,
        [image](auto hud, auto corner, auto player) {
            return reinterpret_cast<Layout>(image + backend::entry::hUDPlayerLayout)(
                reinterpret_cast<void*>(hud), corner, reinterpret_cast<void*>(player));
        },
        [image](auto hud, auto point, auto corner, auto placement) {
            reinterpret_cast<Position>(image + backend::entry::hUDPlayerPosition)(
                reinterpret_cast<void*>(hud), point, corner, placement);
        },
        audience);
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
