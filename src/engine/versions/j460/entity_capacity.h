#pragma once
#include <cstdint>

namespace isaac::engine::j460::entity_capacity {
// Install before the executable entry point, before any Room is constructed.
// Only the update-array constructor's paired capacity and byte count change.
bool install(std::uintptr_t image);
} // namespace isaac::engine::j460::entity_capacity
