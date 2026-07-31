local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local root = configuration.LocalRoot or "universal-hub/local"
local cache = {}

local function import(path)
    if cache[path] ~= nil then
        return cache[path]
    end

    local result
    if configuration.Import then
        result = configuration.Import(path)
    else
        local source = readfile(root .. "/" .. path .. ".lua")
        local chunk, compileError = loadstring(source, path .. ".lua")
        result = assert(chunk, compileError)()
    end
    cache[path] = result
    return result
end

local function copyData(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[copyData(key)] = copyData(child)
    end
    return copy
end

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Store = import("modules/Store")
local Config = import("modules/Config")
local InputCapture = import("modules/InputCapture")
local MenuToggle = import("modules/MenuToggle")
local Registry = import("modules/Registry")
local Session = import("modules/Session")
local Overlay = import("modules/Overlay")
local Catalog = import("games/Catalog")

local registry = Registry.new()
for _, definitionPath in ipairs(Catalog) do
    registry:Register(import(definitionPath))
end

local adapterDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    adapterDefinition,
    ("Universal Hub does not support game %s / place %s"):format(tostring(game.GameId), tostring(game.PlaceId))
)
local adapterModule = import(adapterDefinition.module)
assert(type(adapterModule) == "table" and type(adapterModule.new) == "function", "Invalid game adapter module")
local features = adapterDefinition.features

local Limn = assert(configuration.Limn, "Universal Hub loader must stage Limn before init")
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")
local Helpers =
    assert(configuration.HydroxideHelpers, "Universal Hub loader must stage Hydroxide Helpers before init")
local hydroxideImport =
    assert(configuration.HydroxideImport, "Universal Hub loader must stage a Hydroxide importer before init")
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)
local helpers = Helpers.load({
    import = hydroxideImport,
    modules = adapterDefinition.hydroxide or {},
})
for _, name in ipairs(adapterDefinition.hydroxide or {}) do
    assert(type(helpers[name]) == "table", "Missing Hydroxide helper module: " .. tostring(name))
end

Session.stopPrevious(environment)
local drawingRuntime = Limn.new({
    Drawing = Drawing,
    DrawingImmediate = DrawingImmediate,
    Vector2 = Vector2,
    Input = {
        MapPosition = function(position)
            local topLeftInset = GuiService:GetGuiInset()
            return position + topLeftInset
        end,
        -- The visible menu intentionally sinks pointer input before Limn receives it.
        Processed = "allow",
    },
})
configuration.Limn = nil
configuration.HydroxideHelpers = nil
configuration.HydroxideImport = nil

local configPath = configuration.ConfigPath or ("universal-hub/configs/%s.json"):format(adapterDefinition.id)
local configStore = Config.new({
    decode = function(source)
        return HttpService:JSONDecode(source)
    end,
    encode = function(value)
        return HttpService:JSONEncode(value)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    path = configPath,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
local settings = configStore:load(copyData(adapterDefinition.defaults))
local hasPersistedConfig = type(isfile) == "function" and isfile(configPath)
if not hasPersistedConfig then
    for name, value in pairs(environment.UniversalHubSettings or {}) do
        if settings[name] ~= nil then
            settings[name] = value
        end
    end
end

local townCheckpoint
if adapterDefinition.id == "town" then
    local TownCheckpointStore = import("games/town/CheckpointStore")
    townCheckpoint = TownCheckpointStore.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        deleteFile = type(delfile) == "function" and delfile or nil,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        isFile = type(isfile) == "function" and isfile or nil,
        listFiles = type(listfiles) == "function" and listfiles or nil,
        makeFolder = type(makefolder) == "function" and makefolder or nil,
        readFile = type(readfile) == "function" and readfile or nil,
        root = configuration.TownCopyCheckpointRoot or "universal-hub/private/town-copy",
        userId = LocalPlayer.UserId,
        writeFile = type(writefile) == "function" and writefile or nil,
    })
    if townCheckpoint.available then
        pcall(function()
            townCheckpoint:prune()
        end)
    end
end

local startupCleanups = {}
local function ownStartup(cleanup)
    table.insert(startupCleanups, cleanup)
end
local function failStartup(message)
    for index = #startupCleanups, 1, -1 do
        pcall(startupCleanups[index])
    end
    table.clear(startupCleanups)
    error(message, 0)
end

local initialState = copyData(adapterDefinition.initialState)
initialState.settings = settings
initialState.status = ("Loading %s"):format(adapterDefinition.label)
local store = Store.new(initialState)
ownStartup(function()
    store:Destroy()
end)
environment.UniversalHubSettings = store:Get().settings

local session
local overlay
local adapter
local inputCaptureCreated, inputCaptureResult = pcall(InputCapture.new, {
    releaseMouseOnDisable = adapterDefinition.id == "town",
})
if not inputCaptureCreated then
    failStartup(inputCaptureResult)
end
local inputCapture = inputCaptureResult
ownStartup(function()
    inputCapture:Destroy()
end)
local thirdPersonState

local function setInputCaptured(captured)
    inputCapture:SetEnabled(captured)
end

local function setThirdPerson(enabled)
    if enabled then
        if not thirdPersonState then
            thirdPersonState = {
                cameraMode = LocalPlayer.CameraMode,
                maximumZoom = LocalPlayer.CameraMaxZoomDistance,
                minimumZoom = LocalPlayer.CameraMinZoomDistance,
            }
        end
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMaxZoomDistance = 12
        LocalPlayer.CameraMinZoomDistance = 8
    elseif thirdPersonState then
        LocalPlayer.CameraMode = thirdPersonState.cameraMode
        LocalPlayer.CameraMaxZoomDistance = thirdPersonState.maximumZoom
        LocalPlayer.CameraMinZoomDistance = thirdPersonState.minimumZoom
        thirdPersonState = nil
    end
end

local adapterCapabilities = type(adapterModule.capabilitiesFor) == "function"
        and adapterModule.capabilitiesFor({
            fireTouchInterestAvailable = type(environment.firetouchinterest) == "function",
            gameId = game.GameId,
            placeId = game.PlaceId,
        }, features.capabilities)
    or features.capabilities
local overlayCreated, overlayResult = pcall(Overlay.new, {
    capabilities = adapterCapabilities,
    cosmetics = features.cosmetics,
    cycleGlove = function(direction)
        adapter:cycleGlove(direction)
    end,
    gameLabel = adapterDefinition.label,
    getCamera = function()
        return Workspace.CurrentCamera
    end,
    listPlotOwners = function()
        if adapter and type(adapter.listPlotOwners) == "function" then
            return adapter:listPlotOwners()
        end
        return {}
    end,
    copyPlot = function(ownerName, saveName)
        if not adapter or type(adapter.copyPlot) ~= "function" then
            return false, "Plot copying is not ready"
        end
        task.spawn(function()
            adapter:copyPlot(ownerName, saveName)
        end)
        return true
    end,
    cancelPlotCopy = function()
        if adapter and type(adapter.cancelCopy) == "function" then
            task.spawn(function()
                adapter:cancelCopy()
            end)
            return true
        end
        return false, "Plot copy cancellation is not ready"
    end,
    confirmPlotCopy = function()
        if adapter and type(adapter.confirmCopy) == "function" then
            task.spawn(function()
                adapter:confirmCopy()
            end)
            return true
        end
        return false, "Plot copy confirmation is not ready"
    end,
    discardPlotCopy = function()
        if adapter and type(adapter.discardCopy) == "function" then
            task.spawn(function()
                adapter:discardCopy()
            end)
            return true
        end
        return false, "Plot copy discard is not ready"
    end,
    resumePlotCopy = function()
        if adapter and type(adapter.resumeCopy) == "function" then
            task.spawn(function()
                adapter:resumeCopy()
            end)
            return true
        end
        return false, "Plot copy resume is not ready"
    end,
    retryPlotCopyCleanup = function()
        if adapter and type(adapter.retryCopyCleanup) == "function" then
            task.spawn(function()
                adapter:retryCopyCleanup()
            end)
            return true
        end
        return false, "Plot copy cleanup is not ready"
    end,
    cleanupPlotCopyCheckpoint = function()
        if adapter and type(adapter.cleanupCopyCheckpoint) == "function" then
            task.spawn(function()
                adapter:cleanupCopyCheckpoint()
            end)
            return true
        end
        return false, "Local copy recovery cleanup is not ready"
    end,
    reportPlotCopyError = function(message)
        store:Patch({
            plotCopy = {
                active = false,
                confirmedProgress = 0,
                context = message,
                error = message,
                phase = "Copy blocked",
                state = "error",
            },
        })
    end,
    uiParent = (function()
        local success, parent = pcall(function()
            if type(gethui) == "function" then
                return gethui()
            end
            return game:GetService("CoreGui")
        end)
        return success and parent or nil
    end)(),
    optionLabels = features.optionLabels,
    inputService = UserInputService,
    limn = drawingRuntime,
    setFov = function(value, persist)
        session:setFov(value, persist)
    end,
    setCosmeticsOpen = function(open)
        session:setCosmeticsOpen(open)
    end,
    setCosmeticMode = function(mode)
        session:setCosmeticMode(mode)
    end,
    setInputCaptured = setInputCaptured,
    setMenuVisible = function(visible)
        session:setMenuVisible(visible)
    end,
    setOption = function(name, enabled)
        session:setOption(name, enabled)
        if enabled and features.exclusiveOptions then
            for _, excluded in ipairs(
                features.exclusiveOptions[name] or {}
            ) do
                session:setOption(excluded, false)
            end
        end
    end,
    setRate = function(name, value, persist)
        session:setRate(name, value, persist)
    end,
    cycleSkin = function(direction)
        adapter:cycleSkin(direction)
    end,
    cycleCosmeticWeapon = function(direction)
        adapter:cycleCosmeticWeapon(direction)
    end,
    resetSkin = function()
        adapter:resetSkin()
    end,
    resetGlove = function()
        adapter:resetGlove()
    end,
    setGloveWear = function(alpha)
        adapter:setGloveWear(alpha)
    end,
    setGloveColor = function(color)
        adapter:setGloveColor(color)
    end,
    setWear = function(alpha)
        adapter:setWear(alpha)
    end,
    toggleStatTrak = function()
        adapter:toggleStatTrak()
    end,
    store = store,
})
if not overlayCreated then
    failStartup(overlayResult)
end
overlay = overlayResult
ownStartup(function()
    overlay:destroy()
end)

local created, result = pcall(adapterModule.new, {
    aimClick = mouse2click,
    aimPress = mouse2press,
    aimRelease = mouse2release,
    click = mouse1click,
    fireTouchInterest = type(environment.firetouchinterest) == "function"
            and environment.firetouchinterest
        or nil,
    press = mouse1press,
    release = mouse1release,
    gcObjects = function()
        return getgc(true)
    end,
    getLoadedModules = type(environment.getloadedmodules) == "function"
            and environment.getloadedmodules
        or nil,
    hookFunction = hookfunction,
    isInputCaptured = function()
        return inputCapture:IsEnabled()
    end,
    isFireHeld = function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end,
    isJumpHeld = function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end,
    movementDirection = function()
        local horizontal = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local forward = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
        if horizontal == 0 and forward == 0 then
            return Vector3.new(0, 0, 0)
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return Vector3.new(0, 0, 0)
        end
        local look = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local direction = Vector3.new(right.X, 0, right.Z) * horizontal
            + Vector3.new(look.X, 0, look.Z) * forward
        return direction.Magnitude > 1 and direction.Unit or direction
    end,
    limn = drawingRuntime,
    capabilities = adapterCapabilities,
    oh = helpers,
    render = function(observations, mousePosition, utilityObservations)
        overlay:render(observations, mousePosition, utilityObservations)
    end,
    restoreFunction = restorefunction,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    setThirdPerson = setThirdPerson,
    checkpoint = townCheckpoint,
    gameId = game.GameId,
    generateGuid = function()
        return HttpService:GenerateGUID(false)
    end,
    localPlayer = LocalPlayer,
    jobId = game.JobId,
    now = os.time,
    placeId = game.PlaceId,
    players = Players,
    store = store,
    wait = task.wait,
    workspace = Workspace,
})
if not created then
    failStartup(result)
end
adapter = result
ownStartup(function()
    if type(adapter.stop) == "function" then
        adapter:stop()
    end
end)
if type(adapter.inspectCopyRecovery) == "function" then
    local recovered, _recoveryError = pcall(function()
        adapter:inspectCopyRecovery()
    end)
    if not recovered then
        store:Patch({
            plotCopy = {
                active = false,
                context = "Recovery inspection failed before any Town mutation",
                error = "Persistent copy recovery could not be inspected",
                phase = "Copy blocked",
                state = "error",
            },
        })
    end
end

local sessionCreated, sessionResult = pcall(Session.new, {
    adapter = adapter,
    environment = environment,
    inputCapture = inputCapture,
    overlay = overlay,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    store = store,
})
if not sessionCreated then
    failStartup(sessionResult)
end
session = sessionResult
table.clear(startupCleanups)
local finalized, finalError = pcall(function()
    session.adapterId = adapterDefinition.id
    session.game = adapterDefinition.label
    session.registry = registry
    session.state = store:Get()
    session.store = store
    local menuToggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
        if MenuToggle.shouldToggle(input, gameProcessedEvent, UserInputService) then
            session:toggleMenu()
        end
    end)
    session:Add(function()
        menuToggleConnection:Disconnect()
    end)

    local readyStatus = ("%s ready"):format(adapterDefinition.label)
    store:Patch({ status = readyStatus })
    print("[Universal Hub]", readyStatus)
end)
if not finalized then
    session:stop()
    error(finalError, 0)
end
return session
