#include "net/steam_rooms.h"
#include <shellapi.h>
#include <algorithm>
#include <tuple>
#include <utility>

namespace isaac::lan::steam {
namespace {
constexpr char marker[] = "isaac_lan", kind[] = "room-v1";
constexpr char protocolKey[] = "il_protocol", versionKey[] = "il_version", buildKey[] = "il_build",
               hostKey[] = "il_host", openKey[] = "il_open", nameKey[] = "il_name",
               membersKey[] = "il_members", locationKey[] = "il_ping_location";
// One metadata write switches between public admission and invite-only original seats.
constexpr std::string_view reservedPrefix = "rejoin,";
constexpr int maxListings = 50, equal = 0, worldwide = 3;
constexpr auto callTimeout = std::chrono::seconds(25);
constexpr auto estimateInterval = std::chrono::seconds(1),
               locationRequestInterval = std::chrono::seconds(10);
std::string displayName(std::string name) {
    constexpr size_t limit = 128;
    if (name.size() > limit) {
        size_t end = limit;
        while (end && (static_cast<unsigned char>(name[end]) & 0xc0) == 0x80)
            --end;
        name.resize(end);
    }
    std::erase_if(name, [](unsigned char c) { return c < 32 || c == 127; });
    return name;
}
Id launchInvite(const Api& api) {
    if (api.apps && api.launchCommand) {
        char command[1024]{};
        const int length = api.launchCommand(api.apps, command, sizeof(command));
        if (length > 0 && static_cast<size_t>(length) < sizeof(command)) {
            command[length] = '\0';
            if (const auto id = lobbyFromConnect(command))
                return id;
        }
    }
    int count{};
    auto** argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv)
        return 0;
    Id id = 0;
    for (int i = 1; i + 1 < count; ++i) {
        if (std::wstring_view(argv[i]) != L"+connect_lobby")
            continue;
        std::wstring_view value(argv[i + 1]);
        if (value.size() <= 20 && value.find_first_not_of(L"0123456789") == value.npos)
            id = parseId(std::string(value.begin(), value.end()));
    }
    LocalFree(argv);
    return id;
}
} // namespace
Rooms::Rooms(Api ready, OpenTransport open) : api(ready), openTransport(open), bound(true) {
    listenForInvites();
}
void Rooms::listenForInvites() {
    api.subscribe(&invitations, joinRequested);
    api.subscribe(&presenceInvitations, presenceJoinRequested);
    inspect(launchInvite(api));
}
Rooms::~Rooms() {
    if (bound && api.alive()) {
        api.unsubscribe(&presenceInvitations);
        api.unsubscribe(&invitations);
        dropLobby();
    }
}
void Rooms::event(const std::string& message) const {
    if (logger)
        logger("steam_lobby=" + message);
}
const char* Rooms::name(Op operation) {
    switch (operation) {
    case Op::create:
        return "create";
    case Op::join:
        return "join";
    case Op::list:
        return "list";
    default:
        return "none";
    }
}
bool Rooms::available() {
    if (bound || Clock::now() < retryAt)
        return bound;
    retryAt = Clock::now() + std::chrono::seconds(5);
    bound = api.bind();
    const std::string_view stage = bound ? "ready" : api.bindStage;
    if (stage != lastBindStage) {
        event("api stage=" + std::string(stage));
        lastBindStage = stage;
    }
    if (!bound)
        return false;
    listenForInvites();
    return true;
}
std::string Rooms::field(Id id, const char* key) const {
    const auto* value = api.get(api.match, id, key);
    return value ? value : "";
}
bool Rooms::ours(Id id) const {
    return id && field(id, marker) == kind;
}
bool Rooms::compatible(Id id) const {
    return ours(id) && field(id, protocolKey) == std::to_string(build.protocol) &&
           field(id, versionKey) == build.version && field(id, buildKey) == build.fingerprint;
}
bool Rooms::allowsJoin(Id id, bool invited) const {
    const auto admission = field(id, openKey);
    return admission == "1" ||
           (invited && admission.starts_with(reservedPrefix) &&
            admission.find("," + accountIdentity(api.local) + ",") != std::string::npos);
}
bool Rooms::start(Op type, Call call) {
    error.clear();
    if (!call) {
        event(std::string("request_failed op=") + name(type));
        error = "Steam 房间请求失败";
        return false;
    }
    op = type;
    pending = call;
    deadline = Clock::now() + callTimeout;
    event(std::string("request op=") + name(type));
    return true;
}
bool Rooms::create() {
    if (!available() || lobby || pending || abandoned.size() >= maxPlayers || !build.valid())
        return false;
    return start(Op::create, api.create(api.match, privateLobby, maxPlayers));
}
bool Rooms::browse() {
    if (!available() || lobby || pending || abandoned.size() >= maxPlayers || !build.valid())
        return false;
    listings.clear();
    estimateAt = requestLocationAt = {};
    api.initRelay(api.networkingUtils);
    api.filter(api.match, marker, kind, equal);
    api.filter(api.match, protocolKey, std::to_string(build.protocol).c_str(), equal);
    api.filter(api.match, versionKey, build.version.c_str(), equal);
    api.filter(api.match, buildKey, build.fingerprint.c_str(), equal);
    api.filter(api.match, openKey, "1", equal);
    api.distance(api.match, worldwide);
    api.limit(api.match, maxListings);
    return start(Op::list, api.list(api.match));
}
const std::vector<Listing>& Rooms::rooms() {
    const auto now = Clock::now();
    if (listings.empty() || now < estimateAt)
        return listings;
    estimateAt = now + estimateInterval;
    const bool refreshMissing = now >= requestLocationAt;
    if (refreshMissing)
        requestLocationAt = now + locationRequestInterval;
    for (auto& room : listings) {
        auto location = field(room.id, locationKey);
        room.pingMs = api.estimatePing(api.networkingUtils, location.c_str());
        if (refreshMissing && location.empty())
            api.requestData(api.match, room.id);
    }
    std::ranges::sort(listings, {}, [](const Listing& room) {
        // Known estimates first, with a stable room order for equal estimates.
        return std::tuple{!room.pingMs.has_value(), room.pingMs, room.id};
    });
    return listings;
}
bool Rooms::join(Id id) {
    if (!available() || lobby || pending || !id ||
        (id != invitation && std::none_of(listings.begin(), listings.end(),
                                          [id](const auto& room) { return room.id == id; })))
        return false;
    if (abandoned.size() >= maxPlayers ||
        std::any_of(abandoned.begin(), abandoned.end(),
                    [&](const auto& call) { return call.op == Op::join && call.target == id; })) {
        error = "上一次 Steam 请求仍在结束";
        return false;
    }
    if (!compatible(id)) {
        event("join_rejected reason=incompatible");
        error = "房间已关闭或版本不兼容";
        return false;
    }
    if (!allowsJoin(id, id == invitation)) {
        event("join_rejected reason=admission");
        error = field(id, openKey).starts_with(reservedPrefix) ? "进行中的对局只允许原玩家重连"
                                                               : "房间已关闭或版本不兼容";
        return false;
    }
    target = id;
    targetHost = parseId(field(id, hostKey));
    targetInvited = id == invitation;
    return start(Op::join, api.join(api.match, id));
}
void Rooms::inspect(Id id) {
    if (!id)
        return;
    if (id == lobby) {
        inspecting = 0;
        if (!hosting()) {
            invitation = id;
            event("invite_current_room");
        }
        return;
    }
    if (api.requestData(api.match, id)) {
        inspecting = id;
        inspectAt = {};
        inviteUntil = Clock::now() + callTimeout;
        event("invite_lookup");
    } else
        event("invite_lookup_failed");
}
bool Rooms::accept() {
    const bool ok = invitedToCurrent() ? rejoin() : join(invitation);
    if (ok || !pending)
        dismiss();
    return ok;
}
bool Rooms::invite() {
    if (!active() || !api.overlay(api.utils)) {
        event(active() ? "invite_failed reason=overlay_unavailable"
                       : "invite_failed reason=room_closed");
        error = "Steam 好友邀请不可用";
        return false;
    }
    error.clear();
    api.invite(api.friends, lobby);
    event("invite_overlay_requested");
    return true;
}
void Rooms::disconnectGuest(std::string reason) {
    if (active() && !hosting()) {
        error = std::move(reason);
        transport.reset();
        publishAt = {};
        event("disconnected role=client");
    }
}
bool Rooms::checkOwner() {
    if (api.owner(api.match, lobby) == host)
        return true;
    dropLobby();
    event("owner_left");
    error = "Steam 房主已离开";
    return false;
}
bool Rooms::rejoin() {
    if (!canRejoin() || !checkOwner())
        return false;
    transport = openTransport(api, host, logger);
    if (!transport) {
        error = "当前无法重连游戏";
        return false;
    }
    error.clear();
    event("rejoin role=client");
    return true;
}
void Rooms::reconnected(const std::shared_ptr<DatagramRoute>& route) {
    if (active() && !hosting())
        transport = std::static_pointer_cast<Transport>(route);
}
bool Rooms::setType(int type) {
    if (type == appliedType)
        return true;
    if (!api.setType(api.match, lobby, type))
        return false;
    appliedType = type;
    return true;
}
bool Rooms::visibility() {
    if (!hosting() || !joinOpen || !setType(publicRoom ? privateLobby : publicLobby)) {
        error = "无法修改房间可见性";
        return false;
    }
    error.clear();
    publicRoom = !publicRoom;
    publishAt = {};
    event(publicRoom ? "visibility value=public" : "visibility value=private");
    return true;
}
bool Rooms::publish() {
    const auto* name = api.name(api.friends);
    auto set = [&](const char* key, const std::string& value) {
        return api.set(api.match, lobby, key, value.c_str());
    };
    return set(hostKey, std::to_string(host)) && set(protocolKey, std::to_string(build.protocol)) &&
           set(versionKey, build.version) && set(buildKey, build.fingerprint) &&
           set(nameKey, name ? name : "") && set(membersKey, "1") && set(openKey, "1") &&
           set(marker, kind);
}
Id Rooms::enteredLobby(Op action, Call call, bool failed, int* response) {
    if (failed)
        return 0;
    if (action == Op::create) {
        LobbyCreated value{};
        if (!api.result(api.utils, call, &value, sizeof(value), createResult, &failed) || failed)
            return 0;
        if (response)
            *response = value.result;
        return value.result == 1 ? value.lobby : 0;
    }
    LobbyEntered value{};
    if (!api.result(api.utils, call, &value, sizeof(value), enterResult, &failed) || failed)
        return 0;
    if (response)
        *response = static_cast<int>(value.response);
    return value.response == 1 ? value.lobby : 0;
}
void Rooms::cancelCall() {
    if (pending && op != Op::list)
        abandoned.push_back({op, pending, target});
    pending = 0;
    op = Op::none;
}
void Rooms::reap() {
    std::erase_if(abandoned, [&](const Abandoned& item) {
        bool failed{};
        if (!api.completed(api.utils, item.call, &failed) && !failed)
            return false;
        if (Id entered = enteredLobby(item.op, item.call, failed); entered && entered != lobby)
            api.leave(api.match, entered);
        return true;
    });
}
void Rooms::finishCall() {
    bool failed{};
    if (!api.completed(api.utils, pending, &failed) && !failed) {
        if (Clock::now() > deadline) {
            event(std::string("timeout op=") + name(op));
            cancelCall();
            error = "Steam 房间请求超时";
        }
        return;
    }
    const Call call = std::exchange(pending, 0);
    const auto action = std::exchange(op, Op::none);
    if (action == Op::list) {
        unsigned count{};
        if (failed || !api.result(api.utils, call, &count, sizeof(count), listResult, &failed) ||
            failed) {
            event("result_failed op=list");
            error = "无法获取公开房间";
            return;
        }
        for (unsigned i = 0; i < std::min<unsigned>(count, maxListings); ++i) {
            auto id = api.byIndex(api.match, i);
            if (compatible(id) && field(id, openKey) == "1") {
                auto members = parseId(field(id, membersKey));
                if (members && members < maxPlayers)
                    listings.push_back({id, displayName(field(id, nameKey)),
                                        static_cast<int>(members), std::nullopt});
            }
        }
        event("listed returned=" + std::to_string(count) +
              " compatible=" + std::to_string(listings.size()));
        return;
    }
    int response = -1;
    const Id entered = enteredLobby(action, call, failed, &response);
    if (!entered) {
        event(std::string("result_failed op=") + name(action) +
              " code=" + std::to_string(response));
        error = "无法进入 Steam 房间";
        return;
    }
    lobby = entered;
    const bool creating = action == Op::create;
    host = creating ? api.local : parseId(field(lobby, hostKey));
    const char* issue = nullptr;
    if (!host || (!creating && host != targetHost) || api.owner(api.match, lobby) != host)
        issue = "owner_changed";
    else if (!creating &&
             (lobby != target || !compatible(lobby) || !allowsJoin(lobby, targetInvited)))
        issue = "closed_or_incompatible";
    else if (!(transport = openTransport(api, host, logger)))
        issue = "p2p_open";
    else if (creating && !publish())
        issue = "publish_metadata";
    if (issue) {
        event(std::string("setup_failed op=") + name(action) + " reason=" + issue);
        dropLobby();
        error = "房间已关闭或版本不兼容";
        return;
    }
    event(creating ? "ready role=host" : "ready role=client");
    joinOpen = creating || field(lobby, openKey) == "1";
    if (creating)
        publishedAdmission = "1";
    listings.clear();
}
void Rooms::updatePresence(bool playing) {
    if (playing == !connectValue.empty())
        return;
    const auto* previous = api.getPresence(api.friends, api.local, "connect");
    if (playing) {
        auto connect = std::string(lobbyCommand) + std::to_string(lobby);
        previousConnect = previous ? previous : "";
        if (api.setPresence(api.friends, "connect", connect.c_str())) {
            connectValue = std::move(connect);
            event("friend_connect published");
        }
    } else {
        // Only restore a presence value still owned by this room.
        if (previous && previous == connectValue &&
            !api.setPresence(api.friends, "connect",
                             previousConnect.empty() ? nullptr : previousConnect.c_str()))
            return;
        previousConnect.clear();
        connectValue.clear();
    }
}
void Rooms::updateAdmission(bool inLobby, std::span<const std::string> seats) {
    // A game invite carries a connect string, while a lobby invite grants entry.
    // Friends-only permits either Steam flow without listing the running room.
    if (!inLobby)
        setType(friendsLobby);
    else if (!publicRoom)
        setType(privateLobby);
    std::string admission = "1";
    if (!inLobby && appliedType == publicLobby)
        admission = "0"; // Keep seats private if Steam hasn't applied the visibility change yet.
    else if (!inLobby) {
        admission = reservedPrefix;
        for (const auto& identity : seats) {
            admission += identity;
            admission += ',';
        }
    }
    if (publishedAdmission != admission && api.set(api.match, lobby, openKey, admission.c_str())) {
        publishedAdmission = admission;
        event(inLobby ? "admission value=lobby" : "admission value=original_players");
    }
    if (inLobby && publicRoom && publishedAdmission == "1")
        setType(publicLobby);
    updatePresence(!inLobby);
}
void Rooms::poll(const BuildIdentity& identity, bool inLobby, std::span<const std::string> seats,
                 Logger log) {
    logger = log;
    if (identity.valid() &&
        (identity.version != build.version || identity.fingerprint != build.fingerprint))
        build = identity;
    if (!available())
        return;
    const auto now = Clock::now();
    if (auto id = requested.exchange(0))
        inspect(id);
    if (inspecting && now >= inspectAt) {
        inspectAt = now + std::chrono::milliseconds(250);
        if (ours(inspecting)) {
            invitation = std::exchange(inspecting, 0);
            event("invite_recognized");
        } else if (now >= inviteUntil) {
            inspecting = 0;
            event("invite_unrecognized_or_expired");
        }
    }
    reap();
    if (pending)
        finishCall();
    if (!lobby) {
        updatePresence(false);
        return;
    }
    if (hosting() && joinOpen != inLobby) {
        joinOpen = inLobby;
        publishAt = {};
    }
    if (now >= publishAt) {
        publishAt = now + std::chrono::seconds(1);
        if (!checkOwner())
            return;
        if (hosting()) {
            updateAdmission(inLobby, seats);
            if (publicRoom && joinOpen) {
                auto location = api.localPingLocation(api.networkingUtils);
                if (!location.empty() && location != publishedLocation &&
                    api.set(api.match, lobby, locationKey, location.c_str()))
                    publishedLocation = std::move(location);
            }
            int members = api.members(api.match, lobby);
            if (members != publishedMembers &&
                api.set(api.match, lobby, membersKey, std::to_string(members).c_str()))
                publishedMembers = members;
        }
    }
    if (hosting())
        transport->service([&](Id remote) {
            if (!inLobby)
                return std::ranges::find(seats, accountIdentity(remote)) != seats.end();
            const int count = std::min<int>(api.members(api.match, lobby), maxPlayers);
            for (int i = 0; i < count; ++i)
                if (api.member(api.match, lobby, i) == remote)
                    return true;
            return false;
        });
    if (transport && logger && now >= logAt) {
        logAt = now + std::chrono::seconds(5);
        auto sample = transport->diagnostics();
        if (!sample.empty())
            logger(sample);
    }
}
void Rooms::dropLobby() {
    updatePresence(false);
    if (lobby) {
        if (invitation == lobby)
            dismiss();
        if (host == api.local && api.owner(api.match, lobby) == host)
            api.joinable(api.match, lobby, false);
        api.leave(api.match, lobby);
    }
    transport.reset();
    host = lobby = 0;
    appliedType = privateLobby;
    publicRoom = false;
    publishedAdmission.clear();
    joinOpen = true;
    publishedMembers = 0;
    publishAt = {};
    publishedLocation.clear();
}
void Rooms::leave() {
    if (pending)
        event(std::string("cancel op=") + name(op));
    if (lobby)
        event(hosting() ? "left role=host" : "left role=client");
    cancelCall();
    dropLobby();
    listings.clear();
    error.clear();
}
} // namespace isaac::lan::steam
