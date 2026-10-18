#include "engine/pickup_preview.h"
#include "compat/game_ids.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>
#include <vector>

namespace isaac::presentation::pickup_preview {
namespace {
namespace j460 = isaac::engine::j460;
using Address = std::uintptr_t;
using Update = void(__attribute__((thiscall)) *)(void*);
Address image;
Update originalUpdate;
template <class T> T& at(Address address, unsigned offset) {
    return *reinterpret_cast<T*>(address + offset);
}
void __attribute__((fastcall)) update(void* pickup, void*) {
    // Prediction owns a LootList and several ANM2 objects, not just an entity
    // pose. During LAN play it belongs to each process's viewing player.
    if (!rooms::virtualized())
        originalUpdate(pickup);
}
} // namespace
bool install(Address base) {
    image = base;
    const auto target = reinterpret_cast<void*>(image + j460::entry::pickupUpdateGhosts);
    return MH_CreateHook(target, reinterpret_cast<void*>(update),
                         reinterpret_cast<void**>(&originalUpdate)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
void prepare() {
    if (!rooms::viewReady())
        return;
    rooms::withView(
        [] {
            const auto game = at<Address>(image, j460::globals::game);
            const auto room = at<Address>(game, j460::layout::game::room);
            // Pickups live in the render array, not the first update array.
            // Freeze it: creating/removing a preview can grow the native
            // arrays. The engine owns all preview objects.
            std::vector<Address> pickups;
            const auto list =
                room + j460::layout::room::entities + j460::layout::entityList::renderArray;
            const auto data = at<Address>(list, j460::layout::entityList::data);
            const auto count = at<unsigned>(list, j460::layout::entityList::count);
            for (unsigned i = 0; i < count; ++i) {
                const auto entity = at<Address>(data, i * sizeof(Address));
                if (at<unsigned>(entity, j460::layout::entity::type) ==
                        compat::ids::entity::pickup &&
                    at<bool>(entity, j460::layout::entity::active) &&
                    !at<bool>(entity, j460::layout::entity::removed))
                    pickups.push_back(entity);
            }
            for (auto pickup : pickups)
                originalUpdate(reinterpret_cast<void*>(pickup));
        },
        true);
}
} // namespace isaac::presentation::pickup_preview
