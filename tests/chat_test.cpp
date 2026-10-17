#include "core/chat.h"
#include "core/menu_input.h"
#include "test_support.h"
#include <cstdio>
using namespace isaac::chat;
int main() {
    Editor editor;
    require(editor.insert("你好 abc"), "Unicode text rejected");
    editor.move(-1);
    editor.erase(-1);
    require(editor.text == "你好 ac", "Backspace removed the wrong character");
    editor.move(-1, false, true);
    editor.erase(1);
    require(editor.text == "好 ac", "Delete split UTF-8");
    editor.move(1, true);
    require(editor.selection() == "好", "Selection was byte based");
    editor.insert("再见");
    require(editor.text == "再见 ac", "Selection replacement failed");
    editor.assign(std::string(60, 'a'));
    require(!editor.insert("中") && editor.text.size() == 60, "Chat limit silently truncated");
    editor.anchor = 0;
    require(editor.insert("/console lua " + std::string(1000, 'x')),
            "Commands used chat character limit");
    require(!editor.insert(std::string(maxCommandBytes, 'x')), "Unbounded command accepted");
    editor.assign("");
    require(editor.insert("one\ntwo\tthree"), "Multiline paste rejected");
    require(editor.text == "one two three", "Paste submitted or retained embedded newlines");
    editor.accept();
    editor.insert("draft");
    editor.recall(-1);
    require(editor.text == "one two three", "Input history missing");
    editor.recall(1);
    require(editor.text == "draft", "History navigation lost draft");
    require(!validInput(std::string("\xc0\xaf", 2)) &&
                !validInput(std::string("\xed\xa0\x80", 3)) &&
                !validInput(std::string("abc\0def", 7)) &&
                !validInput(std::string("\xf4\x90\x80\x80", 4)),
            "Malformed UTF-8 or embedded NUL accepted");
    std::string chinese;
    for (unsigned i = 0; i < maxCharacters; ++i)
        chinese += "中";
    require(validInput(chinese) && !validInput(chinese + "文"), "Chinese limit counted bytes");
    require(boundedOutput("中英文", 4) == "中" && boundedOutput("中", 2).empty() &&
                boundedOutput("abc", 2) == "ab",
            "Native output cap split UTF-8");
    editor.reset();
    editor.recall(-1);
    require(editor.text.empty(), "Session reset retained input history");
    isaac::input::ModalInput modal;
    isaac::lan::InputFrame held;
    held.values[isaac::input::action::moveLeft] = isaac::lan::maxInputValue;
    auto frame = held;
    modal.filter(frame, true);
    require(frame == isaac::lan::InputFrame{}, "Typing leaked movement");
    frame = held;
    modal.filter(frame, false);
    require(frame == isaac::lan::InputFrame{}, "Held key leaked when closing chat");
    modal.filter(frame, false);
    frame = held;
    modal.filter(frame, false);
    require(frame == held, "New press after release remained blocked");
    std::puts("PASS chat UTF-8 editing, bounds, selection, paste, history and cleanup");
}
