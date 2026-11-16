#include "engine/versions/j460/death_certificate_return.h"
#include "engine/versions/j460/branch_registers.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/rooms.h"
#include "compat/items/death_certificate.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>
#include <stdexcept>

namespace isaac::engine::j460 {
namespace {
std::uintptr_t image;
template <class T> T& at(std::uintptr_t object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
} // namespace
extern "C" {
void* isaac_lan_certificate_original = nullptr;
void* isaac_lan_certificate_done = nullptr;
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_certificate_return() {
    const auto game = at<std::uintptr_t>(image, globals::game);
    if (!rooms::virtualized() || runtime::replica() ||
        at<int>(game, layout::game::dimension) == compat::items::deathCertificateDimension)
        return false;
    // Native Game::Update has finished the shared pickup countdown. Its
    // viewport can be outside the annex after a per-player rewind; borrow an
    // actual annex occupant for this one native transition, not the update.
    at<int>(game, layout::game::deathCertificateReturnTimer) = 0;
    try {
        const auto locations = rooms::captureLocations();
        std::array<int, 4> dimensions{};
        for (unsigned slot = 0; slot < locations.size() && slot < dimensions.size(); ++slot)
            dimensions[slot] = locations[slot].dimension;
        const auto slot = compat::items::deathCertificateReturnSlot(dimensions, rooms::connected());
        if (!slot)
            return true;
        if (!rooms::withPlayer(*slot, [&] {
                using Transition =
                    void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
                at<int>(game, layout::game::leaveDoor) = -1;
                reinterpret_cast<Transition>(image + entry::engineRoomsTransition)(
                    reinterpret_cast<void*>(game),
                    at<int>(game, layout::game::deathCertificateRoom), -1,
                    compat::items::deathCertificateAnimation, nullptr,
                    at<signed char>(game, layout::game::deathCertificateDimension));
            }))
            throw std::runtime_error("Cannot restore the Death Certificate return context");
    } catch (const std::exception& error) {
        runtime::abort(error.what());
    }
    return true;
}
__attribute__((naked)) void isaac_lan_certificate_thunk() {
    __asm__ __volatile__(ISAAC_LAN_BRANCH_SAVE
                         "call _isaac_lan_certificate_return\n\ttestb %al, %al\n\t"
                         "movl _isaac_lan_certificate_original, %eax\n\tjz 1f\n\t"
                         "movl _isaac_lan_certificate_done, %eax\n\t1:\n\tmovl %eax, "
                         "164(%esp)\n\t" ISAAC_LAN_BRANCH_RESTORE);
}
}
bool installDeathCertificateReturn(std::uintptr_t base) {
    image = base;
    isaac_lan_certificate_done = reinterpret_cast<void*>(image + entry::deathCertificateReturnEnd);
    auto site = reinterpret_cast<void*>(image + entry::deathCertificateReturn);
    return MH_CreateHook(site, reinterpret_cast<void*>(isaac_lan_certificate_thunk),
                         &isaac_lan_certificate_original) == MH_OK &&
           MH_EnableHook(site) == MH_OK;
}
} // namespace isaac::engine::j460
