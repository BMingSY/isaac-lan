#include "engine/versions/common/actor_state.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "compat/game_ids.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <limits>

namespace isaac::engine::native_actor_state {
namespace {
namespace layout = repentance_plus::layout;
using Address = std::uintptr_t;
constexpr unsigned weaponCount = 4, allWeapons = (1u << weaponCount) - 1, unequipped = 0xff;
constexpr float maximumWanted = 6;
constexpr int fadeFlash = -10, gainFlash = 56;

lua::API api;
Address image;
Callbacks context;
template <class T> T& field(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
using Ammo = std::array<std::uint16_t, weaponCount>;
struct Loadout {
    std::uint8_t weapons, equipped;
    Ammo ammo;
};

int crimeView(lua_State* L) {
    try {
        const auto game = field<Address>(image, repentance_plus::globals::game);
        if (!game || !rooms::stateReady() ||
            !field<bool>(game + layout::game::crime, layout::crime::active)) {
            api.pushBoolean(L, false);
            return 1;
        }
        const auto crime = game + layout::game::crime;
        const int arguments = api.getTop(L);
        if (arguments && (arguments != 1 || !runtime::replica()))
            throw std::runtime_error("Only replicas restore the crime mode view");
        std::size_t size = 0;
        const auto bytes = arguments ? api.checkString(L, 1, &size) : nullptr;
        const auto players = context.roster(true);
        for (auto p : players)
            if (!p || field<unsigned>(p, layout::entity::type) != compat::ids::entity::player)
                throw std::runtime_error("Invalid crime mode roster");
        if (!arguments) {
            lan::Writer w(lan::Message::world);
            w.u32(std::bit_cast<std::uint32_t>(field<float>(crime, layout::crime::wanted)));
            w.u32(std::bit_cast<std::uint32_t>(field<int>(crime, layout::crime::starFlash)));
            for (auto p : players) {
                w.u8(field<int>(p, layout::player::controller));
                w.u8(field<unsigned>(p, layout::player::crimeWeapons) & allWeapons);
                w.u8(field<std::uint8_t>(p, layout::player::crimeEquipped));
                for (auto ammo : field<Ammo>(p, layout::player::crimeAmmo))
                    w.u16(ammo);
            }
            api.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto wanted = std::bit_cast<float>(r.u32());
        const auto flash = std::bit_cast<int>(r.u32());
        if (!std::isfinite(wanted) || wanted < 0 || wanted > maximumWanted || flash < fadeFlash ||
            flash > gainFlash)
            throw std::runtime_error("Invalid crime mode wanted level");
        std::vector<Loadout> loadouts;
        for (auto p : players) {
            const auto controller = r.u8();
            Loadout value{r.u8(), r.u8(), {}};
            if (controller != field<int>(p, layout::player::controller) ||
                value.weapons > allWeapons ||
                (value.equipped != unequipped &&
                 (value.equipped >= weaponCount || !(value.weapons & (1u << value.equipped)))))
                throw std::runtime_error("Invalid crime mode loadout");
            for (auto& ammo : value.ammo) {
                ammo = r.u16();
                if (ammo > std::numeric_limits<std::int16_t>::max())
                    throw std::runtime_error("Invalid crime mode ammo");
            }
            loadouts.push_back(value);
        }
        // Commit only after the complete canonical roster matched. The gun effect,
        // police, pickups, and their native owners follow the ordinary room view.
        r.finish();
        field<float>(crime, layout::crime::wanted) = wanted;
        field<int>(crime, layout::crime::starFlash) = flash;
        for (std::size_t i = 0; i < players.size(); ++i) {
            const auto p = players[i];
            const auto& value = loadouts[i];
            field<unsigned>(p, layout::player::crimeWeapons) = value.weapons;
            field<std::uint8_t>(p, layout::player::crimeEquipped) = value.equipped;
            field<Ammo>(p, layout::player::crimeAmmo) = value.ammo;
        }
        api.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        api.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
void bindCrimeView(lua_State* L, const lua::API& lua, Address base, const Callbacks& callbacks) {
    api = lua;
    image = base;
    context = callbacks;
    api.pushClosure(L, crimeView, 0);
    api.setField(L, -2, "crime_view");
}
} // namespace isaac::engine::native_actor_state
