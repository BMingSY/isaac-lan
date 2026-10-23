// Private x86 image: exercise the real J460 menu calls and input-query hook.
// Including input.cpp keeps the query hook under test without installing hooks
// in a process or exposing a production API solely for tests.
#include "test_support.h"
#include "engine/versions/j460/input.cpp"
#include <array>
#include <vector>
#include <thread>

namespace {
int localViewer = 1;
bool replicaViewer = false;
std::vector<isaac::rooms::SavedLocation> playerLocations;
} // namespace
namespace isaac::runtime {
bool replica() {
    return replicaViewer;
}
int localViewSlot() {
    return localViewer;
}
void pollLocalConsole() {}
void refreshAutomation(std::uint32_t) {}
} // namespace isaac::runtime
namespace isaac::rooms {
std::vector<SavedLocation> captureLocations() {
    return playerLocations;
}
} // namespace isaac::rooms
namespace isaac::frontend {
bool capturesInput() {
    return false;
}
} // namespace isaac::frontend
namespace isaac::engine::items {
void grantStartingRewards(void*, unsigned) {
    throw std::runtime_error("The menu fixture must not spawn gameplay actors");
}
} // namespace isaac::engine::items

namespace {
namespace menu = isaac::pause_menu;
namespace input = isaac::input;
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
constexpr unsigned imageSize = 0x880000, menuOffset = 0x23a74;
constexpr unsigned optionsOffset = menuOffset + 0x5b0, playerIndexOffset = menuOffset + 0xfac;
template <class T> T& field(void* memory, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<std::uint8_t*>(memory) + offset);
}
struct Fixture;
Fixture* current = nullptr;
void __attribute__((thiscall)) showFixture(void*);
void __attribute__((thiscall)) hideFixture(void*);
void __attribute__((thiscall)) saveOptionsFixture(void*);
void __attribute__((thiscall)) controlsFixture(void*);
bool __attribute__((thiscall)) queryFixture(void*, int, void*, const int*, void*, int*);
struct QueryCall {
    void* receiver;
    int controller, action;
    Address kind;
};
enum class NativeControls { idle, root, options };
struct Fixture {
    std::uint8_t* image = nullptr;
    std::vector<std::uint8_t> game = std::vector<std::uint8_t>(0x27000, 0);
    std::vector<std::uint8_t> manager = std::vector<std::uint8_t>(0x4ac00, 0);
    std::array<std::array<std::uint8_t, 0x2200>, 4> players{};
    std::array<Address, 4> roster{};
    std::array<int, 256> entries{};
    std::array<float, 32> physicalValues{};
    std::uint32_t physicalEdges = 0;
    std::vector<QueryCall> queries;
    std::vector<char> saveHideOrder;
    NativeControls mode = NativeControls::idle;
    unsigned shows = 0, hides = 0, saves = 0, controls = 0, nativeExits = 0, nativeResumes = 0;
    unsigned controllerChanges = 0, optionConfirms = 0;
    int volume = 5, queryController = 1;
    bool validReceiver = true;

    Fixture() {
        image = static_cast<std::uint8_t*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image != nullptr, "Cannot allocate private pause-menu image");
        current = this;
        const auto jump = [&](unsigned offset, auto destination) {
            image[offset] = 0xe9;
            field<std::uint32_t>(image, offset + 1) =
                static_cast<std::uint32_t>(reinterpret_cast<Address>(destination) -
                                           reinterpret_cast<Address>(image + offset + 5));
        };
        jump(native::entry::pauseMenuShow, showFixture);
        jump(native::entry::pauseMenuHide, hideFixture);
        jump(native::entry::optionsSave, saveOptionsFixture);
        jump(native::entry::pauseMenuControls, controlsFixture);
        require(FlushInstructionCache(GetCurrentProcess(), image, imageSize) != 0,
                "Cannot publish private native-call trampolines");
        field<Address>(image, native::globals::game) = reinterpret_cast<Address>(game.data());
        field<Address>(image, native::globals::manager) = reinterpret_cast<Address>(manager.data());
        for (unsigned slot = 0; slot < 4; ++slot)
            field<int>(players[slot].data(), 0x1618) = static_cast<int>(slot + 1);
        reorder({0, 1, 2, 3});
        entries[0] = 4;
        entries[1] = 0;
        entries[2] = 1; // The controller entry's ID is not its vector index.
        entries[3] = 5;
        options(4);
        input::reset();
        input::image = base();
        input::originalQuery = queryFixture;
        input::localPauseInput = false;
        input::pauseIntent = menu::Intent::none;
        input::viewSlot = -1;
        input::menuConfirm = false;
        localViewer = 1;
        replicaViewer = false;
        playerLocations.clear();
    }
    ~Fixture() {
        input::reset();
        input::originalQuery = nullptr;
        input::image = 0;
        current = nullptr;
        VirtualFree(image, 0, MEM_RELEASE);
    }
    Address base() const {
        return reinterpret_cast<Address>(image);
    }
    void* receiver() {
        return game.data() + menuOffset;
    }
    int& page() {
        return field<int>(game.data(), menuOffset);
    }
    int& selection() {
        return field<int>(game.data(), menuOffset + 8);
    }
    int& viewerIndex() {
        return field<int>(game.data(), playerIndexOffset);
    }
    int& optionSelection() {
        return field<int>(game.data(), optionsOffset + 8);
    }
    void reorder(std::array<unsigned, 4> order) {
        for (unsigned i = 0; i < 4; ++i)
            roster[i] = reinterpret_cast<Address>(players[order[i]].data());
        field<Address>(game.data(), 0x1baa8) = reinterpret_cast<Address>(roster.data());
        field<Address>(game.data(), 0x1baac) =
            reinterpret_cast<Address>(roster.data() + roster.size());
    }
    void options(unsigned count) {
        field<Address>(game.data(), optionsOffset + 0x27c) =
            reinterpret_cast<Address>(entries.data());
        field<Address>(game.data(), optionsOffset + 0x280) =
            reinterpret_cast<Address>(entries.data()) + count * 4;
        field<Address>(game.data(), optionsOffset + 0x284) =
            reinterpret_cast<Address>(entries.data() + entries.size());
    }
    void accept(isaac::lan::Frame frame = {}) {
        frame.players = 4;
        input::apply(frame);
    }
    bool query(int action, unsigned kind = native::entry::inputTriggered, float* result = nullptr,
               int* source = nullptr) {
        return input::query(image + 0x857b18, nullptr, queryController,
                            reinterpret_cast<void*>(base() + kind), &action, result, source);
    }
    void press(unsigned action) {
        physicalValues[action] = 1;
        physicalEdges |= 1u << action;
    }
    void clearPhysical() {
        physicalValues.fill(0);
        physicalEdges = 0;
        queries.clear();
    }
    void onlyLocalQueries() const {
        require(!queries.empty(), "Expected native physical queries");
        for (const auto& query : queries)
            require(query.receiver == image + 0x857b18 && query.controller == -1,
                    "Pause input queried a peer controller instead of the local source");
    }
};

void __attribute__((thiscall)) showFixture(void* receiver) {
    current->validReceiver &= receiver == current->receiver();
    ++current->shows;
    current->page() = 1;
}
void __attribute__((thiscall)) hideFixture(void* receiver) {
    current->validReceiver &= receiver == current->receiver();
    ++current->hides;
    current->saveHideOrder.push_back('H');
    current->page() = 0;
}
void __attribute__((thiscall)) saveOptionsFixture(void* receiver) {
    current->validReceiver &= receiver == current->manager.data() + 0x2a33c && current->page() == 2;
    ++current->saves;
    current->saveHideOrder.push_back('S');
}
bool __attribute__((thiscall)) queryFixture(void* receiver, int controller, void* callback,
                                            const int* action, void* result, int* source) {
    auto& f = *current;
    const auto kind = reinterpret_cast<Address>(callback) - f.base();
    f.queries.push_back({receiver, controller, action ? *action : -1, kind});
    if (!action || *action < 0 || *action >= 32)
        return false;
    const auto value = f.physicalValues[*action];
    if (kind == native::entry::inputValue && result)
        *static_cast<float*>(result) = value;
    const bool pressed = kind == native::entry::inputTriggered
                             ? (f.physicalEdges & (1u << *action)) != 0
                             : value != 0;
    if (pressed && source)
        *source = 99; // Distinguish physical attribution from accepted input.
    return pressed;
}
void __attribute__((thiscall)) controlsFixture(void* receiver) {
    auto& f = *current;
    f.validReceiver &= receiver == f.receiver();
    ++f.controls;
    if (f.mode == NativeControls::root) {
        // Native Controls changes selection before it asks about confirmation.
        if (f.query(23))
            ++f.selection();
        if (f.query(14)) {
            if (f.selection() == 3)
                ++f.nativeExits;
            else if (f.selection() == 2)
                ++f.nativeResumes;
        }
        if (f.query(12) || f.query(15))
            ++f.nativeResumes;
    } else if (f.mode == NativeControls::options) {
        if (f.query(21))
            ++f.volume;
        if (f.query(20))
            --f.volume;
        if (f.query(14)) {
            ++f.optionConfirms;
            if (menu::state(f.base()).optionId == 1)
                ++f.controllerChanges;
        }
    }
}

void nativeCallsAndState() {
    Fixture f;
    const auto absent = menu::state(0);
    require(absent.page == 0 && absent.selection == -1 && absent.controller == -1 &&
                absent.optionId == -1,
            "Absent menu state did not return unavailable fields");
    menu::show(0);
    menu::hide(0);
    menu::controls(0);
    menu::hide(f.base());
    menu::controls(f.base());
    require(f.hides == 0 && f.controls == 0, "Closed menu invoked native controls or hide");
    menu::show(f.base());
    menu::controls(f.base());
    menu::hide(f.base());
    menu::hide(f.base());
    require(f.shows == 1 && f.controls == 1 && f.hides == 1 && f.page() == 0 && f.validReceiver,
            "Show/Controls/Hide did not call the native thiscall receiver exactly once");
    field<Address>(f.image, native::globals::game) = 0;
    menu::show(f.base());
    menu::hide(f.base());
    menu::controls(f.base());
    require(f.shows == 1 && f.controls == 1 && f.hides == 1 &&
                menu::state(f.base()).controller == -1,
            "Missing Game invoked a native menu or fabricated a controller");
}

void optionsSaveBeforeHide() {
    Fixture f;
    const auto managerBefore = f.manager;
    f.page() = 2;
    menu::hide(f.base());
    require(f.saves == 1 && f.hides == 1 && f.page() == 0 &&
                f.saveHideOrder == std::vector<char>{'S', 'H'} && f.validReceiver,
            "Options close did not save Manager's configuration before native Hide");
    menu::hide(f.base());
    require(f.saves == 1 && f.hides == 1 && f.saveHideOrder.size() == 2,
            "Repeated hide saved or closed an already hidden menu");
    for (int page : {1, 3}) {
        f.page() = page;
        f.saveHideOrder.clear();
        menu::hide(f.base());
        require(f.saves == 1 && f.page() == 0 && f.saveHideOrder == std::vector<char>{'H'},
                "Closing Root or Items spuriously saved native Options");
    }
    f.page() = 2;
    f.saveHideOrder.clear();
    field<Address>(f.image, native::globals::manager) = 0;
    menu::hide(f.base());
    require(f.saves == 1 && f.hides == 4 && f.page() == 0 &&
                f.saveHideOrder == std::vector<char>{'H'} && f.validReceiver,
            "Missing Manager was dereferenced or prevented native menu Hide");
    require(f.manager == managerBefore, "Options close modified unrelated native Manager data");
}

void viewerScopes() {
    Fixture f;
    f.viewerIndex() = 2;
    const auto beforeGame = f.game;
    const auto beforePlayers = f.players;
    const auto beforeRoster = f.roster;
    for (unsigned slot = 0; slot < 4; ++slot) {
        menu::selectPlayer(f.base(), slot);
        require(f.viewerIndex() == static_cast<int>(slot) &&
                    menu::state(f.base()).controller == static_cast<int>(slot + 1),
                "Canonical menu state confused zero-based roster index and controller ID");
    }
    f.reorder({2, 0, 3, 1});
    menu::selectPlayer(f.base(), 1);
    require(f.viewerIndex() == 3 && menu::state(f.base()).controller == 2,
            "Selected local player by slot instead of actual roster index");
    f.reorder({1, 0, 2, 3});
    {
        menu::ViewScope outer(f.base(), 1);
        require(f.viewerIndex() == 0 && menu::state(f.base()).controller == 2,
                "Borrowed roster did not scope the local viewer to its first actor");
        {
            menu::ViewScope inner(f.base(), 1);
            require(f.viewerIndex() == 0, "Nested menu view changed local roster coordinates");
        }
        require(f.viewerIndex() == 0, "Nested menu view failed to restore outer index");
    }
    require(f.viewerIndex() == 3, "Borrowed menu view failed to restore canonical index");
    {
        menu::ViewScope mismatch(f.base(), 0);
        menu::ViewScope invalid(f.base(), 4);
        require(f.viewerIndex() == 3, "Nonlocal or invalid view replaced the menu index");
    }
    f.reorder({0, 1, 2, 3});
    f.viewerIndex() = 2;
    require(f.game == beforeGame && f.players == beforePlayers && f.roster == beforeRoster,
            "Menu view scope changed native player ownership or failed to restore its fields");
    f.page() = 0;
    for (localViewer = 0; localViewer < 4; ++localViewer) {
        f.accept();
        require(menu::state(f.base()).controller == localViewer + 1,
                "Accepted network frame did not select this machine's local viewer");
    }
}

void nativePauseDrift() {
    Fixture f;
    // The host remains unpaused across every packet; focus loss opens only the
    // guest's native menu. Repeated synchronization must inspect actual state.
    for (int page : {1, 2, 3}) {
        f.page() = page;
        const auto hides = f.hides;
        menu::synchronize(f.base(), false);
        menu::synchronize(f.base(), false);
        require(f.page() == 0 && f.hides == hides + 1,
                "Unchanged unpaused authority left a native guest overlay open");
    }
    require(f.saves == 1, "Clearing a local Options overlay lost its configuration");
    menu::synchronize(f.base(), true);
    for (int page : {1, 2, 3}) {
        f.page() = page;
        f.selection() = 3;
        menu::synchronize(f.base(), true);
        require(f.page() == page && f.selection() == 3 && f.shows == 1,
                "Repeated paused snapshots reset the local submenu");
    }
    f.page() = 0;
    menu::synchronize(f.base(), true);
    require(f.page() == 1 && f.shows == 2, "Native hide escaped the authority's pause");
}

template <unsigned Marker> DWORD WINAPI physicalState(DWORD index, XINPUT_STATE* result) {
    if (index != 2 || !result)
        return ERROR_DEVICE_NOT_CONNECTED;
    *result = {};
    result->dwPacketNumber = Marker;
    result->Gamepad.wButtons = XINPUT_GAMEPAD_A;
    result->Gamepad.sThumbLX = 17000;
    result->Gamepad.bLeftTrigger = 127;
    return ERROR_SUCCESS;
}
template <class Function> FARPROC procedure(Function fn) {
    FARPROC result;
    memcpy(&result, &fn, sizeof(result));
    return result;
}
template <class Function> Function functionPointer(FARPROC proc) {
    Function result;
    memcpy(&result, &proc, sizeof(result));
    return result;
}
void xinputProviderRouting() {
    Fixture f;
    input::xinputProviders = {};
    input::virtualDevices = false;
    input::labInput = false;
    const auto firstModule = reinterpret_cast<HMODULE>(1);
    const auto secondModule = reinterpret_cast<HMODULE>(2);
    const auto first = functionPointer<input::GetState>(
        input::resolve(firstModule, "XInputGetState", procedure(physicalState<11>)));
    const auto second = functionPointer<input::GetState>(
        input::resolve(secondModule, "XInputGetState", procedure(physicalState<22>)));
    input::xinputProviders[0].extendedState = physicalState<33>;
    XINPUT_STATE value{};
    for (bool lan : {false, true, false}) {
        input::virtualDevices = lan;
        require(first(2, &value) == ERROR_SUCCESS && value.dwPacketNumber == 11 &&
                    value.Gamepad.wButtons == XINPUT_GAMEPAD_A && value.Gamepad.sThumbLX == 17000 &&
                    value.Gamepad.bLeftTrigger == 127,
                "Resolving another XInput DLL replaced the first provider's physical input");
        require(second(2, &value) == ERROR_SUCCESS && value.dwPacketNumber == 22,
                "Second XInput provider lost its own input");
        require(input::extendedState<0>(2, &value) == ERROR_SUCCESS && value.dwPacketNumber == 33,
                "Extended XInput query was redirected through ordinary GetState");
        value.Gamepad.wButtons = 0xffff;
        require(first(0, &value) == (lan ? ERROR_SUCCESS : ERROR_DEVICE_NOT_CONNECTED),
                "Disconnected controller fallback leaked outside LAN");
        if (lan)
            require(value.Gamepad.wButtons == 0, "Virtual controller retained stale buttons");
        require(first(4, &value) == ERROR_DEVICE_NOT_CONNECTED &&
                    first(0, nullptr) == ERROR_DEVICE_NOT_CONNECTED,
                "Invalid XInput device/result accepted");
    }
    require(input::resolve(firstModule, "XInputGetState", nullptr) == nullptr,
            "Missing native export was fabricated");
    input::virtualDevices = true;
    input::labInput = true;
    input::labButtons = XINPUT_GAMEPAD_START;
    require(input::extendedState<0>(0, &value) == ERROR_SUCCESS &&
                value.Gamepad.wButtons == XINPUT_GAMEPAD_START,
            "Isolated test input stopped working on extended XInput");
    require(first(2, &value) == ERROR_SUCCESS && value.dwPacketNumber == 11,
            "Test input replaced a different physical device");
    input::labInput = false;
    input::labButtons = -1;
    input::leaveLan();
    require(first(0, &value) == ERROR_DEVICE_NOT_CONNECTED,
            "Leaving LAN retained a virtual controller");
    input::xinputProviders = {};
}

struct DisconnectFixture {
    HANDLE entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    HANDLE competing = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    std::atomic<unsigned> traversals{0}, frees{0};
    std::atomic<bool> live{true}, overlap{false};
    ~DisconnectFixture() {
        CloseHandle(entered);
        CloseHandle(release);
        CloseHandle(competing);
    }
    void disconnect() {
        const auto ordinal = ++traversals;
        const bool retained = live;
        if (ordinal == 1) {
            SetEvent(entered);
            WaitForSingleObject(release, 5000);
        } else
            SetEvent(competing);
        if (retained) {
            // Model the native vector pointer retained across the XInput call.
            // The old paths could both reach free() with this same pointer.
            if (!live.exchange(false))
                overlap = true;
            ++frees;
        }
    }
};
DisconnectFixture* disconnectFixture = nullptr;
void __cdecl disconnectDevice() {
    disconnectFixture->disconnect();
}
void __cdecl connectCallback() {
    input::pollDevices(); // Native connect callback reenters the poll routine.
}
void inputDisconnectTransactions() {
    input::originalEnumerateDevices = disconnectDevice;
    input::originalPollDevices = disconnectDevice;
    {
        DisconnectFixture unguarded;
        disconnectFixture = &unguarded;
        std::thread foreground(disconnectDevice);
        const bool started = WaitForSingleObject(unguarded.entered, 5000) == WAIT_OBJECT_0;
        std::thread background(disconnectDevice);
        const bool raced = WaitForSingleObject(unguarded.competing, 5000) == WAIT_OBJECT_0;
        background.join();
        SetEvent(unguarded.release);
        foreground.join();
        require(started && raced && unguarded.frees == 2 && unguarded.overlap,
                "Disconnect regression did not reproduce the unguarded double release");
    }
    // Exercise both orderings and the post-LAN drain (virtualDevices=false).
    for (const bool lan : {true, false})
        for (const bool scanFirst : {true, false}) {
            input::virtualDevices = lan;
            DisconnectFixture f;
            disconnectFixture = &f;
            const auto first = scanFirst ? input::enumerateDevices : input::pollDevices;
            const auto second = scanFirst ? input::pollDevices : input::enumerateDevices;
            std::thread foreground(first);
            const bool started = WaitForSingleObject(f.entered, 5000) == WAIT_OBJECT_0;
            std::thread background(second);
            const auto competing = WaitForSingleObject(f.competing, 50);
            SetEvent(f.release);
            foreground.join();
            background.join();
            require(started && competing == WAIT_TIMEOUT && f.traversals == 2 && f.frees == 1 &&
                        !f.overlap,
                    "Hotplug and polling retained/freed the same disconnected native device");
        }
    DisconnectFixture nested;
    disconnectFixture = &nested;
    SetEvent(nested.release);
    input::originalEnumerateDevices = connectCallback;
    input::enumerateDevices();
    require(nested.traversals == 1 && nested.frees == 1,
            "Native connect callback could not reenter input polling");
    input::originalEnumerateDevices = input::originalPollDevices = nullptr;
    disconnectFixture = nullptr;
}

void invalidRosters() {
    Fixture f;
    const auto begin = reinterpret_cast<Address>(f.roster.data());
    const auto check = [&] {
        f.viewerIndex() = 3;
        menu::selectPlayer(f.base(), 1);
        { menu::ViewScope scoped(f.base(), 1); }
        require(f.viewerIndex() == 3 && menu::state(f.base()).controller == -1,
                "Invalid roster escaped fail-closed menu selection");
    };
    for (const auto range : std::array<std::array<Address, 2>, 5>{{{0, 0},
                                                                   {begin, begin},
                                                                   {begin, begin - 4},
                                                                   {begin, begin + 3},
                                                                   {begin, begin + 257 * 4}}}) {
        field<Address>(f.game.data(), 0x1baa8) = range[0];
        field<Address>(f.game.data(), 0x1baac) = range[1];
        check();
    }
    f.reorder({0, 1, 2, 3});
    f.roster[3] = 0;
    f.viewerIndex() = 3;
    menu::selectPlayer(f.base(), 3);
    require(f.viewerIndex() == 3 && menu::state(f.base()).controller == -1,
            "Missing actor was dereferenced or assigned a controller");
    f.viewerIndex() = -1;
    require(menu::state(f.base()).controller == -1, "Negative player index became a controller");
    f.viewerIndex() = 4;
    require(menu::state(f.base()).controller == -1,
            "Out-of-range player index became a controller");
}

void rootIntents() {
    Fixture f;
    require(menu::intent(0, 14) == menu::Intent::none, "Absent image produced a menu command");
    for (int page : {0, 1, 2, 3}) {
        f.page() = page;
        for (int selected : {-1, 0, 1, 2, 3, 4}) {
            f.selection() = selected;
            const auto expected = page == 1 && selected == 2   ? menu::Intent::resume
                                  : page == 1 && selected == 3 ? menu::Intent::exit
                                                               : menu::Intent::none;
            require(menu::intent(f.base(), 14) == expected,
                    "Confirm escaped root-page selection rules");
            for (int action : {12, 15})
                require(menu::intent(f.base(), action) ==
                            (page == 1 ? menu::Intent::resume : menu::Intent::none),
                        "Pause/back became a session resume outside the root menu");
            require(menu::intent(f.base(), 23) == menu::Intent::none,
                    "Navigation became a session command");
        }
    }
}

void optionsBounds() {
    Fixture f;
    f.page() = 2;
    for (int index = 0; index < 4; ++index) {
        f.optionSelection() = index;
        require(menu::changesController(f.base(), 14) == (index == 2),
                "Controller guard used selection index instead of actual entry ID 1");
        require(menu::state(f.base()).optionId == f.entries[index],
                "Read-only options state reported the wrong entry ID");
    }
    const auto begin = reinterpret_cast<Address>(f.entries.data());
    const auto check = [&] {
        require(menu::changesController(f.base(), 14) && menu::state(f.base()).optionId == -1,
                "Invalid options vector or selection did not fail closed");
        require(!menu::changesController(f.base(), 20),
                "Invalid options blocked ordinary navigation");
    };
    for (int selected : {-1, 4, 256}) {
        f.optionSelection() = selected;
        check();
    }
    f.optionSelection() = 0;
    for (const auto bounds :
         std::array<std::array<Address, 3>, 6>{{{0, 0, 0},
                                                {begin, begin, begin},
                                                {begin, begin - 4, begin},
                                                {begin, begin + 16, begin + 12},
                                                {begin, begin + 3, begin + 16},
                                                {begin, begin + 257 * 4, begin + 257 * 4}}}) {
        field<Address>(f.game.data(), optionsOffset + 0x27c) = bounds[0];
        field<Address>(f.game.data(), optionsOffset + 0x280) = bounds[1];
        field<Address>(f.game.data(), optionsOffset + 0x284) = bounds[2];
        check();
    }
    f.options(256);
    f.optionSelection() = 255;
    f.entries[255] = 7;
    require(!menu::changesController(f.base(), 14) && menu::state(f.base()).optionId == 7,
            "Valid maximum options vector was rejected");
    f.page() = 1;
    f.optionSelection() = 2;
    require(!menu::changesController(f.base(), 14) && menu::state(f.base()).optionId == -1,
            "Options guard leaked into the root menu");
}

void localPauseRouting() {
    Fixture f;
    isaac::lan::Frame frame;
    frame.inputs[0].triggered = (1u << 14) | (1u << 0);
    frame.inputs[0].values[0] = 65535;
    frame.inputs[1].values[0] = 4321;
    f.accept(frame);
    f.page() = 1;
    f.selection() = 0;
    input::physicalInput[0].triggered = 0xabcd;
    const auto acceptedBefore = input::accepted;
    const auto physicalBefore = input::physicalInput;
    {
        input::PauseScope scoped(1);
        require(!f.query(14) && scoped.intent() == menu::Intent::none,
                "Guest consumed the host's accepted Confirm as a local pause-menu action");
        float value = -1;
        require(!f.query(0, native::entry::inputValue, &value) && value == 0,
                "Guest pause navigation read accepted host movement");
        f.press(0);
        f.physicalValues[0] = 0.375f;
        int source = -1;
        require(f.query(0, native::entry::inputValue, &value, &source) && value == 0.375f &&
                    source == 99,
                "Local native value/source did not survive pause routing");
        require(f.query(0, native::entry::inputPressed) && f.query(0),
                "Local held/triggered queries were not routed to physical input");
        f.onlyLocalQueries();
    }
    require(input::accepted == acceptedBefore && input::physicalInput == physicalBefore,
            "Pause queries consumed accepted or latched physical gameplay edges");
    require(input::viewSlot == -1 && !input::localPauseInput, "Pause scope leaked into gameplay");
    require(input::hostMenuTriggered(14),
            "Guest pause query cleared the host's authoritative edge");
}

void sameFrameNavigationAndExit() {
    Fixture f;
    f.accept();
    f.page() = 1;
    f.selection() = 2;
    f.mode = NativeControls::root;
    f.press(23);
    f.press(14);
    f.press(12);
    f.press(15);
    {
        input::PauseScope scoped(1);
        menu::controls(f.base());
        require(f.selection() == 3 && scoped.intent() == menu::Intent::exit,
                "Same-frame native Down then Confirm used the stale pre-navigation selection");
        require(f.nativeExits == 0 && f.nativeResumes == 0,
                "Native exit fade or resume executed before the session could coordinate it");
        require(f.queries.size() == 2 && f.queries[0].action == 23 && f.queries[1].action == 14,
                "A captured exit continued querying or dispatching native actions");
        float value = 1;
        require(!f.query(0, native::entry::inputValue, &value) && value == 0,
                "Captured exit did not suppress subsequent native analog input");
        require(f.queries.size() == 2, "Captured exit polled physical controls again");
        f.onlyLocalQueries();
    }
    require(input::pauseIntent == menu::Intent::none && f.validReceiver,
            "Pause intent or native ECX receiver escaped the scoped call");
    for (int action : {12, 14, 15}) {
        f.clearPhysical();
        f.selection() = 2;
        f.press(action);
        input::PauseScope scoped(1);
        menu::controls(f.base());
        require(scoped.intent() == menu::Intent::resume && f.nativeResumes == 0,
                "Root Resume/Back/Pause executed natively instead of returning an intent");
    }
}

void nestedInputScopes() {
    Fixture f;
    f.accept();
    f.page() = 1;
    f.selection() = 3;
    f.press(14);
    {
        input::ViewScope presentation(2);
        {
            input::PauseScope outer(1);
            require(input::viewSlot == 1 && !f.query(14) && outer.intent() == menu::Intent::exit,
                    "Outer pause did not capture its local exit");
            {
                input::PauseScope inner(3);
                require(input::viewSlot == 3 && inner.intent() == menu::Intent::none,
                        "Nested pause reused an outer pending intent");
                f.selection() = 2;
                require(!f.query(14) && inner.intent() == menu::Intent::resume,
                        "Nested pause failed to capture its independent resume");
            }
            require(input::viewSlot == 1 && input::localPauseInput &&
                        outer.intent() == menu::Intent::exit,
                    "Nested pause did not restore the outer view and exit intent");
        }
        require(input::viewSlot == 2 && !input::localPauseInput &&
                    input::pauseIntent == menu::Intent::none,
                "Pause scope did not restore its containing presentation scope");
        f.clearPhysical();
        require(!f.query(0), "Presentation scope stopped using raw local input");
        f.onlyLocalQueries();
    }
    require(input::viewSlot == -1 && !input::localPauseInput,
            "Nested presentation/pause scopes leaked after destruction");
}

void ordinaryOptionsRemainLocal() {
    Fixture f;
    f.accept();
    f.page() = 2;
    f.mode = NativeControls::options;
    f.optionSelection() = 2;
    f.press(14);
    {
        input::PauseScope scoped(1);
        menu::controls(f.base());
        require(f.controllerChanges == 0 && f.optionConfirms == 0 &&
                    scoped.intent() == menu::Intent::none,
                "Controller reassignment escaped its exact native-entry guard");
    }
    f.optionSelection() = -1;
    {
        input::PauseScope scoped(1);
        menu::controls(f.base());
        require(f.optionConfirms == 0, "Malformed option selection reached native Confirm");
    }
    f.clearPhysical();
    f.optionSelection() = 1; // Entry 0 is allowed, although its vector index is 1.
    f.press(14);
    f.press(21);
    {
        input::PauseScope scoped(1);
        menu::controls(f.base());
        require(f.optionConfirms == 1 && f.volume == 6 && scoped.intent() == menu::Intent::none,
                "Ordinary native options or local volume adjustments were blocked");
        f.onlyLocalQueries();
    }
    f.clearPhysical();
    f.press(15);
    {
        input::PauseScope scoped(1);
        require(f.query(15) && scoped.intent() == menu::Intent::none,
                "Options Back became a session resume instead of native submenu navigation");
    }
}

void gameplayRoutingUnchanged() {
    Fixture f;
    isaac::lan::Frame frame;
    frame.inputs[0].values[0] = 65535;
    frame.inputs[0].triggered = 1;
    frame.inputs[1].values[0] = 32768;
    frame.inputs[1].values[7] = 65535;
    frame.inputs[1].triggered = 1u << 7;
    frame.connected = 3;
    f.accept(frame);
    f.queryController = 2;
    float value = 0;
    int source = -1;
    require(f.query(0, native::entry::inputValue, &value, &source) && value == 32768 / 65535.0f &&
                source == 2,
            "Ordinary gameplay no longer used this actor's accepted analog input");
    require(f.query(23) && !f.query(0) && f.queries.empty(),
            "Ordinary gameplay menu-direction edges stopped using accepted input");
    f.queryController = 3;
    value = 1;
    require(!f.query(0, native::entry::inputValue, &value) && value == 0 && f.queries.empty(),
            "Disconnected actor was allowed physical or accepted gameplay input");
    f.queryController = 2;
    f.press(13);
    require(f.query(13), "Map lost its existing local input exception");
    f.onlyLocalQueries();
    f.clearPhysical();
    input::enabled = false;
    f.press(0);
    require(f.query(0) && f.queries.back().controller == 2,
            "Non-LAN input did not pass through its original controller unchanged");
    f.queries.clear();
    input::enabled = true;
    f.queryController = 5;
    require(f.query(0) && f.queries.back().controller == 5,
            "Out-of-party native queries lost their ordinary passthrough");
}

void restartPhysicalRouting() {
    Fixture f;
    f.accept();
    f.press(input::action::restart);
    require(input::restartHeld(), "LAN restart lost physical input behind accepted gameplay input");
    require(f.queries.front().controller == 0, "Restart did not query the physical keyboard");
    f.clearPhysical();
    require(!input::restartHeld(), "Restart retained a released key");
    f.press(input::action::menuBack);
    require(!input::restartHeld(), "An ordinary menu action submitted a restart");
}

void presentationInputRouting() {
    Fixture f;
    isaac::lan::Frame frame;
    frame.connected = 3;
    frame.inputs[1].values[input::action::moveLeft] = 12000;
    f.accept(frame);
    f.queryController = 2;
    isaac::lan::InputFrame preview;
    preview.values[input::action::moveRight] = 32768;
    preview.values[input::action::shootUp] = 24000;
    preview.values[input::action::drop] = 65535;
    preview.triggered = 1u << input::action::drop;
    const auto before = preview;
    float value = -1;
    int source = -1;
    {
        input::ViewScope view(1);
        input::PresentationInputScope outer(preview, 2);
        require(f.query(input::action::moveRight, native::entry::inputValue, &value, &source) &&
                    value == 32768 / 65535.0f && source == 2,
                "Native movement query did not use the current analog preview");
        require(f.query(input::action::drop, native::entry::inputPressed) &&
                    f.query(input::action::drop) && f.query(input::action::drop),
                "Twin separation lost held input or consumed preview edges");
        require(!f.query(input::action::moveLeft, native::entry::inputValue, &value) && value == 0,
                "Native movement query retained old acknowledged input");
        require(f.queries.empty(), "Preview read physical bindings again");
        f.press(input::action::shootRight);
        require(!f.query(input::action::shootRight),
                "Aiming preview read physical input a second time");
        require(f.query(input::action::shootUp, native::entry::inputValue, &value) &&
                    value == 24000 / 65535.0f,
                "Native aiming query ignored the analog preview");
        f.press(input::action::item);
        require(f.query(input::action::item), "Presentation scope intercepted an item action");
        f.queryController = 1;
        require(!f.query(input::action::drop), "Movement preview escaped to another controller");
        f.queryController = 2;
        try {
            isaac::lan::InputFrame empty;
            input::PresentationInputScope inner(empty, 2);
            require(!f.query(input::action::drop), "Nested preview retained the outer held input");
            throw 1;
        } catch (int) {
        }
        require(f.query(input::action::drop), "Unwinding did not restore the outer preview");
    }
    require(f.query(input::action::moveLeft, native::entry::inputValue, &value) &&
                value == 12000 / 65535.0f && !f.query(input::action::drop) &&
                !f.query(input::action::shootUp),
            "Movement preview changed subsequent authoritative gameplay input");
    require(preview == before && input::presentationInput == nullptr,
            "Movement query mutated input or retained a borrowed reference");
}

void pausedInputPreservesOnlyCharge() {
    isaac::lan::InputFrame source;
    for (unsigned action = 0; action < source.values.size(); ++action)
        source.values[action] = static_cast<std::uint16_t>(1234 + action * 301);
    source.triggered = 0xffff;
    const auto before = source;
    const auto paused = input::pausedInput(source);
    require(source == before && paused.triggered == 0,
            "Paused input mutated its source or preserved item/menu trigger edges");
    for (unsigned action = 0; action < paused.values.size(); ++action)
        require(paused.values[action] == (action >= 4 && action < 8 ? source.values[action] : 0),
                "Pause failed to retain held fire exclusively across the resume boundary");
    require(input::pausedInput(paused) == paused &&
                input::pausedInput({}) == isaac::lan::InputFrame{},
            "Repeated/empty paused input introduced new actions");
}

void roomTransferHalfInput() {
    Fixture f;
    isaac::lan::Frame frame;
    frame.connected = 15;
    playerLocations = {{0, 84, 320, 280}, {0, 85, 80, 280}, {1, 84, 80, 280}, {0, 84, 80, 280}};
    for (unsigned slot = 0; slot < 4; ++slot) {
        frame.inputRooms[slot] = isaac::lan::InputRoom{0, 84};
        frame.inputs[slot].values[input::action::moveRight] = 65535;
        frame.inputs[slot].values[input::action::shootUp] = 32768;
        frame.inputs[slot].triggered = 1u << input::action::item;
    }
    f.accept(frame);
    input::finishUpdate();
    for (unsigned slot = 0; slot < 4; ++slot) {
        f.queryController = static_cast<int>(slot + 1);
        require(f.query(input::action::moveRight, native::entry::inputPressed) ==
                    (slot == 0 || slot == 3),
                "Half update moved an arrival using the old room/dimension or blocked a resident");
        require(f.query(input::action::shootUp, native::entry::inputPressed) &&
                    !f.query(input::action::item),
                "Half update released held charge or replayed an item press");
    }
    frame.inputRooms[1] = isaac::lan::InputRoom{0, 85};
    f.accept(frame);
    input::finishUpdate();
    f.queryController = 2;
    require(f.query(input::action::moveRight, native::entry::inputPressed),
            "Fresh destination input did not resume movement in the half update");
    frame.inputRooms[1].reset();
    f.accept(frame);
    input::finishUpdate();
    require(!f.query(input::action::moveRight, native::entry::inputPressed),
            "Unscoped remote input advanced the half update");
    replicaViewer = true;
    f.accept(frame);
    input::finishUpdate();
    require(f.query(input::action::moveRight, native::entry::inputPressed),
            "Authoritative room filtering changed replica input");
}
} // namespace

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"native-calls", nativeCallsAndState},
                     {"options-save-before-hide", optionsSaveBeforeHide},
                     {"native-pause-drift", nativePauseDrift},
                     {"xinput-provider-routing", xinputProviderRouting},
                     {"input-disconnect-transactions", inputDisconnectTransactions},
                     {"viewer-scopes", viewerScopes},
                     {"invalid-rosters", invalidRosters},
                     {"root-intents", rootIntents},
                     {"options-bounds", optionsBounds},
                     {"local-pause-routing", localPauseRouting},
                     {"same-frame-exit", sameFrameNavigationAndExit},
                     {"nested-input-scopes", nestedInputScopes},
                     {"ordinary-options", ordinaryOptionsRemainLocal},
                     {"gameplay-routing", gameplayRoutingUnchanged},
                     {"restart-physical-routing", restartPhysicalRouting},
                     {"movement-preview", presentationInputRouting},
                     {"paused-input", pausedInputPreservesOnlyCharge},
                     {"room-transfer-half-input", roomTransferHalfInput}});
}
