# Component fixtures can exercise an incomplete backend without linking it into an installable DLL.
# No fixture loads or starts the game executable.
function(isaac_add_backend_test name backend)
    cmake_parse_arguments(FIXTURE "" "" "SOURCES;LIBRARIES;COMPILE_OPTIONS" ${ARGN})
    if(FIXTURE_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown backend fixture arguments: ${FIXTURE_UNPARSED_ARGUMENTS}")
    endif()
    string(REPLACE "-" "_" component "${name}")
    set(target "isaac_lan_${component}_${backend}_test")
    add_executable(${target} ${FIXTURE_SOURCES})
    target_include_directories(${target} PRIVATE src)
    if(FIXTURE_LIBRARIES)
        target_link_libraries(${target} PRIVATE ${FIXTURE_LIBRARIES})
    endif()
    if(backend STREQUAL "j835")
        target_compile_definitions(${target} PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(${target} PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(${target} PRIVATE -Wall -Wextra -Werror ${FIXTURE_COMPILE_OPTIONS})
    endif()
    add_test(NAME native.${name}-${backend} COMMAND ${target})
    set_tests_properties(native.${name}-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                              "offline;native-abi")
endfunction()

isaac_add_backend_test(
    mouse
    j835
    SOURCES
    tests/mouse_j835_test.cpp
    src/engine/versions/j835/mouse_input.cpp
    LIBRARIES
    minhook)
isaac_add_backend_test(
    input-queries
    j835
    SOURCES
    tests/input_queries_j835_test.cpp
    src/engine/versions/j835/input_queries.cpp
    LIBRARIES
    minhook)
foreach(backend j460 j835)
    isaac_add_backend_test(sprite-state ${backend} SOURCES tests/sprite_state_backend_test.cpp
                           tests/native_call.cpp src/engine/versions/${backend}/sprite_state.cpp)
    isaac_add_backend_test(
        item-presentation
        ${backend}
        SOURCES
        tests/item_presentation_backend_test.cpp
        tests/native_call.cpp
        src/engine/versions/${backend}/item_presentation.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        scene-update
        ${backend}
        SOURCES
        tests/scene_update_test.cpp
        src/engine/versions/${backend}/scene_update.cpp
        LIBRARIES
        minhook
        COMPILE_OPTIONS
        -msse2)
    isaac_add_backend_test(
        presentation
        ${backend}
        SOURCES
        tests/presentation_backend_test.cpp
        src/engine/versions/${backend}/presentation.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        victory-prompt
        ${backend}
        SOURCES
        tests/victory_prompt_test.cpp
        src/engine/versions/${backend}/victory_prompt.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        crafting-hud
        ${backend}
        SOURCES
        tests/crafting_hud_test.cpp
        src/engine/versions/common/crafting_hud.cpp
        src/engine/versions/${backend}/crafting_hud.cpp
        LIBRARIES
        minhook
        COMPILE_OPTIONS
        -msse2)
    isaac_add_backend_test(
        challenge-hud
        ${backend}
        SOURCES
        tests/challenge_hud_test.cpp
        src/engine/versions/${backend}/challenge_hud.cpp
        LIBRARIES
        minhook
        COMPILE_OPTIONS
        -msse2)
    isaac_add_backend_test(
        combat-feedback
        ${backend}
        SOURCES
        tests/combat_feedback_test.cpp
        src/engine/versions/${backend}/combat_feedback.cpp
        LIBRARIES
        minhook
        COMPILE_OPTIONS
        -msse2)
    isaac_add_backend_test(
        rewind-home
        ${backend}
        SOURCES
        tests/rewind_home_test.cpp
        src/engine/versions/${backend}/rewind.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        bootstrap
        ${backend}
        SOURCES
        tests/bootstrap_backend_test.cpp
        src/engine/versions/${backend}/bootstrap.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(entity-fields ${backend} SOURCES tests/entity_fields_backend_test.cpp
                           src/engine/versions/${backend}/entity_fields.cpp)
    isaac_add_backend_test(
        pickup-preview
        ${backend}
        SOURCES
        tests/pickup_preview_backend_test.cpp
        src/engine/versions/common/pickup_preview.cpp
        src/engine/versions/${backend}/pickup_preview.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        generated-items
        ${backend}
        SOURCES
        tests/generated_items_test.cpp
        src/engine/versions/${backend}/generated_items.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        audio-backend
        ${backend}
        SOURCES
        tests/audio_backend_test.cpp
        src/engine/versions/${backend}/audio.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        room-routing
        ${backend}
        SOURCES
        tests/room_routing_test.cpp
        src/engine/versions/${backend}/room_routing.cpp
        LIBRARIES
        minhook
        COMPILE_OPTIONS
        -msse2)
    isaac_add_backend_test(
        item-backend
        ${backend}
        SOURCES
        tests/item_backend_test.cpp
        src/engine/versions/${backend}/item_effects.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        input-backend
        ${backend}
        SOURCES
        tests/input_backend_test.cpp
        src/engine/versions/${backend}/input.cpp
        src/engine/versions/common/player_input.cpp
        src/engine/versions/${backend}/player_input.cpp
        src/engine/versions/common/input_devices.cpp
        src/engine/versions/${backend}/input_devices.cpp
        src/engine/versions/common/pause_menu.cpp
        src/engine/versions/${backend}/pause_menu.cpp
        LIBRARIES
        minhook)
    if(backend STREQUAL "j835")
        target_sources(
            isaac_lan_input_backend_${backend}_test
            PRIVATE src/engine/versions/j835/input_queries.cpp
                    src/engine/versions/j835/mouse_input.cpp)
    endif()
    isaac_add_backend_test(
        player-input ${backend} SOURCES tests/player_input_backend_test.cpp
        src/engine/versions/common/player_input.cpp src/engine/versions/${backend}/player_input.cpp)
    isaac_add_backend_test(
        pause-backend ${backend} SOURCES tests/pause_backend_test.cpp
        src/engine/versions/common/pause_menu.cpp src/engine/versions/${backend}/pause_menu.cpp)
    isaac_add_backend_test(
        input-devices
        ${backend}
        SOURCES
        tests/input_devices_test.cpp
        src/engine/versions/common/input_devices.cpp
        src/engine/versions/${backend}/input_devices.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(
        session
        ${backend}
        SOURCES
        tests/session_backend_test.cpp
        src/engine/versions/${backend}/session_backend.cpp
        src/engine/versions/common/session_backend.cpp
        LIBRARIES
        minhook)
    isaac_add_backend_test(save ${backend} SOURCES tests/save_backend_test.cpp
                           src/engine/versions/${backend}/save.cpp)
endforeach()
isaac_add_backend_test(
    character-catalog j835 SOURCES tests/character_catalog_test.cpp
    src/engine/versions/j835/characters.cpp src/engine/versions/common/character_catalogue.cpp)
