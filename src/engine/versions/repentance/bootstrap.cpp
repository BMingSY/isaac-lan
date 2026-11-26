#include "engine/bootstrap.h"
#include "engine/imports.h"
#include <mutex>
#include "engine/versions/common/bootstrap_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/profile.h"
namespace isaac::engine::native_bootstrap {
namespace backend = repentance;
namespace layout = backend::layout;
const Bindings bindings{
    {backend::entry::roomUpdate, backend::entry::gameUpdateHalf, backend::entry::gameRender},
    backend::globals::game,
    backend::preferredImageBase,
    backend::diagnosticImageSpan,
    {{layout::game::room, layout::game::roomIndex, layout::game::players, layout::game::frame},
     {layout::room::entities, layout::room::enteredFrame},
     {layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
     {layout::entity::interpolated, layout::entity::positionX, layout::entity::positionY,
      layout::entity::previousX, layout::entity::previousY},
     {layout::vector::end}},
    nullptr};
} // namespace isaac::engine::native_bootstrap

namespace isaac::engine::bootstrap {
namespace {
using OpenDevice = void*(__cdecl*)(const char*);
OpenDevice originalOpenDevice;
void (*platformReady)();
std::once_flag platformStartup;
void* __cdecl openDevice(const char* name) {
    void* device = originalOpenDevice(name);
    // Opening the first device has returned from DirectSound's loader and ZHL's
    // ModInit callbacks, even when OpenAL could not create an audio device.
    std::call_once(platformStartup, platformReady);
    return device;
}
} // namespace
HookTiming scheduleGameHooks(std::uintptr_t image, const std::filesystem::path& directory,
                             void (*ready)()) {
    if (!std::filesystem::is_regular_file(directory / L"dsound.dll") ||
        !std::filesystem::is_regular_file(directory / L"libzhl.dll"))
        return HookTiming::immediate;
    platformReady = ready;
    return imports::replace(image, "alcOpenDevice", reinterpret_cast<void*>(openDevice),
                            reinterpret_cast<void**>(&originalOpenDevice)) ==
                   imports::Result::replaced
               ? HookTiming::deferred
               : HookTiming::missingImport;
}
} // namespace isaac::engine::bootstrap
