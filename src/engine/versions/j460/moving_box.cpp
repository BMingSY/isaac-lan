#include "engine/moving_box.h"
#include "engine/versions/j460/branch_registers.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <unordered_map>

namespace isaac::presentation::moving_box {
namespace {
using Address = std::uintptr_t;
namespace layout = engine::j460::layout;
template <class T> T read(Address object, unsigned offset) {
    return *reinterpret_cast<const T*>(object + offset);
}
struct View {
    unsigned seed;
    bool full;
};
std::unordered_map<Address, View> views;
} // namespace
bool capture(Address player) {
    if (runtime::replica()) {
        const auto found = views.find(player);
        if (found != views.end() &&
            found->second.seed == read<unsigned>(player, layout::entity::initSeed))
            return found->second.full;
    }
    return read<Address>(player, layout::player::movingBoxBegin) !=
           read<Address>(player, layout::player::movingBoxEnd);
}
void apply(Address player, bool full) {
    views[player] = {read<unsigned>(player, layout::entity::initSeed), full};
}
void reset() {
    views.clear();
}
extern "C" {
void* isaac_lan_box_full = nullptr;
void* isaac_lan_box_empty = nullptr;
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_box_icon(Address player) {
    return capture(player);
}
// This replaces only RenderActiveItem's empty-vector branch. The vector,
// native item data, icon textures and crop calculation retain their owners.
__attribute__((naked)) void isaac_lan_box_icon_thunk() {
    __asm__ __volatile__(ISAAC_LAN_BRANCH_SAVE
                         "pushl %ecx\n\tcall _isaac_lan_box_icon\n\taddl $4, %esp\n\t"
                         "testb %al, %al\n\tmovl _isaac_lan_box_empty, %eax\n\tjz 1f\n\t"
                         "movl _isaac_lan_box_full, %eax\n\t1:\n\tmovl %eax, "
                         "164(%esp)\n\t" ISAAC_LAN_BRANCH_RESTORE);
}
}
bool install(Address image) {
    namespace entry = engine::j460::entry;
    isaac_lan_box_full = reinterpret_cast<void*>(image + entry::movingBoxHudFull);
    isaac_lan_box_empty = reinterpret_cast<void*>(image + entry::movingBoxHudEmpty);
    auto site = reinterpret_cast<void*>(image + entry::movingBoxHudBranch);
    return MH_CreateHook(site, reinterpret_cast<void*>(isaac_lan_box_icon_thunk), nullptr) ==
               MH_OK &&
           MH_EnableHook(site) == MH_OK;
}
} // namespace isaac::presentation::moving_box
