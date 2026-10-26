#include "engine/versions/j460/completion_marks.h"
#include <cstdio>
#include <stdexcept>

namespace {
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
} // namespace
int main() {
    try {
        using namespace isaac::engine::j460::completion;
        isaac::lan::Progress host, guest;
        // Isaac: paper, heart, cross, inverted cross. Higher bits belong to
        // official online completion and must not change the single-player card.
        host.counters[173] = 2;
        host.counters[27] = 1 | 8;
        host.counters[41] = 2 | 4;
        host.counters[55] = 8;
        guest.counters[27] = 2;
        const auto marks = layers(preview(0, host));
        require(marks && (*marks)[0] == 2 && (*marks)[1] == 1 && (*marks)[2] == 2 &&
                    (*marks)[3] == 0 && (*marks)[11] == 0,
                "Single-player marks did not preserve normal/hard or strip online colors");
        require((*layers(preview(0, guest)))[1] == 2 && (*layers(preview(21, host)))[1] == 0,
                "Completion crossed a peer or normal/tainted character boundary");
        host.counters[216] = 1;
        require((*layers(preview(21, host)))[1] == 1,
                "Tainted Isaac did not read its own completion counter");
        host.counters[203] = 2;
        require(preview(16, host) == preview(17, host), "Forgotten/Soul did not share marks");
        require(!layers(preview(4096, host)) && !layers(available | 3) &&
                    !layers(available | (1u << 31)),
                "Unavailable or malformed marks accepted");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
