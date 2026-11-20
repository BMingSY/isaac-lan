#include "engine/versions/common/death_certificate_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include "compat/items/death_certificate.h"

namespace isaac::engine::native_certificate_return {
namespace {
void transition(std::uintptr_t image, std::uintptr_t game) {
    using Transition = void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
    const auto room =
        *reinterpret_cast<const int*>(game + j510::layout::game::deathCertificateRoom);
    const auto dimension =
        *reinterpret_cast<const signed char*>(game + j510::layout::game::deathCertificateDimension);
    *reinterpret_cast<int*>(game + j510::layout::game::leaveDoor) = -1;
    reinterpret_cast<Transition>(image + j510::entry::engineRoomsTransition)(
        reinterpret_cast<void*>(game), room, -1, compat::items::deathCertificateAnimation, nullptr,
        dimension);
}
} // namespace
constinit const Bindings bindings{j510::globals::game,
                                  j510::entry::deathCertificateReturn,
                                  j510::entry::deathCertificateReturnEnd,
                                  j510::layout::game::dimension,
                                  j510::layout::game::deathCertificateReturnTimer,
                                  transition};
} // namespace isaac::engine::native_certificate_return
