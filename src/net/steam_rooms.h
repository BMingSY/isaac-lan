#pragma once
#include "net/compatibility.h"
#include "net/steam_transport.h"
#include <chrono>
#include <optional>

namespace isaac::lan::steam {
struct Listing {
    Id id;
    std::string name;
    int players;
    std::optional<int> pingMs;
};
class Rooms {
    using Clock = std::chrono::steady_clock;
    enum class Op { none, create, join, list };
    using OpenTransport = decltype(&Transport::open);
    Api api;
    OpenTransport openTransport = Transport::open;
    std::atomic<Id> requested{0};
    InviteCallback invitations{joinRequested, requested},
        presenceInvitations{presenceJoinRequested, requested};
    bool bound = false, publicRoom = false, joinOpen = true;
    int appliedType = privateLobby;
    bool targetInvited = false;
    struct Abandoned {
        Op op;
        Call call;
        Id target;
    };
    std::vector<Abandoned> abandoned;
    Op op = Op::none;
    Logger logger = nullptr;
    std::string_view lastBindStage;
    void listenForInvites();
    void event(const std::string& message) const;
    static const char* name(Op operation);
    Call pending = 0;
    Id lobby = 0, host = 0, target = 0, targetHost = 0, inspecting = 0, invitation = 0;
    Clock::time_point retryAt{}, deadline{}, inviteUntil{}, inspectAt{}, publishAt{}, logAt{};
    Clock::time_point estimateAt{}, requestLocationAt{};
    int publishedMembers = 0;
    std::string publishedLocation, publishedAdmission, connectValue, previousConnect;
    std::shared_ptr<Transport> transport;
    std::vector<Listing> listings;
    std::string error;
    BuildIdentity build;
    bool ours(Id id) const;
    bool compatible(Id id) const;
    bool allowsJoin(Id id, bool invited) const;
    void updateAdmission(bool inLobby, std::span<const std::string> seats);
    void updatePresence(bool playing);
    bool setType(int type);
    std::string field(Id id, const char* key) const;
    bool start(Op type, Call call);
    void finishCall();
    void cancelCall();
    void reap();
    Id enteredLobby(Op action, Call call, bool failed, int* response = nullptr);
    void dropLobby();
    bool checkOwner();
    void inspect(Id id);
    bool publish();

  public:
    Rooms() = default;
    Rooms(Api ready, OpenTransport open);
    Rooms(const Rooms&) = delete;
    Rooms& operator=(const Rooms&) = delete;
    ~Rooms();
    bool available();
    void poll(const BuildIdentity& identity, bool inLobby, std::span<const std::string> seats,
              Logger log);
    bool create();
    bool browse();
    bool join(Id id);
    bool accept();
    void disconnectGuest(std::string reason = {});
    bool canRejoin() const {
        return lobby && host != api.local && !transport;
    }
    bool rejoin();
    void dismiss() {
        invitation = inspecting = 0;
    }
    bool invitedToCurrent() const {
        return invitation && invitation == lobby && host != api.local;
    }
    bool joiningRun() const {
        return active() && !hosting() && !joinOpen;
    }
    bool invite();
    bool visibility();
    void leave();
    bool busy() const {
        return pending != 0;
    }
    bool active() const {
        return lobby && transport;
    }
    bool hosting() const {
        return active() && host == api.local;
    }
    void reconnected(const std::shared_ptr<DatagramRoute>& route);
    bool isPublic() const {
        return publicRoom;
    }
    Id invited() const {
        return invitation;
    }
    const std::vector<Listing>& rooms();
    const std::string& failure() const {
        return error;
    }
    const std::shared_ptr<Transport>& route() const {
        return transport;
    }
};
} // namespace isaac::lan::steam
