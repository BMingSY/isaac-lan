#pragma once
#include <cstdint>

namespace isaac::presentation::pickup_preview {
bool install(std::uintptr_t image);
// Rebuild native, non-consuming pickup previews for the local view only.
void prepare();
} // namespace isaac::presentation::pickup_preview
