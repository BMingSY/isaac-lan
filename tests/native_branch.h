#pragma once
#include <array>
#include <cstdint>

namespace native_fixture {
// Serialized private-image branch tests. Word order follows PUSHAD; ESP is
// supplied by the fixture. The target must return without stack arguments.
using Registers = std::array<std::uint32_t, 8>;
struct BranchResult {
    Registers registers;
    unsigned flags;
    bool balanced, floatingPreserved;
};
BranchResult branch(void* target, const Registers& registers);
} // namespace native_fixture
