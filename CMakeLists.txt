cmake_minimum_required(VERSION 3.20)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" ISAAC_LAN_VERSION LIMIT_COUNT 1)
project(
    isaac_lan_coop
    VERSION "${ISAAC_LAN_VERSION}"
    LANGUAGES C CXX)
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "VERSION")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(CTest)
option(ISAAC_LAN_BUILD_ENGINE "Build the Windows x86 engine adapter and tools" ON)
if(BUILD_TESTING)
    find_program(
        ISAAC_LAN_LUA
        NAMES lua5.3 lua
        NO_CMAKE_FIND_ROOT_PATH)
    if(ISAAC_LAN_LUA)
        add_test(NAME bridge.entity-codec
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/entity_codec.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.layers
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/layer_contracts.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.api
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/bridge_api.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.goodtrip
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/goodtrip_rules.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.prediction
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/prediction.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.lanbot
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/lanbot.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.grids
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/grids.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.resume
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/bridge_resume.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.mod-loading
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/mod_loading.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.presentation
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/presentation.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.floor
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/floor.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.npc-state
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/npc_state.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.actor-forms
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/actor_forms.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.poop
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/poop.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(
            NAME bridge.special-coordinator
            COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/special_coordinator.lua"
                    "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.special-menu
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/special_menu.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(
            NAME bridge.shared-resources
            COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/shared_resources.lua"
                    "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.shared-curses
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/shared_curses.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.greed
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/greed.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME bridge.special-visuals
                 COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/special_visuals.lua"
                         "${CMAKE_CURRENT_SOURCE_DIR}")
        set_tests_properties(
            bridge.entity-codec
            bridge.layers
            bridge.api
            bridge.goodtrip
            bridge.prediction
            bridge.lanbot
            bridge.grids
            bridge.resume
            bridge.mod-loading
            bridge.presentation
            bridge.floor
            bridge.npc-state
            bridge.actor-forms
            bridge.poop
            bridge.special-coordinator
            bridge.special-menu
            bridge.shared-resources
            bridge.shared-curses
            bridge.greed
            bridge.special-visuals
            PROPERTIES TIMEOUT 30 LABELS "offline;lua")
    endif()
    add_executable(isaac_lan_core_test tests/core_test.cpp)
    target_include_directories(isaac_lan_core_test PRIVATE src)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(isaac_lan_core_test PRIVATE -Wall -Wextra -Werror)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_core_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    foreach(
        test_case
        integers
        strings-blobs
        input-progress
        automation-input
        keyboard-pause
        transition-charge
        audio-ownership
        localized-text
        laser-state
        actor-roster
        log-record
        poop-state
        bootstrap-profile
        intro-barrier
        room-map
        room-transition-context
        compatibility-targets
        truncated-packets
        hashes
        progression
        archive-round-trip
        archive-integrity
        archive-settings
        archive-locations)
        add_test(NAME core.${test_case} COMMAND isaac_lan_core_test ${test_case})
        set_tests_properties(core.${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;core")
    endforeach()
endif()
if(NOT ISAAC_LAN_BUILD_ENGINE)
    return()
endif()
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "The native engine adapter requires a 32-bit Windows toolchain")
endif()
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/app/main.lua" ISAAC_LAN_BRIDGE)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/app/world.lua" ISAAC_LAN_STATE)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/presentation/prediction.lua" ISAAC_LAN_PREDICTION)
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "src/bridge/presentation/prediction.lua")
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "src/bridge/app/world.lua")
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "src/bridge/app/main.lua")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/presentation/menu.lua" ISAAC_LAN_MENU)
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "src/bridge/presentation/menu.lua")
set(ISAAC_LAN_INTEGRATION_MODULES "")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/modules.txt" ISAAC_LAN_MODULE_NAMES)
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS "src/bridge/modules.txt")
foreach(module IN LISTS ISAAC_LAN_MODULE_NAMES)
    set(source_file "${CMAKE_CURRENT_SOURCE_DIR}/src/bridge/${module}.lua")
    file(READ "${source_file}" module_source)
    set_property(
        DIRECTORY
        APPEND
        PROPERTY CMAKE_CONFIGURE_DEPENDS "${source_file}")
    string(
        APPEND ISAAC_LAN_INTEGRATION_MODULES
        "{\"${module}\", \"@isaac-lan/${module}.lua\", R\"IsaacLAN(${module_source})IsaacLAN\"},\n")
endforeach()
configure_file(src/bridge/embedded.h.in generated/embedded_bridge.h @ONLY)
add_library(
    isaac_lan_probe SHARED
    src/app/bootstrap.cpp
    src/diagnostics/runtime_log.cpp
    src/runtime/session.cpp
    src/engine/versions/j460/rooms.cpp
    src/engine/versions/j460/visuals.cpp
    src/engine/versions/j460/input.cpp
    src/engine/versions/j460/save.cpp
    src/engine/versions/j460/audio.cpp
    src/engine/versions/j460/presentation.cpp
    src/engine/versions/j460/item_presentation.cpp
    src/engine/versions/j460/rewind.cpp
    src/presentation/frontend.cpp
    src/diagnostics/lab_capture.cpp)
add_library(isaac_lan_build STATIC src/engine/build.cpp)
target_include_directories(isaac_lan_build PUBLIC src)
target_compile_definitions(isaac_lan_build PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
add_executable(isaac_lan_check tools/game_check.cpp)
target_link_libraries(isaac_lan_check PRIVATE isaac_lan_build)
target_link_libraries(isaac_lan_probe PRIVATE isaac_lan_build)
target_include_directories(isaac_lan_probe PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(IMGUI_SOURCE_DIR
    ""
    CACHE PATH "Unmodified Dear ImGui v1.92.6 source checkout")
if(NOT EXISTS "${IMGUI_SOURCE_DIR}/imgui.h")
    message(FATAL_ERROR "Set IMGUI_SOURCE_DIR to a Dear ImGui v1.92.6 checkout")
endif()
add_library(
    isaac_lan_ui STATIC
    "${IMGUI_SOURCE_DIR}/imgui.cpp"
    "${IMGUI_SOURCE_DIR}/imgui_draw.cpp"
    "${IMGUI_SOURCE_DIR}/imgui_tables.cpp"
    "${IMGUI_SOURCE_DIR}/imgui_widgets.cpp"
    "${IMGUI_SOURCE_DIR}/backends/imgui_impl_win32.cpp"
    "${IMGUI_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp")
target_include_directories(isaac_lan_ui PUBLIC "${IMGUI_SOURCE_DIR}" "${IMGUI_SOURCE_DIR}/backends")
target_link_libraries(isaac_lan_ui PUBLIC opengl32 gdi32 dwmapi)
add_library(isaac_lan_net STATIC src/net/session.cpp src/net/compression.cpp)
target_include_directories(isaac_lan_net PUBLIC src)
target_compile_definitions(isaac_lan_net PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(isaac_lan_net PUBLIC ws2_32 bcrypt)
if(BUILD_TESTING)
    add_executable(isaac_lan_net_test tests/net_test.cpp)
    target_link_libraries(isaac_lan_net_test PRIVATE isaac_lan_net winmm)
    foreach(
        test_case
        codec
        compression-limits
        inputs-2
        inputs-3
        inputs-4
        floor-rejoin
        stage-events
        ending-events
        cinematic-events
        stage-during-rejoin
        rewind
        progression
        r-key
        room-commands
        input-rooms
        lobby
        handshake
        commands
        publication-limits
        integrations
        greed-settings
        host-disconnect)
        add_test(NAME net.${test_case} COMMAND isaac_lan_net_test ${test_case})
        set_tests_properties(net.${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;network")
    endforeach()
endif()
set(MINHOOK_SOURCE_DIR
    ""
    CACHE PATH "Unmodified MinHook v1.3.4 source checkout")
if(NOT EXISTS "${MINHOOK_SOURCE_DIR}/include/MinHook.h")
    message(FATAL_ERROR "Set MINHOOK_SOURCE_DIR to a MinHook v1.3.4 checkout")
endif()
add_subdirectory("${MINHOOK_SOURCE_DIR}" minhook)
set_target_properties(isaac_lan_probe PROPERTIES PREFIX "")
target_compile_definitions(isaac_lan_probe PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(isaac_lan_probe PRIVATE bcrypt iphlpapi gdiplus minhook isaac_lan_net
                                              isaac_lan_ui)
add_executable(isaac_lan_lab tools/lab_runner.cpp)
if(BUILD_TESTING)
    add_executable(isaac_lan_log_test tests/runtime_log_test.cpp src/diagnostics/runtime_log.cpp)
    target_include_directories(isaac_lan_log_test PRIVATE src)
    target_compile_definitions(isaac_lan_log_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MINGW)
        target_compile_options(isaac_lan_log_test PRIVATE -Wall -Wextra -Werror)
        target_link_options(isaac_lan_log_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME log.path-and-records COMMAND isaac_lan_log_test path-and-records)
    set_tests_properties(log.path-and-records PROPERTIES TIMEOUT 30 LABELS "offline;logging")
endif()
add_library(isaac_lan_loader SHARED src/app/loader.cpp src/app/loader.def)
set_target_properties(isaac_lan_loader PROPERTIES PREFIX "" OUTPUT_NAME "winmm")
target_include_directories(isaac_lan_loader PRIVATE src)
target_compile_definitions(isaac_lan_loader PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_definitions(isaac_lan_lab PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MINGW)
    target_link_options(isaac_lan_check PRIVATE -static-libgcc -static-libstdc++ -municode)
    target_compile_options(isaac_lan_build PRIVATE -Wall -Wextra -Werror)
    target_compile_options(isaac_lan_check PRIVATE -Wall -Wextra -Werror)
    target_link_options(isaac_lan_loader PRIVATE -static-libgcc -static-libstdc++ -Wl,--kill-at)
    target_compile_options(isaac_lan_loader PRIVATE -Wall -Wextra -Werror)
    target_link_options(isaac_lan_probe PRIVATE -static-libgcc -static-libstdc++ -Wl,--kill-at)
    target_link_options(isaac_lan_lab PRIVATE -static-libgcc -static-libstdc++ -municode)
    target_compile_options(isaac_lan_probe PRIVATE -Wall -Wextra -Werror)
    target_compile_options(isaac_lan_lab PRIVATE -Wall -Wextra -Werror)
    if(BUILD_TESTING)
        target_link_options(isaac_lan_net_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_net_test PRIVATE -Wall -Wextra -Werror)
    endif()
    target_compile_options(isaac_lan_net PRIVATE -Wall -Wextra -Werror)
endif()
