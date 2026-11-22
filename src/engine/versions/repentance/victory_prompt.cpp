#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = repentance::layout;
const Bindings bindings{repentance::entry::victoryPromptControls,
                        repentance::entry::victoryPromptRender,
                        repentance::entry::victoryPromptHide,
                        repentance::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        std::nullopt};
} // namespace isaac::engine::native_victory_prompt
