#include "net/world_emission.h"
#include "test_support.h"
using namespace isaac::lan;
using namespace std::chrono_literals;

int main() {
    return runTests(
        0, nullptr,
        {{"freshness-and-progress", [] {
              WorldEmission emission;
              const auto now = WorldEmission::Clock::time_point{};
              emission.begin(128 * 1024, now);
              emission.sent(8 * 1024);
              require(!emission.replace(true, 32768, now + 200ms), "Fresh view was interrupted");
              require(!emission.replace(false, 32768, now + 300ms), "Only available view was lost");
              require(emission.replace(true, 32768, now + 300ms),
                      "Old large view blocked fresh state");
              emission.begin(128 * 1024, now + 300ms);
              for (unsigned i = 1; i <= 128; ++i) {
                  require(!emission.replace(true, 32768, now + 300ms + i * 32ms),
                          "Continuous replacement starved complete views");
                  emission.sent(1024);
              }
              emission.begin(128 * 1024, now + 5s);
              require(emission.replace(true, 32768, now + 6s),
                      "Finished replacement retained protection");
              emission = {};
              emission.begin(128 * 1024, now);
              emission.sent(100 * 1024);
              require(!emission.replace(true, 32768, now + 1s), "Nearly completed view was wasted");
              emission = {};
              emission.begin(2048, now);
              require(!emission.replace(true, 32768, now + 1s),
                      "Cheap remaining work was discarded");
          }}});
}
