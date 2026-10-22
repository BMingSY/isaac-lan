#include "engine/versions/j460/spawner_links.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "core/parent_chain.h"
#include <MinHook.h>

namespace isaac::engine::j460::spawner_links {
namespace {
using Lookup = void*(__attribute__((thiscall)) *)(void*);
Lookup originalLookup = nullptr;

// This translation unit, including the instantiated chain walk, is compiled
// with -mgeneral-regs-only. The native leaf preserves XMM/x87 state and EDX;
// its callers use that stronger contract, beyond the usual thiscall ABI.
void* checkedRoot(void* entity) noexcept asm("isaac_lan_checked_spawner_root");
__attribute__((noinline, used)) void* checkedRoot(void* entity) noexcept {
    const auto next = [](void* node) {
        return *reinterpret_cast<void* const*>(static_cast<const char*>(node) +
                                               layout::entity::spawner);
    };
    if (!core::parent_chain::accepts(entity, next(entity), next))
        return entity;
    return originalLookup(entity);
}

__attribute__((naked, fastcall)) void* lookup(void*, void*) {
    // Original: non-null ECX input; EAX == ECX == terminal on return, EDX is
    // unchanged, and the final null-link test sets ZF/PF and clears CF/SF/OF.
    // No owning reference or object field is changed by either path.
    asm volatile("push %edx\n\t"
                 "push %ecx\n\t"
                 "call isaac_lan_checked_spawner_root\n\t"
                 "add $4, %esp\n\t"
                 "pop %edx\n\t"
                 "mov %eax, %ecx\n\t"
                 "cmp %eax, %eax\n\t"
                 "ret");
}
} // namespace

bool install(std::uintptr_t image) {
    auto* target = reinterpret_cast<void*>(image + entry::entitySpawnerRoot);
    if (MH_CreateHook(target, reinterpret_cast<void*>(lookup),
                      reinterpret_cast<void**>(&originalLookup)) != MH_OK)
        return false;
    if (MH_EnableHook(target) != MH_OK) {
        MH_RemoveHook(target);
        originalLookup = nullptr;
        return false;
    }
    return true;
}
} // namespace isaac::engine::j460::spawner_links
