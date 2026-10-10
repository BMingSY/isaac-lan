#pragma once
#include <optional>
#include <string_view>

namespace isaac::input {
inline std::optional<std::string_view> consoleArguments(std::string_view command,
                                                        std::string_view name) {
    const auto separator = command.find_first_of(" \t\r\n");
    if (command.substr(0, separator) != name)
        return {};
    return separator == std::string_view::npos ? std::string_view{} : command.substr(separator + 1);
}
inline std::optional<std::string_view> botConsoleArguments(std::string_view command) {
    return consoleArguments(command, "lanbot");
}
} // namespace isaac::input
