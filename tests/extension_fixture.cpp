#include "engine/module_path.h"
#include "core/extension_package.h"

#ifndef TEST_LOADER_ABI_OFFSET
#define TEST_LOADER_ABI_OFFSET 0
#endif
namespace {
int ownedAddress;
}
extern "C" __declspec(dllexport) unsigned __cdecl IsaacLanLoaderABI() {
    return isaac::updates::loaderABI + TEST_LOADER_ABI_OFFSET;
}
extern "C" __declspec(dllexport) DWORD WINAPI IsaacLanBootstrap(void*) {
    return 0;
}
extern "C" __declspec(dllexport) const wchar_t* __cdecl IsaacLanTestModulePath() {
    static const auto path = isaac::engine::modulePath(&ownedAddress);
    return path.c_str();
}
BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) {
    return TRUE;
}
