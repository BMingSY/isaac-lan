#pragma once
#include <string>
#include <string_view>

namespace isaac::logging {
enum class Level { debug, info, warning, error };
inline Level level(std::string_view message) {
    for (auto token : {"=FAIL", "=ERROR", "_failure=", "_error=", "native_exception"})
        if (message.find(token) != message.npos)
            return Level::error;
    for (auto token : {"=IGNORED", "=TIMEOUT", "half_late=", "network_stall"})
        if (message.find(token) != message.npos)
            return Level::warning;
    for (auto token : {"state_cost ", "state_transfer ", "input_query_rva="})
        if (message.starts_with(token))
            return Level::debug;
    return Level::info;
}
inline std::string record(std::string_view timestamp, unsigned process, Level severity,
                          std::string_view message) {
    const char* names[] = {"DEBUG", "INFO", "WARN", "ERROR"};
    std::string result = "[" + std::string(timestamp) + "] [" +
                         names[static_cast<unsigned>(severity)] +
                         "] [pid=" + std::to_string(process) + "] ";
    for (auto c : message)
        if (c == '\r')
            result += "\\r";
        else if (c == '\n')
            result += "\\n";
        else
            result += c;
    return result + "\r\n";
}
} // namespace isaac::logging
