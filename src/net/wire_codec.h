#pragma once
#include "net/compression.h"
#include "net/protocol.h"

namespace isaac::lan {
inline constexpr std::uint8_t compressedMessageTag = 0x80;
inline constexpr std::size_t minimumMessageCompressionSize = 256;
// One framing policy for every control, chat and extension message. Bulk lanes
// already carry bounded compressed transactions, so do not compress each chunk
// again. Small or incompressible messages keep their original wire bytes.
inline std::vector<std::uint8_t> encodeWire(std::vector<std::uint8_t> message,
                                            StateCompression& codec) {
    if (!validMessageSize(message))
        throw std::runtime_error("Invalid outgoing message size");
    const auto type = static_cast<Message>(message.front());
    if (message.size() < minimumMessageCompressionSize || type == Message::world ||
        type == Message::snapshot || type == Message::stage)
        return message;
    auto compressed = codec.compress(message);
    if (compressed.size() + 1 >= message.size())
        return message;
    compressed.insert(compressed.begin(), compressedMessageTag);
    return compressed;
}
inline std::vector<std::uint8_t> decodeWire(std::span<const std::uint8_t> message,
                                            StateCompression& codec) {
    if (!message.empty() && message.front() == compressedMessageTag &&
        message.size() <= maxLobbyMessageSize) {
        auto decoded = codec.expand(message.subspan(1));
        if (validMessageSize(decoded))
            return decoded;
    } else if (validMessageSize(message)) {
        return {message.begin(), message.end()};
    }
    throw std::runtime_error("Invalid incoming message size");
}
} // namespace isaac::lan
