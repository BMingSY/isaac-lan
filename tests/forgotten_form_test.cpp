#include "test_support.h"
#include "engine/versions/j460/forgotten_form.h"
#include <array>
#include <utility>

namespace {
namespace native = isaac::engine::j460;
namespace ids = isaac::compat::ids;
using Address = std::uintptr_t;
std::array<std::uint8_t, 0x2100> player{}, hidden{};
unsigned calls = 0;
template <class T> T& field(auto& body, unsigned offset) {
    return *reinterpret_cast<T*>(body.data() + offset);
}
bool __attribute__((thiscall)) swap(void* object, bool force, bool quiet) {
    require(object == player.data() && force && quiet, "Incorrect native swap ABI/flags");
    ++calls;
    std::swap(field<int>(player, native::layout::player::type),
              field<int>(hidden, native::layout::player::type));
    return true;
}
bool restore(int desired) {
    return native::forgotten_form::restore(reinterpret_cast<Address>(player.data()), desired, swap);
}
void rejects(int desired) {
    const auto before = calls;
    require(!restore(desired) && calls == before, "Invalid form reached native swap");
}
} // namespace
int main() {
    static_assert(sizeof(Address) == 4);
    field<unsigned>(hidden, native::layout::entity::type) = 1;
    field<int>(player, native::layout::player::type) = ids::player::forgotten;
    field<int>(hidden, native::layout::player::type) = ids::player::soul;
    field<Address>(player, native::layout::player::subplayer) =
        reinterpret_cast<Address>(hidden.data());
    require(restore(ids::player::forgotten) && calls == 0, "Repeated form was not idempotent");
    require(restore(ids::player::soul) && calls == 1, "Forgotten did not switch to Soul");
    require(restore(ids::player::soul) && calls == 1, "Repeated Soul toggled back");
    require(restore(ids::player::forgotten) && calls == 2, "Soul did not switch to Forgotten");
    rejects(ids::player::isaac);
    field<bool>(player, native::layout::player::coopGhost) = true;
    rejects(ids::player::soul);
    field<bool>(player, native::layout::player::coopGhost) = false;
    field<int>(hidden, native::layout::player::type) = ids::player::forgotten;
    rejects(ids::player::soul);
    field<int>(hidden, native::layout::player::type) = ids::player::soul;
    field<unsigned>(hidden, native::layout::entity::type) = 1000;
    rejects(ids::player::soul);
    field<Address>(player, native::layout::player::subplayer) = 0;
    rejects(ids::player::soul);
    field<Address>(player, native::layout::player::subplayer) =
        reinterpret_cast<Address>(player.data());
    rejects(ids::player::soul);
}
