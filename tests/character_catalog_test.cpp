// Exercise the production J460 catalogue against a private x86 image and ABI.
#include "test_support.h"
#include "engine/characters.h"
#include "engine/versions/j460/entrypoints.h"
#include "net/protocol.h"
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr std::size_t imageSize = 0x880000, managerSize = 0x4a940;
constexpr unsigned menuOffset = 0x724140, menuStride = 24, configStride = 0x148;
constexpr unsigned flagsOffset = 0x14 + 0x38, countersOffset = 0x14 + 0x2bc;
constexpr std::array<unsigned, 34> nativeTypes{0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 13,
                                               14, 15, 16, 18, 19, 21, 22, 23, 24, 25, 26, 27,
                                               28, 29, 30, 31, 32, 33, 34, 35, 36, 37};
std::uint8_t* image = nullptr;
std::vector<std::uint8_t> manager(managerSize), configs(50 * configStride);
isaac::lan::Progress personal;
std::array<unsigned, 41> selectionCalls{};
unsigned totalSelectionCalls = 0, translationCalls = 0;
std::string abiError;

template <class T> void store(void* memory, unsigned offset, T value) {
    std::memcpy(static_cast<std::uint8_t*>(memory) + offset, &value, sizeof(value));
}
template <class T> T read(const void* memory, unsigned offset) {
    T value;
    std::memcpy(&value, static_cast<const std::uint8_t*>(memory) + offset, sizeof(value));
    return value;
}
unsigned achievement(unsigned type) {
    return type * 7 + 3;
}
void reject(const char* message) {
    if (abiError.empty())
        abiError = message;
}
// A real callee-cleanup thiscall fixture verifies ECX and the extra stack word.
// Its answer depends on the temporarily installed native progression bytes.
bool __attribute__((thiscall)) selectable(void* entry, int unused) {
    ++totalSelectionCalls;
    const auto begin = reinterpret_cast<std::uintptr_t>(image + menuOffset);
    const auto address = reinterpret_cast<std::uintptr_t>(entry);
    if (address < begin || address >= begin + 36 * menuStride || (address - begin) % menuStride) {
        reject("Selectable received a non-directory ECX receiver");
        return false;
    }
    const unsigned index = (address - begin) / menuStride;
    if (!index || index == 18)
        reject("Catalogue queried a Random placeholder");
    if (unused != 0)
        reject("Selectable received the wrong stack argument");
    if (read<int>(manager.data(), 8) != 0)
        reject("Catalogue left native run-scene unlock exemptions active");
    if (std::memcmp(manager.data() + flagsOffset, personal.achievements.data(),
                    personal.achievements.size()))
        reject("Selectable observed shared achievements instead of personal progress");
    for (unsigned i = 0; i < personal.counters.size(); ++i) {
        const auto actual = read<std::uint32_t>(manager.data(), countersOffset + i * 4);
        if (i == 21) {
            if (actual != personal.counters[i] && actual != std::max(1u, personal.counters[i]))
                reject("Selectable observed an invalid temporary Eden token count");
        } else if (actual != personal.counters[i])
            reject("Selectable observed another profile's counters");
    }
    const auto type = read<unsigned>(entry, 4);
    if (type >= selectionCalls.size()) {
        reject("Mod character was passed through the vanilla unlock predicate");
        return false;
    }
    ++selectionCalls[type];
    // Simulate the native in-run shortcut so scene-isolation regressions also
    // produce incorrect availability, independently of the ABI diagnostics.
    if (read<int>(manager.data(), 8) == 2)
        return true;
    const bool unlocked = type == 0 || manager[flagsOffset + achievement(type)] != 0;
    const auto tokens = read<std::uint32_t>(manager.data(), countersOffset + 21 * 4);
    return unlocked && ((type != 9 && type != 30) || tokens != 0);
}
const char* __attribute__((thiscall)) translate(void* table, const char* section, int language,
                                                const char* key, bool* missing) {
    ++translationCalls;
    if (table != manager.data() + 0x4a920 || !section || !key || !missing || language != 7) {
        reject("String lookup thiscall receiver or stack arguments differ");
        return nullptr;
    }
    const std::string requested = *key == '#' ? key + 1 : key;
    if (requested == "PLAYER_ZERO") {
        *missing = false;
        return "Localized Isaac";
    }
    if (requested == "MOD_ALT") {
        *missing = false;
        return "Localized Mod Alt";
    }
    *missing = true;
    return "NATIVE MISSING-KEY ERROR TEXT"; // Non-null does not mean lookup succeeded.
}
struct PrivateImage {
    PrivateImage() {
        image = static_cast<std::uint8_t*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image != nullptr, "Cannot allocate the private catalogue image");
        const auto jump = [](unsigned offset, auto function) {
            const auto destination = reinterpret_cast<std::uintptr_t>(function);
            const auto displacement = static_cast<std::uint32_t>(
                destination - reinterpret_cast<std::uintptr_t>(image + offset + 5));
            image[offset] = 0xe9;
            store(image, offset + 1, displacement);
        };
        jump(0x546cd0, selectable);
        jump(isaac::engine::j460::entry::stringTableLookup, translate);
        require(FlushInstructionCache(GetCurrentProcess(), image, imageSize) != 0,
                "Cannot publish private ABI trampolines");
    }
    ~PrivateImage() {
        VirtualFree(image, 0, MEM_RELEASE);
    }
};
std::vector<std::unique_ptr<char[]>> strings;
std::vector<std::unique_ptr<std::array<std::uint8_t, 24>>> animations;
void nativeString(std::uint8_t* target, const std::string& value) {
    std::memset(target, 0, 24);
    if (value.size() < 16) {
        std::memcpy(target, value.c_str(), value.size() + 1);
        store(target, 20, 15u);
    } else {
        auto text = std::make_unique<char[]>(value.size() + 1);
        std::memcpy(text.get(), value.c_str(), value.size() + 1);
        store(target, 0, reinterpret_cast<std::uintptr_t>(text.get()));
        store(target, 20, static_cast<unsigned>(value.size()));
        strings.push_back(std::move(text));
    }
    store(target, 16, static_cast<unsigned>(value.size()));
}
std::uint8_t* config(unsigned type) {
    return configs.data() + type * configStride;
}
void animation(unsigned type, const std::string& filename) {
    auto value = std::make_unique<std::array<std::uint8_t, 24>>();
    nativeString(value->data(), filename);
    store(config(type), 0x138, reinterpret_cast<std::uintptr_t>(value->data()));
    animations.push_back(std::move(value));
}
const isaac::characters::Entry& find(const isaac::characters::Catalogue& value, unsigned type) {
    const auto entry = std::find_if(value.entries.begin(), value.entries.end(),
                                    [=](const auto& item) { return item.type == type; });
    require(entry != value.entries.end(), "Expected character missing from native catalogue");
    return *entry;
}
void resetCalls() {
    selectionCalls.fill(0);
    totalSelectionCalls = translationCalls = 0;
    abiError.clear();
}
isaac::characters::Catalogue catalogue() {
    const auto beforeManager = manager, beforeConfigs = configs;
    const auto beforePersonal = personal;
    std::array<std::uint8_t, 36 * menuStride> beforeMenu;
    std::memcpy(beforeMenu.data(), image + menuOffset, beforeMenu.size());
    resetCalls();
    const auto value =
        isaac::characters::catalogue(reinterpret_cast<std::uintptr_t>(image), personal);
    require(abiError.empty(), abiError.c_str());
    require(manager == beforeManager, "Catalogue failed to restore complete native manager state");
    require(personal == beforePersonal, "Catalogue changed its caller's personal progress");
    require(configs == beforeConfigs &&
                !std::memcmp(beforeMenu.data(), image + menuOffset, beforeMenu.size()),
            "Catalogue mutated native configuration or menu entries");
    return value;
}
void unavailable() {
    const auto value = catalogue();
    require(!value.ready && value.entries.empty(), "Unavailable catalogue did not fail closed");
    require(!totalSelectionCalls, "Unavailable configuration called native selection");
}
} // namespace

int main() {
    try {
        PrivateImage privateImage;
        const auto absent = isaac::characters::catalogue(0, personal);
        require(!absent.ready && absent.entries.empty(), "Absent image did not fail closed");
        unavailable(); // No manager during early Lua initialization.
        std::fill(manager.begin(), manager.end(), 0x5a);
        store(image, isaac::engine::j460::globals::manager,
              reinterpret_cast<std::uintptr_t>(manager.data()));
        store(manager.data(), 8,
              2); // Native run-scene exemptions must be suppressed while probing.
        store(manager.data(), 0x4a920, 7);
        std::fill_n(manager.data() + flagsOffset, personal.achievements.size(), 1);
        for (unsigned i = 0; i < personal.counters.size(); ++i)
            store(manager.data(), countersOffset + i * 4, 0xf000u + i);
        personal.counters[3] = 13;
        for (auto type : {1u, 9u, 23u, 30u})
            personal.achievements[achievement(type)] = 1;
        const auto begin = reinterpret_cast<std::uintptr_t>(configs.data());
        const auto end = begin + configs.size();
        store(manager.data(), 0x2a678, begin);
        for (auto badEnd : {begin, begin - 1, begin + 40 * configStride, end - 1,
                            begin + 65537u * configStride}) {
            store(manager.data(), 0x2a67c, badEnd);
            unavailable();
        }
        store(manager.data(), 0x2a67c, end);
        const std::array<std::string, 2> nativePortraits{"gfx/ui/vanilla_normal.anm2",
                                                         "gfx/ui/vanilla_tainted.anm2"};
        for (unsigned page = 0; page < nativePortraits.size(); ++page)
            store(image, isaac::engine::j460::globals::characterMenuPages + page * 12 + 4,
                  reinterpret_cast<std::uintptr_t>(nativePortraits[page].c_str()));
        std::array<std::string, 36> names;
        for (unsigned index = 0; index < names.size(); ++index) {
            const unsigned type = index == 0    ? 0
                                  : index == 18 ? 21
                                                : nativeTypes[index < 18 ? index - 1 : index - 2];
            names[index] = index == 0 || index == 18 ? "Random" : "Anim" + std::to_string(type);
            store(image, menuOffset + index * menuStride,
                  reinterpret_cast<std::uintptr_t>(names[index].c_str()));
            store(image, menuOffset + index * menuStride + 4, type);
            store(image, menuOffset + index * menuStride + 8, bool(type % 2));
        }
        for (unsigned type = 0; type < 50; ++type) {
            store(config(type), 0, type);
            nativeString(config(type) + 4, "NativeName" + std::to_string(type));
            nativeString(config(type) + 0x4c,
                         "gfx/portraits/character_" + std::to_string(type) + ".png");
            nativeString(config(type) + 0x10c, "");
            store(config(type), 0x124, -1);
        }
        nativeString(config(0) + 4, "#PLAYER_ZERO");
        nativeString(config(41) + 4, "ModNormalWithLongName");
        animation(41, "gfx/ui/characters/mod_normal.anm2");
        store(config(41), 0x124, 42);
        nativeString(config(42) + 4, "#MOD_ALT");
        nativeString(config(42) + 0x10c, "ModNormalWithLongName");
        animation(42, "gfx/ui/characters/mod_tainted.anm2");
        store(config(42), 0x124, 41);
        store(config(43), 0x128, true);
        store(config(43), 0x124, 44);
        nativeString(config(44) + 0x10c, "Hidden parent");
        nativeString(config(45) + 0x10c, "Only a skin");
        nativeString(config(46) + 4, "");
        nativeString(config(47) + 4, "#MISSING_KEY");
        store(config(48), 0x124, 65535);
        store(config(49), 0x128, true);
        const auto value = catalogue();
        require(value.ready && value.entries.size() == 39,
                "Native catalogue included hidden or duplicate entries");
        for (auto type : nativeTypes) {
            const auto& entry = find(value, type);
            const bool unlocked = type == 0 || personal.achievements[achievement(type)] != 0;
            require(entry.unlocked == unlocked &&
                        entry.selectable == (unlocked && type != 9 && type != 30),
                    "Base selection or continuation used the wrong local progression");
            require(entry.tainted == (type >= 21) &&
                        entry.animation == "Anim" + std::to_string(type),
                    "Native menu identity, animation or tainted group was lost");
            require(entry.portraitAnm2Path == nativePortraits[type >= 21],
                    "Base portrait animation did not come from its native page");
            require(selectionCalls[type] == 2,
                    "Base selection and continuation were not both queried");
        }
        require(find(value, 0).name == "Localized Isaac",
                "Native localized character name was lost");
        for (auto type : {41u, 42u, 46u, 47u, 48u}) {
            const auto& entry = find(value, type);
            require(entry.selectable && entry.unlocked,
                    "Native Mod character gained an invented achievement lock");
        }
        require(!find(value, 41).tainted && find(value, 42).tainted &&
                    find(value, 41).name == "ModNormalWithLongName" &&
                    find(value, 42).name == "Localized Mod Alt",
                "Mod counterpart or native strings were lost");
        require(find(value, 41).portraitPath == "gfx/portraits/character_41.png" &&
                    find(value, 41).portraitAnm2Path == "gfx/ui/characters/mod_normal.anm2" &&
                    find(value, 42).portraitAnm2Path == "gfx/ui/characters/mod_tainted.anm2",
                "Mod portrait resources did not come from the loaded config");
        require(find(value, 47).name == "#MISSING_KEY",
                "Missing localization exposed native error text");
        require(!find(value, 46).name.empty() &&
                    find(value, 46).name.find("46") != std::string::npos,
                "Empty character name has no ID fallback");
        require(totalSelectionCalls == nativeTypes.size() * 2 && translationCalls >= 3,
                "Catalogue bypassed the expected native ABI calls");
        personal.counters[21] = 1;
        const auto funded = catalogue();
        require(find(funded, 9).selectable && find(funded, 30).selectable,
                "Local Eden token did not enable new runs");
        personal.achievements[achievement(30)] = 0;
        const auto lockedEden = catalogue();
        require(!find(lockedEden, 30).selectable && !find(lockedEden, 30).unlocked,
                "Eden token bypassed the local character unlock");
        // Configuration is copied afresh. Broken native string metadata must
        // not be followed outside its bounds or reused from a prior query.
        store(config(46) + 4, 16, 4097u);
        store(config(46) + 4, 20, 4097u);
        store(config(46) + 4, 0, std::uintptr_t{0});
        store(config(46) + 0x4c, 16, 12u);
        store(config(46) + 0x4c, 20, 3u);
        const auto malformed = catalogue();
        require(find(malformed, 46).name == "Character 46" &&
                    find(malformed, 46).portraitPath.empty(),
                "Invalid native string metadata was not bounded");
        nativeString(config(46) + 4, "Reloaded Mod");
        nativeString(config(46) + 0x4c, "new.png");
        store(config(48), 0, 777u);
        const auto reloaded = catalogue();
        require(reloaded.entries.size() == 38 && find(reloaded, 46).name == "Reloaded Mod" &&
                    find(reloaded, 46).portraitPath == "new.png",
                "Catalogue reused stale entries or accepted a mismatched config ID");
        store(manager.data(), 0x2a678, std::uintptr_t{0});
        store(manager.data(), 0x2a67c, std::uintptr_t{0});
        unavailable();
        std::puts(
            "PASS production character catalogue: native thiscall/ret4, Random slots, personal "
            "progress/scene restoration, Eden continuation, loaded Mod pairs, strings and "
            "fail-closed bounds");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
