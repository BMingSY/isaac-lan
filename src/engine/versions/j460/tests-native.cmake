add_executable(
    isaac_lan_player_outlines_test tests/player_outlines_test.cpp
                                   ${CMAKE_CURRENT_LIST_DIR}/../common/player_outlines.cpp)
target_include_directories(isaac_lan_player_outlines_test PRIVATE src)
target_link_libraries(isaac_lan_player_outlines_test PRIVATE minhook)
if(MINGW)
    target_link_options(isaac_lan_player_outlines_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_player_outlines_test PRIVATE -Wall -Wextra -Werror -msse2)
endif()
add_test(NAME native.player-outlines COMMAND isaac_lan_player_outlines_test)
set_tests_properties(native.player-outlines PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
add_executable(isaac_lan_item_effects_test tests/item_effects_test.cpp)
target_include_directories(isaac_lan_item_effects_test PRIVATE src)
target_link_libraries(isaac_lan_item_effects_test PRIVATE minhook)
if(MINGW)
    target_link_options(isaac_lan_item_effects_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_item_effects_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.item-effects COMMAND isaac_lan_item_effects_test)
set_tests_properties(native.item-effects PROPERTIES TIMEOUT 30 LABELS "offline;native")
add_executable(
    isaac_lan_character_catalog_test
    tests/character_catalog_test.cpp ${ISAAC_LAN_BACKEND_DIR}/characters.cpp
    ${ISAAC_LAN_BACKEND_DIR}/../common/character_catalogue.cpp)
target_include_directories(isaac_lan_character_catalog_test PRIVATE src)
if(MINGW)
    target_link_options(isaac_lan_character_catalog_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_character_catalog_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.character-catalog COMMAND isaac_lan_character_catalog_test)
set_tests_properties(native.character-catalog PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
add_executable(
    isaac_lan_pause_menu_test
    tests/pause_menu_test.cpp
    ${ISAAC_LAN_BACKEND_DIR}/input.cpp
    ${ISAAC_LAN_BACKEND_DIR}/pause_menu.cpp
    ${ISAAC_LAN_BACKEND_DIR}/../common/pause_menu.cpp
    ${ISAAC_LAN_BACKEND_DIR}/input_devices.cpp
    ${ISAAC_LAN_BACKEND_DIR}/../common/input_devices.cpp
    ${ISAAC_LAN_BACKEND_DIR}/player_input.cpp
    ${ISAAC_LAN_BACKEND_DIR}/../common/player_input.cpp)
target_include_directories(isaac_lan_pause_menu_test PRIVATE src)
target_link_libraries(isaac_lan_pause_menu_test PRIVATE minhook)
if(MINGW)
    target_link_options(isaac_lan_pause_menu_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_pause_menu_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.pause-menu COMMAND isaac_lan_pause_menu_test)
set_tests_properties(native.pause-menu PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
add_executable(isaac_lan_frontend_menu_test tests/frontend_menu_test.cpp
                                            src/engine/versions/j460/frontend.cpp)
add_executable(isaac_lan_mouse_input_test tests/mouse_input_test.cpp)
target_include_directories(isaac_lan_mouse_input_test PRIVATE src)
if(MINGW)
    target_link_options(isaac_lan_mouse_input_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_mouse_input_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.mouse-input COMMAND isaac_lan_mouse_input_test)
set_tests_properties(native.mouse-input PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
target_include_directories(isaac_lan_frontend_menu_test PRIVATE src)
if(MINGW)
    target_link_options(isaac_lan_frontend_menu_test PRIVATE -static-libgcc -static-libstdc++)
    target_compile_options(isaac_lan_frontend_menu_test PRIVATE -Wall -Wextra -Werror)
endif()
add_test(NAME native.frontend-menu COMMAND isaac_lan_frontend_menu_test)
set_tests_properties(native.frontend-menu PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
foreach(test_case hornfel rails entity_links)
    add_executable(isaac_lan_${test_case}_test tests/${test_case}_test.cpp)
    target_include_directories(isaac_lan_${test_case}_test PRIVATE src)
    if(MINGW)
        target_link_options(isaac_lan_${test_case}_test PRIVATE -static-libgcc -static-libstdc++)
        target_compile_options(isaac_lan_${test_case}_test PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME native.${test_case} COMMAND isaac_lan_${test_case}_test)
    set_tests_properties(native.${test_case} PROPERTIES TIMEOUT 30 LABELS "offline;native-abi")
endforeach()
target_sources(isaac_lan_hornfel_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/references.cpp)
target_sources(isaac_lan_entity_links_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/references.cpp)
target_sources(isaac_lan_rails_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/grid_state.cpp)
