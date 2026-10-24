#include "net/network_io.h"

namespace isaac::lan {
NetworkIo::NetworkIo() {
    thread = CreateThread(nullptr, 0, run, this, 0, nullptr);
    if (!thread)
        throw std::runtime_error("Cannot start network worker");
}
NetworkIo::~NetworkIo() {
    stop();
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
}
DWORD WINAPI NetworkIo::run(void* argument) {
    static_cast<NetworkIo*>(argument)->runDatagrams();
    return 0;
}
} // namespace isaac::lan
