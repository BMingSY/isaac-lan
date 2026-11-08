#include "runtime/extension_files.h"
#include "core/extension_package.h"
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <fstream>
#include <stdexcept>

namespace isaac::updates {
namespace {
struct Hash {
    BCRYPT_ALG_HANDLE algorithm{};
    BCRYPT_HASH_HANDLE value{};
    ~Hash() {
        if (value)
            BCryptDestroyHash(value);
        if (algorithm)
            BCryptCloseAlgorithmProvider(algorithm, 0);
    }
};
} // namespace
std::filesystem::path workshopSource(const std::filesystem::path& game) {
    const auto common = game.parent_path();
    const auto steamapps = common.parent_path();
    if (_wcsicmp(common.filename().c_str(), L"common") == 0 &&
        _wcsicmp(steamapps.filename().c_str(), L"steamapps") == 0)
        return steamapps / "workshop/content" / workshopApp / workshopItem / workshopDirectory;
    return {};
}
std::string fileHash(const std::filesystem::path& path) {
    Hash hash;
    if (BCryptOpenAlgorithmProvider(&hash.algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
        BCryptCreateHash(hash.algorithm, &hash.value, nullptr, 0, nullptr, 0, 0) < 0)
        throw std::runtime_error("Cannot initialize update SHA-256");
    std::ifstream input(path, std::ios::binary);
    if (!input)
        throw std::runtime_error("Cannot open update DLL");
    std::array<unsigned char, 65536> bytes{};
    while (input) {
        input.read(reinterpret_cast<char*>(bytes.data()), bytes.size());
        if (BCryptHashData(hash.value, bytes.data(), static_cast<ULONG>(input.gcount()), 0) < 0)
            throw std::runtime_error("Cannot hash update DLL");
    }
    std::array<unsigned char, 32> digest{};
    if (!input.eof() || BCryptFinishHash(hash.value, digest.data(), digest.size(), 0) < 0)
        throw std::runtime_error("Cannot finish update SHA-256");
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    for (auto value : digest) {
        result += hex[value >> 4];
        result += hex[value & 15];
    }
    return result;
}
} // namespace isaac::updates
