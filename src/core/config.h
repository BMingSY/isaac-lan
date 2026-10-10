#pragma once
#include "core/log_record.h"
#include <charconv>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::configuration {
struct Settings {
    logging::Level logLevel = logging::Level::info;
    bool performance = false;
    unsigned sampleIntervalMs = 1000;
};
struct Parsed {
    Settings settings;
    std::vector<std::string> warnings;
};
inline constexpr std::string_view defaults =
    "; Isaac LAN: changes take effect after restarting the game.\n"
    "; Logs are separated by launch and run, and are kept until manually removed.\n"
    "[logging]\nlevel = INFO\n\n"
    "[diagnostics]\nperformance = false\nsample_interval_ms = 1000\n";
inline std::string_view trim(std::string_view s) {
    const auto begin = s.find_first_not_of(" \t\r");
    return begin == s.npos ? std::string_view{}
                           : s.substr(begin, s.find_last_not_of(" \t\r") - begin + 1);
}
inline Parsed parse(std::string_view source) {
    Parsed result;
    if (source.starts_with("\xef\xbb\xbf"))
        source.remove_prefix(3);
    std::string section;
    std::vector<std::string> seen;
    unsigned line = 0;
    while (!source.empty()) {
        ++line;
        const auto end = source.find('\n');
        auto text = trim(source.substr(0, end));
        source = end == source.npos ? std::string_view{} : source.substr(end + 1);
        const auto warn = [&](std::string reason) {
            result.warnings.push_back("line=" + std::to_string(line) + " " + reason);
        };
        if (text.empty() || text.front() == ';' || text.front() == '#')
            continue;
        if (text.front() == '[' && text.back() == ']') {
            section = trim(text.substr(1, text.size() - 2));
            continue;
        }
        const auto equal = text.find('=');
        if (equal == text.npos) {
            warn("invalid_assignment");
            continue;
        }
        const auto key = section + "." + std::string(trim(text.substr(0, equal)));
        const auto value = trim(text.substr(equal + 1));
        bool duplicate = false;
        for (const auto& previous : seen)
            duplicate |= previous == key;
        if (duplicate) {
            warn("duplicate_key=" + key);
            continue;
        }
        seen.push_back(key);
        if (key == "logging.level") {
            if (value == "DEBUG")
                result.settings.logLevel = logging::Level::debug;
            else if (value == "INFO")
                result.settings.logLevel = logging::Level::info;
            else if (value == "WARN")
                result.settings.logLevel = logging::Level::warning;
            else if (value == "ERROR")
                result.settings.logLevel = logging::Level::error;
            else
                warn("invalid_value=" + key);
        } else if (key == "diagnostics.performance") {
            if (value == "true" || value == "false")
                result.settings.performance = value == "true";
            else
                warn("invalid_value=" + key);
        } else if (key == "diagnostics.sample_interval_ms") {
            unsigned interval = 0;
            const auto [endValue, error] =
                std::from_chars(value.data(), value.data() + value.size(), interval);
            if (error == std::errc{} && endValue == value.data() + value.size() &&
                interval >= 100 && interval <= 60000)
                result.settings.sampleIntervalMs = interval;
            else
                warn("invalid_value=" + key);
        } else
            warn("unknown_key=" + key);
    }
    return result;
}
} // namespace isaac::configuration
