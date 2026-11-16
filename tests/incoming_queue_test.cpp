#include "net/incoming_queue.h"
#include "test_support.h"
#include <thread>
using namespace isaac::lan;

static IncomingPacket message(Message type, unsigned value) {
    Writer writer(type);
    writer.u32(value);
    return {std::move(writer.bytes), {}, {}};
}
static IncomingPacket view(unsigned tick) {
    IncomingPacket packet;
    packet.world = WorldState{};
    packet.world->tick = tick;
    packet.world->bytes = {1};
    return packet;
}
int main() {
    return runTests(
        0, nullptr,
        {{"latest-and-barriers",
          [] {
              IncomingQueue queue;
              for (unsigned i = 0; i < 10000; ++i) {
                  require(queue.push(view(i)), "Realtime views exhausted receive capacity");
                  require(queue.push(message(Message::input, i)),
                          "Held inputs exhausted receive capacity");
              }
              require(queue.push(message(Message::inputEdges, 7)),
                      "An action lost its reserved space");
              require(queue.push(view(10000)), "New view was rejected after a reliable barrier");
              auto action = queue.pop();
              require(action && action->bytes.front() == static_cast<unsigned>(Message::inputEdges),
                      "Latest state overtook the preceding action");
              auto latest = queue.pop();
              require(latest && latest->world && latest->world->tick == 10000,
                      "A slow consumer retained obsolete views");
              auto input = queue.pop();
              Reader reader(std::span(input->bytes).subspan(1));
              require(reader.u32() == 9999 && !queue.pop(),
                      "Input replacement lost the latest sample");
              require(queue.empty() && queue.queuedBytes() == 0, "Drained queue retained work");
              queue.push(view(10001));
              queue.push(message(Message::input, 10001));
              queue.invalidate();
              require(!queue.pop(), "A realtime value crossed a generation boundary");
              queue.push(message(Message::start, 1));
              queue.push(view(0));
              require(!queue.pop()->world && queue.pop()->world->tick == 0,
                      "New run did not retain reliable-before-world order");
          }},
         {"concurrent-barriers",
          [] {
              IncomingQueue queue;
              std::atomic<bool> done{false};
              constexpr unsigned publications = 20000;
              std::thread producer([&] {
                  for (unsigned i = 1; i <= publications; ++i) {
                      while (!queue.push(message(Message::communication, i)))
                          std::this_thread::yield();
                      queue.push(view(i));
                  }
                  done.store(true, std::memory_order_release);
              });
              unsigned controls = 0, latest = 0;
              bool ordered = true;
              while (!done.load(std::memory_order_acquire) || !queue.empty()) {
                  if (auto packet = queue.pop()) {
                      if (packet->world) {
                          ordered &=
                              packet->world->tick <= controls && packet->world->tick > latest;
                          latest = packet->world->tick;
                      } else {
                          Reader reader(std::span(packet->bytes).subspan(1));
                          ordered &= reader.u32() == ++controls;
                      }
                  } else
                      std::this_thread::yield();
              }
              producer.join();
              require(ordered && controls == publications && latest == publications,
                      "Concurrent handoff lost ordering, a reliable message or the final view");
              require(queue.queuedBytes() == 0, "Concurrent drain leaked the byte budget");
          }},
         {"overflow-isolation", [] {
              IncomingQueue full, healthy;
              for (unsigned i = 0; i < 128; ++i)
                  require(full.push(message(Message::communication, i)),
                          "Reliable queue filled early");
              require(!full.push(message(Message::communication, 128)),
                      "Reliable queue was unbounded");
              healthy.push(message(Message::inputEdges, 1));
              healthy.push(view(2));
              require(healthy.pop().has_value() && healthy.pop()->world->tick == 2,
                      "Another connection could not progress");
              for (unsigned i = 0; i < 128; ++i) {
                  auto packet = full.pop();
                  Reader reader(std::span(packet->bytes).subspan(1));
                  require(reader.u32() == i, "Reliable overflow corrupted the retained order");
              }
              IncomingPacket archive;
              archive.bulk = ReceivedBulk{};
              archive.bulk->checkpoint.resize(maxSnapshotSize);
              require(full.push(std::move(archive)),
                      "A valid archive exceeded the current-value allowance");
              require(full.push(message(Message::ping, 1)),
                      "A large archive consumed all control capacity");
              IncomingPacket another;
              another.bulk = ReceivedBulk{};
              another.bulk->checkpoint = {1};
              require(!full.push(std::move(another)),
                      "Archive backpressure exceeded its byte bound");
              require(full.pop()->bulk.has_value() && full.pop().has_value() &&
                          full.queuedBytes() == 0,
                      "Archive drain did not release the byte budget");
          }}});
}
