#include "core/party.h"
#include "engine/versions/common/death_certificate_return.h"
#include "engine/versions/common/death_certificate_bindings.h"
#include "engine/versions/common/branch_frame.h"
#include "engine/versions/common/hooks.h"
#include "engine/rooms.h"
#include "compat/items/death_certificate.h"
#include "runtime/session.h"
#include <array>
#include <stdexcept>

namespace isaac::engine::native_certificate_return {
namespace {
std::uintptr_t image = 0;
bool installed = false;
void* original = nullptr;
void* done = nullptr;
template <class T> T& at(std::uintptr_t object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
bool finishReturn() {
    const auto game = at<std::uintptr_t>(image, bindings.game);
    if (!game || !rooms::virtualized() || runtime::replica() ||
        at<int>(game, bindings.dimension) == compat::items::deathCertificateDimension)
        return false;
    // The shared pickup countdown has expired, but a per-player rewind can
    // leave the viewport outside the annex. Borrow an annex occupant only for
    // the native return; never run the whole update in that player's context.
    at<int>(game, bindings.timer) = 0;
    const auto locations = rooms::captureLocations();
    std::array<int, party::maxPlayers> dimensions{};
    for (unsigned slot = 0; slot < locations.size() && slot < dimensions.size(); ++slot)
        dimensions[slot] = locations[slot].dimension;
    const auto slot = compat::items::deathCertificateReturnSlot(dimensions, rooms::connected());
    if (!slot)
        return true;
    if (!rooms::withPlayer(*slot, [&] { bindings.transition(image, game); }))
        throw std::runtime_error("Cannot restore the Death Certificate return context");
    return true;
}
} // namespace
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_certificate_prepare(
    native_branch::Frame* frame) noexcept {
    (*frame)[native_branch::continuation] = reinterpret_cast<std::uintptr_t>(done);
    try {
        if (!finishReturn())
            (*frame)[native_branch::continuation] = reinterpret_cast<std::uintptr_t>(original);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
    } catch (...) {
        runtime::abort("Native Death Certificate return failed");
    }
}
__attribute__((naked)) void isaac_lan_certificate_thunk() {
    __asm__ __volatile__(ISAAC_LAN_NATIVE_BRANCH_SAVE
                         "pushl %eax\n\tcall _isaac_lan_certificate_prepare\n\taddl $4, "
                         "%esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE);
}
}
bool install(std::uintptr_t base) {
    if (installed)
        return image == base;
    if (!base)
        return false;
    native_hooks::Group<1> hooks;
    image = base;
    done = reinterpret_cast<void*>(base + bindings.end);
    if (!hooks.add(base + bindings.begin, isaac_lan_certificate_thunk, original) ||
        !hooks.enable()) {
        image = 0;
        original = done = nullptr;
        return false;
    }
    installed = true;
    return true;
}
} // namespace isaac::engine::native_certificate_return
