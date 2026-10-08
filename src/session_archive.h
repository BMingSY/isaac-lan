#pragma once
#include "net_protocol.h"
#include "saved_location.h"
#include <bit>
#include <cmath>

namespace isaac::lan {
struct Archive {
    std::string fingerprint;
    Start settings;
    std::vector<rooms::SavedLocation> locations;
    std::vector<std::uint8_t> game;
    std::vector<std::uint8_t> encode() const {
        Writer w(Message::snapshot);
        w.string("IsaacLAN/save/2");
        w.string(fingerprint);
        w.string(settings.seed);
        w.u8(settings.difficulty);
        for (auto c : settings.characters)
            w.u16(c);
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
        return w.bytes;
    }
    static Archive decode(std::span<const std::uint8_t> bytes) {
        if (bytes.size() < 8 || bytes.size() > maxSnapshotSize)
            throw std::runtime_error("Invalid saved session size");
        Reader checksum(bytes.last(8));
        if (checksum.u64() != snapshotHash(bytes.first(bytes.size() - 8)))
            throw std::runtime_error("Saved session is damaged");
        Reader r(bytes.first(bytes.size() - 8));
        if (r.u8() != static_cast<unsigned>(Message::snapshot) || r.string() != "IsaacLAN/save/2")
            throw std::runtime_error("Unsupported saved session");
        Archive out;
        out.fingerprint = r.string();
        out.settings.seed = r.string();
        out.settings.difficulty = r.u8();
        for (auto& c : out.settings.characters)
            c = r.u16();
        out.settings.progress = r.progress();
        const auto players = r.u8();
        if (players < 2 || players > 4 || out.settings.seed.size() != 8 ||
            out.settings.difficulty > 3)
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
