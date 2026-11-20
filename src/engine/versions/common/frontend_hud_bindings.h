#pragma once
namespace isaac::engine::native_frontend_hud {
struct Bindings {
    unsigned game, players, history;
    struct Entry {
        unsigned statPlayerId, frontendStatHUDReset, historyPlayerId, historyHUDRecomputeAll;
        unsigned playerHUDReset, update, postUpdate, render;
    } entry;
    struct Stats {
        unsigned player, cacheStride, cacheCount;
    } stats;
    struct Player {
        unsigned controller, index, twin, type;
    } player;
    struct Entity {
        unsigned parent, active;
    } entity;
    struct PlayerHud {
        unsigned size, refreshFlags, refreshAll;
    } playerHud;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_frontend_hud
