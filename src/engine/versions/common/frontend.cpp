#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include "engine/frontend.h"
#include "app/content_hash.h"
#include "app/bridge_manifest.h"
#include "engine/lua_api.h"
#include "presentation/chat_input.h"
#include "presentation/main_menu.h"
#include "engine/emotes.h"
#include "engine/build.h"
#include "engine/module_path.h"
#include "runtime/session.h"
#include "runtime/update_notice.h"
#include "core/extension_package.h"
#include "core/room_options.h"
#include "engine/rooms.h"
#include "engine/input.h"
#include "net/host_address.h"
#include "presentation/connection_settings.h"
#include "app/lua_bridge.h"
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
#include "engine/versions/common/frontend_hud.h"
#include "engine/versions/common/minimap.h"
#include "engine/versions/common/frontend_bindings.h"
#include "core/input_actions.h"

namespace isaac::frontend {
using engine::native_frontend::bindings;
namespace menu_context = engine::native_menu;
namespace main_rows = presentation::main_menu;
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
isaac::lua::API lua;
bool bridgeFailed = false, visible = false, guiReady = false;
bool officialRequested = false;
std::optional<main_rows::Position> mainPaper;
enum class MainMenuPointer { none, hover, confirm };
MainMenuPointer mainPointer = MainMenuPointer::none;
std::string error, fingerprint, modFingerprint;
int count = 0, draining = 0;
bool prepared = false;
bool lobbyRequested = false;
bool closeRequested = false, closeSent = false, closeReady = false;
int menuKey = 0;
bool menuClick = false;
bool releaseUpdateInput = false;
std::string menuText;
using MenuRender = void(__cdecl*)();
MenuRender originalMenuRender;
using MenuUpdate = void(__attribute__((thiscall)) *)(void*);
MenuUpdate originalGameMenuUpdate;
engine::native_frontend::DrawMainMenu originalGameMenuRender;
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
using Location = engine::native_minimap::Location;
std::array<Location, lan::maxPlayers> positions;
HWND window;
WNDPROC originalWndProc;
using Swap = BOOL(WINAPI*)(HDC);
Swap originalSwap;
using Init = void(__attribute__((thiscall)) *)(void*, bool);
Init originalInit;
using Close = void(__cdecl*)(lua_State*);
Close originalClose;
bool invoke(int nargs, int results);
template <class T> T& read(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
bool menuAvailable() {
    return menu_context::ready(image, bindings.menu);
}
bool updateNoticeVisible() {
    if (!state || bridgeFailed || visible || !menuAvailable() ||
        updates::startupNotice().version().empty())
        return false;
    const auto manager = read<std::uintptr_t>(image, bindings.menu.manager);
    const auto menus = read<std::uintptr_t>(image, bindings.menu.menus);
    return !read<bool>(menus, bindings.menu.inputBlocked) &&
           read<unsigned>(manager, bindings.menu.managerInputBlock) == 0;
}
int updateContinue(lua_State*) {
    if (updateNoticeVisible()) {
        updates::startupNotice().dismiss();
        releaseUpdateInput = true;
        menuKey = 0;
        menuClick = false;
        logger("update_notice=CONTINUE");
    }
    return 0;
}
int updateExit(lua_State* L) {
    const bool sent = updateNoticeVisible() && window && PostMessageW(window, WM_CLOSE, 0, 0);
    if (sent) {
        updates::startupNotice().dismiss();
        logger("update_notice=EXIT");
    }
    lua.pushBoolean(L, sent);
    return 1;
}
int testUpdateNotice(lua_State* L) {
    const auto* value = lua.toString(L, 1, nullptr);
    if (value && updates::parseVersion(value)) {
        const std::string version = value;
        updates::startupNotice() = updates::Notice([version] { return version; });
        releaseUpdateInput = false;
    }
    return 0;
}
void captureMenuKey() {
    for (const auto& [action, key] : {std::pair{input::action::menuConfirm, VK_RETURN},
                                      {input::action::menuBack, VK_ESCAPE},
                                      {input::action::menuLeft, VK_LEFT},
                                      {input::action::menuRight, VK_RIGHT},
                                      {input::action::menuUp, VK_UP},
                                      {input::action::menuDown, VK_DOWN},
                                      {input::action::menuRightShoulder, 'E'}})
        if (input::menuTriggered(action)) {
            menuKey = key;
            break;
        }
}
bool updateInputReleased() {
    for (const auto action :
         {input::action::menuConfirm, input::action::menuBack, input::action::menuLeft,
          input::action::menuRight, input::action::menuUp, input::action::menuDown})
        if (input::menuHeld(action))
            return false;
    return (GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0;
}
int beginText(lua_State* L) {
    const char* value = lua.toString(L, 1, nullptr);
    const char* field = lua.toString(L, 2, nullptr);
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
    const auto* address = lua.toString(L, 1, &size);
    const auto port = lua.toInteger(L, 2, nullptr);
    if (!address || size > lan::maxHostAddressLength || port < 1 || port > 65535)
        return 0;
    const presentation::ConnectionSettings next{
        std::string(address, size), static_cast<unsigned>(port), connectionSettings.roomOptions};
    if (next != connectionSettings) {
        if (presentation::saveConnectionSettings(connectionPath, next))
            connectionSettings = next;
        else
            logger("connection_settings_save=FAIL");
    }
    return 0;
}
int loadRoomOptions(lua_State* L) {
    lua.pushInteger(L, connectionSettings.roomOptions);
    return 1;
}
int saveRoomOptions(lua_State* L) {
    auto next = connectionSettings;
    next.roomOptions =
        roomOptions::normalize(static_cast<std::uint64_t>(lua.toInteger(L, 1, nullptr)));
    const bool saved =
        roomOptions::valid(next.roomOptions) &&
        (next == connectionSettings || presentation::saveConnectionSettings(connectionPath, next));
    if (saved)
        connectionSettings = next;
    else
        logger("room_options_save=FAIL");
    lua.pushBoolean(L, saved);
    return 1;
}
int officialMenu(lua_State*) {
    officialRequested = true;
    return 0;
}
void openMenu();
void __attribute__((fastcall)) gameMenuUpdate(void* menu, void*) {
    if (!state || bridgeFailed || !menuAvailable()) {
        mainPointer = MainMenuPointer::none;
        originalGameMenuUpdate(menu);
        return;
    }
    if (releaseUpdateInput) {
        releaseUpdateInput = !updateInputReleased();
        return;
    }
    if (visible)
        updates::startupNotice().dismiss();
    else {
        const bool showing = updateNoticeVisible();
        updates::startupNotice().poll();
        if (updateNoticeVisible()) {
            if (!showing) {
                menuKey = 0;
                menuClick = false;
                logger("update_notice=READY version=" + updates::startupNotice().version());
            } else
                captureMenuKey();
            return;
        }
    }
    if (officialRequested && bindings.menu.onlineSelection) {
        officialRequested = false;
        visible = false;
        chat_input::endField();
        input::leaveLan();
        input::confirmOriginalMenu(menu, originalGameMenuUpdate);
        logger("native_online_entry=OFFICIAL");
        return;
    }
    if (!visible) {
        bool confirm = input::menuTriggered(input::action::menuConfirm);
        if (mainPointer != MainMenuPointer::none && mainPaper &&
            menu_context::acceptsInput(image, bindings.menu)) {
            read<int>(reinterpret_cast<std::uintptr_t>(menu), bindings.menu.selection) =
                main_rows::online;
            confirm |= mainPointer == MainMenuPointer::confirm;
        }
        mainPointer = MainMenuPointer::none;
        if ((bindings.menu.onlineSelection || mainPaper) &&
            menu_context::entrySelected(image, bindings.menu, menu, confirm)) {
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
    captureMenuKey();
}

int configurationHash(lua_State* L) {
    std::size_t size = 0;
    const auto data = lua.toString(L, 1, &size);
    if (!data || size > 16 * 1024 * 1024 || modFingerprint.empty()) {
        lua.pushString(L, "");
        return 1;
    }
    try {
        app::ContentHash hash;
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
    const auto key = lua.toString(L, 1, nullptr);
    if (!key || std::strlen(key) > 80 ||
        std::strspn(key, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-") !=
            std::strlen(key))
        return 0;
    wchar_t executable[32768]{};
    GetModuleFileNameW(nullptr, executable, std::size(executable));
    const auto path =
        std::filesystem::path(executable).parent_path() / L"isaac-lan" / L"integrations.ini";
    if (lua.getTop(L) >= 2) {
        std::string value = lua.toBoolean(L, 2) ? "1" : "0";
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
    const auto input = lua.toString(L, 1, nullptr);
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
            app::ContentHash hash;
            hash.text("Isaac LAN/compat-source-v1");
            for (const auto& file : files) {
                hash.text(fs::relative(file, root).generic_string());
                app::ContentHash entry;
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
    wchar_t executable[32768]{};
    if (!GetModuleFileNameW(nullptr, executable, std::size(executable)))
        throw std::runtime_error("Cannot locate game directory");
    auto value = app::buildManifest(std::filesystem::path(executable).parent_path(),
                                    build::version(), logger, engine::modulePath(&fingerprint));
    fingerprint = std::move(value.fingerprint);
    modFingerprint = std::move(value.mods);
}
bool invoke(int nargs, int results) {
    if (lua.pcall(state, nargs, results, 0, 0, nullptr) == 0)
        return true;
    const char* reason = lua.toString(state, -1, nullptr);
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
    const auto n = lua.toInteger(state, -1, nullptr);
    lua.setTop(state, -2);
    return static_cast<int>(n);
}
bool boolean(const char* name) {
    lua.getField(state, -1, name);
    const bool n = lua.toBoolean(state, -1) != 0;
    lua.setTop(state, -2);
    return n;
}
std::string string(const char* name) {
    lua.getField(state, -1, name);
    const auto s = lua.toString(state, -1, nullptr);
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
    count = std::clamp(number("players"), 0, static_cast<int>(lan::maxPlayers));
    const auto phase = static_cast<lan::Phase>(number("phase"));
    if (phase != lan::Phase::idle && phase != lan::Phase::failed && phase != lan::Phase::closed)
        updates::startupNotice().dismiss();
    prepared = boolean("prepared");
    draining = number("draining");
    error = string("error");
    if (lobbyRequested && !prepared && menu_context::returnToMain(image, bindings.menu)) {
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
    engine::native_minimap::setPlayers(prepared, count, positions);
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
bool mainMenuPointer(HWND h, LPARAM coordinates, bool confirm) {
    if (!mainPaper || !state || bridgeFailed || visible || updateNoticeVisible() ||
        !menu_context::acceptsInput(image, bindings.menu))
        return false;
    RECT client{};
    if (!GetClientRect(h, &client) || !client.right || !client.bottom)
        return false;
    const auto width = read<float>(image, bindings.logicalWidth),
               height = read<float>(image, bindings.logicalHeight);
    const float x = static_cast<short>(LOWORD(coordinates)) * width / client.right;
    const float y = static_cast<short>(HIWORD(coordinates)) * height / client.bottom;
    if (!main_rows::hitsOnline(*mainPaper, x, y))
        return false;
    if (mainPointer != MainMenuPointer::confirm)
        mainPointer = confirm ? MainMenuPointer::confirm : MainMenuPointer::hover;
    return true;
}
LRESULT CALLBACK events(HWND h, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_CLOSE && !closeReady && (prepared || draining || closeRequested)) {
        closeRequested = true;
        return 0;
    }
    if (updateNoticeVisible() && message == WM_LBUTTONDOWN) {
        menuClick = true;
        return 0;
    }
    if (const auto handled = chat_input::event(h, message, w, l))
        return *handled;
    if ((message == WM_MOUSEMOVE || message == WM_LBUTTONDOWN) &&
        mainMenuPointer(h, l, message == WM_LBUTTONDOWN) && message == WM_LBUTTONDOWN)
        return 0;
    if (visible && message == WM_LBUTTONDOWN)
        menuClick = true;
    return CallWindowProcW(originalWndProc, h, message, w, l);
}
void map() {
    const auto& markers = engine::native_minimap::frameMarkers();
    if (prepared && !markers.empty()) {
        const auto display = ImGui::GetIO().DisplaySize;
        const float logicalWidth = read<float>(image, bindings.logicalWidth);
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
            ImVec2 pos(marker.x, marker.y);
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
    engine::native_minimap::clearMarkers();
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
    const float width = read<float>(image, bindings.logicalWidth),
                height = read<float>(image, bindings.logicalHeight);
    lua.pushBoolean(state, menuAvailable());
    lua.pushBoolean(state, visible);
    lua.pushInteger(state, menuKey);
    lua.pushString(state, menuText.c_str());
    lua.pushNumber(state, rect.right ? mouse.x * width / rect.right : -1000);
    lua.pushNumber(state, rect.bottom ? mouse.y * height / rect.bottom : -1000);
    lua.pushBoolean(state, menuClick);
    lua.pushString(state, localAddresses.c_str());
    lua.pushString(state, error.c_str());
    lua.pushString(state, updateNoticeVisible() ? updates::startupNotice().version().c_str() : "");
    lua.pushBoolean(state, updateNoticeVisible() && updateInputReleased());
    if (invoke(11, 1))
        visible = lua.toBoolean(state, -1) != 0;
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
void __attribute__((fastcall)) gameMenuRender(void* menu, void*) {
    if (!state || bridgeFailed) {
        originalGameMenuRender(menu);
        return;
    }
    const auto paper = bindings.insertedRow->draw(image, menu, originalGameMenuRender);
    if (!paper || !main_rows::labelVisible(*paper, read<float>(image, bindings.logicalWidth),
                                           read<float>(image, bindings.logicalHeight)))
        return;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanMainMenuEntry") == luaFunction) {
        lua.pushNumber(state, paper->x + main_rows::labelX);
        lua.pushNumber(state, paper->y + main_rows::labelY);
        if (invoke(2, 0))
            mainPaper = paper;
        else
            bridgeFailed = true;
    }
    lua.setTop(state, top);
}
void __cdecl menuRender() {
    mainPaper.reset();
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
    const auto manager = read<std::uintptr_t>(image, bindings.menu.manager);
    if (manager && !engine::native_menu::selectedProfile(image, bindings.menu))
        updates::startupNotice().dismiss();
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
        engine::native_minimap::setPlayers(false, 0, {});
    }
    originalClose(L);
}
void __attribute__((fastcall)) init(void* engine, void*, bool debug) {
    originalInit(engine, debug);
    bridgeFailed = false;
    visible = officialRequested = false;
    mainPaper.reset();
    mainPointer = MainMenuPointer::none;
    menuKey = 0;
    menuClick = false;
    menuText.clear();
    error.clear();
    chat_input::reset();
    engine::native_minimap::setPlayers(false, 0, {});
    state = *reinterpret_cast<lua_State**>(reinterpret_cast<std::uintptr_t>(engine) +
                                           bindings.luaState);
    const auto module = GetModuleHandleA(isaac::engine::profile().luaModule);
    using Symbol = isaac::lua::Symbol;
    if (!lua.load(module,
                  {Symbol::createTable, Symbol::getTop, Symbol::setTop, Symbol::getGlobal,
                   Symbol::setGlobal, Symbol::setField, Symbol::pushClosure, Symbol::getField,
                   Symbol::rawGetI, Symbol::toInteger, Symbol::toBoolean, Symbol::pushBoolean,
                   Symbol::pushInteger, Symbol::pushNumber, Symbol::toString, Symbol::pushString,
                   Symbol::loadBuffer, Symbol::pcall})) {
        logger("frontend_error=missing_lua_api");
        state = nullptr;
        return;
    }
    const int top = lua.getTop(state);
    try {
        modSourceCache.clear();
        manifest();
        if (bindNative(state) != 1)
            throw std::runtime_error("Cannot bind native game interfaces");
        if (!chat_input::bind(state, module))
            throw std::runtime_error("Cannot bind chat input");
        if (engine::profile().capabilities.nativeEmotes && !emotes::bind(state, module))
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
        lua.pushClosure(state, loadRoomOptions, 0);
        lua.setField(state, -2, "menu_room_options");
        lua.pushClosure(state, saveRoomOptions, 0);
        lua.setField(state, -2, "menu_room_options_save");
        if (bindings.menu.onlineSelection) {
            lua.pushClosure(state, officialMenu, 0);
            lua.setField(state, -2, "menu_official");
        }
        lua.createTable(state, 0, 1);
        lua.pushBoolean(state, engine::profile().capabilities.nativeEmotes);
        lua.setField(state, -2, "native_emotes");
        lua.setField(state, -2, "capabilities");
        lua.pushClosure(state, updateContinue, 0);
        lua.setField(state, -2, "update_continue");
        lua.pushClosure(state, updateExit, 0);
        lua.setField(state, -2, "update_exit");
        if (std::filesystem::exists(std::filesystem::path(labRoot) / L".isaac-lan-lab")) {
            lua.pushClosure(state, testUpdateNotice, 0);
            lua.setField(state, -2, "test_update_notice");
        }
        lua.setGlobal(state, "_IsaacLan");
        lua.pushString(state, fingerprint.c_str());
        lua.setGlobal(state, "_IsaacLanFingerprint");
        app::loadBridge(state, lua, invoke, connectionPath.parent_path());
        logger("frontend_bridge=READY manifest=" + fingerprint);
        const auto scenario = std::filesystem::path(labRoot) / L"frontend-scenario.lua";
        if (std::filesystem::exists(std::filesystem::path(labRoot) / L".isaac-lan-lab") &&
            std::filesystem::exists(scenario)) {
            std::ifstream stream(scenario, std::ios::binary);
            const std::string source((std::istreambuf_iterator<char>(stream)),
                                     std::istreambuf_iterator<char>());
            if (lua.loadBuffer(state, source.data(), source.size(),
                               "@isolated-frontend-scenario.lua", "t") != 0 ||
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
    engine::native_minimap::prepareView();
}
const std::vector<presentation::MinimapView>& minimapViews() {
    return engine::native_minimap::minimapViews();
}

void render() {
    renderNativeMenu();
    renderChat();
}
bool capturesInput() {
    return visible || updateNoticeVisible() || chat_input::capturesInput();
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
    if (engine::profile().capabilities.nativeEmotes && !emotes::install(image))
        return false;
    if (MH_CreateHookApi(L"gdi32.dll", "SwapBuffers", reinterpret_cast<void*>(swap),
                         reinterpret_cast<void**>(&originalSwap)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(
            GetProcAddress(GetModuleHandleW(L"gdi32.dll"), "SwapBuffers"))) != MH_OK)
        return false;
    if (!installed &&
        GetFileAttributesW((root + L"\\frontend.test").c_str()) == INVALID_FILE_ATTRIBUTES)
        return true;
    auto target = reinterpret_cast<void*>(image + bindings.luaInit);
    return MH_CreateHook(target, reinterpret_cast<void*>(init),
                         reinterpret_cast<void**>(&originalInit)) == MH_OK &&
           MH_EnableHook(target) == MH_OK && engine::native_frontend_hud::install(image) &&
           engine::native_minimap::install(
               image,
               [] {
                   if (state && !bridgeFailed && prepared) {
                       const int top = lua.getTop(state);
                       if (lua.getGlobal(state, "_IsaacLanMinimapRender") == luaFunction)
                           invoke(0, 0);
                       lua.setTop(state, top);
                   }
               }) &&
           MH_CreateHook(reinterpret_cast<void*>(image + bindings.menuRender),
                         reinterpret_cast<void*>(menuRender),
                         reinterpret_cast<void**>(&originalMenuRender)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + bindings.menuRender)) == MH_OK &&
           (!bindings.insertedRow ||
            (MH_CreateHook(reinterpret_cast<void*>(image + bindings.insertedRow->drawMainMenu),
                           reinterpret_cast<void*>(gameMenuRender),
                           reinterpret_cast<void**>(&originalGameMenuRender)) == MH_OK &&
             MH_EnableHook(reinterpret_cast<void*>(image + bindings.insertedRow->drawMainMenu)) ==
                 MH_OK)) &&
           MH_CreateHook(reinterpret_cast<void*>(image + bindings.menuUpdate),
                         reinterpret_cast<void*>(gameMenuUpdate),
                         reinterpret_cast<void**>(&originalGameMenuUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + bindings.menuUpdate)) == MH_OK &&
           (!bindings.insertedRow || bindings.insertedRow->installNavigation(image));
}
} // namespace isaac::frontend
