#include "engine/moving_box.h"
#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/common/hooks.h"
#include "runtime/session.h"
#include <unordered_map>

namespace isaac::presentation::moving_box {
namespace {
using Address = std::uintptr_t;
const auto& binding = engine::native_moving_box::bindings;
Address image;
bool installed = false;
void* original;
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
        if (found != views.end() && found->second.seed == read<unsigned>(player, binding.initSeed))
            return found->second.full;
    }
    return read<Address>(player, binding.begin) != read<Address>(player, binding.end);
}
void apply(Address player, bool full) {
    views[player] = {read<unsigned>(player, binding.initSeed), full};
}
void reset() {
    views.clear();
}
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_box_icon(
    engine::native_branch::Frame* frame) {
    (*frame)[engine::native_branch::continuation] =
        image + (capture((*frame)[binding.player]) ? binding.full : binding.empty);
}
// This replaces only RenderActiveItem's empty-vector branch. The vector,
// native item data, icon textures and crop calculation retain their owners.
__attribute__((naked)) void isaac_lan_box_icon_thunk() {
    __asm__ __volatile__(ISAAC_LAN_NATIVE_BRANCH_SAVE
                         "pushl %eax\n\tcall _isaac_lan_box_icon\n\taddl $4, "
                         "%esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE);
}
}
bool install(Address base) {
    if (!base || installed)
        return false;
    image = base;
    engine::native_hooks::Group<1> hooks;
    if (!hooks.add(image + binding.branch, isaac_lan_box_icon_thunk, original) || !hooks.enable()) {
        image = 0;
        return false;
    }
    installed = true;
    return true;
}
} // namespace isaac::presentation::moving_box
