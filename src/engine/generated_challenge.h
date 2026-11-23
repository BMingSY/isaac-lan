#pragma once
#include <cstdint>

namespace isaac::engine {
// Independently select the generated-item room style and the native challenge
// used for route queries. The run keeps its LAN identity and characters.
bool installGeneratedChallenge(std::uintptr_t image, bool (*useGlitchedStyle)(),
                               unsigned (*rewardChallenge)());
// Borrow the original native challenge only while a room produces its clear
// reward. This gives locked profiles the same route as the original challenge.
class ChallengeRewardScope {
  public:
    ChallengeRewardScope();
    ~ChallengeRewardScope();
    ChallengeRewardScope(const ChallengeRewardScope&) = delete;
    ChallengeRewardScope& operator=(const ChallengeRewardScope&) = delete;

  private:
    unsigned* challenge = nullptr;
    unsigned previous = 0;
};
} // namespace isaac::engine
