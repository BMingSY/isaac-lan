#pragma once
#include "net/datagram_route.h"
#include "net/steam_api.h"
#include <functional>

namespace isaac::lan::steam {
// Steam virtual port reserved for Isaac LAN P2P sockets.
inline constexpr int virtualPort = 17321;
using Logger = void (*)(const std::string&);
class Transport : public DatagramRoute {
  public:
    static std::shared_ptr<Transport> open(Api& api, Id host, Logger logger = nullptr);
    // Runs on the game's thread. Incoming accounts are checked against the lobby
    // or the run's original seats before accepting their Steam connection.
    virtual void service(const std::function<bool(Id)>& allowed) = 0;
    virtual std::string diagnostics() = 0;
};
} // namespace isaac::lan::steam
