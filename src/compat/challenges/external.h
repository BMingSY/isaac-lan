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
    std::map<std::uint64_t, unsigned> contracts;

  public:
    ExternalCatalog() = default;
    ExternalCatalog(const ExternalCatalog&) = delete;
    ExternalCatalog& operator=(const ExternalCatalog&) = delete;
    unsigned add(unsigned version, std::string name, unsigned character, unsigned difficulty,
                 unsigned players, std::uint64_t contract, bool lockRoomOptions = false) {
        if (!version || version > 65535 || name.empty() || name.size() > 96 ||
            name.find('\0') != std::string::npos || character > unrestrictedCharacter ||
            difficulty > 3 || (players && (players < 2 || players > 4)) || !contract ||
            contracts.contains(contract) || entries.size() + definitions.size() >= maxLobbyRules)
            return 0;
        unsigned slot = externalRuleBase;
        while (entries.contains(slot))
            ++slot;
        auto& entry = entries[slot];
        entry.name = std::move(name);
        contracts.emplace(contract, slot);
        entry.definition = {.id = static_cast<std::uint16_t>(slot),
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
                            .roomOptionsLocked = lockRoomOptions,
                            .requiredPlayers = players,
                            .contract = contract};
        return slot;
    }
    void erase(unsigned id) {
        if (const auto it = entries.find(id); it != entries.end()) {
            contracts.erase(it->second.definition.contract);
            entries.erase(it);
        }
    }
    void clear() {
        entries.clear();
        contracts.clear();
    }
    const Definition* lookup(unsigned id) const {
        if (id < externalRuleBase)
            return find(id);
        const auto it = entries.find(id);
        return it == entries.end() ? nullptr : &it->second.definition;
    }
    const Definition* lookup(const RunRules& rules) const {
        if (!rules.contract)
            return find(rules.id);
        const auto it = contracts.find(rules.contract);
        return it == contracts.end() ? nullptr : lookup(it->second);
    }
    // An unavailable external declaration can be selected before a guest joins.
    int localId(const RunRules& rules) const {
        if (!rules.contract)
            return rules.id;
        const auto* definition = lookup(rules);
        return definition ? definition->id : -1;
    }
    template <typename Visitor> void each(Visitor visit) const {
        for (const auto& def : definitions)
            visit(def);
        for (const auto& [_, entry] : entries)
            visit(entry.definition);
    }
};
} // namespace isaac::compat::challenges
