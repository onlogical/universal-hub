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

local Targeting = importDependency("games/runaways/Targeting", "./Targeting")
local Movement = importDependency("games/runaways/features/Movement", "./features/Movement")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store and context.render, "RUNAWAYS adapter requires a store and renderer")

    local Players = context.players or game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local movement = Movement.new()
    local stopped = false

    local connection = RunService.Heartbeat:Connect(function()
        if stopped then
            return
        end
        local camera = Workspace.CurrentCamera
        local settings = context.store:Get().settings
        movement:update(settings, LocalPlayer.Character, camera, UserInputService)
        context.render(
            camera and Targeting.observations(Players, LocalPlayer, camera) or {},
            UserInputService:GetMouseLocation(),
            {}
        )
    end)

    return {
        capabilities = {
            "boxes",
            "chams",
            "showEnemies",
            "showTeammates",
            "names",
            "health",
            "weapon",
            "fly",
            "flySpeed",
            "speed",
            "walkSpeed",
        },
        isOpponent = function(player)
            return Targeting.isOpponent(LocalPlayer, player)
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            connection:Disconnect()
            movement:stop()
        end,
    }
end

return Adapter
