#include "engine/versions/common/player_seats.h"
#include "engine/moving_box.h"
#include "engine/versions/common/room_hooks.h"
#include "engine/versions/common/scene_update.h"
#include "engine/lua_api.h"
#include "engine/item_presentation.h"
#include "engine/pickup_preview.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "core/localized_text.h"
#include "compat/game_ids.h"
#include "presentation/item_screen.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <deque>
#include <memory>
#include <charconv>

#include "engine/versions/common/item_presentation_bindings.h"

namespace isaac::presentation::items {
namespace {
using engine::native_item_presentation::bindings;
const auto& layout = bindings.layout;
bool installed = false;
constexpr unsigned homeSleepBook = 44, megaMushBook = 45, beastScene = 3, nightmareScene = 5;
constexpr unsigned maxOverlayDelay = 900, maxBodyRoles = 8;
constexpr int trinketType = 2;
using Address = std::uintptr_t;
Address image = 0;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
Address game() {
    return (image ? at<Address>(image, bindings.game) : 0);
}
template <class T> T engine(unsigned offset) {
    return reinterpret_cast<T>(image + offset);
}
using Call = void(__attribute__((thiscall)) *)(void*);
using Show = void(__attribute__((thiscall)) *)(void*, int, int, void*);
using Update = void(__attribute__((thiscall)) *)(void*, bool);
using Load = bool(__attribute__((thiscall)) *)(void*, const char*);
using ItemText = void(__attribute__((thiscall)) *)(void*, void*, void*);

using GetItemConfig = Address(__cdecl*)();
using GetItem = Address(__attribute__((thiscall)) *)(void*, int);
using LookupText = const char*(__attribute__((thiscall)) *)(void*, const char*, int, const char*,
                                                            bool*);
Show originalShow;
Update originalUpdate;
Load originalLoad;
ItemText originalItemText;
void* originalCustomText = nullptr;
void callCustomText(void* hud, void* target, const char* title, const char* subtitle,
                    unsigned style = engine::native_item_presentation::stickyText) {
    bindings.callCustomText(originalCustomText, hud, target, title, subtitle, style);
}
LookupText originalLookupText;
Call originalRender;
using SceneShow = void(__attribute__((thiscall)) *)(void*, int);
SceneShow originalSceneShow;
std::string configuration = "resources/giantbook.xml";
unsigned homeSleepSerial = 0;
void __attribute__((fastcall)) sceneShow(void* scene, void*, int id) {
    if (game() && !runtime::replica() && rooms::virtualized() && id == beastScene &&
        at<int>(game(), layout.game.stage) == compat::ids::stage::home &&
        at<int>(game(), layout.game.stageType) == compat::ids::stageType::wrathOfTheLamb) {
        // Dogma's shutdown starts the run-wide Beast cinematic. Gather its
        // native roster in the triggering living room so
        // the foreground room cannot replace the guest's route context.
        if (rooms::gatherForTransition([=] {
                // Native TV disables the room roster before calling Show.
                // Include peers gathered from other rooms in that same lock.
                for (auto entry = at<Address>(game(), layout.game.players);
                     entry < at<Address>(game(), layout.game.players + sizeof(Address)); entry += 4)
                    at<bool>(at<Address>(entry, 0), layout.player.controls) = false;
                originalSceneShow(scene, id);
            }))
            return;
    }
    originalSceneShow(scene, id);
}

// Both versions construct these native ANM2/config objects in Game's constructor.
// Each player needs a separate overlay: skipping Show would break Mega Mush's
// native visibility restoration. The global overlay also pauses Game::Update,
// dropping another player's item press while the host is showing a book.
struct Overlay {
    // Extension-owned aligned storage; native constructors/destructor own its
    // strings, animations and registered entity reference.
    std::vector<std::uint64_t> storage;
    bool loaded = false;
    void* data() {
        return storage.data();
    }
    Overlay() : storage((layout.overlay.size + sizeof(std::uint64_t) - 1) / sizeof(std::uint64_t)) {
        const auto p = address();
        engine<Call>(bindings.entry.aNM2Construct)(
            reinterpret_cast<void*>(p + layout.overlay.book));
        for (unsigned i = 0; i < layout.overlay.configCount; ++i)
            engine<Call>(bindings.entry.itemOverlayConfigConstruct)(reinterpret_cast<void*>(
                p + layout.overlay.configs + i * layout.overlay.configStride));
        engine<Call>(bindings.entry.aNM2Construct)(
            reinterpret_cast<void*>(p + layout.overlay.mega));
        loaded = originalLoad(storage.data(), configuration.c_str());
        if (!loaded)
            runtime::abort("Could not load native item presentation");
    }
    ~Overlay() {
        engine<Call>(bindings.entry.itemOverlayDestruct)(storage.data());
    }
    Address address() const {
        return reinterpret_cast<Address>(storage.data());
    }
};
std::array<std::unique_ptr<Overlay>, party::maxPlayers> owned;
Address displayOverlay(unsigned slot) {
    if (!game())
        return 0;
    const auto global = game() + layout.game.overlay;
    // Native Game observes the global Home book to change the run to night.
    if (at<unsigned>(global, layout.overlay.state) &&
        at<unsigned>(global, layout.overlay.id) == homeSleepBook)
        return global;
    return runtime::replica() ? global : owned[slot] ? owned[slot]->address() : 0;
}
void __attribute__((fastcall)) update(void* overlay, void*, bool finish) {
    // Replica overlays are display state. Native Update also heals players,
    // changes rooms and emits sounds at animation markers. Those effects run
    // once on the authority; snapshots supply the complete local animation.
    if (runtime::replica() && !runtime::ending() && rooms::virtualized() &&
        reinterpret_cast<Address>(overlay) == game() + layout.game.overlay)
        return;
    originalUpdate(overlay, finish);
}
struct Actor {
    unsigned slot = 0, role = 0;
    Address player = 0;
};
void* actionPlayer = nullptr;
std::array<ItemScreen, party::maxPlayers> screens;
int screenSlot = -1;
unsigned screenGeneration = 0;
Actor owner(void* explicitPlayer) {
    if (!game())
        return {};
    if (!explicitPlayer)
        explicitPlayer = actionPlayer;
    Actor result;
    result.player = rooms::presentationPlayer(explicitPlayer);
    if (!result.player)
        return result;
    const auto controller = isaac::engine::player_seats::owner(
        result.player, at<int>(result.player, layout.player.controller));
    if (controller < 1 || controller > static_cast<int>(party::maxPlayers) ||
        !(rooms::connected() & (1u << (controller - 1))))
        return {};
    result.slot = controller - 1;
    for (auto entry = at<Address>(game(), layout.game.players);
         entry < at<Address>(game(), layout.game.players + sizeof(Address)); entry += 4) {
        const auto player = at<Address>(entry, 0);
        if (player == result.player)
            return result;
        if (isaac::engine::player_seats::owner(player, at<int>(player, layout.player.controller)) ==
            controller)
            ++result.role;
    }
    return {};
}
Address player(unsigned slot, unsigned role) {
    if (!game())
        return 0;
    for (auto entry = at<Address>(game(), layout.game.players);
         entry < at<Address>(game(), layout.game.players + sizeof(Address)); entry += 4) {
        const auto p = at<Address>(entry, 0);
        if (isaac::engine::player_seats::owner(p, at<int>(p, layout.player.controller)) ==
                static_cast<int>(slot + 1) &&
            role-- == 0)
            return p;
    }
    return 0;
}
ItemScreen readScreen() {
    const auto& fields = layout.game;
    const auto g = game();
    return {at<unsigned>(g, fields.pixelation),    at<unsigned>(g, fields.pixelationDuration),
            at<float>(g, fields.dizzyIntensity),   at<float>(g, fields.dizzyTarget),
            at<float>(g, fields.dizzyStep),        at<unsigned>(g, fields.bloomTime),
            at<unsigned>(g, fields.bloomDuration), at<float>(g, fields.bloomIntensity)};
}
void writeScreen(const ItemScreen& value) {
    const auto& fields = layout.game;
    const auto g = game();
    at<unsigned>(g, fields.pixelation) = value.pixels;
    at<unsigned>(g, fields.pixelationDuration) = value.pixelDuration;
    at<float>(g, fields.dizzyIntensity) = value.dizzy;
    at<float>(g, fields.dizzyTarget) = value.target;
    at<float>(g, fields.dizzyStep) = value.step;
    at<unsigned>(g, fields.bloomTime) = value.bloom;
    at<unsigned>(g, fields.bloomDuration) = value.bloomDuration;
    at<float>(g, fields.bloomIntensity) = value.bloomIntensity;
}
using Pixelate = void(__attribute__((thiscall)) *)(void*, int);
using Pill = void(__attribute__((thiscall)) *)(void*, int, int, unsigned);
using Card = void(__attribute__((thiscall)) *)(void*, int, unsigned);
Pixelate originalPixelate;
Pill originalPill;
Card originalCard;
Call originalWavy;
void __attribute__((fastcall)) pixelate(void* g, void*, int duration) {
    const auto actor = owner(nullptr);
    if (!rooms::virtualized() || !actor.player) {
        originalPixelate(g, duration);
        return;
    }
    if (!runtime::replica() && duration > 0)
        withActor(reinterpret_cast<void*>(actor.player), [&] {
            auto screen = readScreen();
            screen.pixelate(static_cast<unsigned>(duration));
            writeScreen(screen);
        });
}
void __attribute__((fastcall)) wavy(void* p, void*) {
    const auto actor = owner(p);
    if (!rooms::virtualized() || !actor.player) {
        originalWavy(p);
        return;
    }
    if (!runtime::replica())
        withActor(p, [&] { originalWavy(p); });
}
void __attribute__((fastcall)) pill(void* p, void*, int effect, int color, unsigned flags) {
    withActor(p, [&] { originalPill(p, effect, color, flags); });
}
void __attribute__((fastcall)) card(void* p, void*, int id, unsigned flags) {
    withActor(p, [&] { originalCard(p, id, flags); });
}
enum class Kind : unsigned char { overlay = 1, item, text, localizedText, fortune, styledText };
bool textEvent(Kind kind) {
    return kind == Kind::text || kind == Kind::localizedText || kind == Kind::fortune ||
           kind == Kind::styledText;
}
bool localizedEvent(Kind kind) {
    return kind == Kind::localizedText || kind == Kind::fortune || kind == Kind::styledText;
}
TextSources lookups, indexedLookups;
using IndexedText = const char*(__attribute__((thiscall)) *)(void*, const char*, int, int);
using Fortune = void(__attribute__((thiscall)) *)(void*, const void*);
IndexedText originalIndexedText;
Fortune originalFortune;
const char* __attribute__((fastcall)) indexedText(void* table, void*, const char* section,
                                                  int language, int index) {
    const auto value = originalIndexedText(table, section, language, index);
    if (rooms::virtualized() && !runtime::replica() && value && section && index >= 0 &&
        index <= 65535 && strnlen(value, 1025) <= 1024 && strnlen(section, 129) <= 128) {
        std::string normalized(value);
        while (!normalized.empty() && normalized.back() == '|')
            normalized.pop_back();
        indexedLookups.record(runtime::tick(), normalized, {section, std::to_string(index)});
    }
    return value;
}
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
            const auto table = at<Address>(image, bindings.manager) + layout.manager.stringTable;
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
    unsigned style = engine::native_item_presentation::stickyText;
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
    if (game() && rooms::virtualized() && id == homeSleepBook &&
        at<int>(game(), layout.game.stage) == compat::ids::stage::home &&
        at<int>(game(), layout.game.stageType) == compat::ids::stageType::original &&
        !runtime::replica()) {
        // Sleep belongs to the whole run, including when a guest finds the bed.
        if (rooms::gatherForTransition([=] {
                for (unsigned slot = 0; slot < party::maxPlayers; ++slot)
                    if (rooms::connected() & (1u << slot)) {
                        auto e = event({slot, 0, player(slot, 0)}, Kind::overlay);
                        e.id = id;
                        e.parameter = delay;
                        enqueue(std::move(e));
                    }
                originalShow(reinterpret_cast<void*>(game() + layout.game.overlay), id, delay,
                             nullptr);
                ++homeSleepSerial;
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
        if (!owned[actor.slot]) {
            auto overlay = std::make_unique<Overlay>();
            if (!overlay->loaded)
                return;
            owned[actor.slot] = std::move(overlay);
        }
        if (id == megaMushBook &&
            reinterpret_cast<Address>(overlay) == game() + layout.game.overlay) {
            // Player's Mega Mush setup writes its appearance into the global
            // overlay before Show. Move that owned ANM2 to the acting peer's
            // overlay; its completion restores this player's visibility.
            auto* source = reinterpret_cast<unsigned char*>(overlay) + layout.overlay.mega;
            auto* destination =
                reinterpret_cast<unsigned char*>(owned[actor.slot]->data()) + layout.overlay.mega;
            // ANM2's two animation states point back to their owning sprite.
            // Moving the storage without rebinding them makes Render read the
            // emptied global sprite's layer vector. Keep each allocation owned
            // exactly once and restore both non-owning self references.
            std::swap_ranges(source, source + layout.sprite.size, destination);
            for (auto sprite : {source, destination}) {
                const auto address = reinterpret_cast<Address>(sprite);
                at<Address>(address, layout.sprite.animationOwner) = address;
                at<Address>(address, layout.sprite.overlayOwner) = address;
            }
        }
        originalShow(owned[actor.slot]->data(), id, delay, target);
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
    if (!runtime::replica() && rooms::virtualized() && party::validSlot(slot) && owned[slot] &&
        reinterpret_cast<Address>(overlay) == game() + layout.game.overlay)
        originalRender(owned[slot]->data());
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
        e.id = at<int>(reinterpret_cast<Address>(item), layout.item.id);
        e.parameter = at<int>(reinterpret_cast<Address>(item), layout.item.type);
        enqueue(std::move(e));
    }
    if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        originalItemText(hud, target, item);
        ++played[1];
    }
}
void customText(void* hud, void* target, const char* title, const char* subtitle, unsigned style) {
    const auto actor = owner(target);
    if (!actor.player) {
        callCustomText(hud, target, title, subtitle, style);
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
        if (style != engine::native_item_presentation::stickyText) {
            e.kind = Kind::styledText;
            e.style = style;
        }
        enqueue(std::move(e));
    }
    if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        callCustomText(hud, target, title, subtitle, style);
        ++played[2];
    }
}
// HUD::ShowFortuneText borrows a native list of strings; it neither retains
// nor frees the list. Keep its x86 MSVC layout confined to this backend.
struct FortuneNode {
    FortuneNode* next;
    FortuneNode* previous;
    const char* text;
    std::array<unsigned char, 12> unused{};
    unsigned size, capacity;
};
static_assert(sizeof(FortuneNode) == 32);
struct FortuneList {
    FortuneNode* head;
    unsigned size;
};
void showFortune(void* hud, const std::string& text) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    do {
        const auto end = text.find('|', start);
        lines.push_back(text.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            break;
        start = end + 1;
    } while (lines.size() < 32);
    std::array<FortuneNode, 33> nodes{};
    const auto count = lines.size();
    for (std::size_t i = 0; i <= count; ++i) {
        nodes[i].next = &nodes[(i + 1) % (count + 1)];
        nodes[i].previous = &nodes[(i + count) % (count + 1)];
        if (i) {
            nodes[i].text = lines[i - 1].c_str();
            nodes[i].size = lines[i - 1].size();
            nodes[i].capacity = std::max(16u, nodes[i].size);
        }
    }
    const FortuneList list{nodes.data(), static_cast<unsigned>(count)};
    originalFortune(hud, &list);
}
void __attribute__((fastcall)) fortune(void* hud, void*, const void* nativeList) {
    const auto actor = owner(nullptr);
    if (!rooms::virtualized() || !actor.player) {
        originalFortune(hud, nativeList);
        return;
    }
    if (!runtime::replica()) {
        const auto list = static_cast<const FortuneList*>(nativeList);
        if (list && list->head && list->size > 0 && list->size <= 32) {
            auto e = event(actor, Kind::fortune);
            const auto* node = list->head->next;
            for (unsigned i = 0; i < list->size && node != list->head; ++i, node = node->next) {
                const auto* text =
                    node->capacity >= 16 ? node->text : reinterpret_cast<const char*>(&node->text);
                if (node->size > 1024 || e.title.size() + node->size + 1 > 1024)
                    break;
                if (i)
                    e.title += '|';
                e.title.append(text, node->size);
            }
            while (!e.title.empty() && e.title.back() == '|')
                e.title.pop_back();
            e.titleSource = indexedLookups.find(runtime::tick(), e.title);
            enqueue(std::move(e));
        }
    }
    if (static_cast<int>(actor.slot) == runtime::localViewSlot()) {
        originalFortune(hud, nativeList);
        ++played[2];
    }
}
std::string fortuneText(const Event& e) {
    return translateText(
        e.title, e.titleSource, [&](const TextSource& source) -> std::optional<std::string> {
            int index = -1;
            const auto result =
                std::from_chars(source.key.data(), source.key.data() + source.key.size(), index);
            if (result.ec != std::errc{} || result.ptr != source.key.data() + source.key.size() ||
                index < 0 || index > 65535)
                return std::nullopt;
            const auto table = at<Address>(image, bindings.manager) + layout.manager.stringTable;
            if (!bindings.indexedTextInRange(table, source.section, index))
                return std::nullopt;
            const auto value = originalIndexedText(
                reinterpret_cast<void*>(table), source.section.c_str(), at<int>(table, 0), index);
            if (value && strnlen(value, 1025) <= 1024)
                return value;
            return std::nullopt;
        });
}
isaac::lua::API lua{};
int overlaySprite(lua_State* L) {
    if (!game()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto slot = lua.checkInteger(L, 1);
    const auto part = lua.getTop(L) >= 3 ? lua.checkInteger(L, 3) : 1;
    auto sample = static_cast<Address*>(lua.toUserdata(L, 2));
    Address overlay = game() + layout.game.overlay;
    if (!party::validSlot(slot) || part < 0 || part > 1 || !sample || lua.rawLength(L, 2) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    overlay = displayOverlay(slot);
    if (!overlay) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!runtime::replica() &&
        (!at<int>(overlay, layout.overlay.state) ||
         (part == 1 ? at<int>(overlay, layout.overlay.id) != megaMushBook
                    : !at<bool>(overlay + layout.overlay.book, layout.sprite.loaded)))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = overlay + (part == 1 ? layout.overlay.mega : layout.overlay.book);
    lua.getMetatable(L, 2);
    lua.setMetatable(L, -2);
    return 1;
}
int pose(lua_State* L) {
    try {
        if (!game())
            throw std::runtime_error("Item presentation requires an active game");
        const auto slot = lua.checkInteger(L, 1);
        if (!party::validSlot(slot))
            throw std::runtime_error("Invalid item overlay slot");
        Address overlay = game() + layout.game.overlay;
        if (lua.getTop(L) == 1) {
            overlay = displayOverlay(slot);
            lan::Writer w(lan::Message::world);
            w.u8(overlay ? at<unsigned>(overlay, layout.overlay.state) : 0);
            w.u8(overlay ? at<unsigned>(overlay, layout.overlay.id) : 0);
            w.u32(overlay ? at<unsigned>(overlay, layout.overlay.delay) : 0);
            screens[slot].write(w);
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
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
        const auto screen = ItemScreen::read(r);
        r.finish();
        if (state > 2 || id >= layout.overlay.configCount || delay > maxOverlayDelay)
            throw std::runtime_error("Invalid item overlay pose");
        if (state && at<unsigned>(overlay, layout.overlay.id) != id)
            originalShow(reinterpret_cast<void*>(overlay), id, delay, nullptr);
        at<unsigned>(overlay, layout.overlay.state) = state;
        at<unsigned>(overlay, layout.overlay.id) = id;
        at<unsigned>(overlay, layout.overlay.delay) = delay;
        screens[slot] = screen;
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int scenePose(lua_State* L) {
    try {
        if (!game())
            throw std::runtime_error("Item presentation requires an active game");
        const auto scene = game() + layout.game.scene;
        if (!lua.getTop(L)) {
            lan::Writer w(lan::Message::world);
            w.u8(at<unsigned>(scene, layout.scene.state));
            w.u8(at<unsigned>(scene, layout.scene.id));
            w.u32(homeSleepSerial);
            const auto manager = at<Address>(image, bindings.manager);
            w.u8(at<bool>(manager + layout.manager.nightmare, layout.nightmare.home));
            w.u32(at<unsigned>(manager + layout.manager.nightmare, layout.nightmare.index));
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply Home scene pose");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto state = r.u8(), id = r.u8();
        const auto sleep = r.u32();
        const auto dreamHome = r.u8();
        const auto dreamIndex = static_cast<int>(r.u32());
        r.finish();
        if (state > 1 || id > 4 || dreamHome > 1 || dreamIndex < -3 || dreamIndex > 1000)
            throw std::runtime_error("Invalid Home scene pose");
        // Sprite loading below supplies this process's own native resources.
        // Do not call Show/Update, which also emit music and route effects.
        at<unsigned>(scene, layout.scene.state) = state;
        at<unsigned>(scene, layout.scene.id) = id;
        const auto manager = at<Address>(image, bindings.manager);
        at<bool>(manager + layout.manager.nightmare, layout.nightmare.home) = dreamHome;
        at<int>(manager + layout.manager.nightmare, layout.nightmare.index) = dreamIndex;
        // The host's NightmareScene stops gameplay snapshot capture. Replaying
        // it when the nighttime snapshot arrives would start a second, delayed
        // dream on the guest. Keep the host's native dream and resume the guest
        // directly in the nighttime room instead.
        homeSleepSerial = sleep;
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int sceneSprite(lua_State* L) {
    if (!game()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    const auto scene = game() + layout.game.scene;
    if (!sample || lua.rawLength(L, 1) != 8 ||
        (!runtime::replica() && (!at<unsigned>(scene, layout.scene.state) ||
                                 !at<bool>(scene + layout.scene.sprite, layout.sprite.loaded)))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = scene + layout.scene.sprite;
    lua.getMetatable(L, 1);
    lua.setMetatable(L, -2);
    return 1;
}
int dreamSprite(lua_State* L) {
    if (!game()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    const auto manager = at<Address>(image, bindings.manager);
    if (!sample || lua.rawLength(L, 1) != 8 ||
        at<int>(manager, layout.manager.scene) != nightmareScene) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto part = lua.checkInteger(L, 2);
    if (part < 0 || part > 1) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = manager + layout.manager.nightmare +
                 (part ? layout.nightmare.bubble : layout.nightmare.background);
    lua.getMetatable(L, 1);
    lua.setMetatable(L, -2);
    return 1;
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
                if (textEvent(e.kind)) {
                    w.string(e.title);
                    w.string(e.subtitle);
                    if (localizedEvent(e.kind))
                        for (const auto* source : {&e.titleSource, &e.subtitleSource}) {
                            source->write(w);
                        }
                    if (e.kind == Kind::styledText)
                        w.u8(e.style);
                } else {
                    w.u32(e.id);
                    w.u32(e.parameter);
                    if (e.kind == Kind::overlay)
                        w.u8(e.hasPlayer);
                }
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
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
            if (e.slot >= party::maxPlayers || e.role >= maxBodyRoles || batch.size() >= maxEvents)
                throw std::runtime_error("Invalid item presentation owner");
            if (textEvent(e.kind)) {
                e.title = r.string();
                e.subtitle = r.string();
                if (e.title.size() > 1024 || e.subtitle.size() > 1024)
                    throw std::runtime_error("Invalid item presentation text");
                if (localizedEvent(e.kind))
                    for (auto* source : {&e.titleSource, &e.subtitleSource}) {
                        *source = TextSource::read(r);
                    }
                if (e.kind == Kind::styledText) {
                    e.style = r.u8();
                    if (!bindings.customTextStyle ||
                        e.style > (engine::native_item_presentation::stickyText |
                                   engine::native_item_presentation::curseText))
                        throw std::runtime_error("Invalid native item text style");
                }
            } else if (e.kind == Kind::overlay || e.kind == Kind::item) {
                e.id = static_cast<int>(r.u32());
                e.parameter = static_cast<int>(r.u32());
                if (e.kind == Kind::overlay) {
                    const auto flag = r.u8();
                    if (flag > 1 || e.id < 0 ||
                        static_cast<unsigned>(e.id) >= layout.overlay.configCount ||
                        e.parameter < 0 || static_cast<unsigned>(e.parameter) > maxOverlayDelay)
                        throw std::runtime_error("Invalid native item overlay");
                    e.hasPlayer = flag;
                } else if (e.id < -1024 || (e.id < 0 && e.parameter == trinketType) ||
                           e.parameter < 1 || e.parameter > 4) {
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
                const auto hud = game() + layout.game.hud;
                if (e.kind == Kind::overlay) {
                    originalShow(reinterpret_cast<void*>(game() + layout.game.overlay), e.id,
                                 e.parameter,
                                 e.hasPlayer ? reinterpret_cast<void*>(target) : nullptr);
                } else if (e.kind == Kind::fortune) {
                    showFortune(reinterpret_cast<void*>(hud), fortuneText(e));
                } else if (textEvent(e.kind)) {
                    const auto title = localText(e.title, e.titleSource),
                               subtitle = localText(e.subtitle, e.subtitleSource);
                    callCustomText(reinterpret_cast<void*>(hud), reinterpret_cast<void*>(target),
                                   title.c_str(), subtitle.c_str(), e.style);
                } else {
                    // Resolve through this version's checked native accessors. Manager's
                    // EntityConfig is not ItemConfig; reading its vectors here
                    // would pass a non-item pointer into the native HUD.
                    const auto config =
                        engine<GetItemConfig>(bindings.entry.managerGetItemConfig)();
                    const auto lookup = engine<GetItem>(
                        e.parameter == trinketType ? bindings.entry.itemConfigGetTrinket
                                                   : bindings.entry.itemConfigGetCollectible);
                    const auto item = lookup(reinterpret_cast<void*>(config), e.id);
                    if (!item || at<int>(item, layout.item.type) != e.parameter ||
                        at<int>(item, layout.item.id) != e.id)
                        return;
                    originalItemText(reinterpret_cast<void*>(hud), reinterpret_cast<void*>(target),
                                     reinterpret_cast<void*>(item));
                }
                ++played[textEvent(e.kind) ? 2 : static_cast<unsigned char>(e.kind) - 1];
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
    if (!game()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    Address overlay = game() + layout.game.overlay;
    if (!runtime::replica()) {
        const auto slot = lua.getTop(L) ? lua.checkInteger(L, 1) : runtime::localViewSlot();
        if (party::validSlot(slot) && owned[slot])
            overlay = owned[slot]->address();
    }
    lua.createTable(L, 0, 6);
    auto integer = [&](const char* name, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, name);
    };
    integer("overlayState", at<int>(overlay, layout.overlay.state));
    integer("overlayID", at<int>(overlay, layout.overlay.id));
    integer("overlayDelay", at<int>(overlay, layout.overlay.delay));
    integer("globalOverlayState", at<int>(game() + layout.game.overlay, layout.overlay.state));
    integer("bookLoaded", at<bool>(overlay + layout.overlay.book, layout.sprite.loaded));
    integer("bookPlaying", at<bool>(overlay + layout.overlay.book, layout.sprite.playing));
    integer("megaLoaded", at<bool>(overlay + layout.overlay.mega, layout.sprite.loaded));
    integer("megaPlaying", at<bool>(overlay + layout.overlay.mega, layout.sprite.playing));
    integer("megaFrame", at<unsigned>(overlay + layout.overlay.mega, layout.sprite.frame));
    integer("overlays", played[0]);
    integer("items", played[1]);
    integer("texts", played[2]);
    integer("sceneState", at<unsigned>(game() + layout.game.scene, layout.scene.state));
    integer("sceneID", at<unsigned>(game() + layout.game.scene, layout.scene.id));
    const auto manager = at<Address>(image, bindings.manager);
    integer("dreamActive", at<int>(manager, layout.manager.scene) == nightmareScene);
    integer("dreamHome", at<bool>(manager + layout.manager.nightmare, layout.nightmare.home));
    return 1;
}
} // namespace
namespace {
bool installHooks(Address base) {
    if (!base || installed)
        return false;
    image = base;
    std::array<void*, 14> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned offset, void* callback, void** original) {
        const auto target = reinterpret_cast<void*>(image + offset);
        if (MH_CreateHook(target, callback, original) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success = hook(bindings.entry.hudShowFortune, reinterpret_cast<void*>(fortune),
                        reinterpret_cast<void**>(&originalFortune)) &&
                   hook(bindings.entry.stringTableIndexed, reinterpret_cast<void*>(indexedText),
                        reinterpret_cast<void**>(&originalIndexedText)) &&
                   hook(bindings.entry.gameAddPixelation, reinterpret_cast<void*>(pixelate),
                        reinterpret_cast<void**>(&originalPixelate)) &&
                   hook(bindings.entry.playerUpdateWavyCap, reinterpret_cast<void*>(wavy),
                        reinterpret_cast<void**>(&originalWavy)) &&
                   hook(bindings.entry.playerUsePill, reinterpret_cast<void*>(pill),
                        reinterpret_cast<void**>(&originalPill)) &&
                   hook(bindings.entry.playerUseCard, reinterpret_cast<void*>(card),
                        reinterpret_cast<void**>(&originalCard)) &&
                   hook(bindings.entry.bossOverlayShow, reinterpret_cast<void*>(sceneShow),
                        reinterpret_cast<void**>(&originalSceneShow)) &&
                   hook(bindings.entry.stringTableLookup, reinterpret_cast<void*>(lookupText),
                        reinterpret_cast<void**>(&originalLookupText)) &&
                   hook(bindings.entry.itemOverlayUpdate, reinterpret_cast<void*>(update),
                        reinterpret_cast<void**>(&originalUpdate)) &&
                   hook(bindings.entry.itemOverlayShow, reinterpret_cast<void*>(show),
                        reinterpret_cast<void**>(&originalShow)) &&
                   hook(bindings.entry.itemOverlayRender, reinterpret_cast<void*>(render),
                        reinterpret_cast<void**>(&originalRender)) &&
                   hook(bindings.entry.itemOverlayLoad, reinterpret_cast<void*>(load),
                        reinterpret_cast<void**>(&originalLoad)) &&
                   hook(bindings.entry.hUDShowItemText, reinterpret_cast<void*>(itemText),
                        reinterpret_cast<void**>(&originalItemText)) &&
                   hook(bindings.entry.hUDShowItemTextCustomUTF8, bindings.customTextDetour,
                        reinterpret_cast<void**>(&originalCustomText));
    if (success) {
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        originalFortune = nullptr;
        originalIndexedText = nullptr;
        originalPixelate = nullptr;
        originalWavy = nullptr;
        originalPill = nullptr;
        originalCard = nullptr;
        originalSceneShow = nullptr;
        originalLookupText = nullptr;
        originalUpdate = nullptr;
        originalShow = nullptr;
        originalRender = nullptr;
        originalLoad = nullptr;
        originalItemText = nullptr;
        originalCustomText = nullptr;
        image = 0;
    }
    installed = success;
    return success;
}
} // namespace
bool install(Address base) {
    return base && !installed && engine::native_scene_update::install(base) &&
           pickup_preview::install(base) && moving_box::install(base) && installHooks(base);
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushInteger, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::createTable, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::newUserdata, isaac::lua::Symbol::rawLength,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable}))
        return false;
    lua.pushClosure(L, synchronize, 0);
    lua.setField(L, -2, "item_presentation_events");
    lua.pushClosure(L, status, 0);
    lua.setField(L, -2, "item_presentation_state");
    lua.pushClosure(L, overlaySprite, 0);
    lua.setField(L, -2, "item_presentation_sprite");
    lua.pushClosure(L, pose, 0);
    lua.setField(L, -2, "item_presentation_pose");
    lua.pushClosure(L, scenePose, 0);
    lua.setField(L, -2, "home_scene_pose");
    lua.pushClosure(L, sceneSprite, 0);
    lua.setField(L, -2, "home_scene_sprite");
    lua.pushClosure(L, dreamSprite, 0);
    lua.setField(L, -2, "home_dream_sprite");
    return true;
}
void withActor(void* player, const std::function<void()>& action) {
    const auto before = actionPlayer;
    actionPlayer = player;
    const auto actor = owner(player);
    const auto previousSlot = screenSlot;
    const auto generation = screenGeneration;
    const auto currentGame = game();
    const bool scoped = rooms::virtualized() && !runtime::replica() && actor.player &&
                        screenSlot != static_cast<int>(actor.slot);
    const auto global = scoped ? readScreen() : ItemScreen{};
    if (scoped) {
        writeScreen(screens[actor.slot]);
        screenSlot = static_cast<int>(actor.slot);
    }
    const auto restore = [&] {
        if (scoped && game() == currentGame) {
            if (generation == screenGeneration)
                screens[actor.slot] = readScreen();
            writeScreen(global);
        }
        screenSlot = generation == screenGeneration ? previousSlot : -1;
        actionPlayer = generation == screenGeneration ? before : nullptr;
    };
    // Native player update and nested item/card/pill calls share one owner's
    // postprocess state. A nested action must not overwrite its caller with a
    // stale saved screen, or leak a direct Game field write to the host view.
    try {
        action();
    } catch (...) {
        restore();
        throw;
    }
    restore();
}
void withScreen(const std::function<void()>& draw) {
    const auto slot = runtime::localViewSlot();
    if (!game() || !rooms::virtualized() || !party::validSlot(slot)) {
        draw();
        return;
    }
    const auto currentGame = game();
    const auto before = readScreen();
    auto display = screens[slot];
    // World/route flashes outside a player action remain global effects.
    if (before.bloom) {
        display.bloom = before.bloom;
        display.bloomDuration = before.bloomDuration;
        display.bloomIntensity = before.bloomIntensity;
    }
    writeScreen(display);
    try {
        draw();
    } catch (...) {
        if (game() == currentGame)
            writeScreen(before);
        throw;
    }
    if (game() == currentGame)
        writeScreen(before);
}
void advance() {
    if (!game() || !rooms::virtualized()) {
        owned = {};
        return;
    }
    if (runtime::replica() || at<int>(game(), layout.game.pauseMenu))
        return;
    for (auto& screen : screens)
        screen.advance();
    // Game skips ItemOverlay::Update when its global overlay is inactive.
    // Owned overlays therefore advance once per accepted host tick, in their
    // owner's room/roster, without pausing another player's simulation/input.
    for (unsigned slot = 0; slot < owned.size(); ++slot)
        if (owned[slot] && at<int>(owned[slot]->address(), layout.overlay.state))
            rooms::withPlayer(slot, [&] { originalUpdate(owned[slot]->data(), false); });
}
void reset(bool preservePixels) {
    moving_box::reset();
    ++screenGeneration;
    screenSlot = -1;
    for (auto& screen : screens) {
        const auto previous = screen;
        screen = {};
        if (preservePixels) {
            screen.pixels = previous.pixels;
            screen.pixelDuration = previous.pixelDuration;
        }
    }
    actionPlayer = nullptr;
    homeSleepSerial = 0;
    owned = {};
    events.clear();
    lookups.clear();
    indexedLookups.clear();
    serial = seen = 0;
    played = {};
}
} // namespace isaac::presentation::items

namespace isaac::engine::native_item_presentation {
void captureCustomText(void* hud, void* actor, const char* title, const char* subtitle,
                       unsigned style) {
    presentation::items::customText(hud, actor, title, subtitle, style);
}
} // namespace isaac::engine::native_item_presentation
