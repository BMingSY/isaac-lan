#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include "engine/frontend.h"
#include "engine/chat_input.h"
#include "engine/emotes.h"
#include "engine/build.h"
#include "runtime/session.h"
#include "engine/rooms.h"
#include "engine/input.h"
#include "net/host_address.h"
#include "presentation/connection_settings.h"
#include "embedded_bridge.h"
#include "diagnostics/lab_capture.h"
#include "diagnostics/performance.h"
#include <MinHook.h>
#include <bcrypt.h>
#include <GL/gl.h>
#include <imgui.h>
#include <imgui_impl_win32.h>
#include <imgui_impl_opengl3.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cstring>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <vector>

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND, UINT, WPARAM, LPARAM);
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"
#include "engine/versions/j460/menu_context.h"
#include "core/level_grid.h"
#include "core/input_actions.h"
#include "compat/game_ids.h"

namespace j460 = isaac::engine::j460;
namespace layout = j460::layout;

namespace isaac::frontend {
namespace {
std::uintptr_t image;
chat::Appearance chatAppearance;
presentation::ChatBackground chatBackground;
std::filesystem::path connectionPath;
presentation::ConnectionSettings connectionSettings;
std::wstring labRoot;
void (*logger)(const std::string&);
int(__cdecl* bindNative)(lua_State*);
lua_State* state = nullptr;
constexpr int luaTable = 5, luaFunction = 6;
struct Lua {
    void(__cdecl* createTable)(lua_State*, int, int);
    int(__cdecl* getTop)(lua_State*);
    void(__cdecl* setTop)(lua_State*, int);
    int(__cdecl* getGlobal)(lua_State*, const char*);
    void(__cdecl* setGlobal)(lua_State*, const char*);
    void(__cdecl* setField)(lua_State*, int, const char*);
    void(__cdecl* pushClosure)(lua_State*, int(__cdecl*)(lua_State*), int);
    int(__cdecl* getField)(lua_State*, int, const char*);
    int(__cdecl* rawGetI)(lua_State*, int, long long);
    long long(__cdecl* integer)(lua_State*, int, int*);
    int(__cdecl* boolean)(lua_State*, int);
    void(__cdecl* pushBoolean)(lua_State*, int);
    void(__cdecl* pushInteger)(lua_State*, long long);
    void(__cdecl* pushNumber)(lua_State*, double);
    const char*(__cdecl* string)(lua_State*, int, std::size_t*);
    const char*(__cdecl* pushString)(lua_State*, const char*);
    int(__cdecl* load)(lua_State*, const char*, std::size_t, const char*, const char*);
    int(__cdecl* pcall)(lua_State*, int, int, int, std::intptr_t, void*);
} lua;
bool bridgeFailed = false, visible = false, guiReady = false;
bool officialRequested = false;
std::string error, fingerprint, modFingerprint;
using StatPlayerId = int(__attribute__((thiscall)) *)(void*, void*);
StatPlayerId originalStatPlayerId = nullptr;
int __attribute__((fastcall)) statPlayerId(void* hud, void*, void* player) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return originalStatPlayerId(hud, player);
    const auto address = reinterpret_cast<std::uintptr_t>(hud);
    // StatHUD owns two scalar stat caches (Jacob and Esau). Clear a stale
    // teammate cache from the pre-network startup before selecting our actor.
    for (unsigned i = 0; i < layout::statHud::cacheCount; ++i) {
        const auto cached = *reinterpret_cast<std::uintptr_t*>(address + layout::statHud::player +
                                                               i * layout::statHud::cacheStride);
        if (cached && *reinterpret_cast<int*>(cached + layout::player::controller) != slot + 1) {
            using Reset = void(__attribute__((thiscall))*)(void*);
            reinterpret_cast<Reset>(image + j460::entry::frontendStatHUDReset)(hud);
            break;
        }
    }
    if (*reinterpret_cast<int*>(reinterpret_cast<std::uintptr_t>(player) +
                                layout::player::controller) != slot + 1)
        return -1;
    return originalStatPlayerId(hud, player);
}
int count = 0, draining = 0;
bool prepared = false;
bool lobbyRequested = false;
bool closeRequested = false, closeSent = false, closeReady = false;
int menuKey = 0;
bool menuClick = false;
std::string menuText;
using MenuRender = void(__cdecl*)();
MenuRender originalMenuRender;
using MenuUpdate = void(__attribute__((thiscall)) *)(void*);
MenuUpdate originalGameMenuUpdate;
std::string localAddresses;
std::string addresses() {
    ULONG size = 16384;
    std::vector<unsigned char> storage(size);
    auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(storage.data());
    auto result = GetAdaptersAddresses(
        AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr, adapters, &size);
    if (result == ERROR_BUFFER_OVERFLOW) {
        storage.resize(size);
        adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(storage.data());
        result = GetAdaptersAddresses(
            AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
            nullptr, adapters, &size);
    }
    std::string out;
    if (result == NO_ERROR)
        for (auto* adapter = adapters; adapter; adapter = adapter->Next) {
            if (adapter->OperStatus != IfOperStatusUp ||
                adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK)
                continue;
            for (auto* address = adapter->FirstUnicastAddress; address; address = address->Next) {
                if (address->Address.lpSockaddr->sa_family != AF_INET)
                    continue;
                const auto* a = reinterpret_cast<const sockaddr_in*>(address->Address.lpSockaddr);
                char buffer[INET_ADDRSTRLEN]{};
                if (InetNtopA(AF_INET, const_cast<IN_ADDR*>(&a->sin_addr), buffer,
                              sizeof(buffer))) {
                    if (!out.empty())
                        out += " / ";
                    out += buffer;
                }
            }
        }
    return out;
}
struct Location {
    int index = -1, dimension = 0;
};
std::array<Location, lan::maxPlayers> positions;
HWND window;
WNDPROC originalWndProc;
using Swap = BOOL(WINAPI*)(HDC);
Swap originalSwap;
using Init = void(__attribute__((thiscall)) *)(void*, bool);
Init originalInit;
using Close = void(__cdecl*)(lua_State*);
Close originalClose;
using MapRender = void(__attribute__((thiscall)) *)(void*);
MapRender originalMapRender;
using TextureRender = void*(__attribute__((thiscall)) *)(void*, const void*, const void*, bool);
TextureRender originalTextureRender;
MapRender originalMapCache;
std::uintptr_t activeMap = 0;
std::array<Location, 2> mapAnchors;
struct Marker {
    ImVec2 position;
    int slot;
    float alpha;
};
std::vector<Marker> markers;
template <class T> T& read(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
bool menuAvailable() {
    return j460::menu_context::ready(image);
}
int beginText(lua_State* L) {
    const char* value = lua.string(L, 1, nullptr);
    const char* field = lua.string(L, 2, nullptr);
    const auto kind = field && std::strcmp(field, "seed") == 0   ? chat_input::TextField::seed
                      : field && std::strcmp(field, "port") == 0 ? chat_input::TextField::port
                                                                 : chat_input::TextField::address;
    menuText = value ? value : "";
    chat_input::beginField(kind, menuText);
    logger("native_menu_text=begin");
    return 0;
}
int endText(lua_State*) {
    chat_input::endField();
    return 0;
}
int loadConnection(lua_State* L) {
    lua.pushString(L, connectionSettings.address.c_str());
    lua.pushInteger(L, connectionSettings.port);
    return 2;
}
int saveConnection(lua_State* L) {
    std::size_t size = 0;
    const auto* address = lua.string(L, 1, &size);
    const auto port = lua.integer(L, 2, nullptr);
    if (!address || size > lan::maxHostAddressLength || port < 1 || port > 65535)
        return 0;
    const presentation::ConnectionSettings next{std::string(address, size),
                                                static_cast<unsigned>(port)};
    if (next != connectionSettings) {
        if (presentation::saveConnectionSettings(connectionPath, next))
            connectionSettings = next;
        else
            logger("connection_settings_save=FAIL");
    }
    return 0;
}
int officialMenu(lua_State*) {
    officialRequested = true;
    return 0;
}
void openMenu();
void __attribute__((fastcall)) gameMenuUpdate(void* menu, void*) {
    if (!state || bridgeFailed || !menuAvailable()) {
        originalGameMenuUpdate(menu);
        return;
    }
    const auto manager = read<std::uintptr_t>(image, j460::globals::menuManager);
    if (!manager || read<int>(manager, layout::menuManager::page) != j460::menuPage::main) {
        originalGameMenuUpdate(menu);
        return;
    }
    if (officialRequested) {
        officialRequested = false;
        visible = false;
        chat_input::endField();
        input::leaveLan();
        input::confirmOriginalMenu(menu, originalGameMenuUpdate);
        logger("native_online_entry=OFFICIAL");
        return;
    }
    if (!visible) {
        const auto gameManager = read<std::uintptr_t>(image, j460::globals::manager);
        if (!read<bool>(manager, layout::menuManager::inputBlocked) &&
            read<unsigned>(gameManager, layout::manager::menuInputBlock) == 0 &&
            read<int>(reinterpret_cast<std::uintptr_t>(menu), layout::mainMenu::selection) ==
                j460::mainMenuSelection::online &&
            input::menuTriggered(input::action::menuConfirm)) {
            visible = true;
            menuKey = 0;
            menuClick = false;
            openMenu();
            logger("native_online_entry=OPEN");
            return;
        }
        originalGameMenuUpdate(menu);
        return;
    }
    if (chat_input::fieldActive()) {
        // The editor owns keyboard messages. Bound menu actions (Space/letters)
        // cannot commit a field or move the selection while it is being typed.
        menuText = chat_input::fieldText();
        menuKey = chat_input::fieldKey();
        // Controller confirmation/cancel still work without keyboard bindings.
        if (input::menuTriggered(input::action::menuConfirm, true))
            menuKey = VK_RETURN;
        else if (input::menuTriggered(input::action::menuBack, true))
            menuKey = VK_ESCAPE;
        return;
    }
    if (chat_input::capturesInput())
        return;
    for (const auto& [action, key] : {std::pair{input::action::menuConfirm, VK_RETURN},
                                      {input::action::menuBack, VK_ESCAPE},
                                      {input::action::menuLeft, VK_LEFT},
                                      {input::action::menuRight, VK_RIGHT},
                                      {input::action::menuUp, VK_UP},
                                      {input::action::menuDown, VK_DOWN}})
        if (input::menuTriggered(action)) {
            menuKey = key;
            break;
        }
}
void __attribute__((fastcall)) mapCache(void* config, void*) {
    rooms::withView([&] {
        const auto game = read<std::uintptr_t>(image, j460::globals::game);
        const auto offset =
            reinterpret_cast<std::uintptr_t>(config) - (game + layout::game::minimap);
        if (offset == layout::minimap::small || offset == layout::minimap::large)
            mapAnchors[offset == layout::minimap::small ? 0 : 1] = {
                read<int>(game, layout::game::roomIndex), read<int>(game, layout::game::dimension)};
        if (runtime::localViewSlot() >= 0) {
            // CacheMap switches targets before flushing. Native menu/scene work
            // already queued for the current target must stay on that target.
            using Flush = void(__attribute__((thiscall))*)(void*, bool);
            reinterpret_cast<Flush>(image + j460::entry::renderingFlush)(
                reinterpret_cast<void*>(image + j460::globals::renderer), false);
        }
        rooms::withMapPickups([&] { originalMapCache(config); });
    });
}
MenuUpdate originalHudUpdate = nullptr, originalHudPostUpdate = nullptr,
           originalHudRender = nullptr, originalMinimapUpdate = nullptr;
StatPlayerId originalHistoryPlayerId = nullptr;
int __attribute__((fastcall)) historyPlayerId(void* history, void*, void* player) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return originalHistoryPlayerId(history, player);
    if (read<int>(reinterpret_cast<std::uintptr_t>(player), layout::player::controller) != slot + 1)
        return -1;
    int result = -1;
    rooms::withView([&] { result = originalHistoryPlayerId(history, player); }, true);
    return result;
}
void bindTeamHud(void* hud) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return;
    const auto game = read<std::uintptr_t>(image, j460::globals::game),
               address = reinterpret_cast<std::uintptr_t>(hud);
    std::array<std::uintptr_t, lan::maxPlayers * 2> desired{};
    unsigned ordinal = 0;
    for (auto entry = read<std::uintptr_t>(game, layout::game::players);
         entry < read<std::uintptr_t>(game, layout::game::players + layout::vector::end) &&
         ordinal < lan::maxPlayers;
         entry += sizeof(std::uintptr_t)) {
        const auto p = read<std::uintptr_t>(entry, 0);
        if (read<int>(p, layout::entity::parent) != 0 || !read<bool>(p, layout::entity::active))
            continue;
        const auto twin = read<std::uintptr_t>(p, layout::player::twin);
        if (twin && twin != p && read<int>(twin, layout::player::index) >= 0 &&
            read<int>(twin, layout::player::index) < read<int>(p, layout::player::index))
            continue;
        desired[ordinal] = p;
        if (twin && twin != p && read<bool>(twin, layout::entity::active) &&
            read<int>(twin, layout::player::type) != compat::ids::player::soulB)
            desired[ordinal + lan::maxPlayers] = twin;
        ++ordinal;
    }
    bool changed = false;
    for (unsigned i = 0; i < desired.size(); ++i) {
        const auto part = address + i * layout::playerHud::size;
        if (read<std::uintptr_t>(part, 0) == desired[i])
            continue;
        // Reset owned caches through the native destructor/reset routine. A
        // pointer-only swap leaves heart and inventory caches from a teammate.
        reinterpret_cast<MenuUpdate>(image +
                                     j460::entry::playerHUDReset)(reinterpret_cast<void*>(part));
        read<std::uintptr_t>(part, 0) = desired[i];
        read<unsigned short>(part, layout::playerHud::refreshFlags) = layout::playerHud::refreshAll;
        changed = true;
    }
    if (changed) {
        using Recompute = void(__attribute__((thiscall))*)(void*, bool);
        reinterpret_cast<Recompute>(image + j460::entry::historyHUDRecomputeAll)(
            reinterpret_cast<void*>(address + layout::hud::history), true);
    }
}
void __attribute__((fastcall)) hudUpdate(void* hud, void*) {
    rooms::withView([&] { originalHudUpdate(hud); });
}
void __attribute__((fastcall)) hudPostUpdate(void* hud, void*) {
    rooms::withView([&] {
        bindTeamHud(hud);
        originalHudPostUpdate(hud);
    });
}
void __attribute__((fastcall)) hudRender(void* hud, void*) {
    rooms::withView([&] {
        bindTeamHud(hud);
        originalHudRender(hud);
    });
}
void __attribute__((fastcall)) minimapUpdate(void* map, void*) {
    rooms::withView([&] { originalMinimapUpdate(map); });
}
void* __attribute__((fastcall)) textureRender(void* texture, void*, const void* quad,
                                              const void* destination, bool transparent) {
    if (activeMap && prepared) {
        const auto source = reinterpret_cast<std::uintptr_t>(texture);
        for (unsigned offset : {layout::minimap::small, layout::minimap::large})
            if (source == read<std::uintptr_t>(activeMap, offset + layout::mapConfig::texture)) {
                const auto config = activeMap + offset;
                const auto anchor = mapAnchors[offset == layout::minimap::small ? 0 : 1];
                const auto* q = static_cast<const float*>(quad);
                const auto* dest = static_cast<const float*>(destination);
                const bool pixels =
                    static_cast<const unsigned char*>(quad)[layout::renderQuad::pixels] != 0;
                const float width =
                    pixels ? 1.0f : static_cast<float>(read<int>(source, layout::texture::width));
                const float height =
                    pixels ? 1.0f : static_cast<float>(read<int>(source, layout::texture::height));
                const float left = q[0] * width, top = q[1] * height, dx = (q[2] - q[0]) * width,
                            dy = (q[5] - q[1]) * height;
                if (dx == 0 || dy == 0 || anchor.index < 0 || anchor.index >= level_grid::cellCount)
                    continue;
                for (int slot = 0; slot < count && slot < static_cast<int>(lan::maxPlayers);
                     ++slot) {
                    const auto p = positions[slot];
                    if (p.index < 0 || p.index >= level_grid::cellCount ||
                        p.dimension != anchor.dimension)
                        continue;
                    const float x =
                        read<float>(config, layout::mapConfig::anchorX) +
                        (p.index % level_grid::width - anchor.index % level_grid::width) *
                            (read<float>(config, layout::mapConfig::cellWidth) +
                             read<float>(config, layout::mapConfig::cellSpacing));
                    const float y =
                        read<float>(config, layout::mapConfig::anchorY) +
                        (p.index / level_grid::width - anchor.index / level_grid::width) *
                            (read<float>(config, layout::mapConfig::cellHeight) +
                             read<float>(config, layout::mapConfig::cellSpacing));
                    const float u = (x - left) / dx, v = (y - top) / dy;
                    if (u < 0 || u > 1 || v < 0 || v > 1)
                        continue;
                    markers.push_back(
                        {ImVec2(dest[0] + u * (dest[2] - dest[0]) + v * (dest[4] - dest[0]),
                                dest[1] + u * (dest[3] - dest[1]) + v * (dest[5] - dest[1])),
                         slot, std::clamp(dest[11], 0.0f, 1.0f)});
                }
            }
    }
    return originalTextureRender(texture, quad, destination, transparent);
}
void __attribute__((fastcall)) minimapRender(void* map, void*) {
    activeMap = reinterpret_cast<std::uintptr_t>(map);
    if (!originalTextureRender) {
        const auto texture =
            read<std::uintptr_t>(activeMap, layout::minimap::small + layout::mapConfig::texture);
        if (texture) {
            const auto target = *reinterpret_cast<void**>(read<std::uintptr_t>(texture, 0) +
                                                          layout::texture::renderVtableSlot);
            if (MH_CreateHook(target, reinterpret_cast<void*>(textureRender),
                              reinterpret_cast<void**>(&originalTextureRender)) == MH_OK)
                MH_EnableHook(target);
        }
    }
    originalMapRender(map);
    activeMap = 0;
}

class Hash {
    BCRYPT_ALG_HANDLE algorithm{};
    BCRYPT_HASH_HANDLE hash{};

  public:
    Hash() {
        if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
            BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0)
            throw std::runtime_error("Cannot initialize manifest hash");
    }
    ~Hash() {
        if (hash)
            BCryptDestroyHash(hash);
        if (algorithm)
            BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    void add(const void* bytes, std::size_t size) {
        if (BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<void*>(bytes)),
                           static_cast<ULONG>(size), 0) < 0)
            throw std::runtime_error("Cannot hash manifest");
    }
    void text(const std::string& value) {
        add(value.data(), value.size());
        const char zero = 0;
        add(&zero, 1);
    }
    void file(const std::filesystem::path& path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream)
            throw std::runtime_error("Cannot read a fingerprinted file");
        std::array<char, 65536> buffer;
        while (stream) {
            stream.read(buffer.data(), buffer.size());
            add(buffer.data(), static_cast<std::size_t>(stream.gcount()));
        }
        if (!stream.eof())
            throw std::runtime_error("Fingerprinted file read failed");
    }
    std::string finish() {
        std::array<unsigned char, 32> bytes{};
        if (BCryptFinishHash(hash, bytes.data(), bytes.size(), 0) < 0)
            throw std::runtime_error("Cannot finish manifest hash");
        std::string out;
        for (auto c : bytes) {
            out += "0123456789abcdef"[c >> 4];
            out += "0123456789abcdef"[c & 15];
        }
        return out;
    }
};
int configurationHash(lua_State* L) {
    std::size_t size = 0;
    const auto data = lua.string(L, 1, &size);
    if (!data || size > 16 * 1024 * 1024 || modFingerprint.empty()) {
        lua.pushString(L, "");
        return 1;
    }
    try {
        Hash hash;
        hash.text(modFingerprint);
        hash.add(data, size);
        lua.pushString(L, hash.finish().c_str());
    } catch (const std::exception&) {
        lua.pushString(L, "");
    }
    return 1;
}
int integrationNonce(lua_State* L) {
    std::array<unsigned char, 16> value{};
    if (BCryptGenRandom(nullptr, value.data(), value.size(), BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
        return 0;
    std::string result;
    for (auto byte : value) {
        result += "0123456789abcdef"[byte >> 4];
        result += "0123456789abcdef"[byte & 15];
    }
    lua.pushString(L, result.c_str());
    return 1;
}
int integrationSetting(lua_State* L) {
    const auto key = lua.string(L, 1, nullptr);
    if (!key || std::strlen(key) > 80 ||
        std::strspn(key, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-") !=
            std::strlen(key))
        return 0;
    wchar_t executable[32768]{};
    GetModuleFileNameW(nullptr, executable, std::size(executable));
    const auto path =
        std::filesystem::path(executable).parent_path() / L"isaac-lan" / L"integrations.ini";
    if (lua.getTop(L) >= 2) {
        std::string value = lua.boolean(L, 2) ? "1" : "0";
        std::error_code error;
        std::filesystem::create_directories(path.parent_path(), error);
        const std::wstring wideKey(key, key + std::strlen(key));
        lua.pushBoolean(L, !error && WritePrivateProfileStringW(L"compatibility", wideKey.c_str(),
                                                                value == "1" ? L"1" : L"0",
                                                                path.c_str()));
    } else {
        const std::wstring wideKey(key, key + std::strlen(key));
        lua.pushBoolean(
            L, GetPrivateProfileIntW(L"compatibility", wideKey.c_str(), 1, path.c_str()) != 0);
    }
    return 1;
}
std::map<std::filesystem::path, std::array<std::string, 4>> modSourceCache;
int modInfo(lua_State* L) {
    namespace fs = std::filesystem;
    const auto input = lua.string(L, 1, nullptr);
    if (!input)
        return 0;
    try {
        std::string source(input);
        std::replace(source.begin(), source.end(), '\\', '/');
        const auto start = source.find("mods/");
        if (start == std::string::npos)
            return 0;
        const auto end = source.find('/', start + 5);
        if (end == std::string::npos)
            return 0;
        const auto folder = source.substr(start + 5, end - start - 5);
        if (folder.empty() || folder == "." || folder == "..")
            return 0;
        wchar_t executable[32768]{};
        GetModuleFileNameW(nullptr, executable, std::size(executable));
        const auto root =
            fs::path(executable).parent_path() / L"mods" /
            fs::path(std::u8string(reinterpret_cast<const char8_t*>(folder.data()), folder.size()));
        if (!fs::is_directory(root) || fs::exists(root / L"disable.it"))
            return 0;
        // Cache per Lua environment; versioned source is immutable while loaded.
        auto& cache = modSourceCache;
        auto found = cache.find(root);
        if (found == cache.end()) {
            std::ifstream metadata(root / L"metadata.xml", std::ios::binary);
            std::string xml((std::istreambuf_iterator<char>(metadata)), {});
            if (xml.size() > 512 * 1024)
                return 0;
            auto tag = [&](const char* key) {
                const std::string open = std::string("<") + key + ">",
                                  close = std::string("</") + key + ">";
                auto a = xml.find(open),
                     b = a == std::string::npos ? a : xml.find(close, a + open.size());
                return b == std::string::npos ? std::string{}
                                              : xml.substr(a + open.size(), b - a - open.size());
            };
            std::vector<fs::path> files;
            for (const auto& item : fs::recursive_directory_iterator(root))
                if (item.is_regular_file() && item.path().extension() == L".lua" &&
                    item.path().filename() != L"gtconfig.lua" &&
                    item.path().filename() != L"eid_config.lua")
                    files.push_back(item.path());
            std::sort(files.begin(), files.end());
            Hash hash;
            hash.text("Isaac LAN/compat-source-v1");
            for (const auto& file : files) {
                hash.text(fs::relative(file, root).generic_string());
                Hash entry;
                entry.file(file);
                hash.text(entry.finish());
            }
            found =
                cache
                    .emplace(root, std::array<std::string, 4>{tag("id"), tag("version"),
                                                              hash.finish(), root.generic_string()})
                    .first;
        }
        lua.createTable(L, 0, 4);
        const std::array<const char*, 4> keys{"workshopId", "metadataVersion", "sourceHash",
                                              "directory"};
        for (unsigned i = 0; i < keys.size(); ++i) {
            lua.pushString(L, found->second[i].c_str());
            lua.setField(L, -2, keys[i]);
        }
        return 1;
    } catch (const std::exception& error) {
        logger(std::string("compat_source_error=") + error.what());
        return 0;
    }
}
void manifest() {
    namespace fs = std::filesystem;
    wchar_t executable[32768]{};
    if (!GetModuleFileNameW(nullptr, executable, std::size(executable)))
        throw std::runtime_error("Cannot locate game directory");
    const auto directory = fs::path(executable).parent_path();
    Hash hash;
    hash.text("Isaac LAN/build-v1");
    hash.text(build::version);
    Hash extension;
    extension.file(directory / L"isaac_lan_probe.dll");
    hash.text(extension.finish());
    fingerprint = hash.finish();
    // Mods are advisory, including unreadable files. They never enter the
    // required build identity used for joining or restoring a saved session.
    modFingerprint.clear();
    try {
        Hash mods;
        mods.text("Isaac LAN/mods-v1");
        std::vector<fs::path> files;
        if (fs::is_directory(directory / L"mods"))
            for (const auto& mod : fs::directory_iterator(directory / L"mods")) {
                if (!mod.is_directory() || fs::exists(mod.path() / L"disable.it"))
                    continue;
                for (const auto& item : fs::recursive_directory_iterator(mod.path()))
                    if (item.is_regular_file())
                        files.push_back(item.path());
            }
        std::sort(files.begin(), files.end());
        for (const auto& file : files) {
            mods.text(fs::relative(file, directory / L"mods").generic_string());
            Hash entry;
            entry.file(file);
            mods.text(entry.finish());
        }
        logger("mod_manifest files=" + std::to_string(files.size()));
        modFingerprint = mods.finish();
    } catch (const std::exception& e) {
        logger("mod_manifest=UNKNOWN " + std::string(e.what()));
    }
}
bool invoke(int nargs, int results) {
    if (lua.pcall(state, nargs, results, 0, 0, nullptr) == 0)
        return true;
    const char* reason = lua.string(state, -1, nullptr);
    error = reason ? reason : "Native bridge returned a Lua error";
    logger("frontend_error=" + error);
    return false;
}
void openMenu() {
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanMenuOpen") == luaFunction && !invoke(0, 0))
        bridgeFailed = true;
    lua.setTop(state, top);
}
int number(const char* name) {
    lua.getField(state, -1, name);
    const auto n = lua.integer(state, -1, nullptr);
    lua.setTop(state, -2);
    return static_cast<int>(n);
}
bool boolean(const char* name) {
    lua.getField(state, -1, name);
    const bool n = lua.boolean(state, -1) != 0;
    lua.setTop(state, -2);
    return n;
}
std::string string(const char* name) {
    lua.getField(state, -1, name);
    const auto s = lua.string(state, -1, nullptr);
    std::string result = s ? s : "";
    lua.setTop(state, -2);
    return result;
}
void poll() {
    if (!state || bridgeFailed)
        return;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanFrame") != luaFunction) {
        lua.setTop(state, top);
        return;
    }
    if (!invoke(0, 1)) {
        bridgeFailed = true;
        runtime::abort(error);
        lua.setTop(state, top);
        return;
    }
    count = number("players");
    prepared = boolean("prepared");
    draining = number("draining");
    error = string("error");
    if (lobbyRequested && !prepared && j460::menu_context::returnToMain(image)) {
        lobbyRequested = false;
        visible = true;
        chat_input::endField();
        menuKey = 0;
        menuClick = false;
        const int saved = lua.getTop(state);
        if (lua.getGlobal(state, "_IsaacLanMenuOpen") == luaFunction) {
            lua.pushBoolean(state, true);
            if (!invoke(1, 0))
                bridgeFailed = true;
        }
        lua.setTop(state, saved);
        logger("native_online_entry=RETURN_LOBBY");
    }
    if (prepared) {
        if (lua.getField(state, -1, "positions") == luaTable) {
            for (unsigned i = 0; i < positions.size(); ++i) {
                positions[i] = {};
                if (lua.getField(state, -1, std::to_string(i).c_str()) == luaTable)
                    positions[i] = {number("index"), number("dimension")};
                lua.setTop(state, -2);
            }
        }
        lua.setTop(state, -2);
    }
    lua.setTop(state, top);
    if (closeRequested) {
        if (!closeSent) {
            runtime::requestWindowClose();
            closeSent = true;
        }
        if (!prepared && !draining) {
            closeRequested = false;
            closeReady = true;
            PostMessageW(window, WM_CLOSE, 0, 0);
        }
    }
}
LRESULT CALLBACK events(HWND h, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_CLOSE && !closeReady && (prepared || draining || closeRequested)) {
        closeRequested = true;
        return 0;
    }
    if (const auto handled = chat_input::event(h, message, w, l))
        return *handled;
    if (visible && message == WM_LBUTTONDOWN)
        menuClick = true;
    return CallWindowProcW(originalWndProc, h, message, w, l);
}
void map() {
    if (prepared && !markers.empty()) {
        const auto display = ImGui::GetIO().DisplaySize;
        const float logicalWidth = read<float>(image, j460::globals::logicalWidth);
        const float scale = logicalWidth > 0 ? display.x / logicalWidth : 2;
        auto* draw = ImGui::GetForegroundDrawList();
        constexpr ImU32 colors[] = {IM_COL32(240, 75, 75, 255), IM_COL32(86, 166, 255, 255),
                                    IM_COL32(249, 219, 66, 255), IM_COL32(94, 226, 112, 255)};
        for (auto marker : markers) {
            if (marker.alpha < .01f)
                continue;
            const bool shared =
                std::count_if(positions.begin(), positions.begin() + count, [&](auto p) {
                    return p.index == positions[marker.slot].index &&
                           p.dimension == positions[marker.slot].dimension;
                }) > 1;
            auto pos = marker.position;
            if (shared) {
                pos.x += (marker.slot % 2) * 3 - 1.5f;
                pos.y += (marker.slot / 2) * 3 - 1.5f;
            }
            pos.x *= scale;
            pos.y *= scale;
            const auto color = (colors[marker.slot] & 0x00ffffffu) |
                               (static_cast<ImU32>(marker.alpha * 255) << 24);
            draw->AddCircleFilled(pos, 2.0f * scale, IM_COL32(20, 15, 12, 200), 12);
            draw->AddCircleFilled(pos, 1.5f * scale, color, 12);
        }
    }
    markers.clear();
}

void renderNativeMenu() {
    if (!state || bridgeFailed || !window)
        return;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanMenuRender") != luaFunction) {
        lua.setTop(state, top);
        return;
    }
    POINT mouse{};
    GetCursorPos(&mouse);
    ScreenToClient(window, &mouse);
    RECT rect{};
    GetClientRect(window, &rect);
    const float width = read<float>(image, j460::globals::logicalWidth),
                height = read<float>(image, j460::globals::logicalHeight);
    lua.pushBoolean(state, menuAvailable());
    lua.pushBoolean(state, visible);
    lua.pushInteger(state, menuKey);
    lua.pushString(state, menuText.c_str());
    lua.pushNumber(state, rect.right ? mouse.x * width / rect.right : -1000);
    lua.pushNumber(state, rect.bottom ? mouse.y * height / rect.bottom : -1000);
    lua.pushBoolean(state, menuClick);
    lua.pushString(state, localAddresses.c_str());
    lua.pushString(state, error.c_str());
    if (invoke(9, 1))
        visible = lua.boolean(state, -1) != 0;
    else
        bridgeFailed = true;
    lua.setTop(state, top);
    menuKey = 0;
    menuClick = false;
    if (!visible)
        chat_input::endField();
}
void renderChat() {
    if (!state || bridgeFailed)
        return;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanChatRender") == luaFunction)
        invoke(0, 0);
    lua.setTop(state, top);
}
void __cdecl menuRender() {
    originalMenuRender();
    renderNativeMenu();
    renderChat();
}
void draw() {
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();
    map();
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}
BOOL WINAPI swap(HDC dc) {
    // Room::Init pumps a blank loading frame through SwapBuffers. Loading a
    // teammate's room must keep this viewport's last completed frame visible,
    // and must not re-enter the frontend/network update inside that transaction.
    if (rooms::backgroundLoading())
        return TRUE;
    if (!state)
        return originalSwap(dc);
    if (!guiReady) {
        window = WindowFromDC(dc);
        if (!window || !wglGetCurrentContext())
            return originalSwap(dc);
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        auto& io = ImGui::GetIO();
        io.IniFilename = nullptr;
        io.LogFilename = nullptr;
        if (!ImGui_ImplWin32_InitForOpenGL(window) || !ImGui_ImplOpenGL3_Init("#version 130")) {
            logger("frontend_error=renderer_init");
            return originalSwap(dc);
        }
        originalWndProc = reinterpret_cast<WNDPROC>(
            SetWindowLongPtrW(window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(events)));
        guiReady = true;
        logger("frontend_renderer=READY");
        localAddresses = addresses();
    }
    poll();
    draw();
    diagnostics::render();
    lab_capture::frame(labRoot);
    return originalSwap(dc);
}
void __cdecl close(lua_State* L) {
    if (state == L) {
        lab_capture::stop();
        state = nullptr;
        chat_input::reset();
        emotes::reset();
    }
    originalClose(L);
}
void __attribute__((fastcall)) init(void* engine, void*, bool debug) {
    originalInit(engine, debug);
    state = *reinterpret_cast<lua_State**>(reinterpret_cast<std::uintptr_t>(engine) +
                                           layout::luaEngine::state);
    const auto module = GetModuleHandleW(L"Lua5.3.3r.dll");
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        auto p = GetProcAddress(module, name);                                                     \
        memcpy(&lua.field, &p, sizeof(p));                                                         \
        if (!lua.field) {                                                                          \
            logger("frontend_error=missing_lua_api " name);                                        \
            state = nullptr;                                                                       \
            return;                                                                                \
        }                                                                                          \
    } while (false)
    IMPORT(createTable, "lua_createtable");
    IMPORT(getTop, "lua_gettop");
    IMPORT(setTop, "lua_settop");
    IMPORT(getGlobal, "lua_getglobal");
    IMPORT(setGlobal, "lua_setglobal");
    IMPORT(setField, "lua_setfield");
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(getField, "lua_getfield");
    IMPORT(rawGetI, "lua_rawgeti");
    IMPORT(integer, "lua_tointegerx");
    IMPORT(boolean, "lua_toboolean");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(pushNumber, "lua_pushnumber");
    IMPORT(string, "lua_tolstring");
    IMPORT(pushString, "lua_pushstring");
    IMPORT(load, "luaL_loadbufferx");
    IMPORT(pcall, "lua_pcallk");
#undef IMPORT
    const int top = lua.getTop(state);
    try {
        modSourceCache.clear();
        manifest();
        if (bindNative(state) != 1)
            throw std::runtime_error("Cannot bind native game interfaces");
        if (!chat_input::bind(state, module))
            throw std::runtime_error("Cannot bind chat input");
        if (!emotes::bind(state, module))
            throw std::runtime_error("Cannot bind original emotes");
        lua.createTable(state, 0, 7);
        for (const auto& [key, value] : {std::pair{"opacity", chatAppearance.opacity},
                                         {"background", chatAppearance.background},
                                         {"border", chatAppearance.border},
                                         {"text", chatAppearance.text},
                                         {"image_width", chatBackground.width},
                                         {"image_height", chatBackground.height}}) {
            lua.pushInteger(state, value);
            lua.setField(state, -2, key);
        }
        lua.pushString(state, chatBackground.animation.c_str());
        lua.setField(state, -2, "image");
        lua.setField(state, -2, "chat_style");
        // Ordinary launches omit the global debug library. Keep the sandbox
        // intact and expose only our source/upvalue inspection functions.
        const auto openDebug =
            std::bit_cast<int(__cdecl*)(lua_State*)>(GetProcAddress(module, "luaopen_debug"));
        if (!openDebug)
            throw std::runtime_error("Cannot initialize private Mod introspection");
        openDebug(state);
        lua.createTable(state, 0, 3);
        for (const auto name : {"getinfo", "getupvalue", "setupvalue"}) {
            lua.getField(state, -2, name);
            lua.setField(state, -2, name);
        }
        lua.setField(state, -3, "debug");
        lua.setTop(state, lua.getTop(state) - 1);
        lua.pushClosure(state, integrationNonce, 0);
        lua.setField(state, -2, "api_nonce");
        lua.pushClosure(state, integrationSetting, 0);
        lua.setField(state, -2, "api_setting");
        lua.pushClosure(state, modInfo, 0);
        lua.setField(state, -2, "api_mod_info");
        lua.pushClosure(state, configurationHash, 0);
        lua.setField(state, -2, "configuration_hash");
        lua.pushClosure(state, beginText, 0);
        lua.setField(state, -2, "menu_text_begin");
        lua.pushClosure(state, endText, 0);
        lua.setField(state, -2, "menu_text_end");
        lua.pushClosure(state, loadConnection, 0);
        lua.setField(state, -2, "menu_connection");
        lua.pushClosure(state, saveConnection, 0);
        lua.setField(state, -2, "menu_connection_save");
        lua.pushClosure(state, officialMenu, 0);
        lua.setField(state, -2, "menu_official");
        lua.setGlobal(state, "_IsaacLan");
        lua.pushString(state, fingerprint.c_str());
        lua.setGlobal(state, "_IsaacLanFingerprint");
        if (lua.load(state, predictionSource, sizeof(predictionSource) - 1,
                     "@isaac-lan/presentation/prediction.lua", "t") != 0 ||
            !invoke(0, 0))
            throw std::runtime_error("Cannot initialize local movement prediction");
        lua.createTable(state, 0, std::size(integrationModules));
        lua.setGlobal(state, "_IsaacLanModules");
        for (const auto& module : integrationModules) {
            lua.getGlobal(state, "_IsaacLanModules");
            if (lua.load(state, module.source, std::strlen(module.source), module.file, "t") != 0 ||
                !invoke(0, 1))
                throw std::runtime_error(std::string("Cannot load integration module ") +
                                         module.file);
            lua.setField(state, -2, module.name);
            lua.setTop(state, -2);
        }
        if (lua.load(state, stateSource, sizeof(stateSource) - 1, "@isaac-lan/app/world.lua",
                     "t") != 0 ||
            !invoke(0, 0))
            throw std::runtime_error("Cannot initialize authoritative state bridge");
        if (lua.load(state, bridgeSource, sizeof(bridgeSource) - 1, "@isaac-lan/app/main.lua",
                     "t") != 0 ||
            !invoke(0, 0))
            throw std::runtime_error("Cannot initialize embedded LAN bridge");
        if (lua.load(state, menuSource, sizeof(menuSource) - 1, "@isaac-lan/presentation/menu.lua",
                     "t") != 0 ||
            !invoke(0, 0))
            throw std::runtime_error("Cannot initialize native LAN menu");
        logger("frontend_bridge=READY manifest=" + fingerprint);
        const auto scenario = std::filesystem::path(labRoot) / L"frontend-scenario.lua";
        if (std::filesystem::exists(std::filesystem::path(labRoot) / L".isaac-lan-lab") &&
            std::filesystem::exists(scenario)) {
            std::ifstream stream(scenario, std::ios::binary);
            const std::string source((std::istreambuf_iterator<char>(stream)),
                                     std::istreambuf_iterator<char>());
            if (lua.load(state, source.data(), source.size(), "@isolated-frontend-scenario.lua",
                         "t") != 0 ||
                !invoke(0, 0))
                throw std::runtime_error("Isolated frontend scenario failed to initialize");
        }
    } catch (const std::exception& e) {
        error = e.what();
        bridgeFailed = true;
        logger("frontend_error=" + error);
    }
    lua.setTop(state, top);
    if (!originalClose) {
        auto fn = GetProcAddress(module, "lua_close");
        if (MH_CreateHook(reinterpret_cast<void*>(fn), reinterpret_cast<void*>(close),
                          reinterpret_cast<void**>(&originalClose)) == MH_OK)
            MH_EnableHook(reinterpret_cast<void*>(fn));
    }
}
} // namespace
void prepareView() {
    if (!originalMapCache || runtime::localViewSlot() < 0)
        return;
    // CacheMap clears an offscreen target and flushes the shared native draw
    // queue. Rebuilding it inside Minimap::Render would consume the room's
    // pending scene into that texture, leaving a black scene and map smears.
    // Resolve the local view before Game::Render starts submitting that scene.
    rooms::withView([&] {
        const auto game = read<std::uintptr_t>(image, j460::globals::game);
        for (unsigned i = 0; i < 2; ++i)
            if (mapAnchors[i].index != read<int>(game, layout::game::roomIndex) ||
                mapAnchors[i].dimension != read<int>(game, layout::game::dimension))
                mapCache(
                    reinterpret_cast<void*>(game + layout::game::minimap +
                                            (i ? layout::minimap::large : layout::minimap::small)),
                    nullptr);
    });
}
void render() {
    renderNativeMenu();
    renderChat();
}
bool capturesInput() {
    return visible || chat_input::capturesInput();
}
void configureChat(const chat::Appearance& appearance,
                   const presentation::ChatBackground& background) {
    chatAppearance = appearance;
    chatBackground = background;
}
void configureConnection(const std::filesystem::path& path) {
    connectionPath = path;
    connectionSettings = presentation::loadConnectionSettings(path);
}
void returnToLobby() {
    lobbyRequested = true;
}
bool install(std::uintptr_t base, const std::wstring& root, void (*log)(const std::string&),
             int(__cdecl* bind)(lua_State*), bool installed) {
    image = base;
    labRoot = root;
    logger = log;
    bindNative = bind;
    if (!emotes::install(image))
        return false;
    if (MH_CreateHookApi(L"gdi32.dll", "SwapBuffers", reinterpret_cast<void*>(swap),
                         reinterpret_cast<void**>(&originalSwap)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(
            GetProcAddress(GetModuleHandleW(L"gdi32.dll"), "SwapBuffers"))) != MH_OK)
        return false;
    if (!installed &&
        GetFileAttributesW((root + L"\\frontend.test").c_str()) == INVALID_FILE_ATTRIBUTES)
        return true;
    auto target = reinterpret_cast<void*>(image + j460::entry::luaEngineInit);
    return MH_CreateHook(target, reinterpret_cast<void*>(init),
                         reinterpret_cast<void**>(&originalInit)) == MH_OK &&
           MH_EnableHook(target) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::frontendStatHUDGetPlayerId),
                         reinterpret_cast<void*>(statPlayerId),
                         reinterpret_cast<void**>(&originalStatPlayerId)) == MH_OK &&
           MH_EnableHook(
               reinterpret_cast<void*>(image + j460::entry::frontendStatHUDGetPlayerId)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::hUDUpdate),
                         reinterpret_cast<void*>(hudUpdate),
                         reinterpret_cast<void**>(&originalHudUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::hUDUpdate)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::hUDPostUpdate),
                         reinterpret_cast<void*>(hudPostUpdate),
                         reinterpret_cast<void**>(&originalHudPostUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::hUDPostUpdate)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::hUDRender),
                         reinterpret_cast<void*>(hudRender),
                         reinterpret_cast<void**>(&originalHudRender)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::hUDRender)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::historyHUDGetPlayerId),
                         reinterpret_cast<void*>(historyPlayerId),
                         reinterpret_cast<void**>(&originalHistoryPlayerId)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::historyHUDGetPlayerId)) ==
               MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::minimapUpdate),
                         reinterpret_cast<void*>(minimapUpdate),
                         reinterpret_cast<void**>(&originalMinimapUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::minimapUpdate)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::minimapRender),
                         reinterpret_cast<void*>(minimapRender),
                         reinterpret_cast<void**>(&originalMapRender)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::minimapRender)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::minimapCache),
                         reinterpret_cast<void*>(mapCache),
                         reinterpret_cast<void**>(&originalMapCache)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::minimapCache)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::menuManagerRender),
                         reinterpret_cast<void*>(menuRender),
                         reinterpret_cast<void**>(&originalMenuRender)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::menuManagerRender)) ==
               MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::menuGameUpdate),
                         reinterpret_cast<void*>(gameMenuUpdate),
                         reinterpret_cast<void**>(&originalGameMenuUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::menuGameUpdate)) == MH_OK;
}
} // namespace isaac::frontend
