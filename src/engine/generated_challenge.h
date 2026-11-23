#pragma once
#include <cstdint>

namespace isaac::engine {
// Use the selected vanilla challenge for route queries. Only DELETE THIS
// supplies room appearance. Each run retains its LAN identity and characters.
bool installGeneratedChallenge(std::uintptr_t image, unsigned (*rewardChallenge)());
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
