#include "core/occurrence_mapping.h"
#include "test_support.h"
#include <algorithm>
#include <array>
#include <random>
#include <string>

void mapping() {
    using namespace std::literals;
    const std::array local = {"red"sv, "blue"sv, "red"sv, "local"sv};
    const std::array remote = {"red"sv, "red"sv, "blue"sv, "red"sv, "missing"sv};
    require(isaac::core::mapOccurrences(local, remote) == std::vector<int>({0, 2, 1, -1, -1}),
            "Duplicate occurrence order or missing fallback changed");
    require(isaac::core::mapOccurrences({}, remote) == std::vector<int>(remote.size(), -1),
            "Empty local names did not use fallback");
    require(isaac::core::mapOccurrences(local, {}).empty(), "Empty remote mapping is not empty");
    std::mt19937 random(73);
    std::vector<std::string> names(4096);
    for (unsigned i = 0; i < names.size(); ++i)
        names[i] = "costume/" + std::to_string(i);
    std::vector<std::string_view> here(names.begin(), names.end()), there = here;
    std::shuffle(there.begin(), there.end(), random);
    const auto result = isaac::core::mapOccurrences(here, there);
    for (unsigned i = 0; i < there.size(); ++i)
        require(result[i] >= 0 && here[result[i]] == there[i], "Large reordered mapping differs");
}
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"mapping", mapping}});
}
