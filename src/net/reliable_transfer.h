#pragma once
#include "net/checkpoint_transfer.h"
#include "net/messages.h"

namespace isaac::lan {
// An immutable prepared transaction. Only the socket owner advances its offset.
struct ReliableTransfer {
    std::shared_ptr<const PreparedCheckpoint> checkpoint;
    std::shared_ptr<const Stage> stage;
    std::vector<std::uint8_t> header;
    std::size_t size() const {
        return checkpoint ? checkpoint->wire.size() : stage->rewind.size();
    }
    Writer chunk(std::size_t offset) const {
        if (stage)
            return stageMessage(*stage, offset);
        Writer w(Message::snapshot);
        w.u32(offset);
        w.blob(bulkChunk(checkpoint->wire, offset));
        return w;
    }
};
} // namespace isaac::lan
