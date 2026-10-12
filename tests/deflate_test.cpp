#include "core/deflate.h"
#include "test_support.h"
#include <array>
#include <random>

namespace {
constexpr std::size_t limit = 2 * 1024 * 1024;
void interoperability() {
    const std::array<std::uint8_t, 19> zlib = {0x78, 0x9c, 0xcb, 0x48, 0xcd, 0xc9, 0xc9,
                                               0x57, 0x28, 0xcf, 0x2f, 0xca, 0x49, 0x01,
                                               0x00, 0x1a, 0x0b, 0x04, 0x5d};
    const std::string expected = "hello world";
    const auto decoded = isaac::compression::inflate(zlib, expected.size(), limit);
    require(std::string(decoded.begin(), decoded.end()) == expected,
            "Independent standard zlib stream did not decode");
    std::mt19937 random(42);
    for (std::size_t size : {1u, 65535u, 65536u, 65537u, 2u * 1024 * 1024}) {
        std::vector<std::uint8_t> input(size);
        for (auto& byte : input)
            byte = random();
        const auto compressed = isaac::compression::deflate(input, limit);
        require(isaac::compression::inflate(compressed, input.size(), limit) == input,
                "Chunk-boundary or maximum-size state did not round trip");
    }
    std::vector<std::uint8_t> repeated(limit, 17);
    const auto compressed = isaac::compression::deflate(repeated, limit);
    require(compressed.size() < repeated.size() / 10 &&
                isaac::compression::inflate(compressed, repeated.size(), limit) == repeated,
            "Portable compression did not compress repeated state");
}
void bounds() {
    const std::vector<std::uint8_t> input(1024, 13);
    auto compressed = isaac::compression::deflate(input, limit);
    rejects([&] { isaac::compression::inflate(compressed, limit + 1, limit); },
            "Oversized output was accepted");
    rejects([&] { isaac::compression::inflate(compressed, input.size() - 1, limit); },
            "Wrong output length was accepted");
    auto trailing = compressed;
    trailing.push_back(0);
    rejects([&] { isaac::compression::inflate(trailing, input.size(), limit); },
            "Trailing compressed bytes were accepted");
    compressed.back() ^= 1;
    rejects([&] { isaac::compression::inflate(compressed, input.size(), limit); },
            "Damaged compressed checksum was accepted");
    rejects([&] { isaac::compression::deflate({}, limit); }, "Empty input was accepted");
    rejects([&] { isaac::compression::deflate(input, input.size() - 1); },
            "Unbounded input was accepted");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"interoperability", interoperability}, {"bounds", bounds}});
}
