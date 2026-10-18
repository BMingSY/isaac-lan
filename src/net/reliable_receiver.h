#pragma once
#include "net/messages.h"

namespace isaac::lan {
struct ReceivedBulk {
    std::optional<Stage> stage;
    std::vector<std::uint8_t> checkpoint;
    std::size_t size() const {
        return stage ? sizeof(Stage) + stage->rewind.size() : checkpoint.size();
    }
};
// Socket-thread assembly only. Lifecycle acceptance and native restoration are
// still decided by Session on the main thread, in received message order.
class ReliableReceiver {
    std::size_t checkpointSize = 0, stageSize = 0;
    std::vector<std::uint8_t> checkpoint, stageBytes;
    std::optional<Stage> stage;

  public:
    void reset() {
        checkpointSize = stageSize = 0;
        checkpoint = {};
        stageBytes = {};
        stage.reset();
    }
    void begin(const StartEnvelope& value) {
        reset();
        checkpointSize = value.size;
    }
    std::optional<ReceivedBulk> snapshot(Reader& r) {
        if (!checkpointSize)
            throw std::runtime_error("Unexpected checkpoint chunk");
        const auto offset = r.u32();
        const auto bytes = r.blob(bulkChunkSize);
        r.finish();
        appendBulkChunk(checkpoint, checkpointSize, offset, bytes,
                        maxSnapshotSize + StateCompression::headerSize);
        if (checkpoint.size() != checkpointSize)
            return {};
        checkpointSize = 0;
        return ReceivedBulk{{}, std::move(checkpoint)};
    }
    std::optional<ReceivedBulk> floor(Reader& r) {
        auto chunk = readStageChunk(r);
        r.finish();
        if (!chunk.offset) {
            if (stage)
                throw std::runtime_error("Overlapping rewind transaction");
            stage = chunk.settings;
            stageSize = chunk.total;
        }
        if (!stage || *stage != chunk.settings || stageSize != chunk.total)
            throw std::runtime_error("Invalid rewind transaction chunk");
        appendBulkChunk(stageBytes, stageSize, chunk.offset, chunk.bytes,
                        maxSnapshotSize + StateCompression::headerSize);
        if (stageBytes.size() != stageSize)
            return {};
        stage->rewind = std::move(stageBytes);
        auto result = ReceivedBulk{std::move(stage), {}};
        stage.reset();
        stageBytes = {};
        return result;
    }
};
} // namespace isaac::lan
