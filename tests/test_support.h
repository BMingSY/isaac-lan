#pragma once
#include <cstdio>
#include <initializer_list>
#include <stdexcept>
#include <string_view>

inline void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}

template <class F> void rejects(F operation, const char* message) {
    try {
        operation();
    } catch (const std::runtime_error&) {
        return;
    }
    throw std::runtime_error(message);
}

struct TestCase {
    const char* name;
    void (*run)();
};

inline int runTests(int argc, char** argv, std::initializer_list<TestCase> cases) {
    if (argc > 2) {
        std::fprintf(stderr, "Usage: %s [case]\n", argv[0]);
        return 1;
    }
    unsigned passed = 0;
    for (const auto& test : cases) {
        if (argc == 2 && std::string_view(argv[1]) != test.name)
            continue;
        try {
            test.run();
            std::printf("PASS %s\n", test.name);
            ++passed;
        } catch (const std::exception& error) {
            std::fprintf(stderr, "FAIL %s: %s\n", test.name, error.what());
            return 1;
        }
    }
    if (!passed) {
        std::fprintf(stderr, "Unknown test case: %s\n", argv[1]);
        return 1;
    }
    std::printf("ALL %u TESTS PASSED\n", passed);
    return 0;
}
