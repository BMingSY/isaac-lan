# Component fixtures can exercise an incomplete backend without linking it into an installable DLL.
# No fixture loads or starts the game executable.
add_executable(isaac_lan_mouse_j835_test tests/mouse_j835_test.cpp
                                         src/engine/versions/j835/mouse_input.cpp)
target_include_directories(isaac_lan_mouse_j835_test PRIVATE src)
target_link_libraries(isaac_lan_mouse_j835_test PRIVATE minhook)
if(MINGW)
    target_link_options(isaac_lan_mouse_j835_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_mouse_j835_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.mouse-j835 COMMAND isaac_lan_mouse_j835_test)
set_tests_properties(native.mouse-j835 PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
add_executable(isaac_lan_input_queries_j835_test tests/input_queries_j835_test.cpp
                                                 src/engine/versions/j835/input_queries.cpp)
target_include_directories(isaac_lan_input_queries_j835_test PRIVATE src)
target_link_libraries(isaac_lan_input_queries_j835_test PRIVATE minhook)
if(MINGW)
    target_link_options(isaac_lan_input_queries_j835_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_input_queries_j835_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.input-queries-j835 COMMAND isaac_lan_input_queries_j835_test)
set_tests_properties(native.input-queries-j835 PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
foreach(backend j460 j835)
    add_executable(isaac_lan_audio_backend_${backend}_test tests/audio_backend_test.cpp
                                                           src/engine/versions/${backend}/audio.cpp)
    target_include_directories(isaac_lan_audio_backend_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_audio_backend_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_audio_backend_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_audio_backend_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_audio_backend_${backend}_test PRIVATE -Wall -Wextra
                                                                               -Werror)
    endif()
    add_test(NAME native.audio-backend-${backend} COMMAND isaac_lan_audio_backend_${backend}_test)
    set_tests_properties(native.audio-backend-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                    "offline;native-abi")
    add_executable(isaac_lan_room_routing_${backend}_test
                   tests/room_routing_test.cpp src/engine/versions/${backend}/room_routing.cpp)
    target_include_directories(isaac_lan_room_routing_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_room_routing_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_room_routing_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_room_routing_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_room_routing_${backend}_test PRIVATE -Wall -Wextra -Werror
                                                                              -msse2)
    endif()
    add_test(NAME native.room-routing-${backend} COMMAND isaac_lan_room_routing_${backend}_test)
    set_tests_properties(native.room-routing-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                   "offline;native-abi")
    add_executable(isaac_lan_item_backend_${backend}_test
                   tests/item_backend_test.cpp src/engine/versions/${backend}/item_effects.cpp)
    target_include_directories(isaac_lan_item_backend_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_item_backend_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_item_backend_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_item_backend_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_item_backend_${backend}_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.item-backend-${backend} COMMAND isaac_lan_item_backend_${backend}_test)
    set_tests_properties(native.item-backend-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                   "offline;native-abi")
    add_executable(
        isaac_lan_input_backend_${backend}_test
        tests/input_backend_test.cpp
        src/engine/versions/${backend}/input.cpp
        src/engine/versions/common/player_input.cpp
        src/engine/versions/${backend}/player_input.cpp
        src/engine/versions/common/input_devices.cpp
        src/engine/versions/${backend}/input_devices.cpp
        src/engine/versions/common/pause_menu.cpp
        src/engine/versions/${backend}/pause_menu.cpp)
    target_include_directories(isaac_lan_input_backend_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_input_backend_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_input_backend_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
        target_sources(
            isaac_lan_input_backend_${backend}_test
            PRIVATE src/engine/versions/j835/input_queries.cpp
                    src/engine/versions/j835/mouse_input.cpp)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_input_backend_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_input_backend_${backend}_test PRIVATE -Wall -Wextra
                                                                               -Werror)
    endif()
    add_test(NAME native.input-backend-${backend} COMMAND isaac_lan_input_backend_${backend}_test)
    set_tests_properties(native.input-backend-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                    "offline;native-abi")
    add_executable(
        isaac_lan_player_input_${backend}_test
        tests/player_input_backend_test.cpp src/engine/versions/common/player_input.cpp
        src/engine/versions/${backend}/player_input.cpp)
    target_include_directories(isaac_lan_player_input_${backend}_test PRIVATE src)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_player_input_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_player_input_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_player_input_${backend}_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.player-input-${backend} COMMAND isaac_lan_player_input_${backend}_test)
    set_tests_properties(native.player-input-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                   "offline;native-abi")
    add_executable(
        isaac_lan_pause_backend_${backend}_test
        tests/pause_backend_test.cpp src/engine/versions/common/pause_menu.cpp
        src/engine/versions/${backend}/pause_menu.cpp)
    target_include_directories(isaac_lan_pause_backend_${backend}_test PRIVATE src)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_pause_backend_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_pause_backend_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_pause_backend_${backend}_test PRIVATE -Wall -Wextra
                                                                               -Werror)
    endif()
    add_test(NAME native.pause-backend-${backend} COMMAND isaac_lan_pause_backend_${backend}_test)
    set_tests_properties(native.pause-backend-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                    "offline;native-abi")
    add_executable(
        isaac_lan_input_devices_${backend}_test
        tests/input_devices_test.cpp src/engine/versions/common/input_devices.cpp
        src/engine/versions/${backend}/input_devices.cpp)
    target_include_directories(isaac_lan_input_devices_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_input_devices_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_input_devices_${backend}_test
                                   PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_input_devices_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_input_devices_${backend}_test PRIVATE -Wall -Wextra
                                                                               -Werror)
    endif()
    add_test(NAME native.input-devices-${backend} COMMAND isaac_lan_input_devices_${backend}_test)
    set_tests_properties(native.input-devices-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                                    "offline;native-abi")
    add_executable(
        isaac_lan_session_${backend}_test
        tests/session_backend_test.cpp src/engine/versions/${backend}/session_backend.cpp
        src/engine/versions/common/session_backend.cpp)
    target_include_directories(isaac_lan_session_${backend}_test PRIVATE src)
    target_link_libraries(isaac_lan_session_${backend}_test PRIVATE minhook)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_session_${backend}_test PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_session_${backend}_test PRIVATE -static-libgcc
                            -static-libstdc++)
        target_compile_options(isaac_lan_session_${backend}_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.session-${backend} COMMAND isaac_lan_session_${backend}_test)
    set_tests_properties(native.session-${backend} PROPERTIES TIMEOUT 30 LABELS
                                                              "offline;native-abi")
    add_executable(isaac_lan_save_${backend}_test tests/save_backend_test.cpp
                                                  src/engine/versions/${backend}/save.cpp)
    target_include_directories(isaac_lan_save_${backend}_test PRIVATE src)
    if(backend STREQUAL "j835")
        target_compile_definitions(isaac_lan_save_${backend}_test PRIVATE ISAAC_LAN_TEST_J835)
    endif()
    if(MINGW)
        target_link_options(isaac_lan_save_${backend}_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_save_${backend}_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.save-${backend} COMMAND isaac_lan_save_${backend}_test)
    set_tests_properties(native.save-${backend} PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
endforeach()
add_executable(
    isaac_lan_character_catalog_j835_test
    tests/character_catalog_test.cpp src/engine/versions/j835/characters.cpp
    src/engine/versions/common/character_catalogue.cpp)
target_include_directories(isaac_lan_character_catalog_j835_test PRIVATE src)
target_compile_definitions(isaac_lan_character_catalog_j835_test PRIVATE ISAAC_LAN_TEST_J835)
if(MINGW)
    target_link_options(isaac_lan_character_catalog_j835_test PRIVATE -static-libgcc
                        -static-libstdc++)
    target_compile_options(isaac_lan_character_catalog_j835_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.character-catalog-j835 COMMAND isaac_lan_character_catalog_j835_test)
set_tests_properties(native.character-catalog-j835 PROPERTIES TIMEOUT 30 LABELS
                                                              "offline;native-abi")
