#pragma once
#include <cstdint>

namespace isaac::engine::native_certificate_return {
struct Bindings {
    std::uint32_t game, begin, end;
    unsigned dimension, timer;
    void (*transition)(std::uintptr_t image, std::uintptr_t game);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_certificate_return
