#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = j510::layout;
const Bindings bindings{j510::entry::victoryPromptControls,
                        j510::entry::victoryPromptRender,
                        j510::entry::victoryPromptHide,
                        j510::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        layout::prompt::nativeVote};
} // namespace isaac::engine::native_victory_prompt
