set(ISAAC_LAN_BACKEND
    "repentance_plus"
    CACHE STRING "Audited native game backend")
set(isaac_lan_editions repentance_plus repentance)
set_property(CACHE ISAAC_LAN_BACKEND PROPERTY STRINGS ${isaac_lan_editions})
if(NOT ISAAC_LAN_BACKEND IN_LIST isaac_lan_editions)
    message(FATAL_ERROR "Unsupported ISAAC_LAN_BACKEND: ${ISAAC_LAN_BACKEND}")
endif()
set(ISAAC_LAN_BACKEND_DIR "${PROJECT_SOURCE_DIR}/src/engine/versions/${ISAAC_LAN_BACKEND}")
if(NOT EXISTS "${ISAAC_LAN_BACKEND_DIR}/sources.cmake")
    if(EXISTS "${ISAAC_LAN_BACKEND_DIR}/profile.json")
        message(
            FATAL_ERROR "Native backend ${ISAAC_LAN_BACKEND} has metadata but no implementation")
    endif()
    message(FATAL_ERROR "Unsupported ISAAC_LAN_BACKEND: ${ISAAC_LAN_BACKEND}")
endif()
find_package(Python3 3.10 REQUIRED COMPONENTS Interpreter)
file(GLOB game_version_profiles CONFIGURE_DEPENDS
     "${PROJECT_SOURCE_DIR}/src/engine/versions/*/profile.json")
set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS
             ${game_version_profiles}
             "${ISAAC_LAN_BACKEND_DIR}/entrypoints.h"
             "${ISAAC_LAN_BACKEND_DIR}/signatures.inc"
             "${PROJECT_SOURCE_DIR}/tools/game_profiles.py"
             "${PROJECT_SOURCE_DIR}/tools/generate_game_profile.py")
execute_process(
    COMMAND
        "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tools/generate_game_profile.py" --backend
        "${ISAAC_LAN_BACKEND}" --output "${PROJECT_BINARY_DIR}/generated" COMMAND_ERROR_IS_FATAL
        ANY)
configure_file("${PROJECT_BINARY_DIR}/generated/game-profile.json"
               "${PROJECT_BINARY_DIR}/game-profile.json" COPYONLY)
configure_file("${PROJECT_BINARY_DIR}/generated/loader-versions.json"
               "${PROJECT_BINARY_DIR}/loader-versions.json" COPYONLY)
add_library(isaac_lan_profile STATIC src/engine/profile.cpp)
target_include_directories(
    isaac_lan_profile
    PUBLIC src
    PRIVATE "${PROJECT_BINARY_DIR}/generated")
include("${ISAAC_LAN_BACKEND_DIR}/sources.cmake")
