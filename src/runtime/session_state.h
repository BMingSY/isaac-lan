#pragma once
#include "runtime/session_archive.h"
#include "runtime/pending_archive.h"
#include <optional>
#include <chrono>
#include <utility>
namespace isaac::runtime {
struct RestartState {
    bool requested = false, exiting = false, heldVoted = false;
    std::optional<std::chrono::steady_clock::time_point> heldAt;
    void close(bool preserveConnection) {
        requested = false;
        if (!preserveConnection)
            *this = {};
    }
};
struct LaunchState {
    bool requested = false, resume = false, promptsPending = false;
};
// View caches end at close; personal-save protection outlives MC_PRE_GAME_EXIT.
struct SessionView {
    bool gated = false, pendingHalf = false;
    bool playingEnding = false, playingCinematic = false, cinematicReady = false;
    std::uint32_t floorEpoch = 0;
    bool firstFloor = false;
    std::optional<std::pair<std::uint8_t, std::uint8_t>> autosaveFloor;
    std::optional<lan::WorldState> authoritative, replicaPending;
    std::optional<unsigned> pendingChallengeFinish;
    void stop() {
        gated = pendingHalf = playingEnding = playingCinematic = cinematicReady = false;
        pendingChallengeFinish.reset();
        firstFloor = false;
        autosaveFloor.reset();
    }
    void clearSnapshots() {
        authoritative.reset();
        replicaPending.reset();
        floorEpoch = 0;
    }
};
struct SavedRun {
    PendingArchive pendingArchive;
    std::string saveError;
    bool networkRun = false, soloContinueAvailable = false;
    bool exitingHost = false, exitingTransient = false;
    std::vector<std::uint8_t> soloState;
    std::optional<std::uint32_t> soloDiskChecksum;
    std::optional<lan::Archive> exitingArchive, resumingArchive;
    std::optional<lan::Progress> localProgress, commonProgress;
    lan::ProgressAwards earnedProgress;
};
} // namespace isaac::runtime
