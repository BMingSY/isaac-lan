#pragma once
#include "runtime/session_archive.h"
#include <filesystem>
#include <optional>

namespace isaac::runtime {
// Own the snapshot and its original save-slot destination until replacement
// succeeds. Neither a menu transition nor a failed retry consumes the snapshot.
class PendingArchive {
    struct Entry {
        std::filesystem::path path;
        lan::Archive archive;
    };
    std::optional<Entry> entry;
    std::string failure;

  public:
    bool pending() const {
        return entry.has_value();
    }
    const std::string& error() const {
        return failure;
    }
    void retain(std::filesystem::path path, lan::Archive archive) {
        if (entry)
            throw std::runtime_error("A LAN save is still pending");
        entry = Entry{std::move(path), std::move(archive)};
    }
    template <class Commit> bool retry(Commit commit) {
        if (!entry)
            return true;
        try {
            const auto bytes = entry->archive.encode();
            commit(entry->path, bytes);
            entry.reset();
            failure.clear();
            return true;
        } catch (const std::exception& error) {
            failure = error.what();
            return false;
        }
    }
};
} // namespace isaac::runtime
