#include "engine/chat_input.h"
#include "engine/emotes.h"
#include "engine/input.h"
#include "engine/lua_api.h"
#include "core/chat.h"
#include "core/input_actions.h"
#include <imm.h>
#include <bcrypt.h>
#include <array>
#include <string>

namespace isaac::chat_input {
namespace {
lua::API lua;
chat::Editor editor;
bool available = false, opened = false, composing = false, wheel = false;
bool submit = false, complete = false;
bool swallowCharacter = false;
unsigned short surrogate = 0;
int scroll = 0;
HWND window = nullptr;
std::string composition;
std::array<bool, 256> consumedKeys{};
std::string utf8(std::wstring_view input) {
    const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(), input.size(),
                                          nullptr, 0, nullptr, nullptr);
    std::string result(count > 0 ? count : 0, '\0');
    if (count > 0)
        WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(), input.size(),
                            result.data(), count, nullptr, nullptr);
    return result;
}
std::wstring wide(std::string_view input) {
    const int count =
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), input.size(), nullptr, 0);
    std::wstring result(count > 0 ? count : 0, L'\0');
    if (count > 0)
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), input.size(),
                            result.data(), count);
    return result;
}
bool copyText(std::string_view text) {
    auto value = wide(text);
    if (value.empty() || !OpenClipboard(window))
        return false;
    bool copied = false;
    const auto bytes = (value.size() + 1) * sizeof(wchar_t);
    auto memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory) {
        auto* target = GlobalLock(memory);
        if (target) {
            std::memcpy(target, value.c_str(), bytes);
            GlobalUnlock(memory);
            if (EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, memory)) {
                memory = nullptr;
                copied = true;
            }
        }
        if (memory)
            GlobalFree(memory);
    }
    CloseClipboard();
    return copied;
}
void clipboard(bool cut) {
    if (copyText(editor.selection()) && cut)
        editor.insert("");
}
int copy(lua_State* L) {
    std::size_t length = 0;
    const auto* value = lua.checkString(L, 1, &length);
    const std::string_view text(value, length);
    lua.pushBoolean(L, available && opened && window && GetForegroundWindow() == window &&
                           length <= chat::maxCommandBytes && chat::boundaries(text) &&
                           copyText(text));
    return 1;
}
void paste() {
    if (!OpenClipboard(window))
        return;
    auto memory = GetClipboardData(CF_UNICODETEXT);
    constexpr std::size_t maxClipboardBytes =
        chat::maxCommandBytes * sizeof(wchar_t) + sizeof(wchar_t);
    if (memory && GlobalSize(memory) <= maxClipboardBytes) {
        const auto* source = static_cast<const wchar_t*>(GlobalLock(memory));
        if (source) {
            const auto capacity = GlobalSize(memory) / sizeof(wchar_t);
            std::size_t length = 0;
            while (length < capacity && source[length])
                ++length;
            if (length < capacity)
                editor.insert(utf8({source, length}));
            GlobalUnlock(memory);
        }
    } else if (memory)
        editor.limit = true;
    CloseClipboard();
}
void cancelComposition() {
    if (window && composing) {
        if (auto context = ImmGetContext(window)) {
            ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
            ImmReleaseContext(window, context);
        }
    }
    composition.clear();
    composing = false;
    surrogate = 0;
}
int configure(lua_State* L) {
    const bool next = lua.toBoolean(L, 1);
    if (!next) {
        opened = wheel = false;
        submit = complete = false;
        cancelComposition();
    }
    available = next;
    return 0;
}
int state(lua_State* L) {
    lua.createTable(L, 0, 10);
    auto boolean = [&](const char* key, bool value) {
        lua.pushBoolean(L, value);
        lua.setField(L, -2, key);
    };
    auto integer = [&](const char* key, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, key);
    };
    boolean("open", opened);
    boolean("composing", composing);
    boolean("submit", submit);
    boolean("complete", complete);
    boolean("limit", editor.limit);
    integer("cursor", editor.cursor);
    integer("anchor", editor.anchor);
    integer("scroll", scroll);
    lua.pushLString(L, editor.text.data(), editor.text.size());
    lua.setField(L, -2, "text");
    lua.pushLString(L, composition.data(), composition.size());
    lua.setField(L, -2, "composition");
    submit = complete = false;
    scroll = 0;
    return 1;
}
int accept(lua_State*) {
    editor.accept();
    return 0;
}
int assign(lua_State* L) {
    std::size_t length = 0;
    const auto* value = lua.checkString(L, 1, &length);
    if (chat::validInput({value, length}))
        editor.assign({value, length});
    return 0;
}
int open(lua_State* L) {
    if (available) {
        opened = lua.toBoolean(L, 1);
        wheel = false;
        if (!opened)
            cancelComposition();
    }
    return 0;
}
int modal(lua_State* L) {
    wheel = available && lua.toBoolean(L, 1);
    return 0;
}
int pointer(lua_State* L) {
    const auto width = lua.checkNumber(L, 1), height = lua.checkNumber(L, 2);
    POINT point{};
    RECT client{};
    const bool active = window && opened && GetForegroundWindow() == window &&
                        GetCursorPos(&point) && ScreenToClient(window, &point) &&
                        GetClientRect(window, &client) && client.right > 0 && client.bottom > 0;
    lua.createTable(L, 0, 3);
    lua.pushNumber(L, active ? point.x * width / client.right : -1000);
    lua.setField(L, -2, "x");
    lua.pushNumber(L, active ? point.y * height / client.bottom : -1000);
    lua.setField(L, -2, "y");
    lua.pushBoolean(L, active && (GetAsyncKeyState(VK_LBUTTON) & 0x8000));
    lua.setField(L, -2, "down");
    return 1;
}
int caret(lua_State* L) {
    if (!window || !opened)
        return 0;
    const auto x = lua.checkNumber(L, 1), y = lua.checkNumber(L, 2), width = lua.checkNumber(L, 3),
               height = lua.checkNumber(L, 4);
    if (width <= 0 || height <= 0)
        return 0;
    RECT rect{};
    GetClientRect(window, &rect);
    if (auto context = ImmGetContext(window)) {
        POINT position{static_cast<LONG>(x * rect.right / width),
                       static_cast<LONG>(y * rect.bottom / height)};
        COMPOSITIONFORM form{CFS_POINT, position, {}};
        ImmSetCompositionWindow(context, &form);
        CANDIDATEFORM candidate{0, CFS_CANDIDATEPOS, position, {}};
        ImmSetCandidateWindow(context, &candidate);
        ImmReleaseContext(window, context);
    }
    return 0;
}
int clear(lua_State*) {
    reset();
    return 0;
}
int roll(lua_State* L) {
    const auto sides = lua.checkInteger(L, 1);
    if (sides < 1 || sides > chat::maxDice)
        return 0;
    const auto bound = static_cast<std::uint32_t>(sides);
    const auto threshold = static_cast<std::uint32_t>(-bound) % bound;
    std::uint32_t value = 0;
    do {
        if (BCryptGenRandom(nullptr, reinterpret_cast<PUCHAR>(&value), sizeof(value),
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
            return 0;
    } while (value < threshold);
    lua.pushInteger(L, 1 + value % bound);
    return 1;
}
int limits(lua_State* L) {
    lua.createTable(L, 0, 4);
    for (const auto& [key, value] : {std::pair{"characters", chat::maxCharacters},
                                     {"commandBytes", chat::maxCommandBytes},
                                     {"history", chat::maxHistory},
                                     {"dice", static_cast<std::size_t>(chat::maxDice)}}) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, key);
    }
    return 1;
}
} // namespace
std::optional<LRESULT> event(HWND hwnd, UINT message, WPARAM key, LPARAM data) {
    window = hwnd;
    if (message == WM_KILLFOCUS) {
        emotes::reset();
        cancelComposition();
        opened = wheel = false;
        submit = complete = false;
        consumedKeys = {};
        return {};
    }
    if (key < consumedKeys.size()) {
        if (message == WM_KEYUP && consumedKeys[key]) {
            consumedKeys[key] = false;
            return 0;
        }
        if (message == WM_KEYDOWN && consumedKeys[key] && !opened)
            return 0;
    }
    const auto toggleKey =
        message == WM_KEYDOWN && key == VK_PROCESSKEY ? ImmGetVirtualKey(hwnd) : key;
    if (available && message == WM_KEYDOWN && toggleKey == VK_OEM_3) {
        if (!(data & (1ll << 30))) {
            opened = !opened;
            if (!opened)
                cancelComposition();
            wheel = false;
            submit = complete = false;
        }
        swallowCharacter = true;
        return 0;
    }
    if (available && message == WM_KEYUP && key == VK_OEM_3)
        return 0;
    if (swallowCharacter && message == WM_CHAR) {
        swallowCharacter = false;
        if (key == '`' || key == '~')
            return 0;
    }
    if (!opened || !available)
        return {};
    if (message == WM_SETCURSOR && LOWORD(data) == HTCLIENT) {
        SetCursor(LoadCursor(nullptr, IDC_ARROW));
        return TRUE;
    }
    if (message == WM_LBUTTONDOWN || message == WM_LBUTTONUP)
        return 0;
    if (message == WM_IME_SETCONTEXT)
        return DefWindowProcW(hwnd, message, key, data & ~ISC_SHOWUICOMPOSITIONWINDOW);
    if (message == WM_IME_STARTCOMPOSITION) {
        composing = true;
        return 0;
    }
    if (message == WM_IME_ENDCOMPOSITION) {
        composing = false;
        composition.clear();
        return 0;
    }
    if (message == WM_IME_COMPOSITION) {
        if (auto context = ImmGetContext(hwnd)) {
            auto read = [&](DWORD flag) {
                const auto bytes = ImmGetCompositionStringW(context, flag, nullptr, 0);
                if (bytes <= 0 ||
                    bytes > static_cast<LONG>(chat::maxCommandBytes * sizeof(wchar_t)))
                    return std::string{};
                std::wstring text(bytes / sizeof(wchar_t), L'\0');
                ImmGetCompositionStringW(context, flag, text.data(), bytes);
                return utf8(text);
            };
            if (data & GCS_RESULTSTR) {
                editor.insert(read(GCS_RESULTSTR));
                composition.clear();
            }
            if (data & GCS_COMPSTR)
                composition = read(GCS_COMPSTR);
            ImmReleaseContext(hwnd, context);
        }
        return 0;
    }
    if (composing)
        return {};
    if (message == WM_CHAR) {
        if (key < 0x20)
            return 0;
        if (key >= 0xd800 && key <= 0xdbff)
            surrogate = static_cast<unsigned short>(key);
        else {
            std::wstring value;
            if (surrogate)
                value.push_back(static_cast<wchar_t>(surrogate));
            surrogate = 0;
            value.push_back(static_cast<wchar_t>(key));
            auto text = utf8(value);
            if (!text.empty())
                editor.insert(text);
        }
        return 0;
    }
    if (message == WM_MOUSEWHEEL) {
        scroll += static_cast<short>(HIWORD(key)) / WHEEL_DELTA;
        return 0;
    }
    if (message == WM_KEYDOWN) {
        if (key < consumedKeys.size())
            consumedKeys[key] = true;
        const bool control = GetKeyState(VK_CONTROL) < 0, shift = GetKeyState(VK_SHIFT) < 0;
        if (control && key == 'A') {
            editor.anchor = 0;
            editor.cursor = editor.text.size();
        } else if (control && (key == 'C' || key == 'X'))
            clipboard(key == 'X');
        else if (control && key == 'V')
            paste();
        else if (key == VK_LEFT || key == VK_RIGHT)
            editor.move(key == VK_LEFT ? -1 : 1, shift);
        else if (key == VK_HOME || key == VK_END)
            editor.move(key == VK_HOME ? -1 : 1, shift, true);
        else if (key == VK_BACK || key == VK_DELETE)
            editor.erase(key == VK_BACK ? -1 : 1);
        else if (key == VK_UP || key == VK_DOWN)
            editor.recall(key == VK_UP ? -1 : 1);
        else if (key == VK_PRIOR || key == VK_NEXT)
            scroll += key == VK_PRIOR ? 5 : -5;
        else if (key == VK_ESCAPE) {
            opened = false;
            submit = complete = false;
        } else if (!(data & (1ll << 30))) {
            if (key == VK_RETURN)
                submit = true;
            if (key == VK_TAB)
                complete = true;
        }
        return 0;
    }
    if (message == WM_KEYUP)
        return 0;
    return {};
}
bool capturesInput() {
    return available && (opened || wheel);
}
void reset() {
    cancelComposition();
    editor.reset();
    opened = wheel = available = submit = complete = false;
    scroll = 0;
    consumedKeys = {};
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module,
                  {lua::Symbol::pushClosure, lua::Symbol::setField, lua::Symbol::createTable,
                   lua::Symbol::pushBoolean, lua::Symbol::pushInteger, lua::Symbol::pushNumber,
                   lua::Symbol::pushLString, lua::Symbol::toBoolean, lua::Symbol::checkString,
                   lua::Symbol::checkNumber, lua::Symbol::checkInteger}))
        return false;
    for (const auto& [name, function] :
         {std::pair<const char*, lua::Function>{"chat_ui_available", configure},
          {"chat_ui_state", state},
          {"chat_ui_accept", accept},
          {"chat_ui_text", assign},
          {"chat_ui_open", open},
          {"chat_ui_modal", modal},
          {"chat_ui_caret", caret},
          {"chat_ui_pointer", pointer},
          {"chat_ui_copy", copy},
          {"chat_ui_reset", clear},
          {"chat_limits", limits},
          {"chat_roll", roll}}) {
        lua.pushClosure(L, function, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::chat_input
