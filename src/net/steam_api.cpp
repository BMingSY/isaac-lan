#include "net/steam_api.h"
#include <isteamnetworkingsockets.h>
#include <isteamnetworkingutils.h>
#include <charconv>
#include <cstring>

namespace isaac::lan::steam {
namespace {
template <class F> bool load(HMODULE library, F& fn, const char* name) {
    auto symbol = GetProcAddress(library, name);
    static_assert(sizeof(fn) == sizeof(symbol));
    std::memcpy(&fn, &symbol, sizeof(fn));
    return fn != nullptr;
}
std::string localLocation(ISteamNetworkingUtils* utils) {
    SteamNetworkPingLocation_t location{};
    if (utils->GetLocalPingLocation(location) < 0)
        return {};
    char text[k_cchMaxSteamNetworkingPingLocationString]{};
    utils->ConvertPingLocationToString(location, text, sizeof(text));
    return text;
}
std::optional<int> estimateFromLocal(ISteamNetworkingUtils* utils, const char* text) {
    SteamNetworkPingLocation_t location{};
    if (!text || !*text || std::strlen(text) >= k_cchMaxSteamNetworkingPingLocationString ||
        !utils->ParsePingLocationString(text, location))
        return std::nullopt;
    const int estimate = utils->EstimatePingTimeFromLocalHost(location);
    return estimate < 0 ? std::nullopt : std::optional{estimate};
}
} // namespace
bool Api::alive() const {
    return !currentPipe || (library == GetModuleHandleW(L"steam_api.dll") && currentPipe() != 0);
}
bool Api::bind() {
    library = GetModuleHandleW(L"steam_api.dll");
    bindStage = library ? "client_exports" : "library";
    void* (*client)();
    int (*user)(), (*pipe)();
    void* (*generic)(void*, int, int, const char*);
    decltype(generic) matchmaking, friendsInterface;
    void* (*utilsInterface)(void*, int, const char*);
    unsigned (*app)(void*);
    if (!library || !load(library, client, "SteamClient") ||
        !load(library, user, "SteamAPI_GetHSteamUser") ||
        !load(library, pipe, "SteamAPI_GetHSteamPipe") ||
        !load(library, generic, "SteamAPI_ISteamClient_GetISteamGenericInterface") ||
        !load(library, matchmaking, "SteamAPI_ISteamClient_GetISteamMatchmaking") ||
        !load(library, friendsInterface, "SteamAPI_ISteamClient_GetISteamFriends") ||
        !load(library, utilsInterface, "SteamAPI_ISteamClient_GetISteamUtils") ||
        !load(library, app, "SteamAPI_ISteamUtils_GetAppID"))
        return false;
    bindStage = "client_session";
    currentPipe = pipe;
    const int hUser = user(), hPipe = pipe();
    if (!hUser || !hPipe)
        return false;
    auto* c = client();
    if (!c)
        return false;
    // Match the flat matchmaking/friends/utility wrappers to their own DLL ABI.
    // Both game builds obtain the independently versioned sockets API from Steam.
    const bool modern = GetProcAddress(library, "SteamAPI_SteamFriends_v017") != nullptr;
    bindStage = "app_id";
    utils = utilsInterface(c, hPipe, modern ? "SteamUtils010" : "SteamUtils008");
    if (!utils || app(utils) != gameApp)
        return false;
    bindStage = "interfaces";
    match = matchmaking(c, hUser, hPipe, "SteamMatchMaking009");
    friends = friendsInterface(c, hUser, hPipe, modern ? "SteamFriends017" : "SteamFriends015");
    sockets = static_cast<ISteamNetworkingSockets*>(
        generic(c, hUser, hPipe, STEAMNETWORKINGSOCKETS_INTERFACE_VERSION));
    networkingUtils = static_cast<ISteamNetworkingUtils*>(
        generic(c, hUser, hPipe, STEAMNETWORKINGUTILS_INTERFACE_VERSION));
    SteamNetworkingIdentity identity{};
    if (!match || !friends || !sockets || !networkingUtils)
        return false;
    initRelay = [](ISteamNetworkingUtils* utils) { utils->InitRelayNetworkAccess(); };
    localPingLocation = localLocation;
    estimatePing = estimateFromLocal;
    bindStage = "identity";
    if (!sockets->GetIdentity(&identity) || !(local = identity.GetSteamID64()))
        return false;
    bindStage = "matchmaking_exports";
    return load(library, create, "SteamAPI_ISteamMatchmaking_CreateLobby") &&
           load(library, join, "SteamAPI_ISteamMatchmaking_JoinLobby") &&
           load(library, leave, "SteamAPI_ISteamMatchmaking_LeaveLobby") &&
           load(library, filter, "SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter") &&
           load(library, distance,
                "SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter") &&
           load(library, limit,
                "SteamAPI_ISteamMatchmaking_AddRequestLobbyListResultCountFilter") &&
           load(library, list, "SteamAPI_ISteamMatchmaking_RequestLobbyList") &&
           load(library, byIndex, "SteamAPI_ISteamMatchmaking_GetLobbyByIndex") &&
           load(library, owner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner") &&
           load(library, members, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers") &&
           load(library, member, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex") &&
           load(library, requestData, "SteamAPI_ISteamMatchmaking_RequestLobbyData") &&
           load(library, set, "SteamAPI_ISteamMatchmaking_SetLobbyData") &&
           load(library, get, "SteamAPI_ISteamMatchmaking_GetLobbyData") &&
           load(library, setType, "SteamAPI_ISteamMatchmaking_SetLobbyType") &&
           load(library, joinable, "SteamAPI_ISteamMatchmaking_SetLobbyJoinable") &&
           load(library, overlay, "SteamAPI_ISteamUtils_IsOverlayEnabled") &&
           load(library, invite, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog") &&
           load(library, name, "SteamAPI_ISteamFriends_GetPersonaName") &&
           load(library, completed, "SteamAPI_ISteamUtils_IsAPICallCompleted") &&
           load(library, result, "SteamAPI_ISteamUtils_GetAPICallResult") &&
           load(library, subscribe, "SteamAPI_RegisterCallback") &&
           load(library, unsubscribe, "SteamAPI_UnregisterCallback");
}
std::uint64_t parseId(std::string_view text) {
    if (text.empty())
        return 0;
    Id id{};
    auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), id);
    return error == std::errc{} && end == text.data() + text.size() ? id : 0;
}
void Callback::callResult(void* data, bool failed, Call) {
    if (!failed)
        event(data);
}
void InviteCallback::event(void* data) {
    // GameLobbyJoinRequested_t starts with the lobby ID, followed by the inviter.
    Id id;
    std::memcpy(&id, data, sizeof(id));
    pending.store(id);
}
int InviteCallback::size() {
    return 2 * sizeof(Id);
}
} // namespace isaac::lan::steam
