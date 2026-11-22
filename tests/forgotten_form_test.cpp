#include "test_support.h"
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/forgotten_form.h"
namespace native = isaac::engine::repentance;
constexpr unsigned playerType = 0x130c, coopGhost = 0x1f88, subplayer = 0x1cb8;
#else
#include "engine/versions/repentance_plus/forgotten_form.h"
namespace native = isaac::engine::repentance_plus;
constexpr unsigned playerType = 0x13c4, coopGhost = 0x20a9, subplayer = 0x1d98;
#endif
constexpr unsigned entityType = 0x28;
#include <array>
#include <utility>

namespace {
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
    std::swap(field<int>(player, playerType), field<int>(hidden, playerType));
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
    field<unsigned>(hidden, entityType) = 1;
    field<int>(player, playerType) = ids::player::forgotten;
    field<int>(hidden, playerType) = ids::player::soul;
    field<Address>(player, subplayer) = reinterpret_cast<Address>(hidden.data());
    require(restore(ids::player::forgotten) && calls == 0, "Repeated form was not idempotent");
    require(restore(ids::player::soul) && calls == 1, "Forgotten did not switch to Soul");
    require(restore(ids::player::soul) && calls == 1, "Repeated Soul toggled back");
    require(restore(ids::player::forgotten) && calls == 2, "Soul did not switch to Forgotten");
    rejects(ids::player::isaac);
    field<bool>(player, coopGhost) = true;
    rejects(ids::player::soul);
    field<bool>(player, coopGhost) = false;
    field<int>(hidden, playerType) = ids::player::forgotten;
    rejects(ids::player::soul);
    field<int>(hidden, playerType) = ids::player::soul;
    field<unsigned>(hidden, entityType) = 1000;
    rejects(ids::player::soul);
    field<Address>(player, subplayer) = 0;
    rejects(ids::player::soul);
    field<Address>(player, subplayer) = reinterpret_cast<Address>(player.data());
    rejects(ids::player::soul);
}
