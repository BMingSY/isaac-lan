#include "net/input_events.h"
#include "test_support.h"

using namespace isaac::lan;
int main() {
    InputEvents sender, receiver;
    InputRoom room{1, 84, 0};
    InputFrame press;
    press.triggered = 1u << isaac::input::action::item;
    const auto first = *sender.submit({0, press, room});
    const auto second = *sender.submit({2, press, room});
    receiver.receive(second);
    require(!receiver.consume(2, room, true), "A later press overtook a missing predecessor");
    // Only the next held sample survives; it carries both recent events.
    const auto message = inputMessage({3, {}, room}, sender.recent());
    require(message.bytes.size() < 1200, "Repeated input exceeded one datagram");
    Reader r(std::span(message.bytes).subspan(1));
    const auto held = readInput(r);
    const auto count = r.u8();
    for (unsigned i = 0; i < count; ++i)
        receiver.receive(readInputEvent(r));
    r.finish();
    require(held.sequence == 3 && receiver.consume(3, room, true) == press.triggered,
            "Next held sample failed to recover a lost short press");
    receiver.receive(first); // Delayed reliable fallback must not repeat it.
    receiver.receive(second);
    require(receiver.consume(3, room, true) == press.triggered && !receiver.consume(3, room, true),
            "Two presses collapsed or a reliable duplicate fired again");
    auto nextRoom = room;
    ++nextRoom.index;
    receiver.receive(*sender.submit({4, press, room}));
    require(!receiver.consume(4, nextRoom, true), "Old-room item action escaped");
    receiver.receive(*sender.submit({5, press, nextRoom}));
    require(receiver.consume(5, nextRoom, true) == press.triggered,
            "Expiring an old-room action blocked the current room");
    auto nextFloor = nextRoom;
    ++nextFloor.epoch;
    receiver.receive(*sender.submit({6, press, nextRoom}));
    receiver.receive(*sender.submit({7, press, nextFloor}));
    require(receiver.consume(7, nextFloor, true) == press.triggered &&
                !receiver.consume(7, nextFloor, true),
            "Reliable floor gap leaked an old action or blocked a new one");
    const auto expired = *sender.submit({8, press, nextFloor});
    receiver.receive(expired);
    require(!receiver.consume(129, nextFloor, true), "Expired action was replayed");
    receiver.receive(*sender.submit({130, press, nextFloor}));
    require(!receiver.consume(130, nextFloor, false), "Stale held input enabled an event");
    receiver.receive(*sender.submit({131, press, nextFloor}));
    require(receiver.consume(131, nextFloor, true) == press.triggered,
            "Expired input left a permanent ordinal gap");
    sender.submit({144, {}, nextFloor});
    require(sender.recent().empty(), "Old events wasted bandwidth indefinitely");
    for (unsigned sequence = 145; sequence < 155; ++sequence)
        sender.submit({sequence, press, nextFloor});
    require(sender.recent().size() == maxRepeatedInputEvents, "Repeated history grew unbounded");
    receiver = {};
    sender = {};
    receiver.receive(*sender.submit({0, press, room}));
    require(receiver.consume(0, room, true) == press.triggered, "Rejoin retained the old stream");
    rejects([&] { receiver.receive({999, {1, press, room}}); }, "Unbounded event gap accepted");
    rejects([&] { receiver.receive({2, {1, {}, room}}); }, "Empty event accepted");
    std::puts("PASS repeated inputs, ordering, reliable fallback, expiry and lifecycle");
}
