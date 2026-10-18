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
include(cmake/Tests.cmake)
option(ISAAC_LAN_BUILD_ENGINE "Build the Windows x86 engine adapter and tools" ON)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/generated/miniz_export.h"
     "#pragma once\n#define MINIZ_EXPORT\n")
add_library(isaac_lan_miniz STATIC vendor/miniz/miniz.c vendor/miniz/miniz_tdef.c
                                   vendor/miniz/miniz_tinfl.c)
target_include_directories(isaac_lan_miniz PUBLIC vendor/miniz
                                                  "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_compile_definitions(isaac_lan_miniz PUBLIC MINIZ_NO_ARCHIVE_APIS MINIZ_NO_STDIO
                                                  MINIZ_NO_TIME MINIZ_NO_ZLIB_COMPATIBLE_NAMES)
add_library(isaac_lan_deflate STATIC src/core/deflate.cpp)
target_include_directories(isaac_lan_deflate PUBLIC src)
target_link_libraries(isaac_lan_deflate PUBLIC isaac_lan_miniz)
file(GLOB ISAAC_LAN_ZSTD_SOURCES CONFIGURE_DEPENDS vendor/zstd/common/*.c vendor/zstd/compress/*.c
     vendor/zstd/decompress/*.c)
add_library(isaac_lan_zstd_vendor STATIC ${ISAAC_LAN_ZSTD_SOURCES})
target_include_directories(isaac_lan_zstd_vendor PUBLIC vendor/zstd)
target_compile_definitions(isaac_lan_zstd_vendor PRIVATE ZSTD_LEGACY_SUPPORT=0 ZSTD_DISABLE_ASM)
add_library(isaac_lan_zstd STATIC src/core/zstd.cpp)
target_include_directories(isaac_lan_zstd PUBLIC src)
target_link_libraries(isaac_lan_zstd PUBLIC isaac_lan_zstd_vendor)
set(ISAAC_LAN_LZ4_SOURCE_DIR
    ""
    CACHE PATH "Optional upstream LZ4 lib directory for benchmarks")
if(BUILD_TESTING AND ISAAC_LAN_LZ4_SOURCE_DIR)
    add_executable(isaac_lan_compression_benchmark tests/compression_benchmark.cpp
                                                   "${ISAAC_LAN_LZ4_SOURCE_DIR}/lz4.c")
    target_include_directories(isaac_lan_compression_benchmark
                               PRIVATE "${ISAAC_LAN_LZ4_SOURCE_DIR}")
    target_link_libraries(isaac_lan_compression_benchmark PRIVATE isaac_lan_deflate isaac_lan_zstd)
    if(MINGW)
        target_link_options(isaac_lan_compression_benchmark PRIVATE -static-libgcc
                            -static-libstdc++)
    endif()
endif()
if(BUILD_TESTING)
    add_executable(isaac_lan_occurrence_mapping_test tests/occurrence_mapping_test.cpp)
    target_include_directories(isaac_lan_occurrence_mapping_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_occurrence_mapping_test PRIVATE -static-libgcc
                            -static-libstdc++)
    endif()
    add_test(NAME core.occurrence-mapping COMMAND isaac_lan_occurrence_mapping_test)
    set_tests_properties(core.occurrence-mapping PROPERTIES TIMEOUT 30 LABELS "offline;core")
    add_executable(isaac_lan_zstd_test tests/zstd_test.cpp)
    target_link_libraries(isaac_lan_zstd_test PRIVATE isaac_lan_zstd)
    if(MINGW)
        target_link_options(isaac_lan_zstd_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    foreach(test_case round-trip prefixes bounds)
        add_test(NAME core.zstd-${test_case} COMMAND isaac_lan_zstd_test ${test_case})
        set_tests_properties(core.zstd-${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;core")
    endforeach()
    if(NOT WIN32)
        find_package(Lua 5.3 EXACT REQUIRED)
        add_executable(isaac_lan_state_codec_runner tests/state_codec_runner.cpp
                                                    src/engine/state_codec.cpp)
        target_include_directories(isaac_lan_state_codec_runner PRIVATE src ${LUA_INCLUDE_DIR})
        target_link_libraries(isaac_lan_state_codec_runner PRIVATE ${LUA_LIBRARIES}
                                                                   ${CMAKE_DL_LIBS})
        set_target_properties(isaac_lan_state_codec_runner PROPERTIES ENABLE_EXPORTS ON)
        target_compile_options(isaac_lan_state_codec_runner PRIVATE -Wall -Wextra -Werror)
        add_test(
            NAME bridge.native-codec
            COMMAND
                isaac_lan_state_codec_runner "${CMAKE_CURRENT_SOURCE_DIR}/tests/native_codec.lua"
                "${CMAKE_CURRENT_SOURCE_DIR}")
        set_tests_properties(bridge.native-codec PROPERTIES TIMEOUT 60 LABELS "offline;lua;core")
    endif()
    add_executable(isaac_lan_session_store_test tests/session_store_test.cpp
                                                src/runtime/session_store.cpp)
    target_include_directories(isaac_lan_session_store_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_session_store_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME runtime.session-store COMMAND isaac_lan_session_store_test)
    set_tests_properties(runtime.session-store PROPERTIES TIMEOUT 30 LABELS "offline;core")
    add_executable(isaac_lan_chat_test tests/chat_test.cpp)
    target_include_directories(isaac_lan_chat_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_chat_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME presentation.chat-input COMMAND isaac_lan_chat_test)
    set_tests_properties(presentation.chat-input PROPERTIES TIMEOUT 30 LABELS "offline;core")
    add_executable(isaac_lan_input_schedule_test tests/input_schedule_test.cpp)
    target_include_directories(isaac_lan_input_schedule_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_input_schedule_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME runtime.input-schedule COMMAND isaac_lan_input_schedule_test)
    set_tests_properties(runtime.input-schedule PROPERTIES TIMEOUT 30 LABELS "offline;core")
    add_executable(isaac_lan_floor_source_test tests/floor_source_test.cpp)
    target_include_directories(isaac_lan_floor_source_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_floor_source_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME native.floor-source COMMAND isaac_lan_floor_source_test)
    set_tests_properties(native.floor-source PROPERTIES TIMEOUT 30 LABELS "offline")
    add_executable(isaac_lan_player_hud_test tests/player_hud_test.cpp)
    target_include_directories(isaac_lan_player_hud_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_player_hud_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME presentation.player-hud COMMAND isaac_lan_player_hud_test)
    set_tests_properties(presentation.player-hud PROPERTIES TIMEOUT 30 LABELS "offline")
    add_executable(isaac_lan_deflate_test tests/deflate_test.cpp)
    target_link_libraries(isaac_lan_deflate_test PRIVATE isaac_lan_deflate)
    if(MINGW)
        target_link_options(isaac_lan_deflate_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    foreach(test_case interoperability bounds)
        add_test(NAME core.deflate-${test_case} COMMAND isaac_lan_deflate_test ${test_case})
        set_tests_properties(core.deflate-${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;core")
    endforeach()
    add_executable(isaac_lan_delta_test tests/snapshot_delta_test.cpp)
    target_include_directories(isaac_lan_delta_test PRIVATE src)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(isaac_lan_delta_test PRIVATE -Wall -Wextra -Werror)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_delta_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    foreach(test_case changes validation)
        add_test(NAME core.delta-${test_case} COMMAND isaac_lan_delta_test ${test_case})
        set_tests_properties(core.delta-${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;core")
    endforeach()
    add_executable(isaac_lan_diagnostics_test tests/diagnostics_test.cpp src/app/configuration.cpp)
    target_include_directories(isaac_lan_diagnostics_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_diagnostics_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(isaac_lan_diagnostics_test PRIVATE -Wall -Wextra -Werror)
    endif()
    foreach(test_case defaults validation preservation bounded-metrics)
        add_test(NAME diagnostics.${test_case} COMMAND isaac_lan_diagnostics_test ${test_case})
        set_tests_properties(diagnostics.${test_case} PROPERTIES TIMEOUT 30 LABELS
                                                                 "offline;diagnostics")
    endforeach()
    find_program(
        ISAAC_LAN_LUA
        NAMES lua5.3 lua
        NO_CMAKE_FIND_ROOT_PATH)
    if(ISAAC_LAN_LUA)
        isaac_add_lua_test(bridge.chat chat.lua)
        isaac_add_lua_test(presentation.chat-render chat_presentation.lua)
        isaac_add_lua_test(bridge.session_lifecycle session_lifecycle.lua)
        isaac_add_lua_test(bridge.party-startup party_startup.lua)
        isaac_add_lua_test(bridge.capture_generation capture_generation.lua)
        isaac_add_lua_test(bridge.replica_pipeline replica_pipeline.lua)
        isaac_add_lua_test(bridge.challenges challenges.lua)
        isaac_add_lua_test(bridge.challenge_menu challenge_menu.lua)
        isaac_add_lua_test(bridge.ping_hud ping_hud.lua)
        isaac_add_lua_test(bridge.hornfel hornfel.lua)
        isaac_add_lua_test(bridge.entity_links entity_links.lua)
        isaac_add_lua_test(bridge.codec-fragments codec_fragments.lua)
        isaac_add_lua_test(bridge.room-capture room_capture.lua)
        isaac_add_lua_test(bridge.motion-intervals motion_intervals.lua)
        isaac_add_lua_test(presentation.attachments attachments.lua)
        isaac_add_lua_test(bridge.entity-codec entity_codec.lua)
        isaac_add_lua_test(bridge.layers layer_contracts.lua)
        isaac_add_lua_test(bridge.api bridge_api.lua)
        isaac_add_lua_test(bridge.goodtrip goodtrip_rules.lua)
        isaac_add_lua_test(bridge.prediction prediction.lua)
        isaac_add_lua_test(bridge.lanbot lanbot.lua)
        isaac_add_lua_test(bridge.lanbot-campaign lanbot_campaign_fixture.lua)
        isaac_add_lua_test(bridge.lanbot-spiders lanbot_spiders_fixture.lua)
        isaac_add_lua_test(bridge.lanbot-greed lanbot_greed_fixture.lua)
        isaac_add_lua_test(bridge.room-entry room_entry_fixture.lua)
        isaac_add_lua_test(bridge.rotgut-arrival rotgut_arrival.lua)
        isaac_add_lua_test(bridge.grids grids.lua)
        isaac_add_lua_test(bridge.resume bridge_resume.lua)
        isaac_add_lua_test(bridge.mod-loading mod_loading.lua)
        isaac_add_lua_test(bridge.presentation presentation.lua)
        isaac_add_lua_test(bridge.actor-costumes actor_costumes.lua)
        isaac_add_lua_test(bridge.floor floor.lua)
        isaac_add_lua_test(bridge.npc-state npc_state.lua)
        isaac_add_lua_test(bridge.actor-forms actor_forms.lua)
        isaac_add_lua_test(bridge.poop poop.lua)
        isaac_add_lua_test(bridge.special-coordinator special_coordinator.lua)
        isaac_add_lua_test(test.scenario-lifecycle scenario_lifecycle.lua)
        isaac_add_lua_test(bridge.special-menu special_menu.lua)
        isaac_add_lua_test(bridge.shared-resources shared_resources.lua)
        isaac_add_lua_test(bridge.shared-curses shared_curses.lua)
        isaac_add_lua_test(bridge.shared-deals shared_deals.lua)
        isaac_add_lua_test(bridge.pills pills.lua)
        isaac_add_lua_test(bridge.pocket-inventory pocket_inventory.lua)
        isaac_add_lua_test(bridge.crafting-bag crafting_bag.lua)
        isaac_add_lua_test(bridge.temporary-effects temporary_effects.lua)
        isaac_add_lua_test(bridge.keeper keeper.lua)
        isaac_add_lua_test(bridge.greed greed.lua)
        isaac_add_lua_test(bridge.special-visuals special_visuals.lua)
        isaac_add_lua_test(bridge.resource-lifecycle resource_lifecycle.lua)
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
        animation-pose
        fixed-state-fields
        localized-text
        laser-state
        actor-roster
        log-record
        poop-state
        bootstrap-profile
        intro-barrier
        room-map
        room-transition-context
        room-scope-ownership
        compatibility-targets
        death-certificate-arrival
        resolved-room-curses
        shared-deal-chances
        truncated-packets
        hashes
        progression
        archive-round-trip
        archive-capacity
        archive-retry
        challenge-rules
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
    src/engine/state_codec.cpp
    src/engine/versions/j460/entity_fields.cpp
    src/engine/versions/j460/bootstrap.cpp
    src/engine/versions/j460/session_backend.cpp
    src/diagnostics/native_exceptions.cpp
    src/app/configuration.cpp
    src/presentation/chat_background.cpp
    src/diagnostics/runtime_log.cpp
    src/diagnostics/performance.cpp
    src/diagnostics/crash_signal.cpp
    src/runtime/session.cpp
    src/runtime/session_store.cpp
    src/engine/versions/j460/rooms.cpp
    src/engine/versions/j460/visuals.cpp
    src/engine/versions/j460/input.cpp
    src/engine/versions/j460/save.cpp
    src/engine/versions/j460/audio.cpp
    src/engine/versions/j460/presentation.cpp
    src/engine/versions/j460/crafting_hud.cpp
    src/engine/versions/j460/challenge_hud.cpp
    src/engine/versions/j460/characters.cpp
    src/engine/versions/j460/pause_menu.cpp
    src/engine/versions/j460/item_presentation.cpp
    src/engine/versions/j460/generated_items.cpp
    src/engine/versions/j460/rewind.cpp
    src/engine/versions/j460/frontend.cpp
    src/engine/versions/j460/chat_input.cpp
    src/engine/versions/j460/emotes.cpp
    src/diagnostics/lab_capture.cpp)
add_library(isaac_lan_build STATIC src/engine/build.cpp)
target_include_directories(isaac_lan_build PUBLIC src)
target_compile_definitions(isaac_lan_build PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
add_executable(isaac_lan_check tools/game_check.cpp)
add_executable(isaac_lan_workshop tools/workshop.cpp)
target_compile_definitions(isaac_lan_workshop PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
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
add_library(isaac_lan_net STATIC src/net/session.cpp src/net/compression.cpp
                                 src/net/host_resolution.cpp)
target_include_directories(isaac_lan_net PUBLIC src)
target_compile_definitions(isaac_lan_net PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(isaac_lan_net PUBLIC ws2_32 bcrypt isaac_lan_deflate isaac_lan_zstd)
add_executable(isaac_lan_replay_world tools/replay_world_states.cpp)
target_link_libraries(isaac_lan_replay_world PRIVATE isaac_lan_net)
if(MINGW)
    target_link_options(isaac_lan_replay_world PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_replay_world PRIVATE -Wall -Wextra -Werror)
endif()
if(BUILD_TESTING)
    add_executable(isaac_lan_net_test tests/net_test.cpp)
    add_executable(isaac_lan_chat_background_test tests/chat_background_test.cpp
                                                  src/presentation/chat_background.cpp)
    target_include_directories(isaac_lan_chat_background_test PRIVATE src)
    target_compile_definitions(isaac_lan_chat_background_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(isaac_lan_chat_background_test PRIVATE gdiplus ole32)
    if(MINGW)
        target_link_options(isaac_lan_chat_background_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_chat_background_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME presentation.chat-background COMMAND isaac_lan_chat_background_test)
    set_tests_properties(presentation.chat-background PROPERTIES TIMEOUT 30 LABELS
                                                                 "offline;presentation")
    foreach(test_case hornfel rails entity_links lua_api)
        add_executable(isaac_lan_${test_case}_test tests/${test_case}_test.cpp)
        target_include_directories(isaac_lan_${test_case}_test PRIVATE src)
        if(MINGW)
            target_link_options(isaac_lan_${test_case}_test PRIVATE -static-libgcc
                                -static-libstdc++)
            target_compile_options(isaac_lan_${test_case}_test PRIVATE -Wall -Wextra -Werror)
        endif()
        add_test(NAME native.${test_case} COMMAND isaac_lan_${test_case}_test)
        set_tests_properties(native.${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    endforeach()
    target_link_libraries(isaac_lan_net_test PRIVATE isaac_lan_net winmm psapi)
    foreach(
        test_case
        codec
        compression-limits
        world-deltas
        delivery-backpressure
        delta-floor-boundary
        inputs-2
        render-inputs
        input-backpressure
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
        lobby-access
        run-rules
        handshake
        host-names
        commands
        loading-exit
        loading-timeout
        publication-limits
        integrations
        communication
        greed-settings
        host-disconnect
        resource-lifecycle)
        add_test(NAME net.${test_case} COMMAND isaac_lan_net_test ${test_case})
        set_tests_properties(net.${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;network")
    endforeach()
    set_tests_properties(net.loading-timeout PROPERTIES TIMEOUT 75)
endif()
set(MINHOOK_SOURCE_DIR
    ""
    CACHE PATH "Unmodified MinHook v1.3.4 source checkout")
if(NOT EXISTS "${MINHOOK_SOURCE_DIR}/include/MinHook.h")
    message(FATAL_ERROR "Set MINHOOK_SOURCE_DIR to a MinHook v1.3.4 checkout")
endif()
add_subdirectory("${MINHOOK_SOURCE_DIR}" minhook)
if(BUILD_TESTING)
    add_executable(isaac_lan_generated_items_test tests/generated_items_test.cpp)
    target_include_directories(isaac_lan_generated_items_test PRIVATE src)
    target_link_libraries(isaac_lan_generated_items_test PRIVATE minhook)
    if(MINGW)
        target_link_options(isaac_lan_generated_items_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_generated_items_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.generated-items COMMAND isaac_lan_generated_items_test)
    set_tests_properties(native.generated-items PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_executable(isaac_lan_crafting_hud_test tests/crafting_hud_test.cpp
                                               src/engine/versions/j460/crafting_hud.cpp)
    target_include_directories(isaac_lan_crafting_hud_test PRIVATE src)
    target_link_libraries(isaac_lan_crafting_hud_test PRIVATE minhook)
    if(MINGW)
        target_link_options(isaac_lan_crafting_hud_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_crafting_hud_test PRIVATE -Wall -Wextra -Werror -msse2)
    endif()
    add_executable(isaac_lan_challenge_hud_test tests/challenge_hud_test.cpp)
    target_include_directories(isaac_lan_challenge_hud_test PRIVATE src)
    target_link_libraries(isaac_lan_challenge_hud_test PRIVATE minhook)
    if(MINGW)
        target_link_options(isaac_lan_challenge_hud_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_challenge_hud_test PRIVATE -Wall -Wextra -Werror -msse2)
    endif()
    add_test(NAME native.challenge-hud COMMAND isaac_lan_challenge_hud_test)
    set_tests_properties(native.challenge-hud PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_test(NAME native.crafting-hud COMMAND isaac_lan_crafting_hud_test)
    set_tests_properties(native.crafting-hud PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_executable(isaac_lan_character_catalog_test tests/character_catalog_test.cpp
                                                    src/engine/versions/j460/characters.cpp)
    target_include_directories(isaac_lan_character_catalog_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_character_catalog_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_character_catalog_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.character-catalog COMMAND isaac_lan_character_catalog_test)
    set_tests_properties(native.character-catalog PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_executable(isaac_lan_pause_menu_test tests/pause_menu_test.cpp
                                             src/engine/versions/j460/pause_menu.cpp)
    target_include_directories(isaac_lan_pause_menu_test PRIVATE src)
    target_link_libraries(isaac_lan_pause_menu_test PRIVATE minhook)
    if(MINGW)
        target_link_options(isaac_lan_pause_menu_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_pause_menu_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.pause-menu COMMAND isaac_lan_pause_menu_test)
    set_tests_properties(native.pause-menu PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_executable(isaac_lan_frontend_menu_test tests/frontend_menu_test.cpp)
    target_include_directories(isaac_lan_frontend_menu_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_frontend_menu_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_frontend_menu_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.frontend-menu COMMAND isaac_lan_frontend_menu_test)
    set_tests_properties(native.frontend-menu PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
    add_executable(isaac_lan_rewind_home_test tests/rewind_home_test.cpp)
    target_include_directories(isaac_lan_rewind_home_test PRIVATE src)
    target_link_libraries(isaac_lan_rewind_home_test PRIVATE minhook)
    if(MINGW)
        target_link_options(isaac_lan_rewind_home_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_rewind_home_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.rewind-home COMMAND isaac_lan_rewind_home_test)
    set_tests_properties(native.rewind-home PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
endif()

set_target_properties(isaac_lan_probe PROPERTIES PREFIX "")
target_compile_definitions(isaac_lan_probe PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(
    isaac_lan_probe
    PRIVATE bcrypt
            iphlpapi
            imm32
            gdiplus
            ole32
            psapi
            minhook
            isaac_lan_net
            isaac_lan_ui)
add_executable(isaac_lan_lab tools/lab_runner.cpp)
add_executable(isaac_lan_heap_watch tools/heap_watch.cpp)
target_link_libraries(isaac_lan_heap_watch PRIVATE dbghelp)
target_include_directories(isaac_lan_heap_watch PRIVATE src)
target_compile_definitions(isaac_lan_heap_watch PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(BUILD_TESTING)
    add_executable(isaac_lan_heap_fixture tests/heap_fixture.cpp src/diagnostics/crash_signal.cpp)
    target_include_directories(isaac_lan_heap_fixture PRIVATE src)
    target_compile_definitions(isaac_lan_heap_fixture PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MINGW)
        target_link_options(isaac_lan_heap_fixture PRIVATE -static-libgcc -static-libstdc++
                            -Wl,--large-address-aware)
        target_compile_options(isaac_lan_heap_fixture PRIVATE -Wall -Wextra -Werror)
    endif()

    add_executable(isaac_lan_log_test tests/runtime_log_test.cpp src/diagnostics/runtime_log.cpp
                                      src/diagnostics/performance.cpp)
    target_link_libraries(isaac_lan_log_test PRIVATE psapi)
    target_include_directories(isaac_lan_log_test PRIVATE src)
    target_compile_definitions(isaac_lan_log_test PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MINGW)
        target_compile_options(isaac_lan_log_test PRIVATE -Wall -Wextra -Werror)
        target_link_options(isaac_lan_log_test PRIVATE -static-libgcc -static-libstdc++)
    endif()
    add_test(NAME log.path-and-records COMMAND isaac_lan_log_test path-and-records)
    add_test(NAME diagnostics.lifecycle COMMAND isaac_lan_log_test metrics-lifecycle)
    set_tests_properties(diagnostics.lifecycle PROPERTIES TIMEOUT 30 LABELS "offline;resources")
    set_tests_properties(log.path-and-records PROPERTIES TIMEOUT 30 LABELS "offline;logging")
endif()
add_library(isaac_lan_loader SHARED src/app/loader.cpp src/app/loader.def)
set_target_properties(isaac_lan_loader PROPERTIES PREFIX "" OUTPUT_NAME "winmm")
target_include_directories(isaac_lan_loader PRIVATE src)
target_compile_definitions(isaac_lan_loader PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_definitions(isaac_lan_lab PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MINGW)
    target_link_options(isaac_lan_heap_watch PRIVATE -static-libgcc -static-libstdc++ -municode
                        -Wl,--large-address-aware)
    target_compile_options(isaac_lan_heap_watch PRIVATE -Wall -Wextra -Werror)
    target_link_options(isaac_lan_check PRIVATE -static-libgcc -static-libstdc++ -municode)
    target_compile_options(isaac_lan_build PRIVATE -Wall -Wextra -Werror)
    target_compile_options(isaac_lan_check PRIVATE -Wall -Wextra -Werror)
    target_link_options(isaac_lan_workshop PRIVATE -static-libgcc -static-libstdc++ -municode)
    target_compile_options(isaac_lan_workshop PRIVATE -Wall -Wextra -Werror)
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
