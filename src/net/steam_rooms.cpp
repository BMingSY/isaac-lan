#include "net/steam_rooms.h"
#include <shellapi.h>
#include <algorithm>
#include <utility>

namespace isaac::lan::steam {
namespace {
constexpr char marker[] = "isaac_lan", kind[] = "room-v1";
constexpr char protocolKey[] = "il_protocol", versionKey[] = "il_version", buildKey[] = "il_build",
               hostKey[] = "il_host", openKey[] = "il_open", nameKey[] = "il_name",
               membersKey[] = "il_members";
constexpr int maxListings = 50, equal = 0, worldwide = 3;
constexpr auto callTimeout = std::chrono::seconds(25);
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
Id launchInvite() {
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
    api.subscribe(&invitations, joinRequested);
}
Rooms::~Rooms() {
    if (bound && api.alive()) {
        api.unsubscribe(&invitations);
        dropLobby();
    }
}
bool Rooms::available() {
    if (bound || Clock::now() < retryAt)
        return bound;
    retryAt = Clock::now() + std::chrono::seconds(5);
    if (!(bound = api.bind()))
        return false;
    api.subscribe(&invitations, joinRequested);
    inspect(launchInvite());
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
bool Rooms::start(Op type, Call call) {
    error.clear();
    if (!call) {
        error = "Steam 房间请求失败";
        return false;
    }
    op = type;
    pending = call;
    deadline = Clock::now() + callTimeout;
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
    api.filter(api.match, marker, kind, equal);
    api.filter(api.match, protocolKey, std::to_string(build.protocol).c_str(), equal);
    api.filter(api.match, versionKey, build.version.c_str(), equal);
    api.filter(api.match, buildKey, build.fingerprint.c_str(), equal);
    api.filter(api.match, openKey, "1", equal);
    api.distance(api.match, worldwide);
    api.limit(api.match, maxListings);
    return start(Op::list, api.list(api.match));
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
    if (!compatible(id) || field(id, openKey) != "1") {
        error = "房间已关闭或版本不兼容";
        return false;
    }
    target = id;
    return start(Op::join, api.join(api.match, id));
}
void Rooms::inspect(Id id) {
    if (!id || id == lobby)
        return;
    if (api.requestData(api.match, id)) {
        inspecting = id;
        inspectAt = {};
        inviteUntil = Clock::now() + callTimeout;
    }
}
bool Rooms::accept() {
    const bool ok = join(invitation);
    if (ok || !pending)
        dismiss();
    return ok;
}
bool Rooms::invite() {
    if (!active() || !joinOpen || !api.overlay(api.utils)) {
        error = "Steam 好友邀请不可用";
        return false;
    }
    error.clear();
    api.invite(api.friends, lobby);
    return true;
}
void Rooms::reconnected(const std::shared_ptr<DatagramRoute>& route) {
    if (active() && !hosting())
        transport = std::static_pointer_cast<Transport>(route);
}
bool Rooms::visibility() {
    if (!hosting() || !joinOpen ||
        !api.setType(api.match, lobby, publicRoom ? privateLobby : publicLobby)) {
        error = "无法修改房间可见性";
        return false;
    }
    error.clear();
    publicRoom = !publicRoom;
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
Id Rooms::enteredLobby(Op action, Call call, bool failed) {
    if (failed)
        return 0;
    if (action == Op::create) {
        LobbyCreated value{};
        return api.result(api.utils, call, &value, sizeof(value), createResult, &failed) &&
                       !failed && value.result == 1
                   ? value.lobby
                   : 0;
    }
    LobbyEntered value{};
    return api.result(api.utils, call, &value, sizeof(value), enterResult, &failed) && !failed &&
                   value.response == 1
               ? value.lobby
               : 0;
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
            error = "无法获取公开房间";
            return;
        }
        for (unsigned i = 0; i < std::min<unsigned>(count, maxListings); ++i) {
            auto id = api.byIndex(api.match, i);
            if (compatible(id) && field(id, openKey) == "1") {
                auto members = parseId(field(id, membersKey));
                if (members && members < maxPlayers)
                    listings.push_back(
                        {id, displayName(field(id, nameKey)), static_cast<int>(members)});
            }
        }
        return;
    }
    const Id entered = enteredLobby(action, call, failed);
    if (!entered) {
        error = "无法进入 Steam 房间";
        return;
    }
    lobby = entered;
    const bool creating = action == Op::create;
    host = creating ? api.local : parseId(field(lobby, hostKey));
    if (!host || api.owner(api.match, lobby) != host ||
        (!creating && (lobby != target || !compatible(lobby) || field(lobby, openKey) != "1")) ||
        !(transport = openTransport(api, host)) || (creating && !publish())) {
        dropLobby();
        error = "房间已关闭或版本不兼容";
        return;
    }
    joinOpen = true;
    listings.clear();
}
void Rooms::poll(const BuildIdentity& identity, bool inLobby, const std::function<bool(Id)>& seat,
                 void (*logger)(const std::string&)) {
    if (identity.valid() &&
        (identity.version != build.version || identity.fingerprint != build.fingerprint))
        build = identity;
    if (!available())
        return;
    const auto now = Clock::now();
    if (auto id = invitations.pending.exchange(0))
        inspect(id);
    if (inspecting && now >= inspectAt) {
        inspectAt = now + std::chrono::milliseconds(250);
        if (ours(inspecting)) {
            invitation = std::exchange(inspecting, 0);
        } else if (now >= inviteUntil)
            inspecting = 0;
    }
    reap();
    if (pending)
        finishCall();
    if (!active())
        return;
    if (now >= publishAt || (hosting() && joinOpen != inLobby)) {
        publishAt = now + std::chrono::seconds(1);
        auto owner = api.owner(api.match, lobby);
        if (owner != host) {
            dropLobby();
            error = "Steam 房主已离开";
            return;
        }
        if (hosting()) {
            if (joinOpen != inLobby && api.joinable(api.match, lobby, inLobby) &&
                api.set(api.match, lobby, openKey, inLobby ? "1" : "0"))
                joinOpen = inLobby;
            int members = api.members(api.match, lobby);
            if (members != publishedMembers &&
                api.set(api.match, lobby, membersKey, std::to_string(members).c_str()))
                publishedMembers = members;
        }
    }
    if (hosting())
        transport->service([&](Id remote) {
            if (!inLobby)
                return seat(remote);
            const int count = std::min<int>(api.members(api.match, lobby), maxPlayers);
            for (int i = 0; i < count; ++i)
                if (api.member(api.match, lobby, i) == remote)
                    return true;
            return false;
        });
    if (logger && now >= logAt) {
        logAt = now + std::chrono::seconds(5);
        auto sample = transport->diagnostics();
        if (!sample.empty())
            logger(sample);
    }
}
void Rooms::dropLobby() {
    if (lobby) {
        if (host == api.local && api.owner(api.match, lobby) == host)
            api.joinable(api.match, lobby, false);
        api.leave(api.match, lobby);
    }
    transport.reset();
    host = lobby = 0;
    publicRoom = false;
    joinOpen = true;
    publishedMembers = 0;
}
void Rooms::leave() {
    cancelCall();
    dropLobby();
    listings.clear();
    error.clear();
}
} // namespace isaac::lan::steam
