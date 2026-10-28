// Private x86 objects and real calling conventions, without a game process.
#include "test_support.h"
#include "engine/versions/j460/entity_size.h"
#include <array>

namespace {
namespace native = isaac::engine::j460;
namespace size = native::entity_size;
using Address = std::uintptr_t;
std::array<std::uint8_t, 0x400> entity{};
std::array<size::Multiplier, 24> points{};
unsigned defaultCalls = 0, explicitCalls = 0;
size::Multiplier receivedMultiplier{};
int receivedPoints = -1;
template <class T> T& field(unsigned offset) {
    return *reinterpret_cast<T*>(entity.data() + offset);
}
void __cdecl defaults(void* object, float radius) {
    require(object == entity.data(), "Wrong native object");
    require(field<Address>(native::layout::entity::configuration) != 0,
            "Missing XML reached the default setter");
    ++defaultCalls;
    field<float>(native::layout::entity::size) = radius;
}
void __attribute__((thiscall)) explicitSize(void* object, float radius, size::Multiplier multiplier,
                                            int count) {
    require(object == entity.data(), "Wrong thiscall object");
    ++explicitCalls;
    receivedMultiplier = multiplier;
    receivedPoints = count;
    field<float>(native::layout::entity::size) = radius;
}
void restore(float radius) {
    size::restore(reinterpret_cast<Address>(entity.data()), radius, defaults, explicitSize);
}
void rejects(float radius) {
    const auto before = entity;
    const auto calls = defaultCalls + explicitCalls;
    bool failed = false;
    try {
        restore(radius);
    } catch (const std::runtime_error&) {
        failed = true;
    }
    require(failed && before == entity && calls == defaultCalls + explicitCalls,
            "Invalid shape reached a native setter or changed the entity");
}
} // namespace

int main() {
    static_assert(sizeof(Address) == 4 && sizeof(size::Multiplier) == 8);
    field<size::Multiplier>(native::layout::entity::sizeMultiplier) = {1.5f, 0.75f};
    for (float radius : {1.0f, 1.0f, 5.5f, 5.5f, 1.0f}) {
        restore(radius);
        require(field<float>(native::layout::entity::size) == radius, "Size did not restore");
        require(receivedMultiplier.x == 1.5f && receivedMultiplier.y == 0.75f &&
                    receivedPoints == 0,
                "Configless shape was replaced with invented defaults");
    }
    require(defaultCalls == 0 && explicitCalls == 5, "Wrong configless setter");
    const auto vector = native::layout::entity::gridCollisionPoints;
    const auto begin = reinterpret_cast<Address>(points.data());
    field<Address>(vector + native::layout::vector::begin) = begin;
    field<Address>(vector + native::layout::vector::end) = begin + 8 * sizeof(points[0]);
    field<Address>(vector + native::layout::vector::capacity) = begin + sizeof(points);
    restore(7);
    require(receivedPoints == 8, "Collision count must use size, not vector capacity");
    rejects(std::numeric_limits<float>::infinity());
    field<Address>(vector + native::layout::vector::end) = begin - 1;
    rejects(8);
    field<Address>(vector + native::layout::vector::end) = begin + 1;
    rejects(8);
    field<Address>(vector + native::layout::vector::end) = begin + sizeof(points) + 8;
    rejects(8);
    field<Address>(vector + native::layout::vector::end) = begin;
    field<size::Multiplier>(native::layout::entity::sizeMultiplier) = {-1, -1};
    rejects(8);
    field<size::Multiplier>(native::layout::entity::sizeMultiplier) = {1, NAN};
    rejects(8);
    field<size::Multiplier>(native::layout::entity::sizeMultiplier) = {1, 1};
    field<Address>(native::layout::entity::configuration) = 1;
    restore(12);
    restore(12);
    require(defaultCalls == 2 && explicitCalls == 6,
            "Configured entities must retain the public setter's behavior");
    field<Address>(native::layout::entity::configuration) = 0;
    restore(3);
    require(defaultCalls == 2 && explicitCalls == 7, "Configuration state was cached");
}
