#pragma once
#include <enet/enet.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <memory>
#include <span>
#include <string>

namespace isaac::lan {
// Authenticated platform accounts act as ENet endpoint addresses. These values
// never go through DNS, Winsock or the wire protocol.
inline ENetAddress accountAddress(std::uint64_t id) {
    ENetAddress address{};
    address.family = ENET_ADDRESS_IPV6;
    std::memcpy(address.host6, &id, sizeof(id));
    return address;
}
inline std::uint64_t addressAccount(const ENetAddress& address) {
    std::uint64_t id = 0;
    std::memcpy(&id, address.host6, sizeof(id));
    return id;
}
inline std::string accountIdentity(std::uint64_t account) {
    std::string value(32, '0');
    for (auto i = value.size(); account; account >>= 4)
        value[--i] = "0123456789abcdef"[account & 15];
    return value;
}
class DatagramRoute {
  public:
    enum class State { connecting, connected, closed };
    virtual State state() = 0;
    virtual ~DatagramRoute() = default;
    virtual std::uint64_t localAccount() const = 0;
    virtual std::uint64_t hostAccount() const = 0;
    virtual std::shared_ptr<DatagramRoute> reconnect() = 0;
    virtual int send(std::uint64_t destination, std::span<const std::uint8_t> bytes) = 0;
    // Zero means empty, -2 discards one malformed datagram, -1 closes the endpoint.
    virtual int receive(std::uint64_t& source, std::span<std::uint8_t> bytes) = 0;
};
} // namespace isaac::lan
