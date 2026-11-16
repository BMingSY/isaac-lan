#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <system_error>

namespace isaac::startup {
// These values cross the loader DLL boundary and are also process exit codes.
// Keep published values stable; allocate a new value when splitting a cause.
enum class Code : std::uint32_t {
    success = 0,
    labEnvironment = 10,
    executablePath = 11,
    installationMarker = 12,
    gameCompatibility = 13,
    legacyDirectories = 14,
    importBinding = 15,
    roomUpdate = 16,
    halfUpdate = 17,
    session = 18,
    windowFocus = 19,
    rendering = 20,
    rooms = 21,
    frontend = 22,
    combatFeedback = 23,
    presentation = 24,
    rewind = 25,
    items = 27,
    documentsDirectory = 28,
    logInitialization = 29,
    dataDirectory = 30,
    labProfile = 31,
    hookLibrary = 32,
    audio = 33,
    playerOutlines = 34,
    playerOpacity = 35,
    generatedItems = 36,
    unexpectedException = 37,
    entryRestore = 90,
    extensionLoad = 100,
    bootstrapExport = 101,
    systemExport = 127,
};
constexpr std::uint32_t value(Code code) {
    return static_cast<std::uint32_t>(code);
}
struct Description {
    std::wstring_view name;
    std::wstring_view reason;
    std::wstring_view action;
};
constexpr Description describe(Code code) {
    constexpr auto report = L"请保留完整错误信息和联机扩展版本，向作者反馈。";
    constexpr auto directory = L"请检查所示目录的写入权限、磁盘空间及安全软件的拦截记录。";
    constexpr auto hooks = L"请确认游戏版本受支持；若安装了其他原生扩展，请检查是否冲突。";
    switch (code) {
    case Code::success:
        return {};
    case Code::labEnvironment:
        return {L"LAB_ENVIRONMENT", L"隔离测试目录的环境变量过长。", L"请使用较短的隔离测试目录。"};
    case Code::executablePath:
        return {L"EXECUTABLE_PATH", L"无法取得有效的游戏路径，或路径与隔离测试配置不符。",
                L"请从已安装扩展的游戏目录启动；隔离测试请检查启动配置。"};
    case Code::installationMarker:
        return {L"INSTALLATION_MARKER", L"缺少有效的安装标记或隔离测试标记。",
                L"请重新运行安装器并选择实际启动的 isaac-ng.exe；隔离测试请重新准备目录。"};
    case Code::gameCompatibility:
        return {L"GAME_COMPATIBILITY", L"游戏版本或原生接口与联机扩展不兼容。",
                L"请使用安装包支持的游戏版本，并检查其他原生扩展是否修改了游戏接口。"};
    case Code::legacyDirectories:
        return {L"DIRECTORIES", L"文档、日志、扩展数据目录或隔离测试路径初始化失败。", directory};
    case Code::importBinding:
        return {L"IMPORT_BINDING", L"无法连接游戏所需的系统或日志接口。", hooks};
    case Code::roomUpdate:
        return {L"ROOM_UPDATE", L"无法初始化原生挂接组件或房间更新接口。", hooks};
    case Code::halfUpdate:
        return {L"HALF_UPDATE", L"无法初始化游戏更新接口。", hooks};
    case Code::session:
        return {L"SESSION", L"无法初始化联机会话接口。", hooks};
    case Code::windowFocus:
        return {L"WINDOW_FOCUS", L"无法初始化游戏窗口焦点接口。", hooks};
    case Code::rendering:
        return {L"RENDERING", L"无法初始化游戏渲染接口。", hooks};
    case Code::rooms:
        return {L"ROOMS", L"无法初始化房间同步接口。", hooks};
    case Code::frontend:
        return {L"FRONTEND", L"无法初始化联机菜单和脚本接口。", hooks};
    case Code::combatFeedback:
        return {L"COMBAT_FEEDBACK", L"无法初始化战斗反馈或音效接口。", hooks};
    case Code::presentation:
        return {L"PRESENTATION", L"无法初始化本机显示或玩家外观接口。", hooks};
    case Code::rewind:
        return {L"REWIND", L"无法初始化回溯接口。", hooks};
    case Code::items:
        return {L"ITEMS", L"无法初始化道具接口。", hooks};
    case Code::documentsDirectory:
        return {L"DOCUMENTS_DIRECTORY", L"无法定位 Windows 文档目录。",
                L"请检查系统文档目录及其重定向位置是否可用。"};
    case Code::logInitialization:
        return {L"LOG_INITIALIZATION", L"无法创建日志目录或打开启动日志。", directory};
    case Code::dataDirectory:
        return {L"DATA_DIRECTORY", L"无法创建游戏目录下的联机数据目录。", directory};
    case Code::labProfile:
        return {L"LAB_PROFILE", L"隔离测试资料路径过长或包含换行符。",
                L"请使用较短且不含换行符的隔离测试目录。"};
    case Code::hookLibrary:
        return {L"HOOK_LIBRARY", L"无法初始化原生接口挂接组件。", hooks};
    case Code::audio:
        return {L"AUDIO", L"无法初始化音效同步接口。", hooks};
    case Code::playerOutlines:
        return {L"PLAYER_OUTLINES", L"无法初始化玩家描边接口。", hooks};
    case Code::playerOpacity:
        return {L"PLAYER_OPACITY", L"无法初始化玩家透明度接口。", hooks};
    case Code::generatedItems:
        return {L"GENERATED_ITEMS", L"无法初始化生成道具接口。", hooks};
    case Code::unexpectedException:
        return {L"STARTUP_EXCEPTION", L"联机扩展初始化时发生异常。", report};
    case Code::entryRestore:
        return {L"ENTRY_RESTORE", L"无法恢复游戏启动入口。", report};
    case Code::systemExport:
        return {L"SYSTEM_EXPORT", L"系统 winmm.dll 缺少游戏所需的接口。",
                L"请检查 Windows 或 Proton 版本及系统组件。"};
    case Code::extensionLoad:
        return {L"EXTENSION_LOAD", L"无法加载联机扩展 DLL。",
                L"请检查安装文件是否完整及安全软件的拦截记录，必要时重新运行安装器。"};
    case Code::bootstrapExport:
        return {L"BOOTSTRAP_EXPORT", L"联机扩展 DLL 缺少启动接口。",
                L"请使用同一安装包重新安装加载器和联机扩展。"};
    }
    return {L"UNKNOWN", L"联机扩展返回了无法识别的初始化错误。", report};
}
struct Failure {
    Code code = Code::success;
    std::wstring path;
    std::error_code systemError;
    std::wstring detail;
};
inline std::wstring message(const Failure& failure) {
    if (failure.code == Code::success)
        return {};
    const auto description = describe(failure.code);
    auto text = L"Isaac LAN 无法初始化（code " + std::to_wstring(value(failure.code)) + L" / " +
                std::wstring(description.name) + L"）。游戏将关闭。\n\n" +
                std::wstring(description.reason);
    if (!failure.path.empty())
        text += L"\n路径：" + failure.path;
    if (failure.systemError) {
        const std::string_view category = failure.systemError.category().name();
        text += L"\n系统错误：" + std::wstring(category.begin(), category.end()) + L":" +
                std::to_wstring(failure.systemError.value());
    }
    if (!failure.detail.empty())
        text += L"\n详情：" + failure.detail;
    text += L"\n\n";
    text += description.action;
    return text;
}
} // namespace isaac::startup
