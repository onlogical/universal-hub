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
local AutoBlossom =
    importDependency("games/stealanegg/features/AutoBlossom", "./features/AutoBlossom")
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
    local function readPing()
        local ok, value = pcall(function()
            return Stats.PerformanceStats.Ping:GetValue()
        end)
        if not ok or type(value) ~= "number" then
            ok, value = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
        end
        if not ok or type(value) ~= "number" then
            ok, value = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
            value = ok and type(value) == "number" and value * 1000 or 0
        end
        return math.round(value)
    end
    local historySettingKey = "UniversalHubStealAnEggFarmHistory"
    if type(gameRuntime.farmHistory) ~= "table" then
        local loaded, history =
            pcall(TeleportService.GetTeleportSetting, TeleportService, historySettingKey)
        gameRuntime.farmHistory = loaded and type(history) == "table" and history
            or { active = false, eggs = {} }
    end
    if type(gameRuntime.farmHistory.eggs) ~= "table" then
        gameRuntime.farmHistory.eggs = {}
    end
    if type(gameRuntime.farmHistory.globalSpawns) ~= "table" then
        gameRuntime.farmHistory.globalSpawns = {}
    end
    local function persistFarmHistory()
        pcall(
            TeleportService.SetTeleportSetting,
            TeleportService,
            historySettingKey,
            gameRuntime.farmHistory
        )
    end
    local function isGlobalSpawnKnown(rarity)
        return gameRuntime.farmHistory.globalSpawns[rarity] == true
    end
    local function markGlobalSpawn(rarity)
        if
            (rarity == "Secret" or rarity == "Eternal")
            and gameRuntime.farmHistory.globalSpawns[rarity] ~= true
        then
            gameRuntime.farmHistory.globalSpawns[rarity] = true
            persistFarmHistory()
        end
    end
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
    local Areas = require(ReplicatedStorage.Directory.Areas)
    local Assets = require(ReplicatedStorage.Directory.Assets)
    local Sakura = require(ReplicatedStorage.Directory.Sakura)
    local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
    local GuardChasePolicy = require(ReplicatedStorage.Library.Modules.GuardAreas.GuardChasePolicy)
    local GuardEscapePrediction =
        require(ReplicatedStorage.Library.Modules.GuardAreas.GuardEscapePrediction)
    local Save = require(ReplicatedStorage.Library.Client.Save)
    local indexCategories = {}
    for _, area in pairs(Areas.Directory) do
        for _, drop in pairs(area.DropTable or {}) do
            local category = drop[1]
            local asset = Assets.Directory[category]
            if drop[2] > 0 and asset and asset.DontRoll ~= true then
                indexCategories[category] = true
            end
        end
    end
    local function isIndexed(category)
        local save = Save.Get()
        return save ~= nil and save.Index[category] == true
    end
    local function isIndexPending(category)
        for _, record in pairs(EggCmds.GetOwnerRuntimeRecords(LocalPlayer.UserId)) do
            if record.AssetCategory == category then
                return true
            end
        end
        return false
    end
    local function hasMissingIndex()
        for category in pairs(indexCategories) do
            if not isIndexed(category) and not isIndexPending(category) then
                return true
            end
        end
        return false
    end
    local function securedEggs()
        local eggs = {}
        for index, egg in ipairs(gameRuntime.farmHistory.eggs) do
            local color = egg.rarityColor
            table.insert(eggs, {
                area = egg.area,
                icon = egg.icon,
                name = egg.name,
                rarity = egg.rarity,
                rarityColor = type(color) == "table"
                        and Color3.new(color[1] or 0.7, color[2] or 0.7, color[3] or 0.7)
                    or Color3.fromRGB(177, 188, 199),
                secured = true,
                size = egg.size,
                state = "Secured",
                target = false,
                uid = ("secured-%d-%s"):format(index, tostring(egg.uid)),
            })
        end
        return eggs
    end
    local function recordSecuredEgg(record)
        local asset = Assets.Directory[record.AssetCategory]
        local rarity = asset and asset.Rarity
        local color = rarity and rarity.Color or Color3.fromRGB(177, 188, 199)
        table.insert(gameRuntime.farmHistory.eggs, 1, {
            area = record.AreaId or "Unknown",
            icon = asset and asset.Icon or "",
            name = asset and asset.DisplayName or record.AssetCategory,
            rarity = rarity and (rarity.DisplayName or rarity._id) or "Unknown",
            rarityColor = { color.R, color.G, color.B },
            size = tonumber(record.AssetScale) or 1,
            uid = record.Uid,
        })
        persistFarmHistory()
    end
    local Constants = require(ReplicatedStorage.Library.Globals.Constants)
    local Network = require(ReplicatedStorage.Library.Client.Network)
    local PlotCmds = require(ReplicatedStorage.Library.Client.PlotCmds)
    local SlotIdentity = require(ReplicatedStorage.Library.Util.AreaEggSlotIdentity)
    local stopped = false
    local navigator
    local antiHit = AntiHit.new({
        eggCmds = EggCmds,
        guardHitEndpoint = Constants.NETWORK_MAP.Guards.FOREST_HIT,
        localPlayer = LocalPlayer,
        logger = context.logger,
        network = Network,
        onRecovered = function()
            if navigator then
                navigator:resume()
            end
        end,
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
        isIndexed = isIndexed,
        localPlayer = LocalPlayer,
        plotCmds = PlotCmds,
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
    local guardConfigs = {}
    local guardModels = {}
    local objects = Workspace:FindFirstChild("__OBJECTS")
    local areas = objects and objects:FindFirstChild("Areas")
    local guardAreas = areas and areas:FindFirstChild("GuardAreas")
    local separationLine = areas and areas:FindFirstChild("SeparationLine")
    for areaId, config in pairs(require(ReplicatedStorage.Directory.Guards).Directory) do
        guardConfigs[areaId] = config
        local area = guardAreas and guardAreas:FindFirstChild(areaId)
        local guard = area and area:FindFirstChild("Guard")
        if guard and guard:IsA("Model") then
            guardModels[areaId] = guard
        end
    end
    local function nativeEscapePosition(record)
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local area = guardAreas and guardAreas:FindFirstChild(record.AreaId)
        local bounds = area and area:FindFirstChild("Bounds")
        if
            not root
            or not root:IsA("BasePart")
            or not bounds
            or not bounds:IsA("BasePart")
            or not separationLine
            or not separationLine:IsA("BasePart")
        then
            return nil
        end
        local direction = -separationLine.CFrame.LookVector
        local ok, distance = pcall(
            GuardEscapePrediction.ResolveExitDistance,
            bounds.CFrame,
            bounds.Size,
            root.Position,
            direction
        )
        return ok and root.Position + direction * (distance + 18) or nil
    end
    local function canOutrunGuard(areaId, playerSpeed)
        local config = guardConfigs[areaId]
        local guard = guardModels[areaId]
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local area = guardAreas and guardAreas:FindFirstChild(areaId)
        local bounds = area and area:FindFirstChild("Bounds")
        if
            not config
            or not guard
            or not guard.Parent
            or not root
            or not root:IsA("BasePart")
            or not bounds
            or not bounds:IsA("BasePart")
            or not separationLine
            or not separationLine:IsA("BasePart")
        then
            return nil
        end
        local direction = -separationLine.CFrame.LookVector
        local distanceOk, exitDistance = pcall(
            GuardEscapePrediction.ResolveExitDistance,
            bounds.CFrame,
            bounds.Size,
            root.Position,
            direction
        )
        if not distanceOk then
            return nil
        end
        local predictionOk, prediction = pcall(GuardEscapePrediction.Resolve, {
            BaseGuardWalkSpeed = config.WalkSpeed,
            ExitDirection = direction,
            ExitDistance = exitDistance,
            FlatRadius = config.FlatRadius,
            GuardStartPosition = guard:GetPivot().Position,
            HitDistance = config.HitDistance or 10,
            PlayerStartPosition = root.Position,
            PlayerWalkSpeed = playerSpeed,
        })
        if not predictionOk then
            return nil
        end
        if prediction.Outcome == "EscapedSafely" or prediction.CatchTime == nil then
            return true
        end
        return prediction.CatchTime - prediction.ExitTime >= readPing() / 1000
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
        canOutrun = canOutrunGuard,
        eggCmds = EggCmds,
        getPing = currentPing,
        guardConfigs = guardConfigs,
        guardModels = guardModels,
        localPlayer = LocalPlayer,
        onEscape = function()
            if navigator then
                navigator:resume()
            end
        end,
        runService = RunService,
        wakingDuration = GuardChasePolicy.GetWakingDuration(),
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
    local requestHttp = context.httpGet
        or function(url)
            local request = environment.request or environment.http_request
            if type(request) == "function" then
                local response = request({ Method = "GET", Url = url })
                assert(
                    type(response) == "table" and type(response.Body) == "string",
                    "HTTP request failed"
                )
                return response.Body
            end
            return game:HttpGet(url, true)
        end
    local serverHop = ServerHop.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        httpGet = requestHttp,
        jobId = context.jobId,
        localPlayer = LocalPlayer,
        logger = context.logger,
        maxPlayers = context.players.MaxPlayers,
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
        table.clear(gameRuntime.farmHistory.globalSpawns)
        persistVisitedServers()
        persistFarmHistory()
    end)
    local function treadmillBottom()
        local plot = PlotCmds.GetPlotData()
        local bottom = plot and plot.PlotFolder:FindFirstChild("TreadmillBottom")
        return bottom and bottom:IsA("BasePart") and bottom or nil
    end
    local function idleTreadmillPosition()
        local bottom = treadmillBottom()
        return bottom and bottom.Position or nil
    end
    local function isOnTreadmill()
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local bottom = treadmillBottom()
        if not root or not root:IsA("BasePart") or not bottom then
            return false
        end
        local position = bottom.CFrame:PointToObjectSpace(root.Position)
        return math.abs(position.X) <= bottom.Size.X * 0.5 + 2
            and math.abs(position.Z) <= bottom.Size.Z * 0.5 + 2
            and math.abs(position.Y) <= 8
    end
    navigator = WalkNavigator.new({
        blockedParts = { treadmillBottom() },
        localPlayer = LocalPlayer,
        pathfindingService = PathfindingService,
        runService = RunService,
        workspace = Workspace,
    })
    local autoFarm
    local autoBlossom
    local blossomSelected = false
    autoBlossom = AutoBlossom.new({
        batAttribute = Sakura.BatToolAttribute,
        canFarm = function()
            local save = Save.Get()
            return save ~= nil and save.Sakura ~= nil and save.Sakura.Unlocked == true
        end,
        collectionService = CollectionService,
        hitCooldown = Sakura.Bloom.HitCooldownSeconds,
        hitRange = Sakura.Bloom.HitRange,
        localPlayer = LocalPlayer,
        navigator = navigator,
        onWorkChanged = function(working)
            if not autoFarm then
                return
            end
            if working and autoFarm:hasPriorityTarget() then
                autoBlossom:setEnabled(false)
                autoFarm:setPaused(false)
                return
            end
            autoFarm:setPaused(working)
        end,
        treeTag = Sakura.TreeTag,
    })
    autoFarm = AutoFarm.new({
        assets = Assets,
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        logger = context.logger,
        getEscapePosition = nativeEscapePosition,
        getIdlePosition = idleTreadmillPosition,
        getResetSeconds = resetSecondsRemaining,
        getSecuredEggs = securedEggs,
        hasMissingIndex = hasMissingIndex,
        isGlobalSpawnKnown = isGlobalSpawnKnown,
        isIndexed = isIndexed,
        isIndexPending = isIndexPending,
        isOnTreadmill = isOnTreadmill,
        leaveTreadmill = function()
            return Network.Invoke(Constants.NETWORK_MAP.Treadmills.REQUEST_UNEQUIP)
        end,
        markGlobalSpawn = markGlobalSpawn,
        navigator = navigator,
        onRareAvailable = function()
            autoBlossom:setEnabled(false)
            autoFarm:setPaused(false)
        end,
        onSecured = recordSecuredEgg,
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
        shouldRunBlossom = function()
            if not blossomSelected or not autoBlossom:hasWork() then
                return false
            end
            autoBlossom:setEnabled(true)
            return true
        end,
        slotIdentity = SlotIdentity,
        workspace = Workspace,
    })
    local inventoryUids = {}
    for uid in pairs((Save.Get() and Save.Get().Inventory) or {}) do
        inventoryUids[uid] = true
    end
    local equipBestQueued = false
    local inventoryConnection = Save.GetStatChangedSignal("Inventory"):Connect(function()
        local nextUids = {}
        local added = false
        for uid in pairs((Save.Get() and Save.Get().Inventory) or {}) do
            nextUids[uid] = true
            added = added or inventoryUids[uid] ~= true
        end
        inventoryUids = nextUids
        if not added or equipBestQueued or stopped then
            return
        end
        equipBestQueued = true
        task.defer(function()
            if not stopped then
                pcall(Network.Invoke, Constants.NETWORK_MAP.Backpack.EQUIP_BEST)
            end
            equipBestQueued = false
        end)
    end)
    local unsubscribePing = context.subscribeFooterMetric("ping", {
        kind = "latency",
        label = "Ping",
    }, readPing)
    local function apply(state)
        local farming = state.settings.autoFarm == true
        blossomSelected = farming and state.settings.autoBlossom == true
        if gameRuntime.farmHistory.active ~= farming then
            if farming then
                table.clear(gameRuntime.farmHistory.eggs)
                table.clear(gameRuntime.farmHistory.globalSpawns)
            end
            gameRuntime.farmHistory.active = farming
            persistFarmHistory()
        end
        antiHit:setEnabled(state.settings.antiHit == true or farming)
        antiTrap:setEnabled(state.settings.antiTrap == true or farming)
        autoOpenEggs:setCompleteIndex(farming and state.settings.autoFarmIndex == true)
        autoOpenEggs:setEnabled(
            state.settings.autoOpenEggs == true
                or (farming and state.settings.autoFarmIndex == true)
        )
        highlightEsp:setAntiTrapEnabled(state.settings.antiTrap == true or farming)
        highlightEsp:setMinimumRarity(state.settings.eggEspMinimumRarity)
        highlightEsp:setMinimumSize(state.settings.eggEspMinimumSize)
        highlightEsp:setEggsEnabled(state.settings.eggEsp == true)
        highlightEsp:setTrapsEnabled(state.settings.trapEsp == true)
        hitAura:setIgnoreFriends(not farming and state.settings.hitAuraIgnoreFriends == true)
        hitAura:setEnabled(state.settings.hitAura == true or farming)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
        lagSafeMovement:setPingThreshold(state.settings.serverHopMaxPing)
        lagSafeMovement:setEnabled(
            (state.settings.antiHit == true or farming) and state.settings.lagSafeMovement == true
        )
        autoFarm:setIdleTreadmill(state.settings.idleTreadmill)
        autoFarm:setTargetRarities(state.settings.autoFarmEternal, state.settings.autoFarmSecret)
        autoFarm:setCompleteIndex(state.settings.autoFarmIndex)
        autoFarm:setServerHopping(state.settings.autoFarmServerHopping)
        autoFarm:setTargetPopulation(state.settings.serverHopTargetPopulation)
        autoFarm:setMaxPing(state.settings.serverHopMaxPing)
        autoFarm:setEnabled(farming)
        autoBlossom:setEnabled(blossomSelected and not autoFarm:hasPriorityTarget())
        if state.settings.serverHop == true then
            context.store:Patch({
                settings = {
                    serverHop = false,
                    serverHopAttempts = 0,
                    serverHopPingGuard = true,
                },
            })
            context.settingsChanged(context.store:Get().settings)
            serverHop:run(
                state.settings.serverHopMaxPing,
                nil,
                nil,
                state.settings.serverHopTargetPopulation
            )
        end
    end
    local unsubscribe = context.store:Subscribe(apply, false)
    local function stop()
        if stopped then
            return
        end
        stopped = true
        pcall(unsubscribe)
        pcall(unsubscribePing)
        pcall(resetConnection.Disconnect, resetConnection)
        pcall(inventoryConnection.Disconnect, inventoryConnection)
        pcall(antiHit.stop, antiHit)
        pcall(antiTrap.stop, antiTrap)
        pcall(autoBlossom.stop, autoBlossom)
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
        local ping = readPing()
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
