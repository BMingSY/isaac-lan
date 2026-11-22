#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = repentance_plus::layout;
const Bindings bindings{repentance_plus::entry::victoryPromptControls,
                        repentance_plus::entry::victoryPromptRender,
                        repentance_plus::entry::victoryPromptHide,
                        repentance_plus::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        layout::prompt::nativeVote};
} // namespace isaac::engine::native_victory_prompt
