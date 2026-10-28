#include "engine/versions/common/scene_update.h"
#include "engine/versions/common/scene_update_bindings.h"
#include "runtime/session.h"
#include <MinHook.h>

extern "C" {
void* isaac_lan_scene_update_original = nullptr;
void* isaac_lan_scene_update_skip = nullptr;
bool __cdecl isaac_lan_scene_update_allowed() {
    // Native scene markers advance the Home route. Replicas consume the
    // authority's pose until terminal native cinematics take over the run.
    return !isaac::runtime::replica() || isaac::runtime::ending();
}
__attribute__((naked)) void isaac_lan_scene_update_boundary() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, %eax\n\tandl $-16, %esp\n\t"
                         "subl $528, %esp\n\tmovl %eax, 512(%esp)\n\tfxsave (%esp)\n\t"
                         "call _isaac_lan_scene_update_allowed\n\ttestb %al, %al\n\tjz 1f\n\t"
                         "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\t"
                         "jmp *_isaac_lan_scene_update_original\n\t"
                         "1:\n\tfxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\t"
                         "jmp *_isaac_lan_scene_update_skip");
}
}
namespace isaac::engine::native_scene_update {
namespace {
bool installed = false;
using Update = void(__attribute__((thiscall)) *)(void*);
void __attribute__((fastcall)) update(void* object, void*) {
    if (isaac_lan_scene_update_allowed())
        reinterpret_cast<Update>(isaac_lan_scene_update_original)(object);
}
} // namespace
bool install(std::uintptr_t image) {
    if (!image || installed)
        return false;
    auto* target = reinterpret_cast<void*>(image + bindings.update);
    auto* detour = bindings.skip ? reinterpret_cast<void*>(isaac_lan_scene_update_boundary)
                                 : reinterpret_cast<void*>(update);
    if (MH_CreateHook(target, detour, &isaac_lan_scene_update_original) != MH_OK) {
        isaac_lan_scene_update_original = nullptr;
        return false;
    }
    isaac_lan_scene_update_skip =
        bindings.skip ? reinterpret_cast<void*>(image + *bindings.skip) : nullptr;
    if (MH_EnableHook(target) != MH_OK) {
        MH_RemoveHook(target);
        isaac_lan_scene_update_original = isaac_lan_scene_update_skip = nullptr;
        return false;
    }
    installed = true;
    return true;
}
} // namespace isaac::engine::native_scene_update
