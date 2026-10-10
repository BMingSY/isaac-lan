#pragma once
#include "net/protocol.h"
#include <deque>
#include <optional>
#include <string>

namespace isaac::presentation {
struct TextSource {
    std::string section, key;
    void write(lan::Writer& w) const {
        w.string(section);
        w.string(key);
    }
    static TextSource read(lan::Reader& r) {
        TextSource source{r.string(), r.string()};
        if (source.section.size() > 128 || source.key.size() > 128 ||
            source.section.empty() != source.key.empty())
            throw std::runtime_error("Invalid item localization key");
        return source;
    }
};
class TextSources {
    struct Lookup {
        unsigned tick;
        std::string value;
        TextSource source;
    };
    std::deque<Lookup> entries;

  public:
    void record(unsigned tick, std::string value, TextSource source) {
        if (value.empty() || value.size() > 1024 || source.section.empty() ||
            source.section.size() > 128 || source.key.empty() || source.key.size() > 128)
            return;
        entries.push_back({tick, std::move(value), std::move(source)});
        while (entries.size() > 64)
            entries.pop_front();
    }
    TextSource find(unsigned tick, const std::string& text) const {
        for (auto it = entries.rbegin(); it != entries.rend(); ++it)
            if (it->tick == tick && it->value == text)
                return it->source;
        return {};
    }
    void clear() {
        entries.clear();
    }
};
template <class Lookup>
std::string translateText(const std::string& fallback, const TextSource& source, Lookup lookup) {
    if (!source.section.empty() && !source.key.empty())
        if (auto value = lookup(source))
            return *value;
    return fallback;
}
} // namespace isaac::presentation
