#pragma once
#include "core/room_options.h"
#include "net/protocol.h"
#include "runtime/saved_location.h"
#include <bit>
#include <cmath>

namespace isaac::lan {
struct Archive {
    std::string fingerprint;
    Start settings;
    std::vector<rooms::SavedLocation> locations;
    std::vector<std::uint8_t> game;
    static constexpr unsigned legacyCharacters = 4;
    std::vector<std::uint8_t> encode() const {
        Writer w(Message::snapshot);
        if (locations.size() < 2 || locations.size() > maxPlayers)
            throw std::runtime_error("Invalid saved player count");
        const bool expanded = locations.size() > legacyCharacters;
        w.string(expanded ? "IsaacLAN/save/8"
                          : (settings.rules.contract ? "IsaacLAN/save/7" : "IsaacLAN/save/6"));
        w.string(fingerprint);
        w.string(settings.seed);
        w.u8(settings.difficulty);
        w.u16(settings.rules.id);
        w.u16(settings.rules.version);
        w.u16(settings.rules.character);
        w.u8(settings.rules.difficulty);
        w.u8(settings.rules.transient);
        w.u64(settings.rules.options);
        if (expanded || settings.rules.contract)
            w.u64(settings.rules.contract);
        if (expanded)
            w.u8(static_cast<std::uint8_t>(locations.size()));
        const auto characterCount = expanded ? locations.size() : legacyCharacters;
        for (unsigned i = 0; i < characterCount; ++i)
            w.u16(settings.characters[i]);
        w.progress(settings.progress);
        w.u8(static_cast<std::uint8_t>(locations.size()));
        for (const auto& p : locations) {
            w.u32(p.dimension);
            w.u32(p.index);
            w.u32(std::bit_cast<std::uint32_t>(p.x));
            w.u32(std::bit_cast<std::uint32_t>(p.y));
        }
        w.blob(game);
        w.u64(snapshotHash(w.bytes));
        // The file reader limits the whole archive, including progression,
        // locations and checksum, rather than only its native game blob.
        if (w.bytes.size() > maxSnapshotSize)
            throw std::runtime_error("Saved session exceeds archive size limit");
        return w.bytes;
    }
    static Archive decode(std::span<const std::uint8_t> bytes) {
        if (bytes.size() < 8 || bytes.size() > maxSnapshotSize)
            throw std::runtime_error("Invalid saved session size");
        Reader checksum(bytes.last(8));
        if (checksum.u64() != snapshotHash(bytes.first(bytes.size() - 8)))
            throw std::runtime_error("Saved session is damaged");
        Reader r(bytes.first(bytes.size() - 8));
        if (r.u8() != static_cast<unsigned>(Message::snapshot))
            throw std::runtime_error("Unsupported saved session");
        const auto format = r.string();
        if (format != "IsaacLAN/save/3" && format != "IsaacLAN/save/4" &&
            format != "IsaacLAN/save/5" && format != "IsaacLAN/save/6" &&
            format != "IsaacLAN/save/7" && format != "IsaacLAN/save/8")
            throw std::runtime_error("Unsupported saved session");
        Archive out;
        out.fingerprint = r.string();
        out.settings.seed = r.string();
        out.settings.difficulty = r.u8();
        out.settings.rules.id = r.u16();
        out.settings.rules.version = r.u16();
        out.settings.rules.character = r.u16();
        out.settings.rules.difficulty = r.u8();
        const auto transient = r.u8();
        out.settings.rules.transient = transient != 0;
        const bool expanded = format == "IsaacLAN/save/8";
        if (format == "IsaacLAN/save/6" || format == "IsaacLAN/save/7" || expanded)
            out.settings.rules.options = roomOptions::normalize(r.u64());
        else if (format != "IsaacLAN/save/3")
            out.settings.rules.options = roomOptions::migrateLegacy(r.u32());
        if (format == "IsaacLAN/save/7" || expanded)
            out.settings.rules.contract = r.u64();
        if (transient > 1 || !out.settings.rules.valid() ||
            !roomOptions::valid(out.settings.rules.options))
            throw std::runtime_error("Invalid saved run rules");
        const unsigned characterCount = expanded ? r.u8() : legacyCharacters;
        if (expanded && (characterCount <= legacyCharacters || characterCount > maxPlayers))
            throw std::runtime_error("Invalid saved player count");
        for (unsigned i = 0; i < characterCount; ++i)
            out.settings.characters[i] = r.u16();
        out.settings.progress =
            r.progress(format != "IsaacLAN/save/3" && format != "IsaacLAN/save/4");
        const auto players = r.u8();
        if (players < 2 || players > characterCount || (expanded && players != characterCount) ||
            out.settings.seed.size() != 8 || out.settings.difficulty > 3)
            throw std::runtime_error("Invalid saved session settings");
        for (unsigned i = 0; i < players; ++i) {
            rooms::SavedLocation p{static_cast<int>(r.u32()), static_cast<int>(r.u32()),
                                   std::bit_cast<float>(r.u32()), std::bit_cast<float>(r.u32())};
            if (p.dimension < 0 || p.dimension > 2 || p.index < -20 || p.index >= 169 ||
                !std::isfinite(p.x) || !std::isfinite(p.y) || std::abs(p.x) > 10000 ||
                std::abs(p.y) > 10000)
                throw std::runtime_error("Invalid saved player location");
            out.locations.push_back(p);
        }
        out.game = r.blob();
        r.finish();
        return out;
    }
};
} // namespace isaac::lan
