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
local AutoFarm = importDependency("games/stealanegg/features/AutoFarm", "./features/AutoFarm")
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
local WalkNavigator =
    importDependency("games/stealanegg/features/WalkNavigator", "./features/WalkNavigator")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Steal An Egg adapter requires a reactive store")

    local environment = type(getgenv) == "function" and getgenv() or _G
    if type(environment.UniversalHubRuntimeState) ~= "table" then
        environment.UniversalHubRuntimeState = {}
    end
    local runtimeState = environment.UniversalHubRuntimeState
    if type(runtimeState.stealanegg) ~= "table" then
        runtimeState.stealanegg = {}
    end
    local gameRuntime = runtimeState.stealanegg
    if type(gameRuntime.visitedServerIds) ~= "table" then
        gameRuntime.visitedServerIds = {}
    end
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or context.players.LocalPlayer
    local CollectionService = game:GetService("CollectionService")
    local HttpService = game:GetService("HttpService")
    local PathfindingService = game:GetService("PathfindingService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local TeleportService = game:GetService("TeleportService")
    local visitedSettingKey = "UniversalHubStealAnEggVisitedServers"
    if next(gameRuntime.visitedServerIds) == nil then
        local loaded, visited =
            pcall(TeleportService.GetTeleportSetting, TeleportService, visitedSettingKey)
        if loaded and type(visited) == "table" then
            for serverId in pairs(visited) do
                gameRuntime.visitedServerIds[serverId] = true
            end
        end
    end
    local function persistVisitedServers()
        pcall(
            TeleportService.SetTeleportSetting,
            TeleportService,
            visitedSettingKey,
            gameRuntime.visitedServerIds
        )
    end
    local AreaEggResetConfig = require(ReplicatedStorage.Directory.AreaEggResetCycle)
    local AreaEggResetTimeUtil = require(ReplicatedStorage.Library.Util.AreaEggResetTimeUtil)
    local Assets = require(ReplicatedStorage.Directory.Assets)
    local Constants = require(ReplicatedStorage.Library.Globals.Constants)
    local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
    local Network = require(ReplicatedStorage.Library.Client.Network)
    local PlotCmds = require(ReplicatedStorage.Library.Client.PlotCmds)
    local SlotIdentity = require(ReplicatedStorage.Library.Util.AreaEggSlotIdentity)
    local antiHit = AntiHit.new({
        eggCmds = EggCmds,
        guardHitEndpoint = Constants.NETWORK_MAP.Guards.FOREST_HIT,
        localPlayer = LocalPlayer,
        logger = context.logger,
        network = Network,
        ragdoll = require(ReplicatedStorage.Library.Modules.Ragdoll),
        runService = RunService,
        slotIdentity = SlotIdentity,
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
        assets = Assets,
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
    local guardModels = {}
    local objects = Workspace:FindFirstChild("__OBJECTS")
    local areas = objects and objects:FindFirstChild("Areas")
    local guardAreas = areas and areas:FindFirstChild("GuardAreas")
    for areaId, config in pairs(require(ReplicatedStorage.Directory.Guards).Directory) do
        guardSpeeds[areaId] = config.WalkSpeed
        local area = guardAreas and guardAreas:FindFirstChild(areaId)
        local guard = area and area:FindFirstChild("Guard")
        if guard and guard:IsA("Model") then
            guardModels[areaId] = guard
        end
    end
    local function currentPing()
        for _, metric in ipairs(context.store:Get().footerMetrics or {}) do
            if metric.id == "ping" and type(metric.value) == "number" then
                return metric.value
            end
        end
        return 0
    end
    local lagSafeMovement = LagSafeMovement.new({
        eggCmds = EggCmds,
        getPing = currentPing,
        guardModels = guardModels,
        guardSpeeds = guardSpeeds,
        localPlayer = LocalPlayer,
        runService = RunService,
    })
    local resetPadding = AreaEggResetConfig.WallCountdownDelayAfterDayStartsSeconds
        + AreaEggResetConfig.WallCountdownSeconds
    local resetUntil = 0
    local now = Workspace:GetServerTimeNow()
    if Workspace:GetAttribute("Event_AdminAbuse") ~= true and AreaEggResetTimeUtil.IsNight(now) then
        resetUntil = AreaEggResetTimeUtil.GetNextResetAt(now) + resetPadding
    end
    local function resetSecondsRemaining()
        return math.max(0, resetUntil - Workspace:GetServerTimeNow())
    end
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
        persistVisited = persistVisitedServers,
        teleportService = TeleportService,
        visitedServerIds = gameRuntime.visitedServerIds,
    })
    local resetConnection = EggCmds.AreaEggResetStartCountdown:Connect(function(payload)
        if type(payload) == "table" and type(payload.DayStartsAt) == "number" then
            resetUntil = math.max(resetUntil, payload.DayStartsAt + resetPadding)
        end
        table.clear(gameRuntime.visitedServerIds)
        gameRuntime.visitedServerIds[context.jobId] = true
        persistVisitedServers()
    end)
    local navigator = WalkNavigator.new({
        localPlayer = LocalPlayer,
        pathfindingService = PathfindingService,
        runService = RunService,
        workspace = Workspace,
    })
    local autoFarm = AutoFarm.new({
        assets = Assets,
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        logger = context.logger,
        getResetSeconds = resetSecondsRemaining,
        navigator = navigator,
        plotCmds = PlotCmds,
        players = context.players,
        publishStatus = function(model)
            if type(model) ~= "table" then
                context.store:Patch({ floatingMonitor = false })
                return
            end
            model.players = #context.players:GetPlayers()
            context.store:Patch({ floatingMonitor = model })
        end,
        serverHop = serverHop,
        slotIdentity = SlotIdentity,
        workspace = Workspace,
    })
    local unsubscribePing = context.subscribeFooterMetric("ping", {
        kind = "latency",
        label = "Ping",
    }, function()
        local item = Stats.Network.ServerStatsItem["Data Ping"]
        return math.round(item:GetValue())
    end)
    local function apply(state)
        local farming = state.settings.autoFarm == true
        antiHit:setEnabled(state.settings.antiHit == true or farming)
        antiTrap:setEnabled(state.settings.antiTrap == true or farming)
        autoOpenEggs:setEnabled(state.settings.autoOpenEggs == true)
        highlightEsp:setAntiTrapEnabled(state.settings.antiTrap == true or farming)
        highlightEsp:setMinimumRarity(state.settings.eggEspMinimumRarity)
        highlightEsp:setMinimumSize(state.settings.eggEspMinimumSize)
        highlightEsp:setEggsEnabled(state.settings.eggEsp == true)
        highlightEsp:setTrapsEnabled(state.settings.trapEsp == true)
        hitAura:setIgnoreFriends(state.settings.hitAuraIgnoreFriends == true)
        hitAura:setEnabled(state.settings.hitAura == true)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
        lagSafeMovement:setPingThreshold(state.settings.serverHopMaxPing)
        lagSafeMovement:setEnabled(
            farming or (state.settings.antiHit == true and state.settings.lagSafeMovement == true)
        )
        autoFarm:setTargetRarities(state.settings.autoFarmEternal, state.settings.autoFarmSecret)
        autoFarm:setServerHopping(state.settings.autoFarmServerHopping)
        autoFarm:setHighPopulation(state.settings.autoFarmHighPopulation)
        autoFarm:setMaxPing(state.settings.serverHopMaxPing)
        autoFarm:setEnabled(farming)
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
        pcall(resetConnection.Disconnect, resetConnection)
        pcall(antiHit.stop, antiHit)
        pcall(antiTrap.stop, antiTrap)
        pcall(autoFarm.stop, autoFarm)
        pcall(autoOpenEggs.stop, autoOpenEggs)
        pcall(highlightEsp.stop, highlightEsp)
        pcall(hitAura.stop, hitAura)
        pcall(instantPrompts.stop, instantPrompts)
        pcall(lagSafeMovement.stop, lagSafeMovement)
        pcall(navigator.stop, navigator)
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
            context.store:Patch({
                notification = {
                    action = "serverHop",
                    confirmLabel = "Try Another",
                    position = "bottom-right",
                    text = ("This server settled at %.0f ms, above your %d ms limit. Hop again?"):format(
                        ping,
                        settings.serverHopMaxPing
                    ),
                    title = "High Server Ping",
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
            and latestSettings.autoFarm ~= true
            and gameRuntime.lagSafePromptServer ~= context.jobId
            and ping > latestSettings.serverHopMaxPing
        then
            gameRuntime.lagSafePromptServer = context.jobId
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
            })
        end
    end)

    return {
        stop = stop,
    }
end

return Adapter
