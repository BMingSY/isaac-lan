#include "engine/versions/common/death_certificate_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "compat/items/death_certificate.h"

namespace isaac::engine::native_certificate_return {
namespace {
void transition(std::uintptr_t image, std::uintptr_t game) {
    using Transition = void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
    const auto room =
        *reinterpret_cast<const int*>(game + j835::layout::game::deathCertificateRoom);
    const auto dimension =
        *reinterpret_cast<const signed char*>(game + j835::layout::game::deathCertificateDimension);
    // Original Game::Update normalizes the special room before calling its
    // lower transition. Use the scoped upper entry while retaining that rule.
    constexpr int specialRoom = -2;
    *reinterpret_cast<int*>(game + j835::layout::game::leaveDoor) = -1;
    reinterpret_cast<Transition>(image + j835::entry::engineRoomsTransition)(
        reinterpret_cast<void*>(game), room, -1, compat::items::deathCertificateAnimation, nullptr,
        room == specialRoom ? 0 : dimension);
}
} // namespace
constinit const Bindings bindings{j835::globals::game,
                                  j835::entry::deathCertificateReturn,
                                  j835::entry::deathCertificateReturnEnd,
                                  j835::layout::game::dimension,
                                  j835::layout::game::deathCertificateReturnTimer,
                                  transition};
} // namespace isaac::engine::native_certificate_return
