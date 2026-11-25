#pragma once
#include "compat/challenges/catalog.h"
#include "core/run_rules.h"
#include <map>
#include <string>

namespace isaac::compat::challenges {
// Map nodes own the menu text for the lifetime of their definitions.
class ExternalCatalog {
    struct Entry {
        std::string name;
        Definition definition{};
    };
    std::map<unsigned, Entry> entries;

  public:
    ExternalCatalog() = default;
    ExternalCatalog(const ExternalCatalog&) = delete;
    ExternalCatalog& operator=(const ExternalCatalog&) = delete;
    bool add(unsigned id, unsigned version, std::string name, unsigned character,
             unsigned difficulty, unsigned players, std::uint64_t contract) {
        if (id < externalRuleBase || id > 65535 || !version || version > 65535 || name.empty() ||
            name.size() > 96 || name.find('\0') != std::string::npos ||
            character > unrestrictedCharacter || difficulty > 3 ||
            (players && (players < 2 || players > 4)) || !contract ||
            entries.size() >= maxExternalRules)
            return false;
        auto [it, added] = entries.try_emplace(id);
        if (!added)
            return false;
        auto& entry = it->second;
        entry.name = std::move(name);
        entry.definition = {.id = static_cast<std::uint16_t>(id),
                            .version = static_cast<std::uint16_t>(version),
                            .character = static_cast<std::uint16_t>(character),
                            .difficulty = static_cast<std::uint8_t>(difficulty),
                            .transient = true,
                            .name = entry.name,
                            .route = "external",
                            .ending = ids::ending::epilogue,
                            .goalStage = -1,
                            .goalStageType = -1,
                            .nextBag = false,
                            .requiredAchievements = {},
                            .roomOptionsLocked = true,
                            .requiredPlayers = players,
                            .contract = contract};
        return true;
    }
    void erase(unsigned id) {
        entries.erase(id);
    }
    void clear() {
        entries.clear();
    }
    const Definition* lookup(unsigned id) const {
        if (id < externalRuleBase)
            return find(id);
        const auto it = entries.find(id);
        return it == entries.end() ? nullptr : &it->second.definition;
    }
    template <typename Visitor> void each(Visitor visit) const {
        for (const auto& def : definitions)
            visit(def);
        for (const auto& [_, entry] : entries)
            visit(entry.definition);
    }
};
} // namespace isaac::compat::challenges
