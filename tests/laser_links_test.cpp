// Exercise the actual x86 Update adapter after native inline parent assignments.
#include "engine/versions/j460/laser_links.cpp"
#include "test_support.h"
#include <array>
#include <map>
#include <set>

namespace {
using namespace isaac::engine::j460;
using namespace isaac::engine::j460::laser_links;
struct Laser {
    std::array<std::uint32_t, (layout::laser::parent + sizeof(void*)) / 4> words{};
};
std::map<void*, std::set<void**>> observers;
unsigned setterCalls = 0, updates = 0;
void* updated = nullptr;

void*& parent(void* value) {
    return *reinterpret_cast<void**>(static_cast<char*>(value) + layout::laser::parent);
}

// Models the native caller's inline unregister/write/register path. This bypasses
// Laser.SetParent, as the four-direction laser creation path does in J460.
void inlineAssign(void* laser, void* value) {
    auto& prior = parent(laser);
    if (prior == value)
        return;
    if (prior)
        require(observers[prior].erase(&prior) == 1, "Old parent lost its registered observer");
    prior = value;
    if (value)
        require(observers[value].insert(&prior).second, "Parent observer was registered twice");
}

void __attribute__((thiscall)) originalSetter(void* laser, void* value) {
    ++setterCalls;
    require(value == nullptr, "Update adapter rewrote a valid parent");
    inlineAssign(laser, value);
}

void __attribute__((thiscall)) originalUpdateStub(void* laser) {
    ++updates;
    updated = laser;
    // Independent set-based traversal fails immediately if the hook leaves a cycle.
    std::set<void*> seen{laser};
    for (auto* value = parent(laser); value; value = parent(value))
        require(seen.insert(value).second, "Native Update received a cyclic parent chain");
}

void reset() {
    observers.clear();
    setterCalls = updates = 0;
    updated = nullptr;
    nativeSetParent = originalSetter;
    originalUpdate = originalUpdateStub;
    resetReplicaIsolation();
}

void destroy(void* value) {
    inlineAssign(value, nullptr);
    for (auto* slot : observers[value])
        *slot = nullptr;
    observers[value].clear();
}

void valid() {
    reset();
    std::array<Laser, 4> nodes{};
    auto* child = &nodes[0];
    updateLaser(child, nullptr);
    require(updates == 1 && updated == child && !setterCalls, "Empty chain changed Update ABI");
    for (unsigned i = 0; i + 1 < nodes.size(); ++i)
        inlineAssign(&nodes[i], &nodes[i + 1]);
    const auto before = observers;
    updateLaser(child, nullptr);
    updateLaser(child, nullptr);
    require(updates == 3 && updated == child && !setterCalls && observers == before,
            "Repeated valid Update changed native references");
    for (unsigned i = 0; i + 1 < nodes.size(); ++i)
        require(parent(&nodes[i]) == &nodes[i + 1], "Valid chain membership changed");
}

void cycles() {
    reset();
    std::array<Laser, 3> nodes{};
    auto *child = &nodes[0], *first = &nodes[1], *second = &nodes[2];
    inlineAssign(child, child);
    updateLaser(child, nullptr);
    require(!parent(child) && observers[child].empty() && setterCalls == 1 && updates == 1,
            "Inline self-parent did not use native observer cleanup before Update");
    inlineAssign(child, first);
    inlineAssign(first, second);
    inlineAssign(second, child);
    updateLaser(child, nullptr);
    require(!parent(child) && observers[first].empty() && parent(first) == second &&
                parent(second) == child && setterCalls == 2 && updates == 2,
            "Indirect cycle repair changed another entity's reference");
    updateLaser(child, nullptr);
    require(setterCalls == 2 && updates == 3, "Repaired Update repeated native cleanup");
    inlineAssign(second, first);
    inlineAssign(child, first);
    updateLaser(child, nullptr);
    require(!parent(child) && parent(first) == second && parent(second) == first &&
                observers[first].size() == 1 && setterCalls == 3 && updates == 4,
            "Existing parent cycle was not detached from the updated laser");
}

void lifecycle() {
    reset();
    std::array<Laser, 3> nodes{};
    auto *child = &nodes[0], *first = &nodes[1], *second = &nodes[2];
    inlineAssign(child, first);
    inlineAssign(child, first);
    inlineAssign(child, second);
    require(observers[first].empty() && observers[second].size() == 1,
            "Native replacement retained an old observer");
    updateLaser(child, nullptr);
    destroy(second);
    require(!parent(child), "Native destruction did not invalidate the borrowed reference");
    updateLaser(child, nullptr);
    inlineAssign(child, second);
    updateLaser(child, nullptr);
    require(!setterCalls && updates == 3 && parent(child) == second,
            "Reused object address retained stale adapter state");
    for (auto& value : nodes)
        destroy(&value);
    for (const auto& [value, slots] : observers) {
        (void)value;
        require(slots.empty(), "Room cleanup retained an observer");
    }
    inlineAssign(child, first);
    updateLaser(child, nullptr);
    require(!setterCalls && updates == 4 && parent(child) == first,
            "Fresh room links inherited adapter cleanup state");
}
} // namespace

int main(int argc, char** argv) {
    static_assert(sizeof(void*) == 4);
    return runTests(argc, argv, {{"valid", valid}, {"cycles", cycles}, {"lifecycle", lifecycle}});
}
