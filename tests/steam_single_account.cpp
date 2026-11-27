#include "net/steam_rooms.h"
#include "test_support.h"
#include <isteamnetworkingsockets.h>
#include <chrono>
#include <cstring>

using namespace isaac::lan;
using namespace isaac::lan::steam;
namespace {
// Opt-in executable mode only. In the actual game the base executable owns both
// initialization and dispatch. An adjacent stock steam_api.dll selects the build.
struct SteamClient {
    HMODULE library =
        LoadLibraryExW(L"steam_api.dll", nullptr,
                       LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    void (*pump)() = nullptr;
    void (*shutdown)() = nullptr;
    template <class F> F symbol(const char* name) {
        auto address = GetProcAddress(library, name);
        require(address, "Missing steam_api.dll export");
        F fn;
        std::memcpy(&fn, &address, sizeof(fn));
        return fn;
    }
    SteamClient() {
        require(library, "Place the game's stock steam_api.dll next to the probe");
        pump = symbol<void (*)()>("SteamAPI_RunCallbacks");
        shutdown = symbol<void (*)()>("SteamAPI_Shutdown");
        require(symbol<bool (*)()>("SteamAPI_InitSafe")(), "Steam initialization failed");
    }
    ~SteamClient() {
        shutdown();
        FreeLibrary(library);
    }
};
} // namespace
void singleAccount() {
    SteamClient client;
    Api api;
    require(api.bind(), "Steam interfaces unavailable");
    Rooms rooms, browser;
    bool inLobby = true;
    const BuildIdentity build{"single-account-test",
                              "isolated-" + std::to_string(GetCurrentProcessId())};
    const std::array seats{accountIdentity(api.local)};
    auto poll = [&] {
        client.pump();
        rooms.poll(build, inLobby, seats, nullptr);
        browser.poll(build, true, {}, nullptr);
    };
    auto wait = [&](auto done) {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30);
        while (std::chrono::steady_clock::now() < deadline) {
            poll();
            require(rooms.failure().empty(), rooms.failure().c_str());
            require(browser.failure().empty(), browser.failure().c_str());
            if (done())
                return;
            Sleep(10);
        }
        throw std::runtime_error("Timed out waiting for Steam");
    };
    poll();
    require(rooms.create(), "Could not request private room");
    wait([&] { return rooms.hosting(); });
    require(!rooms.isPublic(), "Room did not start private");
    SteamNetworkingIdentity self{};
    self.SetSteamID64(api.local);
    const auto peer = api.sockets->ConnectP2P(self, virtualPort, 0, nullptr);
    require(peer, "Steam rejected the local P2P connection");
    struct Connection {
        ISteamNetworkingSockets* sockets;
        HSteamNetConnection handle;
        void close() {
            if (handle)
                sockets->CloseConnection(handle, k_ESteamNetConnectionEnd_App_Generic, nullptr,
                                         false);
            handle = k_HSteamNetConnection_Invalid;
        }
        ~Connection() {
            close();
        }
    } connection{api.sockets, peer};
    auto waitConnected = [&](HSteamNetConnection handle) {
        require(handle, "Steam rejected the P2P connection");
        wait([&] {
            SteamNetConnectionInfo_t info{};
            return api.sockets->GetConnectionInfo(handle, &info) &&
                   info.m_eState == k_ESteamNetworkingConnectionState_Connected;
        });
    };
    waitConnected(peer);
    const std::array<std::uint8_t, 5> sent{2, 3, 5, 7, 11};
    require(api.sockets->SendMessageToConnection(peer, sent.data(), sent.size(),
                                                 k_nSteamNetworkingSend_UnreliableNoDelay,
                                                 nullptr) == k_EResultOK,
            "Could not send local P2P message");
    std::array<std::uint8_t, 5> received{};
    Id source{};
    wait([&] {
        return rooms.route()->receive(source, received) == static_cast<int>(received.size());
    });
    require(source == api.local && received == sent, "Incoming authenticated datagram mismatch");
    require(rooms.route()->send(source, sent) == static_cast<int>(sent.size()),
            "Could not reply to local peer");
    SteamNetworkingMessage_t* message{};
    wait([&] { return api.sockets->ReceiveMessagesOnConnection(peer, &message, 1) == 1; });
    const bool matches = static_cast<size_t>(message->m_cbSize) == sent.size() &&
                         !std::memcmp(message->m_pData, sent.data(), sent.size());
    message->Release();
    require(matches, "Outgoing local datagram mismatch");
    std::printf("Private Steam P2P round trip%s\n", rooms.route()->diagnostics().c_str());
    require(browser.browse(), "Could not request public room list");
    wait([&] { return !browser.busy(); });
    require(browser.rooms().empty(), "Private test room was discoverable");
    require(rooms.visibility(), "Could not publish the test room");
    auto nextBrowse = std::chrono::steady_clock::now();
    wait([&] {
        const auto& list = browser.rooms();
        if (!list.empty() && list.front().pingMs) {
            std::printf("Public room browser estimated %d ms before joining\n",
                        *list.front().pingMs);
            return true;
        }
        const auto now = std::chrono::steady_clock::now();
        if (list.empty() && !browser.busy() && now >= nextBrowse) {
            require(browser.browse(), "Could not refresh public room list");
            nextBrowse = now + std::chrono::seconds(2);
        }
        return false;
    });
    const auto room = browser.rooms().front().id;
    auto currentConnect = [&]() -> std::string {
        const auto* value = api.getPresence(api.friends, api.local, "connect");
        return value ? value : "";
    };
    const auto previousConnect = currentConnect();
    inLobby = false;
    wait([&] { return lobbyFromConnect(currentConnect()) == room; });
    require(browser.browse(), "Cannot query Steam while host is playing");
    nextBrowse = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    wait([&] {
        if (browser.busy())
            return false;
        if (browser.rooms().empty())
            return true;
        // Steam's matchmaking index can return a cached public listing just after a type change.
        const auto now = std::chrono::steady_clock::now();
        if (now >= nextBrowse) {
            require(browser.browse(), "Could not refresh the running room search");
            nextBrowse = now + std::chrono::seconds(2);
        }
        return false;
    });
    std::puts("Steam Friends exposes the running lobby invite; public search excludes it");
    connection.close();
    Connection returning{api.sockets, api.sockets->ConnectP2P(self, virtualPort, 0, nullptr)};
    waitConnected(returning.handle);
    const std::array<std::uint8_t, 5> afterExit{13, 17, 19, 23, 29};
    require(api.sockets->SendMessageToConnection(
                returning.handle, afterExit.data(), afterExit.size(),
                k_nSteamNetworkingSend_UnreliableNoDelay, nullptr) == k_EResultOK,
            "Could not send on the replacement Steam connection");
    wait([&] {
        return rooms.route()->receive(source, received) == static_cast<int>(received.size());
    });
    require(source == api.local && received == afterExit, "Reserved account lost its new datagram");
    std::puts("Reserved account reconnected over Steam P2P while the room was closed to new joins");
    rooms.leave();
    require(previousConnect == currentConnect(), "Steam connect presence remained after leaving");
}
