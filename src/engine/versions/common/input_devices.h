#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace isaac::engine::native_devices {
// Native objects and their vector remain owned by the game. The component
// borrows entries only while excluding scan/poll/update transactions.
struct Bindings {
    std::uint32_t manager, enumerate, poll, update;
    unsigned begin, end, stride, deviceId;
    int firstGamepadId;
};
extern const Bindings bindings;
bool install(std::uintptr_t image, void (*log)(const std::string&));
void assignLanIds(std::uintptr_t image);
void restoreIds(std::uintptr_t image);
std::vector<int> ids(std::uintptr_t image);
} // namespace isaac::engine::native_devices
