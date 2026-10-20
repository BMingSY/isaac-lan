#include "net/world_dependencies.h"
#include "test_support.h"

using namespace isaac::lan;
static void check(bool value) {
    require(value, "World dependency consistency failure");
}
int main() {
    WorldDependencies dependencies;
    const auto view = [](unsigned tick, unsigned revision) {
        WorldState value;
        value.tick = tick;
        value.revision = revision;
        value.bytes = {static_cast<std::uint8_t>(tick)};
        return value;
    };
    // Realtime overtakes reliable data; obsolete waiting views coalesce.
    check(!dependencies.receive(view(1, 1)));
    check(!dependencies.receive(view(3, 2)));
    check(!dependencies.receive(1, {10}));
    const auto first = dependencies.receive(2, {20});
    check(first && first->tick == 3 && first->stable == std::vector<std::uint8_t>{20});
    check(!dependencies.receive(view(2, 1)));
    // A delayed packet may refer to a retained older revision, never the newest.
    const auto older = dependencies.receive(view(4, 1));
    check(older && older->stable == std::vector<std::uint8_t>{10});
    check(!dependencies.receive(view(5, 3)));
    const auto independent = dependencies.receive(view(6, 0));
    check(independent && independent->stable.empty());
    check(!dependencies.receive(3, {30}));
    // Bound cache growth and discard references to evicted revisions.
    for (unsigned revision = 4; revision < 50; ++revision)
        check(!dependencies.receive(revision, std::vector<std::uint8_t>(maxWorldSize / 2, 0)));
    check(dependencies.cachedBytes() <= 4 * maxWorldSize);
    check(!dependencies.receive(view(7, 1)));
    check(!dependencies.receive(view(8, 50)));
    dependencies.reset();
    // Floor/run reset clears waiting views, revision IDs and tick ordering.
    check(!dependencies.receive(1, {99}));
    const auto reset = dependencies.receive(view(0, 1));
    check(reset && reset->tick == 0 && reset->stable == std::vector<std::uint8_t>{99});
    bool rejected = false;
    try {
        dependencies.receive(1, {100});
    } catch (const std::exception&) {
        rejected = true;
    }
    check(rejected);
}
