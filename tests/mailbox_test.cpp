#include "core/spsc_queue.h"
#include "core/latest_mailbox.h"
#include "test_support.h"
#include <thread>
#include <cstdint>

int main() {
    return runTests(
        0, nullptr,
        {{"ownership-and-order", [] {
              isaac::SpscQueue<std::unique_ptr<unsigned>, 2> bounded;
              auto first = std::make_unique<unsigned>(1), second = std::make_unique<unsigned>(2),
                   third = std::make_unique<unsigned>(3);
              require(bounded.push(std::move(first)) && bounded.push(std::move(second)),
                      "Queue filled early");
              require(!bounded.push(std::move(third)) && third && *third == 3,
                      "Backpressure lost producer ownership");
              require(**bounded.pop() == 1 && **bounded.pop() == 2 && !bounded.pop(),
                      "Queue reordered or duplicated values");
              constexpr unsigned count = 100000;
              isaac::SpscQueue<std::unique_ptr<unsigned>, 8> queue;
              std::thread producer([&] {
                  for (unsigned i = 0; i < count; ++i) {
                      auto value = std::make_unique<unsigned>(i);
                      while (!queue.push(std::move(value)))
                          std::this_thread::yield();
                  }
              });
              bool ordered = true;
              for (unsigned i = 0; i < count;) {
                  if (auto value = queue.pop()) {
                      ordered &= **value == i;
                      ++i;
                  } else
                      std::this_thread::yield();
              }
              producer.join();
              require(ordered && queue.empty(), "Concurrent handoff changed order or ownership");
              isaac::LatestMailbox<unsigned> latest;
              for (unsigned i = 0; i < count; ++i)
                  latest.publish(std::make_unique<unsigned>(i));
              require(*latest.take() == count - 1 && !latest.take(),
                      "Latest mailbox retained obsolete work");
          }}});
}
