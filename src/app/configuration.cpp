#include "app/configuration.h"
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#ifdef _WIN32
#include <io.h>
#include <sys/stat.h>
#else
#include <unistd.h>
#endif

namespace isaac::configuration {
Parsed load(const std::filesystem::path& path) {
    std::error_code error;
    if (!std::filesystem::exists(path, error) && !error) {
        std::filesystem::create_directories(path.parent_path(), error);
        if (!error) {
            // Another launch can create this file after exists(). Never open
            // with truncation: preserve a configuration created in that gap.
#ifdef _WIN32
            const int file = _wopen(path.c_str(), _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
                                    _S_IREAD | _S_IWRITE);
#else
            const int file = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
#endif
            if (file < 0 && errno != EEXIST)
                return {{}, {"default_config_write=FAIL"}};
            if (file >= 0) {
                std::size_t written = 0;
                while (written < defaults.size()) {
#ifdef _WIN32
                    const auto count =
                        _write(file, defaults.data() + written, defaults.size() - written);
#else
                    const auto count =
                        write(file, defaults.data() + written, defaults.size() - written);
#endif
                    if (count < 0 && errno == EINTR)
                        continue;
                    if (count <= 0)
                        break;
                    written += static_cast<std::size_t>(count);
                }
#ifdef _WIN32
                const auto closed = _close(file);
#else
                const auto closed = close(file);
#endif
                if (written != defaults.size() || closed != 0)
                    return {{}, {"default_config_write=FAIL"}};
            }
        }
    }
    std::ifstream file(path, std::ios::binary);
    if (!file)
        return {{}, {"config_read=FAIL using_defaults=true"}};
    // A configuration is small; a malformed file must not grow startup memory.
    std::string source(65537, '\0');
    file.read(source.data(), source.size());
    source.resize(static_cast<std::size_t>(file.gcount()));
    if (source.size() > 65536)
        return {{}, {"config_size=FAIL using_defaults=true"}};
    return parse(source);
}
} // namespace isaac::configuration
