#include "engine/versions/common/input_devices.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{repentance_plus::globals::inputManager,
                        repentance_plus::entry::inputEnumerateDevices,
                        repentance_plus::entry::inputPollDevices,
                        0,
                        repentance_plus::layout::inputManager::begin,
                        repentance_plus::layout::inputManager::end,
                        repentance_plus::layout::inputManager::stride,
                        repentance_plus::layout::inputDevice::id,
                        repentance_plus::layout::inputDevice::firstGamepadId};
} // namespace isaac::engine::native_devices
