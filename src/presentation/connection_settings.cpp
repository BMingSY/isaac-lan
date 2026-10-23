#include "presentation/connection_settings.h"
#include "net/host_address.h"
#include <charconv>
#include <fstream>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace isaac::presentation {
namespace {
bool valid(const ConnectionSettings& settings) {
    return (settings.address.empty() || lan::validHostAddress(settings.address)) &&
           settings.port >= 1 && settings.port <= 65535;
}
} // namespace
ConnectionSettings loadConnectionSettings(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    // Bound reads even if this small preference file has been replaced by a log.
    std::string source(lan::maxHostAddressLength + 32, '\0');
    file.read(source.data(), source.size());
    if (file.bad() || !file.eof())
        return {};
    source.resize(static_cast<std::size_t>(file.gcount()));
    const auto separator = source.find("\nport=");
    if (!source.starts_with("address=") || separator == source.npos || source.back() != '\n')
        return {};
    ConnectionSettings result;
    result.address = source.substr(8, separator - 8);
    const auto number =
        std::string_view(source).substr(separator + 6, source.size() - separator - 7);
    const auto [end, error] =
        std::from_chars(number.data(), number.data() + number.size(), result.port);
    return error == std::errc{} && end == number.data() + number.size() && valid(result)
               ? result
               : ConnectionSettings{};
}
bool saveConnectionSettings(const std::filesystem::path& path, const ConnectionSettings& settings) {
    if (path.empty() || !valid(settings))
        return false;
    std::error_code error;
    if (!path.parent_path().empty())
        std::filesystem::create_directories(path.parent_path(), error);
    if (error)
        return false;
#ifdef _WIN32
    const auto process = GetCurrentProcessId();
#else
    const auto process = getpid();
#endif
    auto temporary = path;
    temporary += "." + std::to_string(process) + ".tmp";
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code ignored;
            std::filesystem::remove(path, ignored);
        }
    } cleanup{temporary};
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    file << "address=" << settings.address << "\nport=" << settings.port << '\n';
    file.close();
    if (!file)
        return false;
#ifdef _WIN32
    return MoveFileExW(temporary.c_str(), path.c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    std::filesystem::rename(temporary, path, error);
    return !error;
#endif
}
} // namespace isaac::presentation
