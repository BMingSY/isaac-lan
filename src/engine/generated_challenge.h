#pragma once
#include <cstdint>

namespace isaac::engine {
// Select the original generated-item challenge's room appearance and route
// queries. The run itself retains its LAN identity and selected characters.
bool installGeneratedChallenge(std::uintptr_t image, bool (*enabled)());
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
