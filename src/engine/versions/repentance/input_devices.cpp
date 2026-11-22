#include "engine/versions/common/input_devices.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{repentance::globals::inputManager,
                        repentance::entry::inputEnumerateDevices,
                        repentance::entry::inputPollDevices,
                        repentance::entry::inputUpdate,
                        repentance::layout::inputManager::begin,
                        repentance::layout::inputManager::end,
                        repentance::layout::inputManager::stride,
                        repentance::layout::inputDevice::id,
                        repentance::layout::inputDevice::firstGamepadId};
} // namespace isaac::engine::native_devices
