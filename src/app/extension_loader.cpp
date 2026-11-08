#include "app/extension_loader.h"
#include "core/extension_package.h"
#include "runtime/extension_update.h"
#include "runtime/extension_files.h"
#include <array>
#include <cstring>

namespace isaac::loader {
namespace {
bool labGame(const std::filesystem::path& game) {
    wchar_t root[32768]{};
    const auto length = GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", root, std::size(root));
    return length && length < std::size(root) &&
           _wcsicmp(game.c_str(), (std::filesystem::path(root) / L"game").c_str()) == 0;
}
Extension resolve(HMODULE module, const std::filesystem::path& path) {
    if (!module) {
        const auto error = GetLastError();
        return {nullptr,
                nullptr,
                {startup::Code::extensionLoad,
                 path.wstring(),
                 {static_cast<int>(error), std::system_category()},
                 {}}};
    }
    Bootstrap bootstrap{};
    const auto proc = GetProcAddress(module, "IsaacLanBootstrap");
    if (!proc) {
        const auto error = GetLastError();
        FreeLibrary(module);
        return {nullptr,
                nullptr,
                {startup::Code::bootstrapExport,
                 path.wstring(),
                 {static_cast<int>(error), std::system_category()},
                 L"IsaacLanBootstrap"}};
    }
    std::memcpy(&bootstrap, &proc, sizeof(proc));
    return {module, bootstrap, {}};
}
} // namespace

Extension load(const std::filesystem::path& game, std::string_view baselineVersion,
               std::string_view gameBuild) {
    const auto fallback = game / updates::payloadFile;
    updates::Selection selection{{fallback}, {}, {}};
    if (!labGame(game)) {
        selection = updates::select(game, updates::workshopSource(game), baselineVersion, gameBuild,
                                    updates::fileHash);
    }
    if (!selection.detail.empty())
        OutputDebugStringA(("Isaac LAN update: " + selection.detail + "\n").c_str());
    Extension last;
    for (const auto& path : selection.candidates) {
        const auto module =
            LoadLibraryExW(path.c_str(), nullptr,
                           LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        last = resolve(module, path);
        if (!last.module)
            continue;
        bool compatible = true;
        if (path != fallback) {
            using ABI = unsigned(__cdecl*)();
            ABI abi{};
            const auto proc = GetProcAddress(module, "IsaacLanLoaderABI");
            std::memcpy(&abi, &proc, sizeof(proc));
            compatible = abi && abi() == updates::loaderABI;
        }
        if (compatible)
            return last;
        FreeLibrary(module);
        last = {};
    }
    return last;
}
Extension loadInstalled(const std::filesystem::path& path) {
    return resolve(LoadLibraryW(path.c_str()), path);
}
std::wstring failureMessage(const Extension& extension, DWORD code) {
    if (!code)
        return {};
    // Optional ABI-1 export. Older payloads still use the stable code catalog.
    if (extension.module && extension.bootstrap) {
        using ErrorText = const wchar_t*(__cdecl*)();
        ErrorText errorText{};
        const auto proc = GetProcAddress(extension.module, "IsaacLanBootstrapError");
        std::memcpy(&errorText, &proc, sizeof(proc));
        if (errorText) {
            const auto text = errorText();
            if (text && *text)
                return text;
        }
    }
    auto failure = extension.failure;
    failure.code = static_cast<startup::Code>(code);
    return startup::message(failure);
}
} // namespace isaac::loader
