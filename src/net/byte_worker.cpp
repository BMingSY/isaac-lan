#include "net/byte_worker.h"
#include "net/protocol.h"

namespace isaac::lan {
BulkWorker::BulkWorker() {
    thread = CreateThread(nullptr, 0, run, this, 0, nullptr);
    if (!thread)
        throw std::runtime_error("Cannot start bulk byte worker");
}
BulkWorker::~BulkWorker() {
    stop();
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
}
DWORD WINAPI BulkWorker::run(void* argument) {
    auto& self = *static_cast<BulkWorker*>(argument);
    try {
        StateCompression codec(maxSnapshotSize);
        while (!self.stopping.load(std::memory_order_acquire)) {
            if (!self.tasks.runOne(codec))
                WaitForSingleObject(self.wake.handle(), INFINITE);
        }
    } catch (const std::exception& error) {
        self.failure = error.what();
        self.failed.store(true, std::memory_order_release);
    }
    return 0;
}
} // namespace isaac::lan
