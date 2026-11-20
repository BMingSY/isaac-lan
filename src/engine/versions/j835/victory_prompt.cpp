#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_victory_prompt {
namespace layout = j835::layout;
const Bindings bindings{j835::entry::victoryPromptControls,
                        j835::entry::victoryPromptRender,
                        j835::entry::victoryPromptHide,
                        j835::globals::game,
                        layout::game::victoryPrompt,
                        layout::prompt::animation,
                        layout::prompt::playing,
                        layout::string::size,
                        layout::string::capacity,
                        layout::prompt::selection,
                        layout::prompt::result,
                        std::nullopt};
} // namespace isaac::engine::native_victory_prompt
