#pragma once
#include "net/protocol.h"
#include <functional>
#include <string_view>

namespace isaac::engine::session {
// Original calls are synchronous and may not be retained by a callback.
using Call = std::function<void()>;
struct Callbacks {
    void (*save)(const Call&);
    void (*deleteSave)(const Call&);
    void (*saveRerun)(const Call&);
    void (*serializeProgress)(const Call&);
    void (*executeStart)(const Call&);
    void (*start)(const Call&);
    void (*update)(const Call&);
    void (*consoleUpdate)(const Call&);
    void (*consoleCommand)(std::string_view, const Call&);
    void (*controls)(const Call&);
    void (*executeMenu)(const Call&);
    bool (*restartRequest)(bool held);
};
bool install(std::uintptr_t image, const Callbacks& callbacks);
bool managerReady();
bool gameReady();
bool continueAvailable();
void continueAvailable(bool value);
unsigned saveSlot();
void captureSave();
void suppressDelete();
void clearSave();
lan::Progress readProgress();
void writeProgress(const lan::Progress& value);
void persistProgress();
int pause();
int scene();
bool cinematicFinished();
bool exitRequested();
void cancelExit();
void resetPause();
void pollConsole();
void hideConsole();
std::string executeConsole(std::string_view command);
void controls();
std::uint32_t parseSeed(std::string_view text);
void start(std::uint32_t seed, int character, unsigned difficulty);
void requestContinue();
lan::Stage stage();
void applyStage(const lan::Stage& value);
} // namespace isaac::engine::session
