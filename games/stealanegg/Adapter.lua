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
local BestEggHighlight = importDependency(
    "games/stealanegg/features/BestEggHighlight",
    "./features/BestEggHighlight"
)
local HitAura = importDependency("games/stealanegg/features/HitAura", "./features/HitAura")
local InstantPrompts =
    importDependency("games/stealanegg/features/InstantPrompts", "./features/InstantPrompts")
local InfiniteJump =
    importDependency("games/stealanegg/features/InfiniteJump", "./features/InfiniteJump")
local TreadmillSpeedBoost = importDependency(
    "games/stealanegg/features/TreadmillSpeedBoost",
    "./features/TreadmillSpeedBoost"
)

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
    local hitAura = HitAura.new({
        eggCmds = EggCmds,
        endpoint = require(ReplicatedStorage.Library.Globals.Constants).NETWORK_MAP.Bat.ACTIVATE,
        localPlayer = LocalPlayer,
        network = require(ReplicatedStorage.Library.Client.Network),
        players = context.players,
        runService = RunService,
        workspace = Workspace,
    })
    local instantPrompts = InstantPrompts.new(Workspace)
    local bestEggHighlight = BestEggHighlight.new({
        coreGui = game:GetService("CoreGui"),
        eggCmds = EggCmds,
        runService = RunService,
        workspace = Workspace,
    })
    local infiniteJump = InfiniteJump.new({
        inputService = game:GetService("UserInputService"),
        localPlayer = LocalPlayer,
    })
    local treadmillSpeedBoost = TreadmillSpeedBoost.new({
        localPlayer = LocalPlayer,
        runService = RunService,
        workspace = Workspace,
    })
    local function apply(state)
        antiHit:setEnabled(state.settings.antiHit == true)
        autoOpenEggs:setEnabled(state.settings.autoOpenEggs == true)
        hitAura:setIgnoreFriends(state.settings.hitAuraIgnoreFriends == true)
        hitAura:setEnabled(state.settings.hitAura == true)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
        bestEggHighlight:setEnabled(state.settings.bestEggHighlight == true)
        infiniteJump:setEnabled(state.settings.infiniteJump == true)
        treadmillSpeedBoost:setEnabled(state.settings.treadmillSpeedBoost == true)
    end
    local unsubscribe = context.store:Subscribe(apply, false)
    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        pcall(unsubscribe)
        pcall(antiHit.stop, antiHit)
        pcall(autoOpenEggs.stop, autoOpenEggs)
        pcall(hitAura.stop, hitAura)
        pcall(instantPrompts.stop, instantPrompts)
        pcall(bestEggHighlight.stop, bestEggHighlight)
        pcall(infiniteJump.stop, infiniteJump)
        pcall(treadmillSpeedBoost.stop, treadmillSpeedBoost)
    end
    local applied, applyError = pcall(apply, context.store:Get())
    if not applied then
        stop()
        error(applyError, 0)
    end

    return {
        stop = stop,
    }
end

return Adapter
