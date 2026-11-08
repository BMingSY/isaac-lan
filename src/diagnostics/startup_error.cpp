#include "diagnostics/startup_error.h"
#include "diagnostics/runtime_log.h"
#include <windows.h>

namespace isaac::diagnostics {
namespace {
std::wstring lastFailure;
}
std::uint32_t startupFailure(const startup::Failure& failure) noexcept {
    try {
        lastFailure = startup::message(failure);
        OutputDebugStringW(lastFailure.c_str());
        const auto size =
            WideCharToMultiByte(CP_UTF8, 0, lastFailure.data(),
                                static_cast<int>(lastFailure.size()), nullptr, 0, nullptr, nullptr);
        std::string encoded(size, '\0');
        WideCharToMultiByte(CP_UTF8, 0, lastFailure.data(), static_cast<int>(lastFailure.size()),
                            encoded.data(), size, nullptr, nullptr);
        logging::write("startup_failure=" + encoded);
    } catch (...) {
        // Reporting must preserve the original failure, even before logs exist.
        lastFailure.clear();
    }
    return startup::value(failure.code);
}
const wchar_t* startupFailureMessage() noexcept {
    return lastFailure.c_str();
}
} // namespace isaac::diagnostics
