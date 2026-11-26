#include "engine/versions/common/frontend_hud_bindings.h"
#include "engine/versions/common/frontend_hud.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
namespace isaac::engine::native_frontend_hud {
namespace backend = repentance;
namespace layout = backend::layout;
namespace {
using Hearts = Point*(__attribute__((thiscall)) *)(void*, Point*, void*, const Point*, float);
Hearts originalHearts = nullptr;
Point* __attribute__((fastcall)) drawHearts(void* hud, void*, Point* extent, void* sprite,
                                            const Point* pos, float scale) {
    return originalHearts(
        hud, extent, sprite,
        pos && replace(Component::hearts, hud, {*pos, scale}) ? &outsideViewport : pos, scale);
}
} // namespace
// Both J835 slot methods borrow the position and receive scale in XMM3.
struct SlotArgs {
    unsigned slot;
    const Point* position;
};
struct ActiveArgs {
    SlotArgs item;
    float alpha, unused;
};
extern "C" {
void* isaac_lan_active_item_original = nullptr;
void* isaac_lan_trinket_original = nullptr;
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_active_item_filter(
    void* hud, const ActiveArgs* args, float scale) {
    const auto& item = args->item;
    return item.position &&
           replace(Component::activeItem, hud,
                   {*item.position, scale, args->alpha, static_cast<int>(item.slot)});
}
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_trinket_filter(
    void* hud, const SlotArgs* item, float scale) {
    return item->position && replace(Component::trinket, hud,
                                     {*item->position, scale, 1, static_cast<int>(item->slot)});
}
#define SLOT_DRAW(filter, original, stackBytes)                                                    \
    __asm__ __volatile__("leal 4(%esp), %eax\n\tsubl $16, %esp\n\tmovups %xmm3, (%esp)\n\t"        \
                         "pushl %ecx\n\tpushl 4(%esp)\n\tpushl %eax\n\tpushl %ecx\n\t"             \
                         "call _" #filter "\n\taddl $12, %esp\n\tpopl %ecx\n\t"                    \
                         "movups (%esp), %xmm3\n\taddl $16, %esp\n\ttestb %al, %al\n\t"            \
                         "jnz 1f\n\tjmp *_" #original "\n\t1: ret $" #stackBytes)
__attribute__((naked)) void isaac_lan_active_item_draw() {
    SLOT_DRAW(isaac_lan_active_item_filter, isaac_lan_active_item_original, 16);
}
__attribute__((naked)) void isaac_lan_trinket_draw() {
    SLOT_DRAW(isaac_lan_trinket_filter, isaac_lan_trinket_original, 8);
}
#undef SLOT_DRAW
}
const DrawHook activeItemHook{reinterpret_cast<void*>(isaac_lan_active_item_draw),
                              &isaac_lan_active_item_original};
const DrawHook trinketHook{reinterpret_cast<void*>(isaac_lan_trinket_draw),
                           &isaac_lan_trinket_original};
const DrawHook heartHook{reinterpret_cast<void*>(drawHearts),
                         reinterpret_cast<void**>(&originalHearts)};
const Bindings bindings{
    backend::globals::game,
    layout::game::players,
    layout::hud::history,
    {backend::entry::frontendStatHUDGetPlayerId, backend::entry::frontendStatHUDReset,
     backend::entry::historyHUDGetPlayerId, backend::entry::historyHUDRecomputeAll,
     backend::entry::playerHUDReset, backend::entry::hUDUpdate, backend::entry::hUDPostUpdate,
     backend::entry::hUDRender, backend::entry::playerHudRenderHearts,
     backend::entry::playerHudRenderActiveItem, backend::entry::playerHudRenderTrinket},
    {layout::statHud::player, layout::statHud::cacheStride, layout::statHud::cacheCount},
    {layout::player::controller, layout::player::index, layout::player::twin, layout::player::type},
    {layout::entity::parent, layout::entity::active},
    {layout::playerHud::size, layout::playerHud::refreshFlags, layout::playerHud::refreshAll}};
} // namespace isaac::engine::native_frontend_hud
