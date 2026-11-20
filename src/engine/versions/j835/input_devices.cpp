#include "engine/versions/common/input_devices.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{j835::globals::inputManager,
                        j835::entry::inputEnumerateDevices,
                        j835::entry::inputPollDevices,
                        j835::entry::inputUpdate,
                        j835::layout::inputManager::begin,
                        j835::layout::inputManager::end,
                        j835::layout::inputManager::stride,
                        j835::layout::inputDevice::id,
                        j835::layout::inputDevice::firstGamepadId};
} // namespace isaac::engine::native_devices
