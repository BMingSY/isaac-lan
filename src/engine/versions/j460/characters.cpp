#include "engine/characters.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/completion_marks.h"
#include <algorithm>
#include <cstring>
#include <optional>
#include <unordered_set>

namespace isaac::characters {
std::uint32_t completionPreview(unsigned character, const lan::Progress& personal) {
    return engine::j460::completion::preview(character, personal);
}
std::optional<std::array<std::uint8_t, 12>> completionLayers(std::uint32_t preview) {
    return engine::j460::completion::layers(preview);
}
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
constexpr unsigned configStride = 0x148;
constexpr unsigned menuStride = 0x18;
constexpr unsigned entriesPerPage = 18;
constexpr unsigned edenCounter = 21;

std::optional<std::string> nativeString(Address address) {
    if (!address)
        return {};
    const auto size = at<unsigned>(address, 16), capacity = at<unsigned>(address, 20);
    if (size > 4096 || capacity < size)
        return {};
    if (!size)
        return std::string{};
    const auto data = capacity < 16 ? address : at<Address>(address);
    if (!data && size)
        return {};
    return std::string(reinterpret_cast<const char*>(data), size);
}
std::string text(Address address) {
    if (!address)
        return {};
    const auto data = reinterpret_cast<const char*>(address);
    const auto size = strnlen(data, 4096);
    return size < 4096 ? std::string(data, size) : std::string{};
}
std::string displayName(Address image, Address manager, const std::string& raw) {
    if (raw.empty() || raw.front() != '#')
        return raw;
    using Lookup =
        const char*(__attribute__((thiscall))*)(void*, const char*, int, const char*, bool*);
    const auto table = manager + 0x4a920;
    bool missing = true;
    const auto result = reinterpret_cast<Lookup>(image + engine::j460::entry::stringTableLookup)(
        reinterpret_cast<void*>(table), "Players", at<int>(table), raw.c_str() + 1, &missing);
    return missing || !result ? raw : text(reinterpret_cast<Address>(result));
}

class FrontendProgress {
    Address manager, progress;
    int scene;
    lan::Progress previous;

  public:
    FrontendProgress(Address address, const lan::Progress& personal)
        : manager(address), progress(address + 0x14), scene(at<int>(address, 8)) {
        std::memcpy(previous.achievements.data(), reinterpret_cast<void*>(progress + 0x38),
                    previous.achievements.size());
        std::memcpy(previous.counters.data(), reinterpret_cast<void*>(progress + 0x2bc),
                    sizeof(previous.counters));
        std::memcpy(reinterpret_cast<void*>(progress + 0x38), personal.achievements.data(),
                    personal.achievements.size());
        std::memcpy(reinterpret_cast<void*>(progress + 0x2bc), personal.counters.data(),
                    sizeof(personal.counters));
        // Native achievement queries waive locks in some running challenges.
        // These pure predicates must observe the character menu's context.
        at<int>(manager, 8) = 0;
    }
    ~FrontendProgress() {
        std::memcpy(reinterpret_cast<void*>(progress + 0x38), previous.achievements.data(),
                    previous.achievements.size());
        std::memcpy(reinterpret_cast<void*>(progress + 0x2bc), previous.counters.data(),
                    sizeof(previous.counters));
        at<int>(manager, 8) = scene;
    }
    void allowContinuingEden(const lan::Progress& personal) {
        // Continue restores an existing actor after its token was consumed.
        // Reuse the same native predicate with only this menu resource waived.
        at<unsigned>(progress, 0x2bc + edenCounter * 4) =
            std::max(1u, personal.counters[edenCounter]);
    }
    FrontendProgress(const FrontendProgress&) = delete;
};
struct Choice {
    std::size_t index;
    Address record;
};
} // namespace

Catalogue catalogue(std::uintptr_t image, const lan::Progress& personal) {
    Catalogue result;
    if (!image)
        return result;
    const auto manager = at<Address>(image, engine::j460::globals::manager);
    if (!manager)
        return result;
    const auto begin = at<Address>(manager, 0x2a678), end = at<Address>(manager, 0x2a67c);
    if (!begin || end < begin || (end - begin) % configStride)
        return result;
    const auto count = (end - begin) / configStride;
    if (count < 41 || count > 65536)
        return result;
    auto config = [&](unsigned type) -> Address {
        const auto address = type < count ? begin + type * configStride : 0;
        return address && at<unsigned>(address) == type ? address : 0;
    };
    std::unordered_set<unsigned> seen;
    std::vector<Choice> choices;
    auto add = [&](unsigned type, bool tainted, Address record, const std::string& animation,
                   const std::string& portraitAnm2Path) {
        const auto cfg = config(type);
        if (!cfg || type > 65535 || !seen.insert(type).second)
            return;
        Entry entry;
        entry.type = static_cast<std::uint16_t>(type);
        entry.tainted = tainted;
        const auto raw = nativeString(cfg + 4).value_or("");
        entry.name = displayName(image, manager, raw);
        if (entry.name.empty())
            entry.name = "Character " + std::to_string(type);
        entry.portraitPath = nativeString(cfg + 0x4c).value_or("");
        entry.animation = animation;
        entry.portraitAnm2Path = portraitAnm2Path;
        if (record)
            choices.push_back({result.entries.size(), record});
        else {
            // J460's menu admits Mod entries directly; it does not apply its
            // built-in achievement predicate to a Mod's achievement XML field.
            entry.selectable = entry.unlocked = true;
            const auto anm2 = at<Address>(cfg, 0x138);
            if (anm2)
                entry.portraitAnm2Path = nativeString(anm2).value_or("");
            entry.animation = entry.name;
        }
        result.entries.push_back(std::move(entry));
    };
    for (unsigned page = 0; page < 2; ++page) {
        const auto portrait =
            text(at<Address>(image + engine::j460::globals::characterMenuPages, page * 12 + 4));
        for (unsigned index = 1; index < entriesPerPage; ++index) {
            const auto record = image + engine::j460::globals::characterMenuEntries +
                                (page * entriesPerPage + index) * menuStride;
            add(at<unsigned>(record, 4), page != 0, record, text(at<Address>(record)), portrait);
        }
        for (unsigned type = 41; type < count; ++type) {
            const auto cfg = config(type);
            // Match MenuCharacter's Mod wheel, including its parent/tainted
            // pairing. Do not invent a blacklist for non-starting forms.
            if (!cfg || at<bool>(cfg, 0x128) || at<unsigned>(cfg, 0x11c) != 0)
                continue;
            const auto selected = page ? at<unsigned>(cfg, 0x124) : type;
            add(selected, page != 0, 0, "", "");
        }
    }
    {
        FrontendProgress scope(manager, personal);
        using Available = bool(__attribute__((thiscall))*)(const void*, int);
        const auto available =
            reinterpret_cast<Available>(image + engine::j460::entry::menuCharacterAvailable);
        for (const auto& choice : choices)
            result.entries[choice.index].selectable =
                available(reinterpret_cast<const void*>(choice.record), 0);
        scope.allowContinuingEden(personal);
        for (const auto& choice : choices)
            result.entries[choice.index].unlocked =
                available(reinterpret_cast<const void*>(choice.record), 0);
    }
    result.ready = true;
    return result;
}
} // namespace isaac::characters
