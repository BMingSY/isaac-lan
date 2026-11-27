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
    int type = -1, invites = 0, joins = 0;
    bool ready = false, joinable = true, overlay = true;
    std::vector<Id> list, left, members{me, friendId};
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
            *static_cast<LobbyEntered*>(result) = {platform.expected, 0, false, 1};
        else
            *static_cast<unsigned*>(result) = platform.list.size();
        return true;
    };
    a.owner = [](void*, Id) { return platform.owner; };
    a.leave = [](void*, Id id) { platform.left.push_back(id); };
    a.get = [](void*, Id id, const char* k) { return platform.data[id][k].c_str(); };
    a.set = [](void*, Id id, const char* k, const char* v) {
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
    a.requestData = [](void*, Id) { return true; };
    a.filter = [](void*, const char* k, const char* v, int) { platform.filters[k] = v; };
    a.distance = [](void*, int) {};
    a.limit = [](void*, int) {};
    a.byIndex = [](void*, int i) { return platform.list.at(i); };
    return a;
}
void contracts() {
    Rooms rooms(makeApi(),
                [](Api&, Id) -> std::shared_ptr<Transport> { return std::make_shared<Route>(); });
    auto poll = [&](bool lobby = true) {
        rooms.poll(
            {"version", "fingerprint"}, lobby, [](Id id) { return id == friendId; }, nullptr);
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
    notify(roomId);
    require(rooms.accept(), "Fresh invite did not start");
    poll();
    require(rooms.active() && !rooms.hosting() && !rooms.visibility(),
            "Invited guest cannot own the lobby");
}
} // namespace
void singleAccount();
int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "single-account")
        return runTests(argc, argv, {{"single-account", singleAccount}});
    return runTests(argc, argv, {{"rooms", contracts}});
}
