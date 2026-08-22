local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local DefensiveStyle = importDependency(
    "games/duelinggrounds/features/combat/DefensiveStyle",
    "./DefensiveStyle"
)
local DynamicStyle = importDependency(
    "games/duelinggrounds/features/combat/DynamicStyle",
    "./DynamicStyle"
)
local FlashyStyle = importDependency(
    "games/duelinggrounds/features/combat/FlashyStyle",
    "./FlashyStyle"
)
local OffensiveStyle = importDependency(
    "games/duelinggrounds/features/combat/OffensiveStyle",
    "./OffensiveStyle"
)

local Styles = {}

function Styles.preferences(name, state, dynamicState)
    if name == "defensive" then
        return DefensiveStyle.preferences(state)
    end
    if name == "dynamic" then
        return DynamicStyle.preferences(dynamicState)
    end
    if name == "flashy" then
        return FlashyStyle.preferences(state)
    end
    return OffensiveStyle.preferences(state)
end

return Styles
