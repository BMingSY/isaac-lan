#include "engine/versions/common/character_catalogue.h"
#include <algorithm>
#include <cstring>
#include <optional>
#include <unordered_set>

namespace isaac::engine::native_characters {
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
namespace config {
inline constexpr unsigned stride = 0x148, id = 0, name = 4, portrait = 0x4c;
inline constexpr unsigned parentNameSize = 0x11c, taintedType = 0x124, hidden = 0x128;
inline constexpr unsigned modPortrait = 0x138;
} // namespace config
namespace nativeStringLayout {
inline constexpr unsigned size = 16, capacity = 20, inlineBytes = 16, maxBytes = 4096;
} // namespace nativeStringLayout
namespace pageLayout {
inline constexpr unsigned count = 2, size = 12, portrait = 4;
} // namespace pageLayout
namespace menuEntry {
inline constexpr unsigned name = 0, type = 4;
} // namespace menuEntry
inline constexpr unsigned nativeTypes = 41, maxTypes = 65536;
constexpr unsigned menuStride = 0x18;
constexpr unsigned entriesPerPage = 18;
constexpr unsigned edenCounter = 21;

std::optional<std::string> nativeString(Address address) {
    if (!address)
        return {};
    const auto size = at<unsigned>(address, nativeStringLayout::size),
               capacity = at<unsigned>(address, nativeStringLayout::capacity);
    if (size > nativeStringLayout::maxBytes || capacity < size)
        return {};
    if (!size)
        return std::string{};
    const auto data = capacity < nativeStringLayout::inlineBytes ? address : at<Address>(address);
    if (!data && size)
        return {};
    return std::string(reinterpret_cast<const char*>(data), size);
}
std::string text(Address address) {
    if (!address)
        return {};
    const auto data = reinterpret_cast<const char*>(address);
    const auto size = strnlen(data, nativeStringLayout::maxBytes);
    return size < nativeStringLayout::maxBytes ? std::string(data, size) : std::string{};
}
std::string displayName(const Directory& directory, const std::string& raw) {
    if (raw.empty() || raw.front() != '#')
        return raw;
    const auto table = directory.manager + directory.stringTable;
    bool missing = true;
    const auto result = directory.lookup(reinterpret_cast<void*>(table), "Players", at<int>(table),
                                         raw.c_str() + 1, &missing);
    return missing || !result ? raw : text(reinterpret_cast<Address>(result));
}

class FrontendProgress {
    const Directory& directory;
    Address progress;
    int scene;
    lan::Progress previous;

  public:
    FrontendProgress(const Directory& directory, const lan::Progress& personal)
        : directory(directory), progress(directory.manager + directory.progressOffset),
          scene(at<int>(directory.manager, directory.scene)),
          previous(native_progress::readNative(progress, directory.progress)) {
        native_progress::write(progress, directory.progress, personal);
        // Native achievement predicates waive locks during some challenges.
        at<int>(directory.manager, directory.scene) = 0;
    }
    ~FrontendProgress() {
        native_progress::writeNative(progress, directory.progress, previous);
        at<int>(directory.manager, directory.scene) = scene;
    }
    void allowContinuingEden(const lan::Progress& personal) {
        at<unsigned>(progress, directory.progress.counters + edenCounter * sizeof(unsigned)) =
            std::max(1u, personal.counters[edenCounter]);
    }
    FrontendProgress(const FrontendProgress&) = delete;
};
struct Choice {
    std::size_t index;
    Address record;
};
} // namespace

characters::Catalogue catalogue(const Directory& directory, const lan::Progress& personal) {
    characters::Catalogue result;
    const auto manager = directory.manager;
    if (!manager)
        return result;
    const auto begin = at<Address>(manager, directory.configs),
               end = at<Address>(manager, directory.configs + sizeof(Address));
    if (!begin || end < begin || (end - begin) % config::stride)
        return result;
    const auto count = (end - begin) / config::stride;
    if (count < nativeTypes || count > maxTypes)
        return result;
    auto findConfig = [&](unsigned type) -> Address {
        const auto address = type < count ? begin + type * config::stride : 0;
        return address && at<unsigned>(address, config::id) == type ? address : 0;
    };
    std::unordered_set<unsigned> seen;
    std::vector<Choice> choices;
    auto add = [&](unsigned type, bool tainted, Address record, const std::string& animation,
                   const std::string& portraitAnm2Path) {
        const auto cfg = findConfig(type);
        if (!cfg || type >= maxTypes || !seen.insert(type).second)
            return;
        characters::Entry entry;
        entry.type = static_cast<std::uint16_t>(type);
        entry.tainted = tainted;
        const auto raw = nativeString(cfg + config::name).value_or("");
        entry.name = displayName(directory, raw);
        if (entry.name.empty())
            entry.name = "Character " + std::to_string(type);
        entry.portraitPath = nativeString(cfg + config::portrait).value_or("");
        entry.animation = animation;
        entry.portraitAnm2Path = portraitAnm2Path;
        if (record)
            choices.push_back({result.entries.size(), record});
        else {
            // Both native menus admit Mod entries directly without applying their
            // built-in achievement predicate to a Mod's achievement XML field.
            entry.selectable = entry.unlocked = true;
            const auto anm2 = at<Address>(cfg, config::modPortrait);
            if (anm2)
                entry.portraitAnm2Path = nativeString(anm2).value_or("");
            entry.animation = entry.name;
        }
        result.entries.push_back(std::move(entry));
    };
    for (unsigned page = 0; page < pageLayout::count; ++page) {
        const auto portrait =
            text(at<Address>(directory.pages, page * pageLayout::size + pageLayout::portrait));
        for (unsigned index = 1; index < entriesPerPage; ++index) {
            const auto record = directory.entries + (page * entriesPerPage + index) * menuStride;
            add(at<unsigned>(record, menuEntry::type), page != 0, record,
                text(at<Address>(record, menuEntry::name)), portrait);
        }
        for (unsigned type = nativeTypes; type < count; ++type) {
            const auto cfg = findConfig(type);
            // Match MenuCharacter's Mod wheel, including its parent/tainted
            // pairing. Do not invent a blacklist for non-starting forms.
            if (!cfg || at<bool>(cfg, config::hidden) ||
                at<unsigned>(cfg, config::parentNameSize) != 0)
                continue;
            const auto selected = page ? at<unsigned>(cfg, config::taintedType) : type;
            add(selected, page != 0, 0, "", "");
        }
    }
    {
        FrontendProgress scope(directory, personal);
        const auto available = directory.available;
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
} // namespace isaac::engine::native_characters
