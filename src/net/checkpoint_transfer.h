#pragma once
#include "net/byte_worker.h"
#include "net/bulk_transfer.h"

namespace isaac::lan {
struct PreparedCheckpoint {
    Start settings;
    std::vector<std::uint8_t> wire;
    std::uint64_t checksum = 0;
    std::size_t rawSize = 0;
};
using CheckpointPreparation = ByteResult<std::shared_ptr<const PreparedCheckpoint>>;
inline std::shared_ptr<CheckpointPreparation> prepareCheckpoint(BulkWorker& worker,
                                                                Start settings) {
    return worker.submit([settings = std::move(settings)](StateCompression& codec) mutable {
        auto result = std::make_shared<PreparedCheckpoint>();
        result->rawSize = settings.snapshot.size();
        result->wire = codec.compress(settings.snapshot);
        result->checksum = snapshotHash(result->wire);
        settings.snapshot = {};
        result->settings = std::move(settings);
        return std::shared_ptr<const PreparedCheckpoint>(std::move(result));
    });
}
inline std::shared_ptr<ByteResult<std::vector<std::uint8_t>>>
restoreCheckpoint(BulkWorker& worker, std::vector<std::uint8_t> wire, std::uint64_t checksum) {
    return worker.submit([wire = std::move(wire), checksum](StateCompression& codec) {
        if (snapshotHash(wire) != checksum)
            throw std::runtime_error("Checkpoint transfer is damaged");
        return codec.expand(wire);
    });
}
} // namespace isaac::lan
