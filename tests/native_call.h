#pragma once
#include <cstdint>
#include <initializer_list>

namespace native_fixture {
// Serialized x86 fixtures only. Stack words are in argument order; the
// target receives ECX and must pop its own stack arguments (thiscall).
struct CallResult {
    std::uint32_t eax;
    bool balanced, preserved;
};
CallResult call(void* target, void* receiver, std::initializer_list<std::uint32_t> arguments);
} // namespace native_fixture
