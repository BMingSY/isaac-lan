#pragma once
#include "core/startup_error.h"

namespace isaac::diagnostics {
std::uint32_t startupFailure(const startup::Failure& failure) noexcept;
// Borrowed UTF-16 text, valid until the next failure or module unload.
const wchar_t* startupFailureMessage() noexcept;
} // namespace isaac::diagnostics
