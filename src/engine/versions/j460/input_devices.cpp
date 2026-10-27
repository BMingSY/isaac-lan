#include "engine/versions/common/input_devices.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_devices {
const Bindings bindings{j460::globals::inputManager,        j460::entry::inputEnumerateDevices,
                        j460::entry::inputPollDevices,      0,
                        j460::layout::inputManager::begin,  j460::layout::inputManager::end,
                        j460::layout::inputManager::stride, j460::layout::inputDevice::id};
} // namespace isaac::engine::native_devices
