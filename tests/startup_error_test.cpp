#include "core/startup_error.h"
#include "test_support.h"
#include <set>

namespace {
using namespace isaac::startup;
void contract() {
    const std::pair<Code, std::uint32_t> published[] = {
        {Code::success, 0},
        {Code::labEnvironment, 10},
        {Code::executablePath, 11},
        {Code::installationMarker, 12},
        {Code::gameCompatibility, 13},
        {Code::legacyDirectories, 14},
        {Code::importBinding, 15},
        {Code::roomUpdate, 16},
        {Code::halfUpdate, 17},
        {Code::session, 18},
        {Code::windowFocus, 19},
        {Code::rendering, 20},
        {Code::rooms, 21},
        {Code::frontend, 22},
        {Code::combatFeedback, 23},
        {Code::presentation, 24},
        {Code::rewind, 25},
        {Code::items, 27},
        {Code::documentsDirectory, 28},
        {Code::logInitialization, 29},
        {Code::dataDirectory, 30},
        {Code::labProfile, 31},
        {Code::hookLibrary, 32},
        {Code::audio, 33},
        {Code::playerOutlines, 34},
        {Code::playerOpacity, 35},
        {Code::generatedItems, 36},
        {Code::unexpectedException, 37},
        {Code::entryRestore, 90},
        {Code::extensionLoad, 100},
        {Code::bootstrapExport, 101},
        {Code::systemExport, 127},
    };
    for (const auto& [code, number] : published)
        require(value(code) == number, "Published loader/exit code changed meaning");
    std::set<std::uint32_t> numbers;
    std::set<std::wstring_view> names;
    const auto check = [&](Code code) {
        require(numbers.insert(value(code)).second, "Startup codes overlap");
        if (code == Code::success)
            return;
        const auto info = describe(code);
        require(!info.name.empty() && info.name != L"UNKNOWN" && !info.reason.empty() &&
                    !info.action.empty(),
                "A startup failure has no actionable description");
        require(names.insert(info.name).second, "Startup names overlap");
    };
    for (const auto& [code, number] : published)
        check(code);
}
void messages() {
    require(message({}).empty(), "Success produced a failure dialog");
    const auto legacy = message({Code::legacyDirectories, {}, {}, {}});
    require(legacy.find(L"code 14") != legacy.npos && legacy.find(L"目录") != legacy.npos &&
                legacy.find(L"游戏版本") == legacy.npos,
            "Legacy directory failure still recommends changing game versions");
    const auto compatibility = message({Code::gameCompatibility, {}, {}, L"unsupported build"});
    require(compatibility.find(L"code 13") != compatibility.npos &&
                compatibility.find(L"unsupported build") != compatibility.npos,
            "Game compatibility evidence was lost");
    const auto path = L"C:\\用户\\文档\\" + std::wstring(300, L'长') + L"\\startup.log";
    const Failure failure{
        Code::logInitialization, path, {13, std::generic_category()}, L"locked fixture"};
    const auto text = message(failure);
    require(text.find(path) != text.npos && text.find(L"generic:13") != text.npos &&
                text.find(L"locked fixture") != text.npos && text.find(L"code 29") != text.npos,
            "Dialog truncated Unicode paths or confused system and startup codes");
    const auto unknown = message({static_cast<Code>(4001), {}, {}, {}});
    require(unknown.find(L"4001") != unknown.npos && unknown.find(L"UNKNOWN") != unknown.npos &&
                unknown.find(L"游戏版本") == unknown.npos,
            "Unknown future codes were misdiagnosed or lost");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"contract", contract}, {"messages", messages}});
}
