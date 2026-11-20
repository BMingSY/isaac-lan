#include "engine/pickup_preview.h"
#include "compat/game_ids.h"
#include "engine/rooms.h"
#include "engine/versions/common/pickup_preview_bindings.h"
#include <MinHook.h>
#include <vector>

namespace isaac::presentation::pickup_preview {
namespace {
using engine::native_pickup_preview::bindings;
bool installed;
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
    if (!base || installed)
        return false;
    image = base;
    const auto target = reinterpret_cast<void*>(image + bindings.update);
    if (MH_CreateHook(target, reinterpret_cast<void*>(update),
                      reinterpret_cast<void**>(&originalUpdate)) == MH_OK) {
        if (MH_EnableHook(target) == MH_OK) {
            installed = true;
            return true;
        }
        MH_RemoveHook(target);
    }
    image = 0;
    originalUpdate = nullptr;
    return false;
}
void prepare() {
    if (!image || !originalUpdate || !rooms::viewReady())
        return;
    rooms::withView(
        [] {
            const auto game = at<Address>(image, bindings.game);
            if (!game)
                return;
            const auto room = at<Address>(game, bindings.room);
            if (!room)
                return;
            // Pickups live in the render array, not the first update array.
            // Freeze it: creating/removing a preview can grow the native
            // arrays. The engine owns all preview objects.
            std::vector<Address> pickups;
            const auto list = room + bindings.entities + bindings.renderArray;
            const auto data = at<Address>(list, bindings.data);
            const auto count = at<unsigned>(list, bindings.count);
            if (!data)
                return;
            for (unsigned i = 0; i < count; ++i) {
                const auto entity = at<Address>(data, i * sizeof(Address));
                if (entity && at<unsigned>(entity, bindings.type) == compat::ids::entity::pickup)
                    pickups.push_back(entity);
            }
            for (auto pickup : pickups)
                originalUpdate(reinterpret_cast<void*>(pickup));
        },
        true);
}
} // namespace isaac::presentation::pickup_preview
