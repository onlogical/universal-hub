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
local AntiTrap = importDependency("games/stealanegg/features/AntiTrap", "./features/AntiTrap")
local AutoOpenEggs =
    importDependency("games/stealanegg/features/AutoOpenEggs", "./features/AutoOpenEggs")
local HighlightEsp =
    importDependency("games/stealanegg/features/HighlightEsp", "./features/HighlightEsp")
local HitAura = importDependency("games/stealanegg/features/HitAura", "./features/HitAura")
local InstantPrompts =
    importDependency("games/stealanegg/features/InstantPrompts", "./features/InstantPrompts")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Steal An Egg adapter requires a reactive store")

    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or context.players.LocalPlayer
    local CollectionService = game:GetService("CollectionService")
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
    local antiTrap = AntiTrap.new({
        collectionService = CollectionService,
        localPlayer = LocalPlayer,
    })
    local autoOpenEggs = AutoOpenEggs.new({
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        renderer = require(ReplicatedStorage.Library.Client.Eggs.PlacedEggRenderer),
        runService = RunService,
    })
    local highlightEsp = HighlightEsp.new({
        assets = require(ReplicatedStorage.Directory.Assets),
        collectionService = CollectionService,
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        runService = RunService,
        trapIcon = require(ReplicatedStorage.Directory.Gears._Index.Other.Trap).Icon,
        workspace = Workspace,
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
    local function apply(state)
        antiHit:setEnabled(state.settings.antiHit == true)
        antiTrap:setEnabled(state.settings.antiTrap == true)
        autoOpenEggs:setEnabled(state.settings.autoOpenEggs == true)
        highlightEsp:setAntiTrapEnabled(state.settings.antiTrap == true)
        highlightEsp:setMinimumRarity(state.settings.eggEspMinimumRarity)
        highlightEsp:setMinimumSize(state.settings.eggEspMinimumSize)
        highlightEsp:setEggsEnabled(state.settings.eggEsp == true)
        highlightEsp:setTrapsEnabled(state.settings.trapEsp == true)
        hitAura:setIgnoreFriends(state.settings.hitAuraIgnoreFriends == true)
        hitAura:setEnabled(state.settings.hitAura == true)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
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
        pcall(antiTrap.stop, antiTrap)
        pcall(autoOpenEggs.stop, autoOpenEggs)
        pcall(highlightEsp.stop, highlightEsp)
        pcall(hitAura.stop, hitAura)
        pcall(instantPrompts.stop, instantPrompts)
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
