// Exercise the production hooks with both audited native ABIs, without the game.
#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/item_presentation.cpp"
#include <map>
#include <set>
#include <iostream>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned overlayOffset = 0x1bcc0, overlayBytes = 0x1260, configs = 47;
constexpr unsigned megaOffset = 0x114c, delayOffset = 0x1144, sceneOffset = 0x1cf20;
constexpr unsigned playersOffset = 0x1ba50, controllerOffset = 0x154c, controlsOffset = 0x360;
constexpr unsigned hudOffset = 0x3da4c, pauseOffset = 0x10203c, nightmareOffset = 0x211bc;
constexpr unsigned tableOffset = 0x4a234, pixelsOffset = 0x24363c, dizzyOffset = 0x283c04;
constexpr unsigned bloomOffset = 0x1c3148;
#else
#include "engine/versions/j460/entrypoints.h"
namespace backend = isaac::engine::j460;
constexpr unsigned overlayOffset = 0x1c034, overlayBytes = 0x12b8, configs = 48;
constexpr unsigned megaOffset = 0x11a4, delayOffset = 0x119c, sceneOffset = 0x1d2ec;
constexpr unsigned playersOffset = 0x1baa8, controllerOffset = 0x1618, controlsOffset = 0x410;
constexpr unsigned hudOffset = 0x1da04, pauseOffset = 0x23a74, nightmareOffset = 0x21628;
constexpr unsigned tableOffset = 0x4a920, pixelsOffset = 0x269e0, dizzyOffset = 0x67738;
constexpr unsigned bloomOffset = 0x26528;
#endif
struct lua_State {
    int top = 1;
    std::array<long long, 3> arguments{};
    std::string input, output;
    bool success = false, validUserdata = true;
    std::size_t userdataBytes = 8;
    std::array<std::uintptr_t, 2> sample{0x12345678, 0}, result{};
    std::map<std::string, long long> values;
    long long value = 0;
    unsigned metatables = 0;
};
namespace {
namespace lan = isaac::lan;
namespace items = isaac::presentation::items;
namespace binding = isaac::engine::native_item_presentation;
using Address = std::uintptr_t;
using Screen = isaac::presentation::ItemScreen;
unsigned char* image = nullptr;
std::vector<unsigned char> game(0x290000), manager(0x50000);
std::array<std::array<unsigned char, 0x1700>, 5> players{};
std::array<Address, 5> roster{};
std::array<unsigned char, 32> category{}, sentinel{};
std::array<Address, 2> strings{};
std::array<int, 2> itemConfig{1, 123};
unsigned tick = 100, epoch = 7, connected = 15;
int localSlot = 0, selectedRoom = -1;
bool replica = false, ending = false, virtualized = true, loadSucceeds = true;
bool gatherAccepted = true, lookupMissing = false;
unsigned shows = 0, updates = 0, renders = 0, texts = 0, itemTexts = 0, fortunes = 0;
unsigned loads = 0, destructs = 0, configConstructs = 0, sceneShows = 0, indexedCalls = 0;
unsigned pillCalls = 0, cardCalls = 0, pixelCalls = 0, wavyCalls = 0, nextToken = 0;
unsigned styleObserved = 0, flagsObserved = 0, installScene = 0, installPreview = 0;
int idObserved = 0, delayObserved = 0, colorObserved = 0, roomObserved = -1;
void* objectObserved = nullptr;
void* playerObserved = nullptr;
std::string titleObserved, subtitleObserved, fortuneObserved, loadedPath, lastError;
std::set<unsigned> allocations;
std::vector<Address> constructors;
std::function<void()> nativeAction, gathered;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address word(const void* pointer) {
    return reinterpret_cast<Address>(pointer);
}
void* overlay() {
    return game.data() + overlayOffset;
}
void* hud() {
    return game.data() + hudOffset;
}
void* table() {
    return manager.data() + tableOffset;
}
void* scene() {
    return game.data() + sceneOffset;
}
void jump(unsigned rva, void* function) {
    auto* destination = image + rva;
    std::memset(destination, 0x90, 16);
    destination[0] = 0xe9;
    const auto relative = word(function) - word(destination + 5);
    std::memcpy(destination + 1, &relative, 4);
}
unsigned call(unsigned rva, void* receiver, std::initializer_list<unsigned> arguments = {}) {
    const auto result = native_fixture::call(image + rva, receiver, arguments);
    require(result.balanced && result.preserved,
            "Native item hook corrupted its stack or nonvolatile registers");
    return result.eax;
}
void __attribute__((fastcall)) constructSprite(void* sprite, void*) {
    std::memset(sprite, 0, 0x114);
    const auto token = ++nextToken;
    allocations.insert(token);
    field<unsigned>(sprite, 0x18) = token;
    field<Address>(sprite, 0x30) = field<Address>(sprite, 0x50) = word(sprite);
    constructors.push_back(word(sprite));
}
void __attribute__((fastcall)) constructConfig(void* config, void*) {
    std::memset(config, 0, 0x58);
    field<unsigned>(config, 0) = 0xc0ffee;
    ++configConstructs;
    constructors.push_back(word(config));
}
void releaseSprite(void* sprite) {
    require(field<Address>(sprite, 0x30) == word(sprite) &&
                field<Address>(sprite, 0x50) == word(sprite),
            "Moved ANM2 retained a reference to another owner");
    require(allocations.erase(field<unsigned>(sprite, 0x18)) == 1,
            "Native sprite allocation was lost or freed twice");
}
void __attribute__((fastcall)) destructOverlay(void* object, void*) {
    for (unsigned i = 0; i < configs; ++i)
        require(field<unsigned>(object, 0x11c + i * 0x58) == 0xc0ffee,
                "Native overlay configuration construction was incomplete");
    releaseSprite(static_cast<unsigned char*>(object) + 8);
    releaseSprite(static_cast<unsigned char*>(object) + megaOffset);
    ++destructs;
}
bool __attribute__((fastcall)) loadOverlay(void* object, void*, const char* path) {
    ++loads;
    loadedPath = path;
    require(object == overlay() || (word(object) & 7) == 0,
            "Owned native overlay storage is not aligned");
    if (object != overlay()) {
        require(constructors.size() >= configs + 2, "Missing native overlay constructors");
        const auto start = constructors.size() - configs - 2;
        require(constructors[start] == word(object) + 8 &&
                    constructors.back() == word(object) + megaOffset,
                "Native overlay sprite positions differ from this version");
        for (unsigned i = 0; i < configs; ++i)
            require(constructors[start + i + 1] == word(object) + 0x11c + i * 0x58,
                    "Native overlay configuration stride or count differs");
    }
    field<bool>(object, 0x111) = loadSucceeds;
    return loadSucceeds;
}
void __attribute__((fastcall)) showOverlay(void* object, void*, int id, int delay, void* player) {
    ++shows;
    objectObserved = object;
    playerObserved = player;
    idObserved = id;
    delayObserved = delay;
    field<unsigned>(object, 0) = 1;
    field<int>(object, 4) = id;
    field<int>(object, delayOffset) = delay;
}
void __attribute__((fastcall)) updateOverlay(void* object, void*, bool finish) {
    require(!finish, "Owned overlay finished outside the native animation");
    ++updates;
    objectObserved = object;
    roomObserved = selectedRoom;
}
void __attribute__((fastcall)) renderOverlay(void* object, void*) {
    ++renders;
    objectObserved = object;
}
void __attribute__((fastcall)) showItem(void* object, void*, void* player, void* config) {
    ++itemTexts;
    objectObserved = object;
    playerObserved = player;
    require(config == itemConfig.data(), "Item text did not resolve through native configuration");
}
void recordText(void* object, void* player, const char* title, const char* subtitle,
                unsigned style) {
    ++texts;
    objectObserved = object;
    playerObserved = player;
    titleObserved = title;
    subtitleObserved = subtitle;
    styleObserved = style;
}
#ifdef ISAAC_LAN_TEST_J835
void __attribute__((fastcall)) showText(void* object, void*, const char* title,
                                        const char* subtitle, bool sticky, bool curse) {
    recordText(object, nullptr, title, subtitle, (sticky ? 1 : 0) | (curse ? 2 : 0));
}
#else
void __attribute__((fastcall)) showText(void* object, void*, void* player, const char* title,
                                        const char* subtitle) {
    recordText(object, player, title, subtitle, 1);
}
#endif
void customText(void* player, const char* title, const char* subtitle, unsigned style = 1) {
#ifdef ISAAC_LAN_TEST_J835
    items::withActor(player, [&] {
        call(backend::entry::hUDShowItemTextCustomUTF8, hud(),
             {word(title), word(subtitle), style & 1, (style >> 1) & 1});
    });
#else
    require(style == 1, "J460 fixture received an unsupported text style");
    call(backend::entry::hUDShowItemTextCustomUTF8, hud(),
         {word(player), word(title), word(subtitle)});
#endif
}
const char* __attribute__((fastcall)) lookupText(void* object, void*, const char* section,
                                                 int language, const char* key, bool* missing) {
    require(object == table() && std::string(section) == "Items" && std::string(key) == "name",
            "Text localization lost its native receiver or key");
    *missing = lookupMissing;
    return language ? "local title" : "host title";
}
const char* __attribute__((fastcall)) indexedText(void* object, void*, const char* section,
                                                  int language, int index) {
    require(object == table() && std::string(section) == "Fortunes" && index == 1,
            "Unchecked fortune index reached the native iterator");
    ++indexedCalls;
    return language ? "local first|local second|" : "host first|host second|";
}
void __attribute__((fastcall)) showFortune(void* object, void*, const void* list) {
    require(object == hud(), "Fortune receiver is not the native HUD");
    ++fortunes;
    fortuneObserved.clear();
    const auto* words = static_cast<const Address*>(list);
    auto node = field<Address>(reinterpret_cast<void*>(words[0]), 0);
    for (unsigned i = 0; i < words[1]; ++i) {
        auto* pointer = reinterpret_cast<void*>(node);
        const auto* text = field<unsigned>(pointer, 28) >= 16
                               ? field<const char*>(pointer, 8)
                               : reinterpret_cast<const char*>(node + 8);
        if (i)
            fortuneObserved += '|';
        fortuneObserved.append(text, field<unsigned>(pointer, 24));
        node = field<Address>(pointer, 0);
    }
    require(node == words[0], "Borrowed fortune list is not circular");
}
void __attribute__((fastcall)) pixelate(void* object, void*, int duration) {
    require(object == game.data(), "Pixelation receiver differs from Game");
    ++pixelCalls;
    field<unsigned>(object, pixelsOffset) = field<unsigned>(object, pixelsOffset + 4) = duration;
}
void __attribute__((fastcall)) wavy(void* player, void*) {
    ++wavyCalls;
    playerObserved = player;
    field<float>(game.data(), dizzyOffset + 4) = 0.75f;
    field<float>(game.data(), dizzyOffset + 8) = 0.25f;
}
void __attribute__((fastcall)) pill(void* player, void*, int effect, int color, unsigned flags) {
    ++pillCalls;
    playerObserved = player;
    idObserved = effect;
    colorObserved = color;
    flagsObserved = flags;
    if (nativeAction)
        nativeAction();
}
void __attribute__((fastcall)) card(void* player, void*, int id, unsigned flags) {
    ++cardCalls;
    playerObserved = player;
    idObserved = id;
    flagsObserved = flags;
    if (nativeAction)
        nativeAction();
}
void __attribute__((fastcall)) showScene(void* object, void*, int id) {
    ++sceneShows;
    objectObserved = object;
    idObserved = id;
}
Address __cdecl getConfig() {
    return word(itemConfig.data());
}
Address __attribute__((fastcall)) getItem(void* config, void*, int id) {
    require(config == itemConfig.data(), "ItemConfig receiver was confused with EntityConfig");
    return id == itemConfig[1] ? word(itemConfig.data()) : 0;
}
void initializeGlobal() {
    std::memset(overlay(), 0, overlayBytes);
    constructSprite(static_cast<unsigned char*>(overlay()) + 8, nullptr);
    for (unsigned i = 0; i < configs; ++i)
        constructConfig(static_cast<unsigned char*>(overlay()) + 0x11c + i * 0x58, nullptr);
    constructSprite(static_cast<unsigned char*>(overlay()) + megaOffset, nullptr);
}
void resetFixture() {
    items::reset();
    if (!allocations.empty())
        destructOverlay(overlay(), nullptr);
    require(allocations.empty(), "A reset retained an owned native allocation");
    std::fill(game.begin(), game.end(), 0xa5);
    std::fill(manager.begin(), manager.end(), 0);
    field<Address>(image, backend::globals::game) = word(game.data());
    field<Address>(image, backend::globals::manager) = word(manager.data());
    field<int>(game.data(), 0) = 4;
    field<int>(game.data(), 4) = 0;
    field<int>(game.data(), pauseOffset) = 0;
    field<Address>(game.data(), playersOffset) = word(roster.data());
    field<Address>(game.data(), playersOffset + 4) = word(roster.data() + roster.size());
    for (unsigned i = 0; i < players.size(); ++i) {
        players[i].fill(0xa5);
        field<unsigned>(players[i].data(), controllerOffset) = i == 4 ? 2 : i + 1;
        field<bool>(players[i].data(), controlsOffset) = true;
        roster[i] = word(players[i].data());
    }
    initializeGlobal();
    constructors.clear();
    items::writeScreen({});
    field<unsigned>(scene(), 0) = field<unsigned>(scene(), 4) = 0;
    category.fill(0);
    sentinel.fill(0);
    field<bool>(sentinel.data(), 0xd) = true;
    field<Address>(sentinel.data(), 4) = word(category.data());
    field<Address>(category.data(), 0) = field<Address>(category.data(), 8) = word(sentinel.data());
    field<const char*>(category.data(), 0x10) = "fortunes";
    strings = {word(sentinel.data()), 2};
    field<Address>(category.data(), 0x14) = word(strings.data());
    field<Address>(table(), 0xc) = word(sentinel.data());
    field<unsigned>(table(), 0x10) = 1;
    tick = 100;
    epoch = 7;
    connected = 15;
    localSlot = 0;
    selectedRoom = -1;
    replica = ending = lookupMissing = false;
    virtualized = loadSucceeds = gatherAccepted = true;
    shows = updates = renders = texts = itemTexts = fortunes = loads = destructs = 0;
    configConstructs = sceneShows = indexedCalls = pillCalls = cardCalls = pixelCalls = wavyCalls =
        0;
    nativeAction = gathered = {};
    lastError.clear();
}
std::string collect(unsigned slot) {
    lua_State L;
    L.arguments[0] = slot;
    require(items::synchronize(&L) == 1, "Collect presentation events");
    return L.output;
}
bool apply(const std::string& bytes) {
    lua_State L;
    L.input = bytes;
    require(items::synchronize(&L) == 1, "Apply presentation events");
    return L.success;
}
std::string hexBytes(const std::string& text) {
    std::string bytes;
    for (std::size_t i = 0; i < text.size(); i += 2)
        bytes += static_cast<char>(std::stoul(text.substr(i, 2), nullptr, 16));
    return bytes;
}
std::string screenBytes(const Screen& screen) {
    lan::Writer w(lan::Message::world);
    screen.write(w);
    return {reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1};
}
void configureLua() {
    items::lua.getTop = [](lua_State* L) { return L->top; };
    items::lua.checkInteger = [](lua_State* L, int i) { return L->arguments.at(i - 1); };
    items::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    items::lua.pushLString = [](lua_State* L, const char* bytes, std::size_t size) {
        L->output.assign(bytes, size);
        return L->output.c_str();
    };
    items::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
    items::lua.pushInteger = [](lua_State* L, long long value) { L->value = value; };
    items::lua.createTable = [](lua_State* L, int, int) { L->values.clear(); };
    items::lua.setField = [](lua_State* L, int, const char* key) { L->values[key] = L->value; };
    items::lua.toUserdata = [](lua_State* L, int) -> void* {
        return L->validUserdata ? L->sample.data() : nullptr;
    };
    items::lua.rawLength = [](lua_State* L, int) { return L->userdataBytes; };
    items::lua.newUserdata = [](lua_State* L, std::size_t size) -> void* {
        require(size == 8, "Borrowed Sprite wrapper became an owning native object");
        return L->result.data();
    };
    items::lua.getMetatable = [](lua_State*, int) { return 1; };
    items::lua.setMetatable = [](lua_State* L, int) {
        ++L->metatables;
        return 1;
    };
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
bool ending() {
    return ::ending;
}
unsigned tick() {
    return ::tick;
}
unsigned worldEpoch() {
    return epoch;
}
int localViewSlot() {
    return localSlot;
}
void abort(const std::string& error) {
    lastError = error;
}
} // namespace isaac::runtime
namespace isaac::rooms {
bool virtualized() {
    return ::virtualized;
}
unsigned connected() {
    return ::connected;
}
std::uintptr_t presentationPlayer(void* explicitPlayer) {
    return word(explicitPlayer);
}
bool gatherForTransition(const std::function<void()>& action) {
    if (gatherAccepted)
        gathered = action;
    return gatherAccepted;
}
bool withPlayer(unsigned slot, const std::function<void()>& action) {
    const auto previous = selectedRoom;
    selectedRoom = slot;
    action();
    selectedRoom = previous;
    return true;
}
void withView(const std::function<void()>& action, bool) {
    action();
}
} // namespace isaac::rooms
namespace isaac::engine::native_scene_update {
bool install(std::uintptr_t) {
    ++installScene;
    return true;
}
} // namespace isaac::engine::native_scene_update
namespace isaac::presentation::pickup_preview {
bool install(std::uintptr_t) {
    ++installPreview;
    return true;
}
} // namespace isaac::presentation::pickup_preview
int main() {
    try {
        require(!items::install(0) && !installScene && !installPreview,
                "An empty image reached component installation");
        constexpr unsigned imageBytes = 0x900000;
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageBytes, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate native item fixture");
        const std::vector<std::pair<unsigned, void*>> hooks{
            {backend::entry::hudShowFortune, reinterpret_cast<void*>(showFortune)},
            {backend::entry::stringTableIndexed, reinterpret_cast<void*>(indexedText)},
            {backend::entry::gameAddPixelation, reinterpret_cast<void*>(pixelate)},
            {backend::entry::playerUpdateWavyCap, reinterpret_cast<void*>(wavy)},
            {backend::entry::playerUsePill, reinterpret_cast<void*>(pill)},
            {backend::entry::playerUseCard, reinterpret_cast<void*>(card)},
            {backend::entry::bossOverlayShow, reinterpret_cast<void*>(showScene)},
            {backend::entry::stringTableLookup, reinterpret_cast<void*>(lookupText)},
            {backend::entry::itemOverlayUpdate, reinterpret_cast<void*>(updateOverlay)},
            {backend::entry::itemOverlayShow, reinterpret_cast<void*>(showOverlay)},
            {backend::entry::itemOverlayRender, reinterpret_cast<void*>(renderOverlay)},
            {backend::entry::itemOverlayLoad, reinterpret_cast<void*>(loadOverlay)},
            {backend::entry::hUDShowItemText, reinterpret_cast<void*>(showItem)},
            {backend::entry::hUDShowItemTextCustomUTF8, reinterpret_cast<void*>(showText)}};
        for (const auto& [rva, function] : hooks)
            jump(rva, function);
        jump(backend::entry::aNM2Construct, reinterpret_cast<void*>(constructSprite));
        jump(backend::entry::itemOverlayConfigConstruct, reinterpret_cast<void*>(constructConfig));
        jump(backend::entry::itemOverlayDestruct, reinterpret_cast<void*>(destructOverlay));
        jump(backend::entry::managerGetItemConfig, reinterpret_cast<void*>(getConfig));
        jump(backend::entry::itemConfigGetCollectible, reinterpret_cast<void*>(getItem));
        jump(backend::entry::itemConfigGetTrinket, reinterpret_cast<void*>(getItem));
        FlushInstructionCache(GetCurrentProcess(), image, imageBytes);
        for (const auto& [conflict, function] : hooks) {
            require(MH_CreateHook(image + conflict, function, nullptr) == MH_OK,
                    "Prepare foreign item hook");
            require(!items::installHooks(word(image)) && !items::image && !items::originalShow &&
                        !items::originalCustomText && !items::originalLoad,
                    "Partial item installation retained its native state");
            require(MH_CreateHook(image + conflict, function, nullptr) == MH_ERROR_ALREADY_CREATED,
                    "Item rollback removed a foreign hook");
            for (const auto& [rva, callback] : hooks) {
                if (rva == conflict)
                    continue;
                require(MH_CreateHook(image + rva, callback, nullptr) == MH_OK &&
                            MH_RemoveHook(image + rva) == MH_OK,
                        "Item rollback leaked an owned hook");
            }
            require(MH_RemoveHook(image + conflict) == MH_OK, "Remove conflict fixture");
        }
        require(items::install(word(image)) && !items::install(word(image)) && installScene == 1 &&
                    installPreview == 1,
                "Item install retry failed or duplicate install changed dependencies");
        configureLua();
        std::cout << "fixture ordinary" << std::endl;
        resetFixture();
        virtualized = false;
        connected = 0;
        call(backend::entry::itemOverlayShow, overlay(), {4, 9, 0});
        call(backend::entry::itemOverlayUpdate, overlay(), {0});
        call(backend::entry::itemOverlayRender, overlay());
        customText(nullptr, "ordinary", "subtitle");
        call(backend::entry::gameAddPixelation, game.data(), {20});
        require(shows == 1 && updates == 1 && renders == 1 && texts == 1 && pixelCalls == 1 &&
                    titleObserved == "ordinary" && !loads && collect(0).empty(),
                "Ordinary presentation was virtualized or its native arguments changed");

        resetFixture();
        std::cout << "fixture mega" << std::endl;
        const auto before = game;
        const auto globalMega = field<unsigned>(overlay(), megaOffset + 0x18);
        call(backend::entry::itemOverlayShow, overlay(), {45, 7, word(players[4].data())});
        require(shows == 1 && loads == 1 && configConstructs == configs &&
                    allocations.size() == 4 && objectObserved != overlay() &&
                    playerObserved == players[4].data() &&
                    field<unsigned>(objectObserved, megaOffset + 0x18) == globalMega &&
                    field<unsigned>(overlay(), megaOffset + 0x18) != globalMega &&
                    field<unsigned>(overlay(), 0) == 0,
                "Mega Mush did not transfer its owned animation to the acting peer");
        auto expected = before;
        std::memcpy(expected.data() + overlayOffset + megaOffset,
                    static_cast<unsigned char*>(overlay()) + megaOffset, 0x114);
        require(game == expected, "Owned overlay changed unrelated native Game bytes");
        const auto packet = collect(1);
        require(packet == hexBytes("010000000100000064000000070101010000002d0000000701") &&
                    collect(0).empty(),
                "Overlay wire bytes or secondary-body ownership changed");
        items::advance();
        require(updates == 1 && roomObserved == 1, "Owned overlay advanced in another peer's room");
        field<int>(game.data(), pauseOffset) = 1;
        items::advance();
        require(updates == 1, "Paused presentation advanced its native overlay");
        localSlot = 1;
        call(backend::entry::itemOverlayRender, overlay());
        require(renders == 2 && objectObserved != overlay(),
                "Local peer's owned overlay was hidden");
        items::reset();
        require(destructs == 1 && allocations.size() == 2 && collect(1).empty(),
                "Reset leaked an overlay or retained its event");
        replica = true;
        require(apply(packet) && shows == 2 && objectObserved == overlay() &&
                    playerObserved == players[4].data() && apply(packet) && shows == 2,
                "Replica failed to resolve the secondary body or replayed a duplicate event");
        call(backend::entry::itemOverlayUpdate, overlay(), {0});
        require(updates == 1, "Replica ran authoritative item animation side effects");
        ending = true;
        call(backend::entry::itemOverlayUpdate, overlay(), {0});
        require(updates == 2, "Ending overlay did not resume native updates");

        resetFixture();
        std::cout << "fixture load-failure" << std::endl;
        loadSucceeds = false;
        call(backend::entry::itemOverlayShow, overlay(), {2, 0, word(players[0].data())});
        require(!lastError.empty() && shows == 0 && destructs == 1 && allocations.size() == 2 &&
                    !items::owned[0],
                "Failed native configuration retained or displayed an overlay");
        loadSucceeds = true;
        call(backend::entry::itemOverlayShow, overlay(), {2, 0, word(players[0].data())});
        const char path[] = "resources/test-giantbook.xml";
        call(backend::entry::itemOverlayLoad, overlay(), {word(path)});
        require(destructs == 2 && allocations.size() == 2,
                "Reload retained native overlay resources");
        call(backend::entry::itemOverlayShow, overlay(), {3, 0, word(players[0].data())});
        require(loadedPath == path && allocations.size() == 4,
                "Recreated overlay used a stale config");

        resetFixture();
        std::cout << "fixture custom-text" << std::endl;
        customText(players[1].data(), "guest", "description");
        require(texts == 0 && collect(0).empty(), "A guest's item text appeared on the host HUD");
        auto textPacket = collect(1);
        require(textPacket == hexBytes("0100000001000000640000000701000300056775657374"
                                       "000b6465736372697074696f6e"),
                "Default custom-text wire bytes changed during backend extraction");
        items::reset();
        replica = true;
        localSlot = 1;
        require(apply(textPacket) && texts == 1 && titleObserved == "guest" &&
                    subtitleObserved == "description" && styleObserved == 1 &&
                    objectObserved == hud(),
                "Custom text did not survive its native ABI and wire round trip");
#ifndef ISAAC_LAN_TEST_J835
        require(playerObserved == players[1].data(), "J460 custom text lost its actor parameter");
#endif
        for (unsigned style : {0u, 1u, 2u, 3u}) {
#ifndef ISAAC_LAN_TEST_J835
            if (style != 1)
                continue;
#endif
            resetFixture();
            bool missing = false;
            const char section[] = "Items", key[] = "name";
            const auto title = call(backend::entry::stringTableLookup, table(),
                                    {word(section), 0, word(key), word(&missing)});
            customText(players[1].data(), reinterpret_cast<const char*>(title), "subtitle", style);
            textPacket = collect(1);
            items::reset();
            replica = true;
            localSlot = 1;
            field<int>(table(), 0) = 1;
            require(apply(textPacket) && texts == 1 && titleObserved == "local title" &&
                        styleObserved == style,
                    "Localized item text lost its original display flags");
        }
#ifdef ISAAC_LAN_TEST_J835
        auto invalidStyle = textPacket;
        invalidStyle.back() = 4;
        items::reset();
        require(!apply(invalidStyle) && texts == 1, "Unknown item style flags reached the HUD");
#endif
        resetFixture();
        for (int type : {1, 2, 3, 4}) {
            itemConfig = {type, 123};
            call(backend::entry::hUDShowItemText, hud(),
                 {word(players[1].data()), word(itemConfig.data())});
            const auto itemPacket = collect(1);
            items::reset();
            replica = true;
            localSlot = 1;
            const auto count = itemTexts;
            require(apply(itemPacket) && itemTexts == count + 1 &&
                        playerObserved == players[1].data(),
                    "Native item text lost its collectible/trinket configuration");
            items::reset();
            replica = false;
            localSlot = 0;
        }

        resetFixture();
        std::cout << "fixture fortune" << std::endl;
        const char fortunesSection[] = "Fortunes";
        call(backend::entry::stringTableIndexed, table(), {word(fortunesSection), 0, 1});
        std::array<std::array<unsigned char, 32>, 3> nodes{};
        const char* lines[] = {"host first", "host second"};
        for (unsigned i = 0; i < nodes.size(); ++i) {
            field<Address>(nodes[i].data(), 0) = word(nodes[(i + 1) % 3].data());
            field<Address>(nodes[i].data(), 4) = word(nodes[(i + 2) % 3].data());
            if (i) {
                std::memcpy(nodes[i].data() + 8, lines[i - 1], std::strlen(lines[i - 1]));
                field<unsigned>(nodes[i].data(), 24) = std::strlen(lines[i - 1]);
                field<unsigned>(nodes[i].data(), 28) = 15;
            }
        }
        const std::array<Address, 2> list{word(nodes.data()), 2};
        const auto nodeSnapshot = nodes;
        items::withActor(players[1].data(),
                         [&] { call(backend::entry::hudShowFortune, hud(), {word(list.data())}); });
        require(nodes == nodeSnapshot && !fortunes,
                "Fortune capture modified or displayed a borrowed list");
        const auto fortunePacket = collect(1);
        items::reset();
        replica = true;
        localSlot = 1;
        field<int>(table(), 0) = 1;
        require(apply(fortunePacket) && fortunes == 1 && indexedCalls == 2 &&
                    fortuneObserved == "local first|local second|",
                "Fortune localization or its borrowed replay list changed");
#ifdef ISAAC_LAN_TEST_J835
        require(binding::bindings.indexedTextInRange(word(table()), "FORTUNES", 1) &&
                    !binding::bindings.indexedTextInRange(word(table()), "Fortunes", 2) &&
                    !binding::bindings.indexedTextInRange(word(table()), "absent", 0) &&
                    !binding::bindings.indexedTextInRange(word(table()), "Fortunes", -1),
                "J835 fortune bounds do not match its native category map");
        strings[1] = 1;
        items::reset();
        require(apply(fortunePacket) && fortunes == 2 && indexedCalls == 2 &&
                    fortuneObserved == "host first|host second",
                "Out-of-range native fortune index did not use the captured fallback");
#endif

        resetFixture();
        std::cout << "fixture screens" << std::endl;
        const Screen global{19, 20, 0.5f, 0.75f, 0.125f, 8, 9, 0.25f};
        items::writeScreen(global);
        const auto gameBefore = game;
        nativeAction = [&] {
            call(backend::entry::gameAddPixelation, game.data(), {31});
            call(backend::entry::playerUpdateWavyCap, players[1].data());
        };
        call(backend::entry::playerUsePill, players[1].data(), {71, 15, 0x55aa});
        require(pillCalls == 1 && colorObserved == 15 && flagsObserved == 0x55aa &&
                    pixelCalls == 0 && wavyCalls == 1 && game == gameBefore &&
                    items::screens[1].pixels == 31 && items::screens[1].target == 0.75f,
                "Pill scope leaked its screen state or changed native arguments");
        nativeAction = [&] {
            items::withActor(players[2].data(),
                             [&] { call(backend::entry::gameAddPixelation, game.data(), {52}); });
            call(backend::entry::gameAddPixelation, game.data(), {41});
        };
        call(backend::entry::playerUseCard, players[1].data(), {14, 0x80});
        require(cardCalls == 1 && idObserved == 14 && flagsObserved == 0x80 &&
                    items::screens[1].pixels == 41 && items::screens[2].pixels == 52 &&
                    game == gameBefore,
                "Nested card scope overwrote another owner's screen state");
        try {
            items::withActor(players[1].data(), [&] {
                call(backend::entry::gameAddPixelation, game.data(), {61});
                throw std::runtime_error("fixture actor exit");
            });
        } catch (const std::runtime_error&) {
        }
        require(game == gameBefore && items::screens[1].pixels == 61 && !items::actionPlayer &&
                    items::screenSlot == -1,
                "Exceptional actor scope did not restore borrowed state");
        localSlot = 1;
        try {
            items::withScreen([&] {
                require(field<unsigned>(game.data(), pixelsOffset) == 61 &&
                            field<unsigned>(game.data(), bloomOffset) == global.bloom,
                        "Local display lost its actor effect or global route flash");
                throw std::runtime_error("fixture draw exit");
            });
        } catch (const std::runtime_error&) {
        }
        require(game == gameBefore, "Exceptional render scope leaked its viewport effects");
        items::reset(true);
        require(items::screens[1].pixels == 61 && !items::screens[1].bloom &&
                    items::screens[1].target == 0,
                "Pixel-preserving reset retained unrelated effects");
        items::withActor(players[1].data(), [&] { items::reset(); });
        require(!items::screens[1].pixels && game == gameBefore,
                "A scope crossing reset restored stale per-player effects");
        items::withActor(players[1].data(),
                         [&] { field<Address>(image, backend::globals::game) = 0; });
        const auto releasedGame = game;
        items::withScreen([] {});
        require(game == releasedGame && items::screenSlot == -1 && !items::actionPlayer,
                "Released Game was restored through a stale actor or render scope");
        field<Address>(image, backend::globals::game) = word(game.data());
        items::writeScreen(global);
        replica = true;
        items::withActor(players[1].data(), [&] {
            call(backend::entry::gameAddPixelation, game.data(), {71});
            call(backend::entry::playerUpdateWavyCap, players[1].data());
        });
        require(pixelCalls == 0 && wavyCalls == 1 && game == gameBefore,
                "Replica recomputed authority-owned screen effects");

        resetFixture();
        call(backend::entry::itemOverlayShow, overlay(), {2, 3, word(players[1].data())});
        std::cout << "fixture pose" << std::endl;
        lua_State pose;
        pose.arguments[0] = 1;
        items::pose(&pose);
        require(pose.output == hexBytes("010200000003") + screenBytes({}),
                "Item pose field order or screen encoding changed");
        auto posePacket = pose.output;
        items::reset();
        replica = true;
        localSlot = 1;
        pose.top = 2;
        pose.input = posePacket;
        const auto showCount = shows;
        require(items::pose(&pose) == 1 && pose.success && shows == showCount + 1 &&
                    field<unsigned>(overlay(), 4) == 2 &&
                    field<unsigned>(overlay(), delayOffset) == 3,
                "Replica pose used the wrong native layout");
        auto expectedPose = game;
        pose.input[1] = static_cast<char>(configs);
        require(items::pose(&pose) == 1 && !pose.success && game == expectedPose &&
                    shows == showCount + 1,
                "Invalid version-specific overlay ID changed native state");
        pose.input = posePacket + "x";
        require(items::pose(&pose) == 1 && !pose.success && game == expectedPose,
                "Trailing item pose bytes were applied before validation");
        lua_State sprite;
        sprite.top = 3;
        sprite.arguments = {1, 0, 1};
        items::overlaySprite(&sprite);
        require(sprite.result[0] == sprite.sample[0] &&
                    sprite.result[1] == word(overlay()) + megaOffset && sprite.metatables == 1,
                "Mega sprite wrapper lost its borrowed ownership or metatable");
        sprite.arguments[2] = 0;
        items::overlaySprite(&sprite);
        require(sprite.result[1] == word(overlay()) + 8, "Book sprite offset differs");
        sprite.userdataBytes = 16;
        items::overlaySprite(&sprite);
        require(!sprite.success && sprite.metatables == 2,
                "Owning Sprite userdata was borrowed unsafely");
        sprite.userdataBytes = 8;
        items::sceneSprite(&sprite);
        require(sprite.result[1] == word(scene()) + 8, "Home scene Sprite offset differs");
        field<int>(manager.data(), 8) = 5;
        sprite.arguments[1] = 1;
        items::dreamSprite(&sprite);
        require(sprite.result[1] == word(manager.data()) + nightmareOffset + 0x134,
                "Nightmare bubble Sprite offset differs");
        sprite.arguments[1] = 0;
        items::dreamSprite(&sprite);
        require(sprite.result[1] == word(manager.data()) + nightmareOffset + 0x20,
                "Nightmare background Sprite offset differs");

        resetFixture();
        std::cout << "fixture home" << std::endl;
        field<int>(game.data(), 0) = 13;
        call(backend::entry::itemOverlayShow, overlay(), {44, 6, word(players[1].data())});
        require(gathered && !shows, "Home sleep did not wait for its gathered roster");
        gathered();
        require(shows == 1 && objectObserved == overlay() && !playerObserved &&
                    items::homeSleepSerial == 1 && !collect(0).empty() && !collect(3).empty(),
                "Home sleep lost its run-wide overlay and peer events");
        field<int>(game.data(), 4) = 1;
        call(backend::entry::bossOverlayShow, scene(), {3});
        require(sceneShows == 0, "Beast scene started before its roster was gathered");
        gathered();
        for (auto& player : players)
            require(!field<bool>(player.data(), controlsOffset),
                    "Gathered player controls stayed enabled");
        require(sceneShows == 1 && objectObserved == scene(), "Native Home scene receiver changed");
        field<unsigned>(scene(), 0) = 1;
        field<unsigned>(scene(), 4) = 3;
        field<bool>(manager.data(), nightmareOffset + 0x5e8) = true;
        field<int>(manager.data(), nightmareOffset + 0x3a0) = -3;
        lua_State home;
        home.top = 0;
        items::scenePose(&home);
        require(home.output == hexBytes("01030000000101fffffffd"), "Home pose encoding changed");
        auto homePacket = home.output;
        replica = true;
        home.top = 1;
        home.input = homePacket;
        const auto sceneCount = sceneShows;
        items::scenePose(&home);
        require(home.success && sceneShows == sceneCount,
                "Home pose replayed native route effects");
        const auto beforeHome = game, beforeManager = manager;
        home.input.back() = 0;
        items::scenePose(&home);
        require(!home.success && game == beforeHome && manager == beforeManager,
                "Invalid Home pose partially modified native state");

        resetFixture();
        std::cout << "fixture event-lifecycle" << std::endl;
        for (unsigned i = 0; i < 35; ++i)
            customText(players[1].data(), "bounded", "queue");
        auto batch = collect(1);
        require(static_cast<unsigned char>(batch[0]) == 24 &&
                    batch.substr(1, 4) == hexBytes("0000000c"),
                "Presentation queue exceeded its bounded history");
        tick = 190;
        require(!collect(1).empty(), "Presentation expired before its age boundary");
        tick = 191;
        require(collect(1).empty(), "Expired presentation remained in the wire batch");
        tick = 100;
        ++epoch;
        require(collect(1).empty(), "Previous room epoch leaked presentation events");
        items::reset();
        replica = true;
        localSlot = 1;
        --epoch;
        auto invalidBatch = batch + "x";
        require(!apply(invalidBatch) && texts == 0 && apply(batch) && texts == 24,
                "Batch parsing applied partial native effects or consumed its serials on failure");
        require(apply(batch) && texts == 24, "Repeated snapshot duplicated custom text");
        items::reset();
        ++epoch;
        require(apply(batch) && texts == 24, "Stale world event was replayed after a room change");

        items::reset();
        const auto retained = game;
        field<Address>(image, backend::globals::game) = 0;
        items::withScreen([] {});
        items::withActor(nullptr, [] {});
        items::advance();
        lua_State missing;
        items::status(&missing);
        require(!missing.success, "Missing game exposed native presentation state");
        items::pose(&missing);
        require(!missing.success, "Missing game accepted an item pose");
        require(game == retained, "An absent game caused a stale presentation write");
        field<Address>(image, backend::globals::game) = word(game.data());
        destructOverlay(overlay(), nullptr);
        require(allocations.empty() && MH_Uninitialize() == MH_OK,
                "Native presentation cleanup failed");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "item presentation native ownership, wire, scopes and ABI passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
