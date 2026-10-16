function(isaac_add_lua_test name script)
    add_test(NAME ${name} COMMAND "${ISAAC_LAN_LUA}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/${script}"
                                  "${CMAKE_CURRENT_SOURCE_DIR}")
    set_tests_properties(${name} PROPERTIES TIMEOUT 30 LABELS "offline;lua")
endfunction()
