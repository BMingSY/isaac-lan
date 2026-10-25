#include "net/host_resolution.h"
#include <ws2tcpip.h>
#include <algorithm>
#include <stdexcept>
namespace isaac::lan {
namespace {
constexpr std::size_t maxHostAddresses = 16;
struct ResolveRequest {
    std::shared_ptr<HostResolution> result;
    std::string address;
    std::uint16_t port;
};
DWORD WINAPI resolveHost(void* argument) {
    const std::unique_ptr<ResolveRequest> request(static_cast<ResolveRequest*>(argument));
    auto& result = *request->result;
    WSADATA data{};
    result.error = WSAStartup(MAKEWORD(2, 2), &data);
    if (!result.error) {
        addrinfo hints{};
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;
        addrinfo* found = nullptr;
        result.error = getaddrinfo(request->address.c_str(), nullptr, &hints, &found);
        if (!result.error) {
            std::vector<ENetAddress> ipv6, ipv4;
            for (auto entry = found; entry; entry = entry->ai_next) {
                ENetAddress address{};
                if (enet_address_set_sockaddr(&address, entry->ai_addr,
                                              static_cast<int>(entry->ai_addrlen)))
                    continue;
                address.port = request->port;
                auto& family = address.family == ENET_ADDRESS_IPV6 ? ipv6 : ipv4;
                if (family.size() < maxHostAddresses &&
                    std::none_of(family.begin(), family.end(), [&](const auto& prior) {
                        return enet_address_equal_host(&prior, &address);
                    }))
                    family.push_back(address);
            }
            freeaddrinfo(found);
            // Try both families early, even when DNS returns many AAAA records.
            for (std::size_t i = 0; i < std::max(ipv6.size(), ipv4.size()); ++i) {
                if (i < ipv6.size())
                    result.addresses.push_back(ipv6[i]);
                if (i < ipv4.size())
                    result.addresses.push_back(ipv4[i]);
            }
            if (result.addresses.size() > maxHostAddresses)
                result.addresses.resize(maxHostAddresses);
        }
        WSACleanup();
    }
    result.ready.store(true, std::memory_order_release);
    return 0;
}
} // namespace
std::shared_ptr<HostResolution> resolveHost(const std::string& address, std::uint16_t port) {
    auto result = std::make_shared<HostResolution>();
    auto request = std::make_unique<ResolveRequest>(ResolveRequest{result, address, port});
    const auto worker = CreateThread(nullptr, 0, resolveHost, request.get(), 0, nullptr);
    if (!worker)
        throw std::runtime_error("Cannot start host name resolution");
    request.release();
    CloseHandle(worker);
    return result;
}
} // namespace isaac::lan
