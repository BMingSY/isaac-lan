#pragma once
#include "runtime/session_archive.h"
#include <filesystem>
#include <optional>
namespace isaac::runtime {
class SessionStore {
    std::filesystem::path path;

  public:
    explicit SessionStore(std::filesystem::path value) : path(std::move(value)) {}
    std::size_t write(const lan::Archive& archive) const;
    std::size_t writeBytes(const std::vector<std::uint8_t>& bytes) const;
    std::optional<lan::Archive> read() const;
};
} // namespace isaac::runtime
