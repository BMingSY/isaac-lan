#include "presentation/connection_settings.h"
#include "test_support.h"
#include <chrono>
#include <fstream>

int main() {
    using namespace isaac::presentation;
    const auto root = std::filesystem::temp_directory_path() /
                      ("isaac-connection-" +
                       std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::filesystem::remove_all(path);
        }
    } cleanup{root};
    const auto path = root / "isaac-lan/connection.txt";
    require(loadConnectionSettings(path) == ConnectionSettings{},
            "Missing file did not use defaults");
    const ConnectionSettings first{"room.example.com", 31234};
    require(saveConnectionSettings(path, first), "Cannot save first connection");
    require(loadConnectionSettings(path) == first, "New menu instance lost connection");
    const ConnectionSettings next{"192.168.1.42", 65535};
    require(saveConnectionSettings(path, next) && loadConnectionSettings(path) == next,
            "Replacing a previous connection failed");
    for (const auto& bad : {ConnectionSettings{"bad\naddress", 123},
                            {"ok", 0},
                            {"ok", 65536},
                            {std::string(254, 'a'), 10}}) {
        require(!saveConnectionSettings(path, bad) && loadConnectionSettings(path) == next,
                "Invalid preference replaced the last usable connection");
    }
    require(saveConnectionSettings(path, {"", 1}) &&
                loadConnectionSettings(path) == ConnectionSettings{"", 1},
            "Host-only port or cleared address was not retained");
    for (const auto& source :
         {"", "address=host\nport=0\n", "address=host\nport=123.5\n", "address=host\nport=65536\n",
          "address=host\nport=123\nextra", "port=5\n"}) {
        std::ofstream(path, std::ios::binary) << source;
        require(loadConnectionSettings(path) == ConnectionSettings{},
                "Malformed file did not fall back");
    }
    std::ofstream(path, std::ios::binary) << std::string(100000, 'x');
    require(loadConnectionSettings(path) == ConnectionSettings{}, "Oversize preferences accepted");
    const auto blocked = root / "blocked";
    std::filesystem::create_directory(blocked);
    std::ofstream(blocked / "keep") << "keep";
    require(!saveConnectionSettings(blocked, first) && std::filesystem::exists(blocked / "keep"),
            "Write failure replaced an existing target");
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root))
        require(entry.path().extension() != ".tmp", "Failed save left temporary file");
    std::puts("PASS connection restart, validation, replacement and failed-write cleanup");
}
