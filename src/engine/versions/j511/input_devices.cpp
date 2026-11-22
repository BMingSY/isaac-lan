#include "engine/versions/common/input_devices.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{j511::globals::inputManager,
                        j511::entry::inputEnumerateDevices,
                        j511::entry::inputPollDevices,
                        0,
                        j511::layout::inputManager::begin,
                        j511::layout::inputManager::end,
                        j511::layout::inputManager::stride,
                        j511::layout::inputDevice::id,
                        j511::layout::inputDevice::firstGamepadId};
} // namespace isaac::engine::native_devices
