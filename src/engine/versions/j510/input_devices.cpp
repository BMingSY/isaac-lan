#include "engine/versions/common/input_devices.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{j510::globals::inputManager,
                        j510::entry::inputEnumerateDevices,
                        j510::entry::inputPollDevices,
                        0,
                        j510::layout::inputManager::begin,
                        j510::layout::inputManager::end,
                        j510::layout::inputManager::stride,
                        j510::layout::inputDevice::id,
                        j510::layout::inputDevice::firstGamepadId};
} // namespace isaac::engine::native_devices
