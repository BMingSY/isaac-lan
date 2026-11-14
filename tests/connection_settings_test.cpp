#include "presentation/connection_settings.h"
#include "core/room_options.h"
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
    for (const char* host : {"2001:db8::1234", "[2001:db8::1234]", "fe80::abcd%12",
                             "[fe80::abcd%12]", "::ffff:192.168.1.42"}) {
        const ConnectionSettings ipv6{host, 31234};
        require(saveConnectionSettings(path, ipv6) && loadConnectionSettings(path) == ipv6,
                "IPv6 preferences did not survive a menu restart");
    }
    const ConnectionSettings next{"192.168.1.42", 65535, isaac::roomOptions::known};
    require(saveConnectionSettings(path, next) && loadConnectionSettings(path) == next,
            "Replacing a previous connection failed");
    for (const auto& bad : {ConnectionSettings{"bad\naddress", 123},
                            {"ok", 0},
                            {"ok", 65536},
                            {"[room.example.com]", 123},
                            {"[::1", 123},
                            {"::1]", 123},
                            {"[::1]:123", 123},
                            {"host.example:123", 123},
                            {"fe80::1%", 123},
                            {"fe80::1%eth0", 123},
                            {"fe80::1%4294967296", 123},
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
    std::ofstream(path, std::ios::binary) << "address=old.example\nport=12345\n";
    require(loadConnectionSettings(path) == ConnectionSettings{"old.example", 12345, 0},
            "Legacy IP preferences did not load");
    std::ofstream(path, std::ios::binary) << "address=new.example\nport=12345\nroomOptions="
                                          << (isaac::roomOptions::known | (1ull << 63)) << '\n';
    require(loadConnectionSettings(path) ==
                ConnectionSettings{"new.example", 12345, isaac::roomOptions::known},
            "Unknown future option bit lost known preferences");
    for (const auto legacy : {8u, 16u, 24u, 31u}) {
        std::ofstream(path, std::ios::binary)
            << "address=old.example\nport=12345\nroomOptions=" << legacy << '\n';
        const auto expected =
            (legacy & 7) | (isaac::roomOptions::autoTeleport &
                            (legacy & 16 ? ~0ull : ~isaac::roomOptions::ordinaryRooms));
        const auto migrated = loadConnectionSettings(path);
        require(migrated.roomOptions == expected, "Legacy gather preference lost its selection");
        require(saveConnectionSettings(path, migrated) && loadConnectionSettings(path) == migrated,
                "Saving migrated preferences changed the room selection");
    }
    std::ofstream(path, std::ios::binary)
        << "address=host\nport=12345\nroomOptions=18446744073709551616\n";
    require(loadConnectionSettings(path) == ConnectionSettings{}, "Overflowed room mask accepted");
    for (const auto& group : isaac::roomOptions::teleportGroups) {
        for (unsigned bit = 0; bit < isaac::roomOptions::roomTypeCount; ++bit) {
            const auto member = isaac::roomOptions::firstRoomFlag << bit;
            if (!(group.flag & member))
                continue;
            std::ofstream(path, std::ios::binary)
                << "address=types.example\nport=12345\nroomOptions=" << (member | 7) << '\n';
            const auto migrated = loadConnectionSettings(path);
            require(migrated.roomOptions == (group.flag | 7),
                    "Individual room preference did not select its whole group");
            require(saveConnectionSettings(path, migrated) &&
                        loadConnectionSettings(path) == migrated,
                    "Grouped preference changed on a second load");
        }
    }
    std::ofstream(path, std::ios::binary)
        << "address=types.example\nport=12345\nroomOptions="
        << isaac::roomOptions::roomFlags({isaac::roomOptions::RoomType::teleporter,
                                          isaac::roomOptions::RoomType::teleporterExit})
        << '\n';
    require(loadConnectionSettings(path).roomOptions == 0,
            "Unused teleporter preference remained enabled");
    const auto blocked = root / "blocked";
    std::filesystem::create_directory(blocked);
    std::ofstream(blocked / "keep") << "keep";
    require(!saveConnectionSettings(blocked, first) && std::filesystem::exists(blocked / "keep"),
            "Write failure replaced an existing target");
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root))
        require(entry.path().extension() != ".tmp", "Failed save left temporary file");
    std::puts("PASS connection restart, validation, replacement and failed-write cleanup");
}
