# Component fixtures can exercise an incomplete backend without linking it into an installable DLL.
# No fixture loads or starts the game executable.
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
