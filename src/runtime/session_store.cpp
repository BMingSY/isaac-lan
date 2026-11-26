#include "runtime/session_store.h"
#include <fstream>
#ifdef _WIN32
#include <windows.h>
#endif
namespace isaac::runtime {
namespace {
void commit(const std::filesystem::path& temporary, const std::filesystem::path& path) {
#ifdef _WIN32
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot commit LAN saved session");
#else
    std::filesystem::rename(temporary, path);
#endif
}
std::size_t replaceFile(const std::filesystem::path& path, std::filesystem::path temporary,
                        const std::vector<std::uint8_t>& bytes) {
    temporary += ".tmp";
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    if (!file)
        throw std::runtime_error("Cannot open LAN saved session temporary file");
    file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    file.close();
    if (!file)
        throw std::runtime_error("Cannot write LAN saved session");
    commit(temporary, path);
    return bytes.size();
}
std::optional<lan::Archive> readFile(const std::filesystem::path& path) {
    if (!std::filesystem::exists(path) || std::filesystem::file_size(path) > lan::maxSnapshotSize)
        return {};
    std::ifstream file(path, std::ios::binary);
    const std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
    return lan::Archive::decode(bytes);
}
} // namespace
std::filesystem::path SessionStore::floorPath() const {
    return std::filesystem::path(path).replace_extension(".floor.bin");
}
std::size_t SessionStore::write(const lan::Archive& archive) const {
    return writeBytes(archive.encode());
}
std::size_t SessionStore::writeBytes(const std::vector<std::uint8_t>& bytes) const {
    // Both commits are atomic. Even if the process exits between them, Continue
    // finds the explicit snapshot in the floor file instead of an older floor.
    const auto floor = floorPath();
    const auto size = replaceFile(floor, path, bytes);
    commit(floor, path);
    return size;
}
std::size_t SessionStore::writeFloor(const std::vector<std::uint8_t>& bytes) const {
    const auto floor = floorPath();
    return replaceFile(floor, floor, bytes);
}
std::optional<lan::Archive> SessionStore::read() const {
    try {
        if (auto saved = readFile(floorPath()))
            return saved;
    } catch (const std::runtime_error&) {
        if (!std::filesystem::exists(path))
            throw;
    }
    return readFile(path);
}
void SessionStore::discard() const {
    std::filesystem::remove(path);
    std::filesystem::remove(floorPath());
}
} // namespace isaac::runtime
