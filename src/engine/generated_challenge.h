#pragma once
#include <cstdint>

namespace isaac::engine {
// The generated-item challenge's visual effects and its route to the Chest
// can be selected independently. The run keeps its LAN identity.
bool installGeneratedChallenge(std::uintptr_t image, bool (*useGlitchedStyle)(),
                               bool (*useBlueBabyRoute)());
// Borrow the original native challenge only while a room produces its clear
// reward. This gives locked profiles the same route as the original challenge.
class GeneratedChallengeRewardScope {
  public:
    GeneratedChallengeRewardScope();
    ~GeneratedChallengeRewardScope();
    GeneratedChallengeRewardScope(const GeneratedChallengeRewardScope&) = delete;
    GeneratedChallengeRewardScope& operator=(const GeneratedChallengeRewardScope&) = delete;

  private:
    unsigned* challenge = nullptr;
    unsigned previous = 0;
};
} // namespace isaac::engine
