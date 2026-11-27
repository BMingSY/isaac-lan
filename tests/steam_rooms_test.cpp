#include "net/steam_rooms.h"
#include "test_support.h"
#include <cstring>
#include <map>
#include <set>
using namespace isaac::lan;
using namespace isaac::lan::steam;
namespace {
constexpr Id me = 17, friendId = 23, stranger = 29, roomId = 101, otherRoom = 102;
struct Platform {
    Id owner = me, expected = 0;
    unsigned enterResponse = 1;
    int type = -1, invites = 0, joins = 0;
    bool ready = false, joinable = true, overlay = true;
    std::vector<Id> list, left, requests, members{me, friendId};
    std::string localLocation;
    std::map<std::string, int> estimates;
    unsigned relayStarts = 0, locationWrites = 0;
    std::map<Id, std::map<std::string, std::string>> data;
    std::map<std::string, std::string> filters;
    Callback* invite = nullptr;
} platform;
class Route final : public Transport {
  public:
    std::set<Id> admitted;
    Id localAccount() const override {
        return me;
    }
    Id hostAccount() const override {
        return platform.owner;
    }
    State state() override {
        return State::connected;
    }
    std::shared_ptr<DatagramRoute> reconnect() override {
        return {};
    }
    int send(Id, std::span<const std::uint8_t>) override {
        return 0;
    }
    int receive(Id&, std::span<std::uint8_t>) override {
        return 0;
    }
    void service(const std::function<bool(Id)>& allowed) override {
        admitted.clear();
        for (auto id : {me, friendId, stranger})
            if (allowed(id))
                admitted.insert(id);
    }
    std::string diagnostics() override {
        return {};
    }
};
Api makeApi() {
    Api a;
    a.local = me;
    a.initRelay = [](ISteamNetworkingUtils*) { ++platform.relayStarts; };
    a.localPingLocation = [](ISteamNetworkingUtils*) { return platform.localLocation; };
    a.estimatePing = [](ISteamNetworkingUtils*, const char* location) -> std::optional<int> {
        auto found = platform.estimates.find(location);
        return found == platform.estimates.end() ? std::nullopt : std::optional{found->second};
    };
    a.subscribe = [](void* sub, int) { platform.invite = static_cast<Callback*>(sub); };
    a.unsubscribe = [](void*) { platform.invite = nullptr; };
    a.create = [](void*, int type, int limit) -> Call {
        require(limit == maxPlayers, "Wrong capacity");
        platform.type = type;
        return 1;
    };
    a.join = [](void*, Id id) -> Call {
        ++platform.joins;
        platform.expected = id;
        return 2;
    };
    a.list = [](void*) -> Call { return 3; };
    a.completed = [](void*, Call, bool*) { return platform.ready; };
    a.result = [](void*, Call, void* result, int, int type, bool*) {
        if (type == createResult)
            *static_cast<LobbyCreated*>(result) = {1, roomId};
        else if (type == enterResult)
            *static_cast<LobbyEntered*>(result) = {platform.expected, 0, false,
                                                   platform.enterResponse};
        else
            *static_cast<unsigned*>(result) = platform.list.size();
        return true;
    };
    a.owner = [](void*, Id) { return platform.owner; };
    a.leave = [](void*, Id id) { platform.left.push_back(id); };
    a.get = [](void*, Id id, const char* k) { return platform.data[id][k].c_str(); };
    a.set = [](void*, Id id, const char* k, const char* v) {
        if (std::string_view(k) == "il_ping_location")
            ++platform.locationWrites;
        platform.data[id][k] = v;
        return true;
    };
    a.name = [](void*) { return "Host"; };
    a.members = [](void*, Id) { return static_cast<int>(platform.members.size()); };
    a.member = [](void*, Id, int i) { return platform.members.at(i); };
    a.joinable = [](void*, Id, bool open) {
        platform.joinable = open;
        return true;
    };
    a.setType = [](void*, Id, int type) {
        platform.type = type;
        return true;
    };
    a.overlay = [](void*) { return platform.overlay; };
    a.invite = [](void*, Id) { ++platform.invites; };
    a.requestData = [](void*, Id id) {
        platform.requests.push_back(id);
        return true;
    };
    a.filter = [](void*, const char* k, const char* v, int) { platform.filters[k] = v; };
    a.distance = [](void*, int) {};
    a.limit = [](void*, int) {};
    a.byIndex = [](void*, int i) { return platform.list.at(i); };
    return a;
}
std::vector<std::string> events;
void contracts() {
    Rooms rooms(makeApi(), [](Api&, Id, Logger) -> std::shared_ptr<Transport> {
        return std::make_shared<Route>();
    });
    auto poll = [&](bool lobby = true) {
        rooms.poll(
            {"version", "fingerprint"}, lobby, [](Id id) { return id == friendId; },
            [](const auto& message) { events.push_back(message); });
    };
    poll();
    require(rooms.create() && rooms.busy() && platform.type == privateLobby, "Default visibility");
    rooms.leave();
    platform.ready = true;
    poll();
    require(!rooms.active() && platform.left == std::vector<Id>{roomId},
            "Cancelled creation leaked a lobby");
    require(rooms.create(), "Retry failed");
    poll();
    require(rooms.hosting() && !rooms.isPublic(), "Host did not own private room");
    auto route = std::static_pointer_cast<Route>(rooms.route());
    require(route->admitted.contains(friendId) && !route->admitted.contains(stranger),
            "Admission ignored lobby membership");
    require(rooms.visibility() && rooms.isPublic() && platform.type == publicLobby,
            "Public visibility");
    require(rooms.invite() && platform.invites == 1, "Invite dialog did not open");
    platform.overlay = false;
    require(!rooms.invite() && platform.invites == 1, "Missing overlay was not reported");
    platform.members = {me, stranger};
    poll(false);
    require(!platform.joinable && !rooms.visibility() && route->admitted == std::set<Id>{friendId},
            "Active run admitted another account");
    poll();
    require(platform.joinable, "Returning lobby stayed locked");
    rooms.leave();
    platform.list = {otherRoom, roomId};
    require(rooms.browse(), "Could not browse");
    poll();
    require(!platform.filters.empty() && rooms.rooms().size() == 1 && rooms.rooms()[0].id == roomId,
            "Browser included a foreign lobby");
    require(!rooms.join(otherRoom) && !platform.joins, "Joined a foreign room");
    auto notify = [&](Id id) {
        platform.invite->event(&id);
        poll();
    };
    notify(otherRoom);
    require(!rooms.invited(), "Official invitation was claimed");
    notify(roomId);
    require(rooms.invited() == roomId && !platform.joins,
            "Invitation joined before user selected a save");
    rooms.dismiss();
    require(!rooms.invited(), "Invitation not dismissed");
    notify(roomId);
    platform.owner = stranger;
    require(rooms.accept(), "Could not start invited join");
    poll();
    require(!rooms.active() && platform.left.back() == roomId, "Accepted a migrated owner");
    platform.owner = friendId;
    platform.data[roomId]["il_host"] = std::to_string(friendId);
    constexpr unsigned roomFull = 4;
    platform.enterResponse = roomFull;
    notify(roomId);
    require(rooms.accept(), "Full room request did not start");
    poll();
    require(!rooms.active(), "Steam rejected the request but the room stayed active");
    platform.enterResponse = 1;
    notify(roomId);
    require(rooms.accept(), "Fresh invite did not start");
    poll();
    require(rooms.active() && !rooms.hosting() && !rooms.visibility(),
            "Invited guest cannot own the lobby");
    for (const char* expected :
         {"steam_lobby=ready role=host", "steam_lobby=ready role=client",
          "steam_lobby=cancel op=create", "steam_lobby=invite_failed reason=overlay_unavailable",
          "steam_lobby=invite_recognized", "steam_lobby=setup_failed op=join reason=owner_changed",
          "steam_lobby=result_failed op=join code=4"})
        require(std::find(events.begin(), events.end(), expected) != events.end(), expected);
}
void browserLatency() {
    platform = {};
    Rooms rooms(makeApi(), [](Api&, Id, Logger) -> std::shared_ptr<Transport> {
        return std::make_shared<Route>();
    });
    auto poll = [&](bool inLobby = true) {
        rooms.poll({"version", "fingerprint"}, inLobby, [](Id) { return false; }, nullptr);
    };
    platform.ready = true;
    poll();
    require(rooms.create(), "Could not create a room without a relay measurement");
    poll();
    require(rooms.visibility(), "Relay measurement blocked public visibility");
    poll();
    require(platform.locationWrites == 0, "Published an empty location");
    platform.localLocation = "local";
    poll(false);
    poll();
    require(platform.data[roomId]["il_ping_location"] == "local",
            "Late location was not published");
    poll(false);
    poll();
    require(platform.locationWrites == 1, "Unchanged location published repeatedly");
    rooms.leave();
    require(rooms.create(), "Could not create a second room");
    poll();
    require(rooms.visibility(), "Could not reopen a public room");
    poll();
    require(platform.locationWrites == 2, "A new lobby inherited the previous publication");
    rooms.leave();

    constexpr Id slow = 200, fast = 201, slowTie = 202, unknown = 203, missing = 204;
    for (Id id : {slow, fast, slowTie, unknown, missing})
        platform.data[id] = platform.data[roomId];
    platform.data[slow]["il_ping_location"] = "far";
    platform.data[slowTie]["il_ping_location"] = "far";
    platform.data[unknown]["il_ping_location"] = "unparseable";
    platform.data[missing].erase("il_ping_location");
    platform.estimates = {{"local", 0}, {"far", 130}};
    platform.list = {unknown, slowTie, missing, fast, slow};
    require(rooms.browse() && platform.relayStarts == 1, "Browsing did not prepare relay data");
    poll();
    const auto& list = rooms.rooms();
    require(list.size() == 5 && list[0].id == fast && list[0].pingMs == 0 && list[1].id == slow &&
                list[1].pingMs == 130 && list[2].id == slowTie && list[3].id == unknown &&
                !list[3].pingMs && list[4].id == missing && !list[4].pingMs,
            "Room order did not preserve zero, equal or unavailable estimates");
    require(platform.requests == std::vector<Id>{missing}, "Missing location was not requested");
    platform.data[missing]["il_ping_location"] = "near";
    platform.estimates["near"] = 50;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (rooms.rooms()[1].id != missing && std::chrono::steady_clock::now() < deadline)
        Sleep(10);
    require(list[1].id == missing && list[1].pingMs == 50 && list.back().id == unknown &&
                platform.requests.size() == 1,
            "Late metadata did not update the list in place");
    require(rooms.join(missing) && platform.expected == missing, "Wrong join target after sorting");
}
} // namespace
void singleAccount();
int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "single-account")
        return runTests(argc, argv, {{"single-account", singleAccount}});
    return runTests(argc, argv, {{"rooms", contracts}, {"browser-latency", browserLatency}});
}
