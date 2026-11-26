#pragma once

namespace isaac::lua {
enum class Version { v53, v54 };
constexpr const char* versionName(Version version) {
    return version == Version::v54 ? "5.4" : "5.3";
}
} // namespace isaac::lua
