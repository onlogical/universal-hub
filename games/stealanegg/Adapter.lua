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
local LagSafeMovement =
    importDependency("games/stealanegg/features/LagSafeMovement", "./features/LagSafeMovement")
local ServerHop = importDependency("games/stealanegg/features/ServerHop", "./features/ServerHop")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Steal An Egg adapter requires a reactive store")

    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or context.players.LocalPlayer
    local CollectionService = game:GetService("CollectionService")
    local HttpService = game:GetService("HttpService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local TeleportService = game:GetService("TeleportService")
    local Constants = require(ReplicatedStorage.Library.Globals.Constants)
    local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
    local Network = require(ReplicatedStorage.Library.Client.Network)
    local antiHit = AntiHit.new({
        eggCmds = EggCmds,
        guardHitEndpoint = Constants.NETWORK_MAP.Guards.FOREST_HIT,
        localPlayer = LocalPlayer,
        logger = context.logger,
        network = Network,
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
        endpoint = Constants.NETWORK_MAP.Bat.ACTIVATE,
        localPlayer = LocalPlayer,
        network = Network,
        players = context.players,
        runService = RunService,
        workspace = Workspace,
    })
    local instantPrompts = InstantPrompts.new(Workspace)
    local guardSpeeds = {}
    for areaId, config in pairs(require(ReplicatedStorage.Directory.Guards).Directory) do
        guardSpeeds[areaId] = config.WalkSpeed
    end
    local lagSafeMovement = LagSafeMovement.new({
        eggCmds = EggCmds,
        guardSpeeds = guardSpeeds,
        localPlayer = LocalPlayer,
        runService = RunService,
    })
    local serverHop = ServerHop.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        httpGet = function(url)
            return game:HttpGet(url, true)
        end,
        jobId = context.jobId,
        localPlayer = LocalPlayer,
        logger = context.logger,
        placeId = context.placeId,
        teleportService = TeleportService,
    })
    local unsubscribePing = context.subscribeFooterMetric("ping", {
        kind = "latency",
        label = "Ping",
    }, function()
        local item = Stats.Network.ServerStatsItem["Data Ping"]
        return math.round(item:GetValue())
    end)
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
        lagSafeMovement:setEnabled(
            state.settings.antiHit == true and state.settings.lagSafeMovement == true
        )
        if state.settings.serverHop == true then
            context.store:Patch({
                settings = {
                    serverHop = false,
                    serverHopAttempts = 0,
                    serverHopPingGuard = true,
                },
            })
            context.settingsChanged(context.store:Get().settings)
            serverHop:run(state.settings.serverHopMaxPing)
        end
    end
    local unsubscribe = context.store:Subscribe(apply, false)
    local stopped = false
    local function stop()
        if stopped then
            return
        end
        stopped = true
        pcall(unsubscribe)
        pcall(unsubscribePing)
        pcall(antiHit.stop, antiHit)
        pcall(antiTrap.stop, antiTrap)
        pcall(autoOpenEggs.stop, autoOpenEggs)
        pcall(highlightEsp.stop, highlightEsp)
        pcall(hitAura.stop, hitAura)
        pcall(instantPrompts.stop, instantPrompts)
        pcall(lagSafeMovement.stop, lagSafeMovement)
        pcall(serverHop.stop, serverHop)
    end
    local applied, applyError = pcall(apply, context.store:Get())
    if not applied then
        stop()
        error(applyError, 0)
    end
    task.delay(10, function()
        local settings = context.store:Get().settings
        local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        if stopped then
            return
        end
        if settings.serverHopPingGuard == true then
            if ping <= settings.serverHopMaxPing then
                context.store:Patch({
                    settings = { serverHopAttempts = 0, serverHopPingGuard = false },
                })
                context.settingsChanged(context.store:Get().settings)
                return
            end
            if settings.serverHopAttempts < 5 then
                context.store:Patch({
                    settings = { serverHopAttempts = settings.serverHopAttempts + 1 },
                })
                context.settingsChanged(context.store:Get().settings)
                serverHop:run(settings.serverHopMaxPing)
                return
            end
            context.store:Patch({
                notification = {
                    action = "serverHop",
                    confirmLabel = "Try Again",
                    position = "bottom-right",
                    text = ("No server below %d ms was found after 5 hops."):format(
                        settings.serverHopMaxPing
                    ),
                    title = "Ping Limit Not Met",
                    tone = "warning",
                },
                settings = { serverHopAttempts = 0, serverHopPingGuard = false },
            })
            context.settingsChanged(context.store:Get().settings)
            return
        end
        local latestSettings = context.store:Get().settings
        if
            latestSettings.lagSafeMovement ~= true
            and latestSettings.lagSafePromptServer ~= context.jobId
            and ping > latestSettings.serverHopMaxPing
        then
            context.store:Patch({
                notification = {
                    action = "lagSafeMovement",
                    confirmLabel = "Enable",
                    position = "bottom-right",
                    text = ("Ping is %.0f ms. Use safer movement while carrying eggs near fast bosses?"):format(
                        ping
                    ),
                    title = "High Ping Detected",
                    tone = "warning",
                },
                settings = { lagSafePromptServer = context.jobId },
            })
            context.settingsChanged(context.store:Get().settings)
        end
    end)

    return {
        stop = stop,
    }
end

return Adapter
