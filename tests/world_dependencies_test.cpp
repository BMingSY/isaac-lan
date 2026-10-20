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
    // A changed inventory travels with a complete latest view while its
    // reliable copy is delayed. Older reliable data must not replace it.
    auto inlineView = view(7, 5);
    inlineView.stable = {50};
    const auto inlineResult = dependencies.receive(std::move(inlineView));
    check(inlineResult && inlineResult->tick == 7 && inlineResult->stable[0] == 50);
    check(!dependencies.receive(4, {40}));
    check(!dependencies.receive(5, {50}));
    check(!dependencies.receive(view(6, 4)));
    const auto retained = dependencies.receive(view(8, 5));
    check(retained && retained->stable[0] == 50);
    // Bound cache growth and discard references to evicted revisions.
    for (unsigned revision = 6; revision < 50; ++revision)
        check(!dependencies.receive(revision, std::vector<std::uint8_t>(maxWorldSize / 2, 0)));
    check(dependencies.cachedBytes() <= 4 * maxWorldSize);
    check(!dependencies.receive(view(9, 1)));
    check(!dependencies.receive(view(10, 50)));
    auto stale = view(9, 51);
    stale.stable = {51};
    check(!dependencies.receive(std::move(stale)));
    const auto waiting = dependencies.receive(50, {50});
    check(waiting && waiting->tick == 10 && waiting->stable[0] == 50);
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
