#include "runtime/session_store.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
} // namespace
int main() {
    const auto root = std::filesystem::temp_directory_path() /
                      ("isaac-session-store-" +
                       std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    const auto path = root / "slot/session.bin";
    try {
        isaac::runtime::SessionStore store(path);
        require(!store.read(), "Missing save was accepted");
        isaac::lan::Archive archive;
        archive.fingerprint = "test";
        archive.settings.seed = "YV039KQF";
        archive.settings.characters = {0, 1, 0, 0};
        archive.locations = {{0, 84, 10.f, 20.f}, {0, 85, 20.f, 30.f}};
        archive.game = {1, 2, 3};
        store.write(archive);
        require(store.read()->encode() == archive.encode(), "Persisted archive differs");
        archive.game = {4, 5};
        store.write(archive);
        require(store.read()->game == archive.game, "Existing archive was not replaced");
        const auto previous = store.read()->encode();
        // A blocked staging path cannot destroy the committed save.
        std::filesystem::create_directory(path.string() + ".tmp");
        bool failed = false;
        try {
            store.write(archive);
        } catch (const std::exception&) {
            failed = true;
        }
        require(failed && store.read()->encode() == previous,
                "Failed write damaged committed save");
        std::ofstream(path, std::ios::binary | std::ios::trunc) << "truncated";
        failed = false;
        try {
            failed = !store.read();
        } catch (const std::exception&) {
            failed = true;
        }
        require(failed, "Corrupt archive was accepted");
        std::filesystem::remove_all(root);
        std::cout << "PASS session store replacement, corruption and failed-write protection\n";
        return 0;
    } catch (const std::exception& error) {
        std::filesystem::remove_all(root);
        std::cerr << error.what() << '\n';
        return 1;
    }
}
