#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = j511::layout;
const Bindings bindings{j511::entry::victoryPromptControls,
                        j511::entry::victoryPromptRender,
                        j511::entry::victoryPromptHide,
                        j511::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        layout::prompt::nativeVote};
} // namespace isaac::engine::native_victory_prompt
