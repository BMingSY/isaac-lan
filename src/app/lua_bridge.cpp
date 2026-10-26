#include "app/lua_bridge.h"
#include "engine/lua_api.h"
#include "embedded_bridge.h"
#include <cstring>
#include <iterator>
#include <stdexcept>
#include <string>

namespace isaac::app {
void loadBridge(lua_State* state, const lua::API& lua,
                const std::function<bool(int, int)>& invoke) {
    if (lua.loadBuffer(state, predictionSource, sizeof(predictionSource) - 1,
                       "@isaac-lan/presentation/prediction.lua", "t") != 0 ||
        !invoke(0, 0))
        throw std::runtime_error("Cannot initialize local movement prediction");
    lua.createTable(state, 0, std::size(integrationModules));
    lua.setGlobal(state, "_IsaacLanModules");
    for (const auto& module : integrationModules) {
        lua.getGlobal(state, "_IsaacLanModules");
        if (lua.loadBuffer(state, module.source, std::strlen(module.source), module.file, "t") !=
                0 ||
            !invoke(0, 1))
            throw std::runtime_error(std::string("Cannot load integration module ") + module.file);
        lua.setField(state, -2, module.name);
        lua.setTop(state, -2);
    }
    if (lua.loadBuffer(state, stateSource, sizeof(stateSource) - 1, "@isaac-lan/app/world.lua",
                       "t") != 0 ||
        !invoke(0, 0))
        throw std::runtime_error("Cannot initialize authoritative state bridge");
    if (lua.loadBuffer(state, bridgeSource, sizeof(bridgeSource) - 1, "@isaac-lan/app/main.lua",
                       "t") != 0 ||
        !invoke(0, 0))
        throw std::runtime_error("Cannot initialize embedded LAN bridge");
    if (lua.loadBuffer(state, menuSource, sizeof(menuSource) - 1,
                       "@isaac-lan/presentation/menu.lua", "t") != 0 ||
        !invoke(0, 0))
        throw std::runtime_error("Cannot initialize native LAN menu");
}
} // namespace isaac::app
