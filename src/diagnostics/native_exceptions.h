#pragma once
#include <cstdint>
namespace isaac::diagnostics {
void observeExceptions(std::uintptr_t image, bool (*scopeActive)());
}
