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

local AntiHit = importDependency("games/stealanegg/features/AntiHit", "./features/AntiHit")
local AutoOpenEggs =
    importDependency("games/stealanegg/features/AutoOpenEggs", "./features/AutoOpenEggs")
local InstantPrompts =
    importDependency("games/stealanegg/features/InstantPrompts", "./features/InstantPrompts")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Steal An Egg adapter requires a reactive store")

    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or context.players.LocalPlayer
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
    local antiHit = AntiHit.new({
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        ragdoll = require(ReplicatedStorage.Library.Modules.Ragdoll),
        runService = RunService,
        slotIdentity = require(ReplicatedStorage.Library.Util.AreaEggSlotIdentity),
        workspace = Workspace,
    })
    local autoOpenEggs = AutoOpenEggs.new({
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        renderer = require(ReplicatedStorage.Library.Client.Eggs.PlacedEggRenderer),
        runService = RunService,
    })
    local instantPrompts = InstantPrompts.new(Workspace)
    local unsubscribe = context.store:Subscribe(function(state)
        antiHit:setEnabled(state.settings.antiHit == true)
        autoOpenEggs:setEnabled(state.settings.autoOpenEggs == true)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
    end)
    local stopped = false

    return {
        stop = function()
            if stopped then
                return
            end
            stopped = true
            unsubscribe()
            antiHit:stop()
            autoOpenEggs:stop()
            instantPrompts:stop()
        end,
    }
end

return Adapter
