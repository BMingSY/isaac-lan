execute_process(COMMAND "${NATIVE}" --wire OUTPUT_VARIABLE wire COMMAND_ERROR_IS_FATAL ANY)
string(REPLACE "\r" "" wire "${wire}")
string(REPLACE "\n" ";" wire "${wire}")
list(GET wire 0 neutral)
list(GET wire 1 pointer)
list(GET wire 2 mixed)
execute_process(COMMAND "${LUA}" "${SCRIPT}" "${neutral}" "${pointer}" "${mixed}" "${INPUT_MODULE}"
                        COMMAND_ERROR_IS_FATAL ANY)
