#include "engine/module_path.h"
#include "core/extension_package.h"
#include "core/startup_error.h"

#ifndef TEST_LOADER_ABI_OFFSET
#define TEST_LOADER_ABI_OFFSET 0
#endif
namespace {
int ownedAddress;
}
extern "C" __declspec(dllexport) unsigned __cdecl IsaacLanLoaderABI() {
    return isaac::updates::loaderABI + TEST_LOADER_ABI_OFFSET;
}
#ifndef TEST_NO_BOOTSTRAP
extern "C" __declspec(dllexport) DWORD WINAPI IsaacLanBootstrap(void*) {
#ifdef TEST_STARTUP_FAILURE
    return isaac::startup::value(isaac::startup::Code::logInitialization);
#else
    return 0;
#endif
}
#endif
#ifdef TEST_STARTUP_FAILURE
extern "C" __declspec(dllexport) const wchar_t* __cdecl IsaacLanBootstrapError() {
    static const auto message =
        isaac::startup::message({isaac::startup::Code::logInitialization,
                                 L"C:\\文档\\startup.log",
                                 {ERROR_ACCESS_DENIED, std::system_category()},
                                 {}});
    return message.c_str();
}
#endif
extern "C" __declspec(dllexport) const wchar_t* __cdecl IsaacLanTestModulePath() {
    static const auto path = isaac::engine::modulePath(&ownedAddress);
    return path.c_str();
}
BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) {
    return TRUE;
}
