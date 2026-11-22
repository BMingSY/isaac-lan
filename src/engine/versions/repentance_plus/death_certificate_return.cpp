#include "engine/versions/common/death_certificate_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "compat/items/death_certificate.h"

namespace isaac::engine::native_certificate_return {
namespace {
void transition(std::uintptr_t image, std::uintptr_t game) {
    using Transition = void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
    const auto room =
        *reinterpret_cast<const int*>(game + repentance_plus::layout::game::deathCertificateRoom);
    const auto dimension = *reinterpret_cast<const signed char*>(
        game + repentance_plus::layout::game::deathCertificateDimension);
    *reinterpret_cast<int*>(game + repentance_plus::layout::game::leaveDoor) = -1;
    reinterpret_cast<Transition>(image + repentance_plus::entry::engineRoomsTransition)(
        reinterpret_cast<void*>(game), room, -1, compat::items::deathCertificateAnimation, nullptr,
        dimension);
}
} // namespace
constinit const Bindings bindings{repentance_plus::globals::game,
                                  repentance_plus::entry::deathCertificateReturn,
                                  repentance_plus::entry::deathCertificateReturnEnd,
                                  repentance_plus::layout::game::dimension,
                                  repentance_plus::layout::game::deathCertificateReturnTimer,
                                  transition};
} // namespace isaac::engine::native_certificate_return
