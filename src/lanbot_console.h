#pragma once
#include <optional>
#include <string_view>

namespace isaac::input {
inline std::optional<std::string_view> botConsoleArguments(std::string_view command) {
    const auto separator = command.find_first_of(" \t\r\n");
    if (command.substr(0, separator) != "lanbot")
        return {};
    return separator == std::string_view::npos ? std::string_view{} : command.substr(separator + 1);
}
} // namespace isaac::input
