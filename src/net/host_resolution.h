#pragma once
#include <winsock2.h>
#include <atomic>
#include <memory>
#include <vector>
#include <string>
#include <cstdint>
namespace isaac::lan {
struct HostResolution {
    std::atomic<bool> ready{false};
    std::vector<sockaddr_in> addresses;
    int error = 0;
};
std::shared_ptr<HostResolution> resolveHost(const std::string& address, std::uint16_t port);
} // namespace isaac::lan
