#pragma once
#include <cstdint>

namespace isaac::engine::native_victory_prompt {
struct State {
    bool open = false;
    int selection = -1, result = 0;
    bool nativeVote = false, idle = false;
};
bool install(std::uintptr_t image);
State read();
} // namespace isaac::engine::native_victory_prompt
