#pragma once
#include <array>
#include <cstdint>
#include <span>

namespace isaac::engine {
struct RequiredSection {
    std::uint32_t start, size, flags;
};
struct Signature {
    std::uint32_t rva;
    const char* name;
    std::array<unsigned char, 16> bytes;
    std::uint16_t mask;
};
struct Capabilities {
    bool nativeEmotes;
};
struct MenuFont {
    const char* path;
    float scale;
};
struct PresentationResources {
    bool nativeLobby;
    MenuFont small, normal, heading;
};
// The selected build supplies immutable metadata. Native objects and ownership
// remain private to its backend; consumers cannot select arbitrary addresses.
struct Profile {
    const char* id;
    const char* version;
    const char* name;
    const char* documentsDirectory;
    const char* luaModule;
    std::uint32_t versionRva, minimumImageSize;
    std::span<const RequiredSection> sections;
    std::span<const Signature> signatures;
    Capabilities capabilities;
    PresentationResources presentation;
};
const Profile& profile();
} // namespace isaac::engine
