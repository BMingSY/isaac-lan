#include "engine_item_presentation.h"
#include "engine_rooms.h"
#include "runtime_net.h"
#include "net_protocol.h"
#include "localized_text.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <deque>
#include <memory>

namespace isaac::presentation::items {
namespace {
using Address = std::uintptr_t;
Address image = 0;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
Address game() {
    return at<Address>(image, 0x871678);
}
template <class T> T engine(unsigned offset) {
    return reinterpret_cast<T>(image + offset);
}
using Call = void(__attribute__((thiscall)) *)(void*);
using Show = void(__attribute__((thiscall)) *)(void*, int, int, void*);
using Update = void(__attribute__((thiscall)) *)(void*, bool);
using Load = bool(__attribute__((thiscall)) *)(void*, const char*);
using ItemText = void(__attribute__((thiscall)) *)(void*, void*, void*);
using CustomText = void(__attribute__((thiscall)) *)(void*, void*, const char*, const char*);
using GetItemConfig = Address(__cdecl*)();
using GetItem = Address(__attribute__((thiscall)) *)(void*, int);
using LookupText = const char*(__attribute__((thiscall)) *)(void*, const char*, int, const char*,
                                                            bool*);
Show originalShow;
Update originalUpdate;
Load originalLoad;
ItemText originalItemText;
CustomText originalCustomText;
LookupText originalLookupText;
Call originalRender;
std::string configuration = "resources/giantbook.xml";

// J460 constructs these native ANM2/config objects in Game's constructor.
// Each player needs a separate overlay: skipping Show would break Mega Mush's
// native visibility restoration. The global overlay also pauses Game::Update,
// dropping another player's item press while the host is showing a book.
struct Overlay {
    alignas(8) std::array<unsigned char, 0x12b8> storage{};
    Overlay() {
        const auto p = address();
        engine<Call>(0x74c0)(reinterpret_cast<void*>(p + 8));
        for (unsigned i = 0; i < 48; ++i)
            engine<Call>(0x5abcf0)(reinterpret_cast<void*>(p + 0x11c + i * 0x58));
        engine<Call>(0x74c0)(reinterpret_cast<void*>(p + 0x11a4));
        if (!originalLoad(storage.data(), configuration.c_str()))
            runtime::abort("Could not load native item presentation");
    }
    ~Overlay() {
        engine<Call>(0x5abd80)(storage.data());
    }
    Address address() const {
        return reinterpret_cast<Address>(storage.data());
    }
};
std::array<std::unique_ptr<Overlay>, 4> owned;
Address displayOverlay(unsigned slot) {
    const auto global = game() + 0x1c034;
    // Native Game observes the global Home book to change the run to night.
    if (at<unsigned>(global, 0) && at<unsigned>(global, 4) == 44)
        return global;
    return runtime::replica() ? global : owned[slot] ? owned[slot]->address() : 0;
}
void __attribute__((fastcall)) update(void* overlay, void*, bool finish) {
    // Replica overlays are display state. Native Update also heals players,
    // changes rooms and emits sounds at animation markers. Those effects run
    // once on the authority; snapshots supply the complete local animation.
    if (runtime::replica() && !runtime::ending() && rooms::virtualized() &&
        reinterpret_cast<Address>(overlay) == game() + 0x1c034)
        return;
    originalUpdate(overlay, finish);
}
struct Actor {
    unsigned slot = 0, role = 0;
    Address player = 0;
};
Actor owner(void* explicitPlayer) {
    Actor result;
    result.player = rooms::presentationPlayer(explicitPlayer);
    if (!result.player)
        return result;
    const auto controller = at<int>(result.player, 0x1618);
    if (controller < 1 || controller > 4 || !(rooms::connected() & (1u << (controller - 1))))
        return {};
    result.slot = controller - 1;
    for (auto entry = at<Address>(game(), 0x1baa8); entry < at<Address>(game(), 0x1baac);
         entry += 4) {
        const auto player = at<Address>(entry, 0);
        if (player == result.player)
            return result;
        if (at<int>(player, 0x1618) == controller)
            ++result.role;
    }
    return {};
}
Address player(unsigned slot, unsigned role) {
    for (auto entry = at<Address>(game(), 0x1baa8); entry < at<Address>(game(), 0x1baac);
         entry += 4) {
        const auto p = at<Address>(entry, 0);
        if (at<int>(p, 0x1618) == static_cast<int>(slot + 1) && role-- == 0)
            return p;
    }
    return 0;
}
enum class Kind : unsigned char { overlay = 1, item, text, localizedText };
TextSources lookups;
const char* __attribute__((fastcall)) lookupText(void* table, void*, const char* section,
                                                 int language, const char* key, bool* missing) {
    const auto value = originalLookupText(table, section, language, key, missing);
    if (rooms::virtualized() && !runtime::replica() && value && *value && missing && !*missing &&
        section && key && strnlen(value, 1025) <= 1024 && strnlen(section, 129) <= 128 &&
        strnlen(key, 129) <= 128) {
        lookups.record(runtime::tick(), value, {section, key});
    }
    return value;
}
std::string localText(const std::string& fallback, const TextSource& source) {
    return translateText(
        fallback, source, [&](const TextSource& entry) -> std::optional<std::string> {
            const auto table = at<Address>(image, 0x87169c) + 0x4a920;
            bool missing = false;
            const auto value =
                originalLookupText(reinterpret_cast<void*>(table), entry.section.c_str(),
                                   at<int>(table, 0), entry.key.c_str(), &missing);
            if (!missing && value)
                return value;
            return std::nullopt;
        });
}
struct Event {
    unsigned serial, tick, epoch, slot, role;
    Kind kind;
    int id = 0, parameter = 0;
    bool hasPlayer = false;
    std::string title, subtitle;
    TextSource titleSource, subtitleSource;
};
constexpr unsigned maxEvents = 24, maxAge = 90;
std::deque<Event> events;
unsigned serial = 0, seen = 0;
std::array<unsigned, 3> played{};
Event event(const Actor& actor, Kind kind) {
    return {++serial,
            runtime::tick(),
            runtime::worldEpoch(),
            actor.slot,
            actor.role,
            kind,
            0,
            0,
            false,
            {},
            {},
            {},
            {}};
}
void enqueue(Event e) {
    events.push_back(std::move(e));
    while (events.size() > maxEvents)
        events.pop_front();
}
void __attribute__((fastcall)) show(void* overlay, void*, int id, int delay, void* target) {
    if (runtime::ending()) {
        // Terminal native books (including Beast's sleep/ending) belong to
        // the run. Their markers must reach the native cinematic state machine.
        originalShow(overlay, id, delay, target);
        return;
    }
    if (rooms::virtualized() && id == 44 && at<int>(game(), 0) == 13 && at<int>(game(), 4) == 0 &&
        !runtime::replica()) {
        // Sleep belongs to the whole run, including when a guest finds the bed.
        if (rooms::gatherForTransition([=] {
                for (unsigned slot = 0; slot < 4; ++slot)
                    if (rooms::connected() & (1u << slot)) {
                        auto e = event({slot, 0, player(slot, 0)}, Kind::overlay);
                        e.id = id;
                        e.parameter = delay;
                        enqueue(std::move(e));
                    }
                originalShow(reinterpret_cast<void*>(game() + 0x1c034), id, delay, nullptr);
            }))
            return;
    }
    const auto actor = owner(target);
    if (!actor.player) {
        originalShow(overlay, id, delay, target);
        return;
    }
    if (!runtime::replica()) {
        auto e = event(actor, Kind::overlay);
        e.id = id;
        e.parameter = delay;
        e.hasPlayer = target != nullptr;
        enqueue(std::move(e));
    }
    if (!runtime::replica()) {
        if (!owned[actor.slot])
            owned[actor.slot] = std::make_unique<Overlay>();
        if (id == 45 && reinterpret_cast<Address>(overlay) == game() + 0x1c034) {
            // Player's Mega Mush setup writes its appearance into the global
            // overlay before Show. Move that owned ANM2 to the acting peer's
            // overlay; its completion restores this player's visibility.
            auto* source = reinterpret_cast<unsigned char*>(overlay) + 0x11a4;
            auto* destination = owned[actor.slot]->storage.data() + 0x11a4;
            std::swap_ranges(source, source + 0x114, destination);
        }
        originalShow(owned[actor.slot]->storage.data(), id, delay, target);
        if (static_cast<int>(actor.slot) == runtime::localViewSlot())
            ++played[0];
    } else if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        originalShow(overlay, id, delay, target);
        ++played[0];
    }
}
void __attribute__((fastcall)) render(void* overlay, void*) {
    originalRender(overlay);
    const int slot = runtime::localViewSlot();
    if (!runtime::replica() && rooms::virtualized() && slot >= 0 && slot < 4 && owned[slot] &&
        reinterpret_cast<Address>(overlay) == game() + 0x1c034)
        originalRender(owned[slot]->storage.data());
}
bool __attribute__((fastcall)) load(void* overlay, void*, const char* path) {
    owned = {};
    configuration = path;
    return originalLoad(overlay, path);
}
void __attribute__((fastcall)) itemText(void* hud, void*, void* target, void* item) {
    const auto actor = owner(target);
    if (!actor.player) {
        originalItemText(hud, target, item);
        return;
    }
    if (!runtime::replica() && item) {
        auto e = event(actor, Kind::item);
        e.id = at<int>(reinterpret_cast<Address>(item), 4);
        e.parameter = at<int>(reinterpret_cast<Address>(item), 0);
        enqueue(std::move(e));
    }
    if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        originalItemText(hud, target, item);
        ++played[1];
    }
}
void __attribute__((fastcall)) customText(void* hud, void*, void* target, const char* title,
                                          const char* subtitle) {
    const auto actor = owner(target);
    if (!actor.player) {
        originalCustomText(hud, target, title, subtitle);
        return;
    }
    if (!runtime::replica()) {
        auto e = event(actor, Kind::text);
        // Native item names/descriptions are short. Keep the bounded event
        // batch below Lua's 65535-byte string limit, without native pointers.
        e.title.assign(title ? title : "", title ? strnlen(title, 1024) : 0);
        e.subtitle.assign(subtitle ? subtitle : "", subtitle ? strnlen(subtitle, 1024) : 0);
        // Each process loads fonts for its own language. Sending the host's
        // translated glyphs to an English client leaves only digits visible.
        // Keep native localization keys and resolve them on the receiving HUD.
        e.titleSource = lookups.find(runtime::tick(), e.title);
        e.subtitleSource = lookups.find(runtime::tick(), e.subtitle);
        if (!e.titleSource.key.empty() || !e.subtitleSource.key.empty())
            e.kind = Kind::localizedText;
        enqueue(std::move(e));
    }
    if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        originalCustomText(hud, target, title, subtitle);
        ++played[2];
    }
}
struct API {
    int(__cdecl* getTop)(lua_State*);
    long long(__cdecl* checkInteger)(lua_State*, int);
    const char*(__cdecl* checkString)(lua_State*, int, std::size_t*);
    const char*(__cdecl* pushString)(lua_State*, const char*, std::size_t);
    void(__cdecl* pushInteger)(lua_State*, long long);
    void(__cdecl* pushBoolean)(lua_State*, int);
    void(__cdecl* createTable)(lua_State*, int, int);
    void(__cdecl* pushClosure)(lua_State*, int(__cdecl*)(lua_State*), int);
    void(__cdecl* setField)(lua_State*, int, const char*);
    void*(__cdecl* toUserdata)(lua_State*, int);
    void*(__cdecl* newUserdata)(lua_State*, std::size_t);
    std::size_t(__cdecl* rawLength)(lua_State*, int);
    int(__cdecl* getMetatable)(lua_State*, int);
    int(__cdecl* setMetatable)(lua_State*, int);
} lua{};
int overlaySprite(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto part = lua.getTop(L) >= 3 ? lua.checkInteger(L, 3) : 1;
    auto sample = static_cast<Address*>(lua.toUserdata(L, 2));
    Address overlay = game() + 0x1c034;
    if (slot < 0 || slot >= 4 || part < 0 || part > 1 || !sample || lua.rawLength(L, 2) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    overlay = displayOverlay(slot);
    if (!overlay) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!runtime::replica() && (!at<int>(overlay, 0) || (part == 1 ? at<int>(overlay, 4) != 45
                                                                   : !at<bool>(overlay, 0x111)))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = overlay + (part == 1 ? 0x11a4 : 8);
    lua.getMetatable(L, 2);
    lua.setMetatable(L, -2);
    return 1;
}
int pose(lua_State* L) {
    try {
        const auto slot = lua.checkInteger(L, 1);
        if (slot < 0 || slot >= 4)
            throw std::runtime_error("Invalid item overlay slot");
        Address overlay = game() + 0x1c034;
        if (lua.getTop(L) == 1) {
            overlay = displayOverlay(slot);
            lan::Writer w(lan::Message::world);
            w.u8(overlay ? at<unsigned>(overlay, 0) : 0);
            w.u8(overlay ? at<unsigned>(overlay, 4) : 0);
            w.u32(overlay ? at<unsigned>(overlay, 0x119c) : 0);
            lua.pushString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                           w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica() || slot != runtime::localViewSlot())
            throw std::runtime_error("Only the local replica applies item overlay pose");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto state = r.u8(), id = r.u8();
        const auto delay = r.u32();
        r.finish();
        if (state > 2 || id >= 48 || delay > 900)
            throw std::runtime_error("Invalid item overlay pose");
        if (state && at<unsigned>(overlay, 4) != id)
            originalShow(reinterpret_cast<void*>(overlay), id, delay, nullptr);
        at<unsigned>(overlay, 0) = state;
        at<unsigned>(overlay, 4) = id;
        at<unsigned>(overlay, 0x119c) = delay;
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int synchronize(lua_State* L) {
    try {
        if (!runtime::replica()) {
            const auto slot = lua.checkInteger(L, 1);
            lan::Writer w(lan::Message::world);
            w.u8(0);
            for (const auto& e : events) {
                if (slot != e.slot || e.epoch != runtime::worldEpoch() ||
                    runtime::tick() - e.tick > maxAge)
                    continue;
                ++w.bytes[1];
                w.u32(e.serial);
                w.u32(e.tick);
                w.u32(e.epoch);
                w.u8(e.slot);
                w.u8(e.role);
                w.u8(static_cast<unsigned char>(e.kind));
                if (e.kind == Kind::text || e.kind == Kind::localizedText) {
                    w.string(e.title);
                    w.string(e.subtitle);
                    if (e.kind == Kind::localizedText)
                        for (const auto* source : {&e.titleSource, &e.subtitleSource}) {
                            source->write(w);
                        }
                } else {
                    w.u32(e.id);
                    w.u32(e.parameter);
                    if (e.kind == Kind::overlay)
                        w.u8(e.hasPlayer);
                }
            }
            lua.pushString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                           w.bytes[1] ? w.bytes.size() - 1 : 0);
            return 1;
        }
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        if (!size) {
            lua.pushBoolean(L, true);
            return 1;
        }
        if (size > 65535)
            throw std::runtime_error("Too many item presentation events");
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        std::vector<Event> batch;
        const auto count = r.u8();
        if (count > maxEvents)
            throw std::runtime_error("Too many item presentation events");
        for (unsigned i = 0; i < count; ++i) {
            Event e{};
            e.serial = r.u32();
            e.tick = r.u32();
            e.epoch = r.u32();
            e.slot = r.u8();
            e.role = r.u8();
            e.kind = static_cast<Kind>(r.u8());
            if (e.slot >= 4 || e.role >= 8 || batch.size() >= maxEvents)
                throw std::runtime_error("Invalid item presentation owner");
            if (e.kind == Kind::text || e.kind == Kind::localizedText) {
                e.title = r.string();
                e.subtitle = r.string();
                if (e.kind == Kind::localizedText)
                    for (auto* source : {&e.titleSource, &e.subtitleSource}) {
                        *source = TextSource::read(r);
                    }
            } else if (e.kind == Kind::overlay || e.kind == Kind::item) {
                e.id = static_cast<int>(r.u32());
                e.parameter = static_cast<int>(r.u32());
                if (e.kind == Kind::overlay) {
                    const auto flag = r.u8();
                    if (flag > 1 || e.id < 0 || e.id >= 48 || e.parameter < 0 || e.parameter > 900)
                        throw std::runtime_error("Invalid native item overlay");
                    e.hasPlayer = flag;
                } else if (e.id < 0 || e.parameter < 1 || e.parameter > 4) {
                    throw std::runtime_error("Invalid native item text");
                }
            } else {
                throw std::runtime_error("Invalid item presentation kind");
            }
            batch.push_back(std::move(e));
        }
        r.finish();
        for (const auto& e : batch) {
            if (e.serial <= seen)
                continue;
            seen = e.serial;
            if (e.slot != static_cast<unsigned>(runtime::localViewSlot()) ||
                e.epoch != runtime::worldEpoch() ||
                (runtime::tick() > e.tick && runtime::tick() - e.tick > maxAge))
                continue;
            const auto target = player(e.slot, e.role);
            if (!target)
                continue;
            rooms::withView([&] {
                const auto hud = game() + 0x1da04;
                if (e.kind == Kind::overlay) {
                    originalShow(reinterpret_cast<void*>(game() + 0x1c034), e.id, e.parameter,
                                 e.hasPlayer ? reinterpret_cast<void*>(target) : nullptr);
                } else if (e.kind == Kind::text || e.kind == Kind::localizedText) {
                    const auto title = localText(e.title, e.titleSource),
                               subtitle = localText(e.subtitle, e.subtitleSource);
                    originalCustomText(reinterpret_cast<void*>(hud),
                                       reinterpret_cast<void*>(target), title.c_str(),
                                       subtitle.c_str());
                } else {
                    // Resolve through J460's checked native accessors. Manager's
                    // EntityConfig is not ItemConfig; reading its vectors here
                    // would pass a non-item pointer into the native HUD.
                    const auto config = engine<GetItemConfig>(0x2ca00)();
                    const auto lookup = engine<GetItem>(e.parameter == 2 ? 0x32fd70 : 0x32fd10);
                    const auto item = lookup(reinterpret_cast<void*>(config), e.id);
                    if (!item || at<int>(item, 0) != e.parameter || at<int>(item, 4) != e.id)
                        return;
                    originalItemText(reinterpret_cast<void*>(hud), reinterpret_cast<void*>(target),
                                     reinterpret_cast<void*>(item));
                }
                ++played[e.kind == Kind::localizedText ? 2
                                                       : static_cast<unsigned char>(e.kind) - 1];
            });
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int status(lua_State* L) {
    Address overlay = game() + 0x1c034;
    if (!runtime::replica()) {
        const auto slot = lua.getTop(L) ? lua.checkInteger(L, 1) : runtime::localViewSlot();
        if (slot >= 0 && slot < 4 && owned[slot])
            overlay = owned[slot]->address();
    }
    lua.createTable(L, 0, 6);
    auto integer = [&](const char* name, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, name);
    };
    integer("overlayState", at<int>(overlay, 0));
    integer("overlayID", at<int>(overlay, 4));
    integer("overlayDelay", at<int>(overlay, 0x119c));
    integer("globalOverlayState", at<int>(game() + 0x1c034, 0));
    integer("bookLoaded", at<bool>(overlay, 0x111));
    integer("bookPlaying", at<bool>(overlay, 0x4c));
    integer("megaLoaded", at<bool>(overlay, 0x12ad));
    integer("megaPlaying", at<bool>(overlay, 0x11e8));
    integer("megaFrame", at<unsigned>(overlay, 0x11e4));
    integer("overlays", played[0]);
    integer("items", played[1]);
    integer("texts", played[2]);
    return 1;
}
} // namespace
bool install(Address base) {
    image = base;
    auto hook = [&](unsigned offset, void* callback, void** original) {
        const auto target = reinterpret_cast<void*>(image + offset);
        return MH_CreateHook(target, callback, original) == MH_OK && MH_EnableHook(target) == MH_OK;
    };
    return hook(0x626af0, reinterpret_cast<void*>(lookupText),
                reinterpret_cast<void**>(&originalLookupText)) &&
           hook(0x5aca90, reinterpret_cast<void*>(update),
                reinterpret_cast<void**>(&originalUpdate)) &&
           hook(0x5ad210, reinterpret_cast<void*>(show), reinterpret_cast<void**>(&originalShow)) &&
           hook(0x5acfe0, reinterpret_cast<void*>(render),
                reinterpret_cast<void**>(&originalRender)) &&
           hook(0x5abe70, reinterpret_cast<void*>(load), reinterpret_cast<void**>(&originalLoad)) &&
           hook(0x5a2d20, reinterpret_cast<void*>(itemText),
                reinterpret_cast<void**>(&originalItemText)) &&
           hook(0x5a3410, reinterpret_cast<void*>(customText),
                reinterpret_cast<void**>(&originalCustomText));
}
bool bind(lua_State* L, HMODULE module) {
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        const auto p = GetProcAddress(module, name);                                               \
        std::memcpy(&lua.field, &p, sizeof(p));                                                    \
        if (!lua.field)                                                                            \
            return false;                                                                          \
    } while (false)
    IMPORT(getTop, "lua_gettop");
    IMPORT(checkInteger, "luaL_checkinteger");
    IMPORT(checkString, "luaL_checklstring");
    IMPORT(pushString, "lua_pushlstring");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(createTable, "lua_createtable");
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(setField, "lua_setfield");
    IMPORT(toUserdata, "lua_touserdata");
    IMPORT(newUserdata, "lua_newuserdata");
    IMPORT(rawLength, "lua_rawlen");
    IMPORT(getMetatable, "lua_getmetatable");
    IMPORT(setMetatable, "lua_setmetatable");
#undef IMPORT
    lua.pushClosure(L, synchronize, 0);
    lua.setField(L, -2, "item_presentation_events");
    lua.pushClosure(L, status, 0);
    lua.setField(L, -2, "item_presentation_state");
    lua.pushClosure(L, overlaySprite, 0);
    lua.setField(L, -2, "item_presentation_sprite");
    lua.pushClosure(L, pose, 0);
    lua.setField(L, -2, "item_presentation_pose");
    return true;
}
void advance() {
    if (!rooms::virtualized()) {
        owned = {};
        return;
    }
    if (runtime::replica() || at<int>(game(), 0x23a74))
        return;
    // Game skips ItemOverlay::Update when its global overlay is inactive.
    // Owned overlays therefore advance once per accepted host tick, in their
    // owner's room/roster, without pausing another player's simulation/input.
    for (unsigned slot = 0; slot < owned.size(); ++slot)
        if (owned[slot] && at<int>(owned[slot]->address(), 0))
            rooms::withPlayer(slot, [&] { originalUpdate(owned[slot]->storage.data(), false); });
}
void reset() {
    owned = {};
    events.clear();
    lookups.clear();
    serial = seen = 0;
    played = {};
}
} // namespace isaac::presentation::items
