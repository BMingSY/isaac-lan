#pragma once
#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::chat {
inline constexpr std::size_t maxCharacters = 60, maxCommandBytes = 2048, maxHistory = 200,
                             maxInputHistory = 64, maxOutputBytes = 16384;
inline constexpr unsigned maxDice = 1000000000;
struct Appearance {
    unsigned opacity = 70;
    unsigned background = 0x231b18, border = 0x79604c, text = 0xe8dfcb;
    std::string backgroundImage;
};

// Byte boundaries of Unicode scalar values, including the final end boundary.
// Never split UTF-8 during editing or silently accept an overlong encoding.
inline std::optional<std::vector<std::size_t>> boundaries(std::string_view text) {
    std::vector<std::size_t> result;
    for (std::size_t i = 0; i < text.size();) {
        result.push_back(i);
        const auto lead = static_cast<unsigned char>(text[i++]);
        unsigned length = 0, value = 0, minimum = 0;
        if (lead < 0x80) {
            length = 0;
            value = lead;
        } else if (lead >= 0xc2 && lead <= 0xdf) {
            length = 1;
            value = lead & 0x1f;
            minimum = 0x80;
        } else if (lead >= 0xe0 && lead <= 0xef) {
            length = 2;
            value = lead & 0xf;
            minimum = 0x800;
        } else if (lead >= 0xf0 && lead <= 0xf4) {
            length = 3;
            value = lead & 7;
            minimum = 0x10000;
        } else
            return {};
        if (i + length > text.size())
            return {};
        for (unsigned n = 0; n < length; ++n) {
            const auto c = static_cast<unsigned char>(text[i++]);
            if ((c & 0xc0) != 0x80)
                return {};
            value = (value << 6) | (c & 0x3f);
        }
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) ||
            value == 0 || value == 0x7f ||
            (value < 0x20 && value != '\r' && value != '\n' && value != '\t'))
            return {};
    }
    result.push_back(text.size());
    return result;
}
inline std::string_view boundedOutput(std::string_view text, std::size_t limit) {
    auto end = std::min(text.size(), limit);
    while (end > 0 && end < text.size() && (static_cast<unsigned char>(text[end]) & 0xc0) == 0x80)
        --end;
    return text.substr(0, end);
}
inline bool validInput(std::string_view value) {
    const auto offsets = boundaries(value);
    if (!offsets || value.size() > maxCommandBytes)
        return false;
    return value.starts_with('/') || offsets->size() - 1 <= maxCharacters;
}

class Editor {
    std::vector<std::string> history;
    std::size_t historyAt = 0;
    std::string draft;

  public:
    std::string text;
    std::size_t cursor = 0, anchor = 0;
    bool limit = false;
    void assign(std::string value) {
        text = std::move(value);
        cursor = anchor = text.size();
        limit = false;
    }
    bool insert(std::string value) {
        // Pasting multiple lines is one submission, never a sequence of commands.
        for (auto& c : value)
            if (c == '\r' || c == '\n' || c == '\t')
                c = ' ';
        const auto first = std::min(cursor, anchor), last = std::max(cursor, anchor);
        auto next = text.substr(0, first) + value + text.substr(last);
        if (!validInput(next)) {
            limit = true;
            return false;
        }
        text = std::move(next);
        cursor = anchor = first + value.size();
        limit = false;
        return true;
    }
    void move(int direction, bool select = false, bool edge = false) {
        const auto offsets = boundaries(text).value();
        const auto at = std::lower_bound(offsets.begin(), offsets.end(), cursor) - offsets.begin();
        if (!select && cursor != anchor && !edge)
            cursor = direction < 0 ? std::min(cursor, anchor) : std::max(cursor, anchor);
        else if (edge)
            cursor = direction < 0 ? 0 : text.size();
        else
            cursor = offsets[std::clamp<std::ptrdiff_t>(at + direction, 0, offsets.size() - 1)];
        if (!select)
            anchor = cursor;
    }
    void erase(int direction) {
        if (cursor == anchor)
            move(direction, true);
        insert("");
    }
    std::string selection() const {
        return text.substr(std::min(cursor, anchor),
                           std::max(cursor, anchor) - std::min(cursor, anchor));
    }
    void accept() {
        if (!text.empty() && (history.empty() || history.back() != text)) {
            history.push_back(text);
            if (history.size() > maxInputHistory)
                history.erase(history.begin());
        }
        historyAt = history.size();
        draft.clear();
        assign("");
    }
    void recall(int direction) {
        if (historyAt == history.size())
            draft = text;
        historyAt = static_cast<std::size_t>(std::clamp<std::ptrdiff_t>(
            static_cast<std::ptrdiff_t>(historyAt) + direction, 0, history.size()));
        assign(historyAt == history.size() ? draft : history[historyAt]);
    }
    void reset() {
        *this = {};
    }
};
} // namespace isaac::chat
