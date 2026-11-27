#pragma once
#include <atomic>
#include <cstdint>
#include <string_view>
#include <windows.h>

class ISteamNetworkingSockets;
class ISteamNetworkingUtils;
namespace isaac::lan::steam {
using Id = std::uint64_t;
using Call = std::uint64_t;
constexpr unsigned gameApp = 250900;
constexpr int privateLobby = 0, publicLobby = 2;
constexpr int listResult = 510, createResult = 513, enterResult = 504, joinRequested = 333;
struct LobbyCreated {
    int result;
    Id lobby;
};
struct LobbyEntered {
    Id lobby;
    unsigned permissions;
    bool locked;
    unsigned response;
};
static_assert(sizeof(LobbyCreated) == 16 && sizeof(LobbyEntered) == 24);

// The game owns SteamAPI_Init/Shutdown and the callback pump. Only bind public
// functions exported by the steam_api.dll it has already loaded.
struct Api {
    ISteamNetworkingSockets* sockets = nullptr;
    ISteamNetworkingUtils* networkingUtils = nullptr;
    void *match = nullptr, *friends = nullptr, *utils = nullptr;
    Id local = 0;
    HMODULE library = nullptr;
    int (*currentPipe)() = nullptr;
    bool alive() const;
    const char* bindStage = "library";
    bool bind();
    Call (*create)(void*, int, int) = nullptr;
    Call (*join)(void*, Id) = nullptr;
    void (*leave)(void*, Id) = nullptr;
    void (*filter)(void*, const char*, const char*, int) = nullptr;
    void (*distance)(void*, int) = nullptr;
    void (*limit)(void*, int) = nullptr;
    Call (*list)(void*) = nullptr;
    Id (*byIndex)(void*, int) = nullptr;
    Id (*owner)(void*, Id) = nullptr;
    int (*members)(void*, Id) = nullptr;
    Id (*member)(void*, Id, int) = nullptr;
    bool (*requestData)(void*, Id) = nullptr;
    bool (*set)(void*, Id, const char*, const char*) = nullptr;
    const char* (*get)(void*, Id, const char*) = nullptr;
    bool (*setType)(void*, Id, int) = nullptr;
    bool (*joinable)(void*, Id, bool) = nullptr;
    bool (*overlay)(void*) = nullptr;
    void (*invite)(void*, Id) = nullptr;
    const char* (*name)(void*) = nullptr;
    bool (*completed)(void*, Call, bool*) = nullptr;
    bool (*result)(void*, Call, void*, int, int, bool*) = nullptr;
    void (*subscribe)(void*, int) = nullptr;
    void (*unsubscribe)(void*) = nullptr;
};
// CCallbackBase ABI in the Windows x86 Steam client. MSVC places the
// three-argument overload of Run first. Distinct names preserve this order
// under MinGW. No virtual destructor is present in the SDK interface.
class Callback {
  public:
    virtual void callResult(void* data, bool failed, Call);
    virtual void event(void* data) = 0;
    virtual int size() = 0;
    std::uint8_t flags = 0;
    int callback;
    explicit Callback(int id) : callback(id) {}
};
class InviteCallback : public Callback {
  public:
    InviteCallback() : Callback(joinRequested) {}
    void event(void* data) override;
    int size() override;
    std::atomic<Id> pending{0};
};
std::uint64_t parseId(std::string_view value);
} // namespace isaac::lan::steam
