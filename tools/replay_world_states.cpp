#include "core/snapshot_delta.h"
#include "net/compression.h"
#include "net/protocol.h"
#include <algorithm>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>

// Read an unmodified host stream captured by the loopback fixture. This tool
// shares the production codecs; it never loads the game or touches a save.
int main(int argc, char** argv) {
    try {
        if (argc != 3 && argc != 5)
            throw std::runtime_error("Usage: replay_world_states INPUT OUTPUT [FIRST_TICK COUNT]");
        const std::filesystem::path output(argv[2]);
        std::filesystem::create_directories(output);
        std::ifstream input(argv[1], std::ios::binary);
        if (!input)
            throw std::runtime_error("Cannot read captured stream");
        std::ofstream csv(output / "states.csv");
        csv << "tick,epoch,raw,wire,full_wire,delta,full_codec\n";
        const auto firstDump = argc == 5 ? std::stoul(argv[3]) : UINT32_MAX;
        unsigned dumps = argc == 5 ? std::stoul(argv[4]) : 0;
        isaac::lan::StateCompression compression;
        using Bytes = std::vector<std::uint8_t>;
        std::deque<std::pair<std::uint32_t, Bytes>> cache;
        Bytes assembling;
        std::uint32_t tick = 0, epoch = 0, base = 0, total = 0;
        bool delta = false;
        std::uint64_t states = 0, wireBytes = 0, fullBytes = 0;
        while (true) {
            unsigned char prefix[2];
            input.read(reinterpret_cast<char*>(prefix), 2);
            if (input.gcount() == 0)
                break;
            if (input.gcount() != 2)
                throw std::runtime_error("Truncated stream prefix");
            const auto size = static_cast<std::size_t>((prefix[0] << 8) | prefix[1]);
            if (!size || size > isaac::lan::maxMessageSize)
                throw std::runtime_error("Invalid stream message size");
            Bytes packet(size);
            input.read(reinterpret_cast<char*>(packet.data()), size);
            if (input.gcount() != static_cast<std::streamsize>(size))
                throw std::runtime_error("Truncated stream message");
            isaac::lan::Reader reader(packet);
            const auto type = static_cast<isaac::lan::Message>(reader.u8());
            if (type == isaac::lan::Message::stage || type == isaac::lan::Message::start) {
                cache.clear();
                assembling.clear();
            }
            if (type != isaac::lan::Message::world)
                continue;
            const auto next = reader.u32(), offset = reader.u32(), count = reader.u32();
            if (!offset) {
                tick = next;
                total = count;
                epoch = reader.u32();
                const auto mode = reader.u8();
                if (mode > 1 || !total || total > isaac::lan::maxWorldSize + 5)
                    throw std::runtime_error("Invalid captured world header");
                delta = mode != 0;
                base = reader.u32();
                reader.u8();
                reader.u8();
                reader.u8();
                for (unsigned i = 0; i < isaac::lan::maxPlayers; ++i)
                    reader.u32();
                assembling.clear();
            }
            const auto chunk = reader.blob(3000);
            reader.finish();
            if (next != tick || count != total || offset != assembling.size() ||
                chunk.size() > total - assembling.size())
                throw std::runtime_error("Invalid captured world chunk");
            assembling.insert(assembling.end(), chunk.begin(), chunk.end());
            if (assembling.size() != total)
                continue;
            Bytes value;
            if (delta) {
                const auto found =
                    std::find_if(cache.begin(), cache.end(),
                                 [base](const auto& entry) { return entry.first == base; });
                if (found == cache.end())
                    throw std::runtime_error("Missing recorded baseline");
                if (assembling.front() == isaac::lan::StateCompression::zstdPrefix)
                    value = compression.expand(assembling, found->second);
                else
                    value = isaac::core::SnapshotDelta::apply(found->second,
                                                              compression.expand(assembling));
            } else
                value = compression.expand(assembling);
            const auto full = compression.compress(value).size();
            csv << tick << ',' << epoch << ',' << value.size() << ',' << total << ',' << full << ','
                << delta << ",zstd\n";
            ++states;
            wireBytes += total;
            fullBytes += full;
            if (dumps && tick >= firstDump) {
                std::ofstream dump(output / ("state-" + std::to_string(tick) + ".bin"),
                                   std::ios::binary);
                dump.write(reinterpret_cast<const char*>(value.data()), value.size());
                --dumps;
            }
            cache.emplace_back(tick, std::move(value));
            std::size_t bytes = 0;
            for (auto at = cache.rbegin(); at != cache.rend(); ++at)
                bytes += at->second.size();
            while (cache.size() > 32 || bytes > 8 * isaac::lan::maxWorldSize) {
                bytes -= cache.front().second.size();
                cache.pop_front();
            }
        }
        std::cout << "states=" << states << " full_wire=" << fullBytes
                  << " actual_wire=" << wireBytes << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
