#pragma once
#include "core/log_record.h"
#include "core/chat.h"
#include <algorithm>
#include <charconv>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::configuration {
struct Settings {
    unsigned inputHz = 60;
    logging::Level logLevel = logging::Level::info;
    bool performance = false;
    unsigned sampleIntervalMs = 1000;
    chat::Appearance chat;
};
struct Parsed {
    Settings settings;
    std::vector<std::string> warnings;
    std::vector<std::string> keys{};
};
inline constexpr std::string_view defaults =
    "; Isaac LAN：修改后重启游戏生效。\n"
    "[network]\n"
    "; 客机输入发送频率：30 / 60，默认 60；各端可以不同。\n"
    "; 30 减少输入流量，但可能多等一个渲染帧；主机模拟和本机显示频率不变。\n"
    "input_hz = 60\n\n"
    "[logging]\n"
    "; 日志与原版 log.txt 位于同一游戏数据目录，按启动和局次分目录保存。\n"
    "; startup.log 记录启动和退出，runtime.log 记录局内事件。\n"
    "; 历史日志可手动清理。\n"
    "; 日志等级：DEBUG / INFO / WARN / ERROR，默认 INFO。\n"
    "level = INFO\n\n"
    "[diagnostics]\n"
    "; 性能统计：true / false，默认 false；排查卡顿时可开启。\n"
    "; 开启后在同一日志目录生成 performance.jsonl。\n"
    "performance = false\n"
    "; 性能统计采样间隔（毫秒）：100–60000，默认 1000。\n"
    "sample_interval_ms = 1000\n\n"
    "[chat]\n"
    "; 聊天背景不透明度：0–100，0 完全透明，100 不透明。\n"
    "background_opacity = 70\n"
    "; 背景、边框与文字颜色：六位 RGB 十六进制，不加 #。\n"
    "background_color = 231B18\n"
    "border_color = 79604C\n"
    "text_color = E8DFCB\n";
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
    auto& seen = result.keys;
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
        if (key == "network.input_hz") {
            if (value == "30" || value == "60")
                result.settings.inputHz = value == "30" ? 30 : 60;
            else
                warn("invalid_value=" + key);
        } else if (key == "logging.level") {
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
        } else if (key == "chat.background_opacity") {
            unsigned opacity = 0;
            const auto [endValue, error] =
                std::from_chars(value.data(), value.data() + value.size(), opacity);
            if (error == std::errc{} && endValue == value.data() + value.size() && opacity <= 100)
                result.settings.chat.opacity = opacity;
            else
                warn("invalid_value=" + key);
        } else if (key == "chat.background_color" || key == "chat.border_color" ||
                   key == "chat.text_color") {
            unsigned color = 0;
            const auto [endValue, error] =
                std::from_chars(value.data(), value.data() + value.size(), color, 16);
            if (value.size() != 6 || error != std::errc{} ||
                endValue != value.data() + value.size())
                warn("invalid_value=" + key);
            else if (key == "chat.background_color")
                result.settings.chat.background = color;
            else if (key == "chat.border_color")
                result.settings.chat.border = color;
            else
                result.settings.chat.text = color;
        } else
            warn("unknown_key=" + key);
    }
    return result;
}
// Append documented defaults only for absent keys. Existing values, including
// invalid ones, remain the user's text; parse() supplies their runtime fallback.
inline std::string missingDefaults(const Parsed& parsed) {
    std::string additions, section, emittedSection, comments;
    auto remaining = defaults;
    while (!remaining.empty()) {
        const auto end = remaining.find('\n');
        const auto line = trim(remaining.substr(0, end));
        remaining = end == remaining.npos ? std::string_view{} : remaining.substr(end + 1);
        if (line.empty()) {
            comments.clear();
        } else if (line.front() == '[' && line.back() == ']') {
            section = line.substr(1, line.size() - 2);
            comments.clear();
        } else if (line.front() == ';' || line.front() == '#') {
            comments += std::string(line) + "\n";
        } else if (const auto equal = line.find('='); equal != line.npos) {
            const auto key = section + "." + std::string(trim(line.substr(0, equal)));
            if (std::find(parsed.keys.begin(), parsed.keys.end(), key) == parsed.keys.end()) {
                if (emittedSection != section) {
                    additions += "\n[" + section + "]\n";
                    emittedSection = section;
                }
                additions += comments + std::string(line) + "\n";
            }
            comments.clear();
        }
    }
    return additions;
}
} // namespace isaac::configuration
