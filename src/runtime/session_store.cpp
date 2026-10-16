#include "runtime/session_store.h"
#include <fstream>
#ifdef _WIN32
#include <windows.h>
#endif
namespace isaac::runtime {
std::size_t SessionStore::write(const lan::Archive& archive) const {
    auto temporary = path;
    temporary += ".tmp";
    const auto bytes = archive.encode();
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    file.close();
    if (!file)
        throw std::runtime_error("Cannot write LAN saved session");
#ifdef _WIN32
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot commit LAN saved session");
#else
    std::filesystem::rename(temporary, path);
#endif
    return bytes.size();
}
std::optional<lan::Archive> SessionStore::read() const {
    if (!std::filesystem::exists(path) || std::filesystem::file_size(path) > lan::maxSnapshotSize)
        return {};
    std::ifstream file(path, std::ios::binary);
    const std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
    return lan::Archive::decode(bytes);
}
} // namespace isaac::runtime
