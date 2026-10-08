#include "game_build.h"
#include <cstdio>
#include <cwchar>

int wmain(int argc, wchar_t** argv) {
    const bool code = argc == 3 && std::wcscmp(argv[1], L"--code") == 0;
    if (argc != 2 && !code) {
        std::fputs("Usage: isaac_lan_check.exe [--code] <isaac-ng.exe>\n", stderr);
        return 2;
    }
    const auto error = isaac::build::checkFile(argv[code ? 2 : 1], code);
    if (!error.empty()) {
        std::printf("%s\n", error.c_str());
        return 1;
    }
    std::printf("Supported game build: %s%s\n", isaac::build::version,
                code ? "; engine entry points verified" : "");
    return 0;
}
