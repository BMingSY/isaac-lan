#pragma once
#include <array>
#include <cstdint>
#include <cstring>

namespace isaac::engine::native_save {
// GameState::Read can request deletion of the file on parse failure. A LAN
// stream has no backing file. Borrow the four filename slots as empty MSVC
// strings for this call, then restore their exact bytes and native ownership.
// Read and Clear do not assign to these strings on either supported build.
class FileNames {
    struct String {
        std::array<char, 16> text{};
        std::uint32_t size = 0, capacity = 15;
    };
    static_assert(sizeof(String) == 24);
    std::uintptr_t state;
    const std::array<unsigned, 4>& offsets;
    std::array<String, 4> saved;

  public:
    FileNames(std::uintptr_t state, const std::array<unsigned, 4>& offsets)
        : state(state), offsets(offsets) {
        const String empty;
        for (unsigned i = 0; i < offsets.size(); ++i) {
            auto* target = reinterpret_cast<void*>(state + offsets[i]);
            std::memcpy(&saved[i], target, sizeof(String));
            std::memcpy(target, &empty, sizeof(String));
        }
    }
    ~FileNames() {
        for (unsigned i = 0; i < offsets.size(); ++i)
            std::memcpy(reinterpret_cast<void*>(state + offsets[i]), &saved[i], sizeof(String));
    }
    FileNames(const FileNames&) = delete;
    FileNames& operator=(const FileNames&) = delete;
};
} // namespace isaac::engine::native_save
