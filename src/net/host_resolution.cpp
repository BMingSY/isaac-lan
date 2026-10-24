#include "net/host_resolution.h"
#include <ws2tcpip.h>
#include <algorithm>
#include <stdexcept>
namespace isaac::lan {
namespace {
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
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;
        addrinfo* found = nullptr;
        result.error = getaddrinfo(request->address.c_str(), nullptr, &hints, &found);
        if (!result.error) {
            for (auto entry = found; entry && result.addresses.size() < 16;
                 entry = entry->ai_next) {
                if (entry->ai_family != AF_INET || entry->ai_addrlen != sizeof(sockaddr_in))
                    continue;
                auto address = *reinterpret_cast<const sockaddr_in*>(entry->ai_addr);
                address.sin_port = htons(request->port);
                if (std::none_of(result.addresses.begin(), result.addresses.end(),
                                 [&](const auto& prior) {
                                     return prior.sin_addr.s_addr == address.sin_addr.s_addr;
                                 }))
                    result.addresses.push_back(address);
            }
            freeaddrinfo(found);
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
