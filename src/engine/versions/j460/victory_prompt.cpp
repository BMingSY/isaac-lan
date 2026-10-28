#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = j460::layout;
const Bindings bindings{j460::entry::victoryPromptControls,
                        j460::entry::victoryPromptRender,
                        j460::entry::victoryPromptHide,
                        j460::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        layout::prompt::nativeVote};
} // namespace isaac::engine::native_victory_prompt
