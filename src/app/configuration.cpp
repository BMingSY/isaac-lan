#include "app/configuration.h"
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#include <optional>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <sys/stat.h>
#else
#include <unistd.h>
#endif

namespace isaac::configuration {
namespace {
enum class Written { success, exists, failed };
Written writeExclusive(const std::filesystem::path& path, std::string_view text) {
#ifdef _WIN32
    const int file =
        _wopen(path.c_str(), _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY, _S_IREAD | _S_IWRITE);
#else
    const int file = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
#endif
    if (file < 0)
        return errno == EEXIST ? Written::exists : Written::failed;
    std::size_t written = 0;
    while (written < text.size()) {
#ifdef _WIN32
        const auto count = _write(file, text.data() + written, text.size() - written);
#else
        const auto count = write(file, text.data() + written, text.size() - written);
#endif
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            break;
        written += static_cast<std::size_t>(count);
    }
#ifdef _WIN32
    const auto flushed = _commit(file);
    const auto closed = _close(file);
#else
    const auto flushed = fsync(file);
    const auto closed = close(file);
#endif
    return written == text.size() && flushed == 0 && closed == 0 ? Written::success
                                                                 : Written::failed;
}
std::optional<std::string> read(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file)
        return {};
    // A malformed file must not grow startup memory or be rewritten partially.
    std::string source(65537, '\0');
    file.read(source.data(), source.size());
    source.resize(static_cast<std::size_t>(file.gcount()));
    return file.bad() ? std::nullopt : std::optional(std::move(source));
}
bool supplement(const std::filesystem::path& path, const std::string& original,
                const std::string& additions) {
    auto text = original;
    if (!text.empty() && text.back() != '\n')
        text += '\n';
    text += additions;
    if (text.size() > 65536)
        return false;
#ifdef _WIN32
    const auto pid = GetCurrentProcessId();
#else
    const auto pid = getpid();
#endif
    auto temporary = path;
    temporary += ".upgrade-" + std::to_string(pid) + ".tmp";
    const auto written = writeExclusive(temporary, text);
    if (written == Written::exists)
        return false;
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code error;
            std::filesystem::remove(path, error);
        }
    } cleanup{temporary};
    // A second game or editor may have saved since our initial read. Leave its
    // content alone and retry on a future launch rather than replacing it.
    if (written != Written::success || read(path) != original)
        return false;
#ifdef _WIN32
    return MoveFileExW(temporary.c_str(), path.c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    std::error_code error;
    std::filesystem::rename(temporary, path, error);
    return !error;
#endif
}
} // namespace
Parsed load(const std::filesystem::path& path) {
    std::error_code error;
    if (!std::filesystem::exists(path, error) && !error) {
        std::filesystem::create_directories(path.parent_path(), error);
        // Exclusive creation preserves a configuration created by another game
        // between exists() and open(). Never truncate an existing config.
        if (!error && writeExclusive(path, defaults) == Written::failed)
            return {{}, {"default_config_write=FAIL"}};
    }
    const auto source = read(path);
    if (!source)
        return {{}, {"config_read=FAIL using_defaults=true"}};
    if (source->size() > 65536)
        return {{}, {"config_size=FAIL using_defaults=true"}};
    auto result = parse(*source);
    const auto additions = missingDefaults(result);
    if (!additions.empty() && !supplement(path, *source, additions))
        result.warnings.push_back("config_upgrade=FAIL using_missing_defaults=true");
    return result;
}
} // namespace isaac::configuration
