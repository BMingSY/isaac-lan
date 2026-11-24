#include "engine/versions/common/input_devices.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <mutex>

namespace isaac::engine::native_devices {
namespace {
template <class T> T& at(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
struct DeviceId {
    std::uintptr_t device;
    int original, assigned;
};
std::vector<DeviceId> savedIds;
// Scan and poll retain device pointers across native callbacks and releases.
// The whole transaction must be exclusive, including the post-LAN drain.
// A native connect callback may reenter polling on the same thread.
std::recursive_mutex mutex;
using Poll = void(__cdecl*)();
using Update = void(__attribute__((thiscall)) *)(void*);
Poll originalEnumerate, originalPoll;
Update originalUpdate;
std::uintptr_t installedImage;
void (*logger)(const std::string&);
void __cdecl enumerate() {
    const std::lock_guard lock(mutex);
    originalEnumerate();
}
void __cdecl poll() {
    const std::lock_guard lock(mutex);
    originalPoll();
}
void __attribute__((fastcall)) update(void* manager, void*) {
    const std::lock_guard lock(mutex);
    originalUpdate(manager);
}
template <class F> void visit(std::uintptr_t image, F&& fn) {
    if (!image)
        return;
    const auto manager = image + bindings.manager;
    const auto begin = at<std::uintptr_t>(manager, bindings.begin);
    const auto end = at<std::uintptr_t>(manager, bindings.end);
    if (!begin || end < begin || (end - begin) % bindings.stride)
        return;
    for (auto p = begin; p != end; p += bindings.stride)
        if (const auto device = at<std::uintptr_t>(p, 0))
            fn(device, at<int>(device, bindings.deviceId));
}
} // namespace
bool install(std::uintptr_t image, void (*log)(const std::string&)) {
    const std::lock_guard lock(mutex);
    if (installedImage)
        return image == installedImage;
    if (!image)
        return false;
    std::array<void*, 3> targets{};
    unsigned created = 0;
    auto hook = [&](std::uint32_t rva, auto replacement, auto& original) {
        auto* target = reinterpret_cast<void*>(image + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(replacement),
                          reinterpret_cast<void**>(&original)) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success = hook(bindings.enumerate, enumerate, originalEnumerate) &&
                   hook(bindings.poll, poll, originalPoll) &&
                   (!bindings.update || hook(bindings.update, update, originalUpdate));
    if (success)
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
    if (success)
        success = MH_ApplyQueued() == MH_OK;
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        originalEnumerate = originalPoll = nullptr;
        originalUpdate = nullptr;
        return false;
    }
    installedImage = image;
    logger = log;
    return true;
}
void rescan(std::uintptr_t image) {
    const std::lock_guard lock(mutex);
    if (installedImage && image == installedImage)
        originalEnumerate();
}
void assignLanIds(std::uintptr_t image) {
    const std::lock_guard lock(mutex);
    if (!installedImage || image != installedImage || !savedIds.empty())
        return;
    std::vector<DeviceId> devices;
    visit(image, [&](auto device, int id) {
        if (id >= bindings.firstGamepadId)
            devices.push_back({device, id, 0});
    });
    constexpr unsigned controllerCount = 4;
    if (devices.size() < controllerCount)
        return;
    std::sort(devices.begin(), devices.end(),
              [](const auto& a, const auto& b) { return a.original < b.original; });
    // Reserve before writes so allocation failure cannot lose the restore set.
    savedIds.reserve(controllerCount);
    for (unsigned i = 0; i < controllerCount; ++i) {
        auto device = devices[i];
        device.assigned = static_cast<int>(i + 1);
        savedIds.push_back(device);
        at<int>(device.device, bindings.deviceId) = device.assigned;
    }
    if (logger)
        for (const auto& device : savedIds)
            if (device.original != device.assigned)
                logger("input_lan_id=" + std::to_string(device.original) + "->" +
                       std::to_string(device.assigned));
}
void restoreIds(std::uintptr_t image) {
    const std::lock_guard lock(mutex);
    if (!installedImage || image != installedImage)
        return;
    visit(image, [](auto device, int& id) {
        for (const auto& saved : savedIds)
            if (saved.device == device && id == saved.assigned)
                id = saved.original;
    });
    savedIds.clear();
}
std::vector<int> ids(std::uintptr_t image) {
    const std::lock_guard lock(mutex);
    std::vector<int> result;
    visit(image, [&](auto, int id) { result.push_back(id); });
    return result;
}
} // namespace isaac::engine::native_devices
