#pragma once

namespace isaac::bootstrap {
enum class Profile { installed, isolated, wrongPath, missingMarker };

// A lab environment can outlive its launcher in Steam. It may redirect only
// the marked executable it names, never an ordinary installed game.
constexpr Profile profile(bool installed, bool requestedLab, bool matchesLab, bool markedLab) {
    if (requestedLab && matchesLab)
        return markedLab ? Profile::isolated : Profile::missingMarker;
    if (installed)
        return Profile::installed;
    return requestedLab ? Profile::wrongPath : Profile::missingMarker;
}
} // namespace isaac::bootstrap
