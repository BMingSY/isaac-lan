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
    return originalHearts(hud, extent, sprite,
                          pos && replaceHearts(hud, *pos, scale) ? &outsideViewport : pos, scale);
}
} // namespace
extern "C" {
void* isaac_lan_active_item_original = nullptr;
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_hide_active_item(void* hud) {
    return hideActiveItem(hud);
}
// J835 supplies scale in XMM3 and four stack arguments.
__attribute__((naked)) void isaac_lan_active_item_draw() {
    __asm__ __volatile__("subl $16, %esp\n\tmovups %xmm3, (%esp)\n\tpushl %ecx\n\t"
                         "call _isaac_lan_hide_active_item\n\tpopl %ecx\n\t"
                         "movups (%esp), %xmm3\n\taddl $16, %esp\n\ttestb %al, %al\n\t"
                         "jnz 1f\n\tjmp *_isaac_lan_active_item_original\n\t1: ret $16");
}
}
const DrawHook activeItemHook{reinterpret_cast<void*>(isaac_lan_active_item_draw),
                              &isaac_lan_active_item_original};
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
     backend::entry::playerHudRenderActiveItem},
    {layout::statHud::player, layout::statHud::cacheStride, layout::statHud::cacheCount},
    {layout::player::controller, layout::player::index, layout::player::twin, layout::player::type},
    {layout::entity::parent, layout::entity::active},
    {layout::playerHud::size, layout::playerHud::refreshFlags, layout::playerHud::refreshAll}};
} // namespace isaac::engine::native_frontend_hud
