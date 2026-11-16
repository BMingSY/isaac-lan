#include "test_support.h"
#include "engine/visuals.h"
#include "engine/versions/j460/layout.h"
#include "net/protocol.h"
#include <array>
#include <cstdio>
#include <cstring>

namespace isaac::runtime {
bool replica() {
    return false;
}
void abort(const std::string& reason) {
    throw std::runtime_error(reason);
}
} // namespace isaac::runtime
namespace {
using Address = std::uintptr_t;
namespace layout = isaac::engine::j460::layout;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
} // namespace
int main() {
    static_assert(sizeof(Address) == 4);
    alignas(Address) std::array<std::byte, layout::player::extraAnimationActive + 1> player{};
    alignas(Address) std::array<std::byte, 24> animation{};
    const auto p = reinterpret_cast<Address>(player.data());
    const auto data = reinterpret_cast<Address>(animation.data());
    const auto state = p + layout::entity::sprite + layout::sprite::animation;
    at<unsigned>(p, layout::entity::type) = 1;
    at<Address>(state, layout::animationState::data) = data;
    auto name = [&](const std::string& value) {
        animation.fill({});
        at<unsigned>(data, 0x10) = value.size();
        at<unsigned>(data, 0x14) = 15;
        std::memcpy(animation.data(), value.c_str(), value.size() + 1);
    };
    name("LightTravel");
    require(isaac::visuals::actorDepartureAnimation(p).empty(),
            "Inactive old action leaked into a new departure");
    at<bool>(p, layout::player::extraAnimationActive) = true;
    const auto snapshot = player;
    const auto light = isaac::visuals::actorDepartureAnimation(p);
    require(light == "LightTravel" && snapshot == player,
            "Departure capture changed native state or lost the light animation");
    name("Trapdoor");
    require(isaac::visuals::actorDepartureAnimation(p) == "Trapdoor" && light == "LightTravel",
            "Departure name borrowed storage from a later animation");
    const std::string heapName(isaac::lan::Stage::maxDepartureAnimationLength, 'a');
    at<Address>(data, 0) = reinterpret_cast<Address>(heapName.c_str());
    at<unsigned>(data, 0x10) = at<unsigned>(data, 0x14) = heapName.size();
    require(isaac::visuals::actorDepartureAnimation(p) == heapName,
            "Heap-owned animation name used the inline buffer");
    at<unsigned>(data, 0x10) = heapName.size() + 1;
    rejects([&] { isaac::visuals::actorDepartureAnimation(p); },
            "Malformed native string was read beyond capacity");
    ++at<unsigned>(data, 0x14);
    rejects([&] { isaac::visuals::actorDepartureAnimation(p); },
            "Oversized native animation escaped its wire limit");
    at<Address>(state, layout::animationState::data) = 0;
    require(isaac::visuals::actorDepartureAnimation(p).empty(),
            "Missing native animation data acquired a guessed action");
    at<unsigned>(p, layout::entity::type) = 2;
    rejects([&] { isaac::visuals::actorDepartureAnimation(p); }, "Non-player animation accepted");
    rejects([] { isaac::visuals::actorDepartureAnimation(0); }, "Null departure player accepted");
    std::puts("PASS native departure capture, inactive actions, ownership and bounds");
}
