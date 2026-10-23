#include "core/menu_input.h"
#include "core/automation_input.h"
#include "test_support.h"
#include <limits>

int main(int argc, char** argv) {
    using namespace isaac;
    lan::InputFrame input;
    input.values[input::action::moveRight] = lan::maxInputValue;
    input.pointer = {true, -123.25f, 876.5f};
    if (argc == 2 && std::string_view(argv[1]) == "--wire") {
        for (const auto& sample : {lan::InputFrame{}, input}) {
            lan::Writer packet(lan::Message::input);
            packet.input(sample);
            for (std::size_t i = 1; i < packet.bytes.size(); ++i)
                std::printf("%02x", packet.bytes[i]);
            std::puts("");
        }
        return 0;
    }
    lan::Writer encoded(lan::Message::input);
    encoded.input(input);
    require(encoded.bytes.size() == lan::inputWireSize + 1,
            "Input size disagrees with local capture");
    lan::Reader reader{std::span(encoded.bytes).subspan(1)};
    require(reader.input() == input, "Pointer roundtrip failed");
    reader.finish();
    const auto good = encoded.bytes;
    constexpr auto pointerOffset = lan::actionCount * 2 + 2 + 1;
    for (const auto value : {2, 255}) {
        encoded.bytes = good;
        encoded.bytes[pointerOffset] = value;
        rejects([&] { lan::Reader{std::span(encoded.bytes).subspan(1)}.input(); },
                "Invalid pointer flag accepted");
    }
    for (const auto value : {std::numeric_limits<float>::infinity(),
                             std::numeric_limits<float>::quiet_NaN(), 32769.0f}) {
        input.pointer.x = value;
        rejects([&] { lan::Writer(lan::Message::input).input(input); },
                "Invalid outbound pointer accepted");
        encoded.bytes = good;
        lan::Writer invalid(lan::Message::input);
        invalid.u32(std::bit_cast<std::uint32_t>(value));
        std::copy(invalid.bytes.begin() + 1, invalid.bytes.end(),
                  encoded.bytes.begin() + pointerOffset + 1);
        rejects([&] { lan::Reader{std::span(encoded.bytes).subspan(1)}.input(); },
                "Invalid inbound pointer accepted");
    }
    for (std::size_t size = 0; size < lan::inputWireSize; ++size)
        rejects([&] { lan::Reader{std::span(good).subspan(1, size)}.input(); },
                "Truncated pointer accepted");
    input.pointer = {true, 123, 456};
    require(input::transitionInput(input, true).pointer == input.pointer &&
                input::pausedInput(input).pointer == input.pointer,
            "Transition/pause released held mouse fire");
    require(!input::transitionInput(input, false).pointer.active &&
                !lan::menuInput(input).pointer.active,
            "Pointer crossed a floor/menu input boundary");
    input::ModalInput modal;
    auto sample = input;
    modal.filter(sample, true);
    require(sample == lan::InputFrame{}, "Modal UI leaked pointer input");
    sample = input;
    modal.filter(sample, false);
    require(!sample.pointer.active, "Closing chat fired a held mouse button");
    sample = {};
    modal.filter(sample, false);
    sample = input;
    modal.filter(sample, false);
    require(sample == input, "Mouse did not rearm after release");
    input::AutomationInput bot;
    bot.set(true, 0, 1);
    require(!bot.compose(input, 1, false).pointer.active &&
                !bot.compose(input, 10, true).pointer.active,
            "Manual pointer bypassed automation ownership");
    bot.clear();
    require(bot.compose(input, 11, false) == input,
            "Manual pointer did not recover after automation");
    std::puts("PASS pointer wire, malformed inputs, modal, automation and lifecycle filtering");
}
