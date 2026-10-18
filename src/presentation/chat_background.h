#pragma once
#include <filesystem>
#include <string>

namespace isaac::presentation {
struct ChatBackground {
    std::string animation;
    unsigned width = 0, height = 0;
    std::string warning;
};
// Prepare a validated, local image for the game's ordinary Sprite API.
// An empty selection uses the solid-color panel without creating cache files.
// User files are read only; generated files belong to configDirectory/cache/chat.
ChatBackground prepareChatBackground(const std::filesystem::path& configDirectory,
                                     const std::string& selectedImage);
} // namespace isaac::presentation
