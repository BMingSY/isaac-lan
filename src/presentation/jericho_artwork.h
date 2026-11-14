#pragma once
#include <filesystem>
#include <string>

namespace isaac::presentation {
// Extract the embedded atlas and Sprite descriptor into an owned, content-keyed
// cache. No workshop files or game resources are modified.
std::string prepareJerichoArtwork(const std::filesystem::path& configDirectory);
} // namespace isaac::presentation
