#pragma once
#include <cstdint>
#include <string>

namespace isaac::engine::native_item_presentation {
using Address = std::uintptr_t;
inline constexpr unsigned stickyText = 1, curseText = 2;
struct Bindings {
    struct Entries {
        unsigned aNM2Construct, itemOverlayConfigConstruct, itemOverlayDestruct;
        unsigned itemOverlayLoad, itemOverlayUpdate, itemOverlayShow, itemOverlayRender;
        unsigned hUDShowItemText, hUDShowItemTextCustomUTF8, hudShowFortune;
        unsigned stringTableLookup, stringTableIndexed, gameAddPixelation, playerUpdateWavyCap;
        unsigned playerUsePill, playerUseCard, bossOverlayShow;
        unsigned managerGetItemConfig, itemConfigGetCollectible, itemConfigGetTrinket;
    } entry;
    unsigned game, manager;
    struct Layout {
        struct Game {
            unsigned stage, stageType, players, overlay, scene, hud, pauseMenu;
            unsigned pixelation, pixelationDuration, dizzyIntensity, dizzyTarget, dizzyStep;
            unsigned bloomTime, bloomDuration, bloomIntensity;
        } game;
        struct Player {
            unsigned controller, controls;
        } player;
        struct Overlay {
            unsigned size, state, id, book, configs, configCount, configStride, mega, delay;
        } overlay;
        struct Sprite {
            unsigned size, animationOwner, overlayOwner, loaded, playing, frame;
        } sprite;
        struct Scene {
            unsigned state, id, sprite;
        } scene;
        struct Manager {
            unsigned scene, stringTable, nightmare;
        } manager;
        struct Nightmare {
            unsigned home, index, background, bubble;
        } nightmare;
        struct Item {
            unsigned id, type;
        } item;
    } layout;
    // Repentance+ accepts an actor and always uses sticky, non-curse text. J835
    // accepts two style flags and inherits the actor from the active scope.
    bool customTextStyle;
    void* customTextDetour;
    void (*callCustomText)(void* original, void* hud, void* actor, const char* title,
                           const char* subtitle, unsigned style);
    bool (*indexedTextInRange)(Address table, const std::string& category, int index);
};
extern const Bindings bindings;
void captureCustomText(void* hud, void* actor, const char* title, const char* subtitle,
                       unsigned style);
} // namespace isaac::engine::native_item_presentation
