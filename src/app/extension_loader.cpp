#include "app/extension_loader.h"
#include "core/extension_package.h"
#include "runtime/extension_update.h"
#include <bcrypt.h>
#include <array>
#include <cstring>
#include <fstream>
#include <stdexcept>

namespace isaac::loader {
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
bool labGame(const std::filesystem::path& game) {
    wchar_t root[32768]{};
    const auto length = GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", root, std::size(root));
    return length && length < std::size(root) &&
           _wcsicmp(game.c_str(), (std::filesystem::path(root) / L"game").c_str()) == 0;
}
} // namespace
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

Extension load(const std::filesystem::path& game, std::string_view baselineVersion,
               std::string_view gameBuild) {
    const auto fallback = game / updates::payloadFile;
    updates::Selection selection{{fallback}, {}};
    if (!labGame(game)) {
        std::filesystem::path source;
        const auto common = game.parent_path();
        const auto steamapps = common.parent_path();
        if (_wcsicmp(common.filename().c_str(), L"common") == 0 &&
            _wcsicmp(steamapps.filename().c_str(), L"steamapps") == 0)
            source = steamapps / "workshop/content" / updates::workshopApp / updates::workshopItem /
                     updates::workshopDirectory;
        selection = updates::select(game, source, baselineVersion, gameBuild, fileHash);
    }
    if (!selection.detail.empty())
        OutputDebugStringA(("Isaac LAN update: " + selection.detail + "\n").c_str());
    for (const auto& path : selection.candidates) {
        const auto module =
            LoadLibraryExW(path.c_str(), nullptr,
                           LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        if (!module)
            continue;
        Bootstrap bootstrap{};
        auto proc = GetProcAddress(module, "IsaacLanBootstrap");
        std::memcpy(&bootstrap, &proc, sizeof(proc));
        bool compatible = true;
        if (path != fallback) {
            using ABI = unsigned(__cdecl*)();
            ABI abi{};
            proc = GetProcAddress(module, "IsaacLanLoaderABI");
            std::memcpy(&abi, &proc, sizeof(proc));
            compatible = abi && abi() == updates::loaderABI;
        }
        if (bootstrap && compatible)
            return {module, bootstrap};
        FreeLibrary(module);
    }
    return {};
}
} // namespace isaac::loader
