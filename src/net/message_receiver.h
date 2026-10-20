#pragma once
#include "net/network_io.h"
#include "net/messages.h"

namespace isaac::lan {
// Both transports share reliable transaction decoding and cache invalidation.
// Delivery framing, generation checks and scheduling stay with the transport.
template <class Respond>
IncomingPacket receiveMessage(std::vector<std::uint8_t> bytes, WorldTransfer& world,
                              ReliableReceiver& reliable, bool answerPing, Respond respond) {
    IncomingPacket packet;
    const auto type = static_cast<Message>(bytes.at(0));
    Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
    if (type == Message::snapshot) {
        packet.bulk = reliable.snapshot(r);
    } else if (type == Message::stage) {
        packet.bulk = reliable.floor(r);
        if (packet.bulk)
            world.resetReceiver();
    } else if (type == Message::ping && answerPing) {
        Writer pong(Message::pong);
        pong.u32(r.u32());
        r.finish();
        respond(std::move(pong));
    } else {
        bool deliver = true;
        if (type == Message::applied) {
            const auto epoch = r.u32(), tick = r.u32();
            r.finish();
            deliver = world.acknowledge(epoch, tick);
        }
        if (type == Message::start || type == Message::restart || type == Message::ending ||
            type == Message::returnLobby) {
            world.resetReceiver();
            reliable.reset();
        }
        if (type == Message::start || type == Message::restart) {
            reliable.begin(readStart(r));
            r.finish();
        }
        if (deliver)
            packet.bytes = std::move(bytes);
    }
    return packet;
}
} // namespace isaac::lan
