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

local function extend(target, additions)
    for key, value in pairs(additions or {}) do
        assert(target[key] == nil, "Composition must not replace shared context: " .. tostring(key))
        target[key] = value
    end
    return target
end

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local NativeVisualPolicy = import("modules/NativeVisualPolicy")
local NativeWorldRenderer = import("modules/NativeWorldRenderer")
local WorldRenderer = import("modules/WorldRenderer")
local NativeMenu = import("modules/NativeMenu")
local HubView = import("modules/HubView")
local PresentationCatalog = import("modules/presentation/Catalog")
local PresentationHost = import("modules/PresentationHost")
local PresentationRuntime = import("modules/presentation/Runtime")
local StandardPanels = import("modules/presentation/StandardPanels")
local CosmeticsPanel = import("modules/presentation/CosmeticsPanel")
local Compatibility = import("games/Compatibility")
local Catalog = import("games/Catalog")

local registry = Registry.new()
for _, definitionPath in ipairs(Catalog) do
    registry:Register(Compatibility.Compose(import(definitionPath)))
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
local presentation = import(adapterDefinition.presentation)
local features = adapterDefinition.features
local compositionModule
local compositionDependencies = {}
if adapterDefinition.composition then
    compositionModule = import(adapterDefinition.composition)
    assert(
        type(compositionModule) == "table" and type(compositionModule.bind) == "function",
        "Invalid game composition module"
    )
    local declaredSources = {}
    for _, path in ipairs(adapterDefinition.sources) do
        declaredSources[path] = true
    end
    local dependencyNames = {}
    for name, path in pairs(compositionModule.dependencies or {}) do
        assert(type(name) == "string" and name ~= "", "Composition dependency names must be strings")
        assert(
            type(path) == "string" and declaredSources[path],
            "Composition dependency must be declared by the selected definition"
        )
        table.insert(dependencyNames, name)
    end
    table.sort(dependencyNames)
    for _, name in ipairs(dependencyNames) do
        compositionDependencies[name] = import(compositionModule.dependencies[name])
    end
end

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

local session
local overlay
local adapter
local store
local function noAfterAdapter(_adapter) end
local composition = {
    adapter = {},
    afterAdapter = noAfterAdapter,
    inputCapture = {
        releaseMouseOnDisable = false,
    },
    overlay = {},
}
if compositionModule then
    composition = compositionModule.bind({
        config = function(name, fallback)
            local value = configuration[name]
            return value == nil and fallback or value
        end,
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        files = {
            delete = type(delfile) == "function" and delfile or nil,
            isFile = type(isfile) == "function" and isfile or nil,
            list = type(listfiles) == "function" and listfiles or nil,
            makeFolder = type(makefolder) == "function" and makefolder or nil,
            read = type(readfile) == "function" and readfile or nil,
            write = type(writefile) == "function" and writefile or nil,
        },
        getAdapter = function()
            return adapter
        end,
        getStore = function()
            return store
        end,
        spawn = task.spawn,
        userId = LocalPlayer.UserId,
    }, compositionDependencies)
    assert(type(composition) == "table", "Game composition must return a table")
    assert(
        composition.adapter == nil or type(composition.adapter) == "table",
        "Game composition adapter context must be a table"
    )
    assert(
        composition.inputCapture == nil or type(composition.inputCapture) == "table",
        "Game composition input context must be a table"
    )
    assert(
        composition.overlay == nil or type(composition.overlay) == "table",
        "Game composition overlay context must be a table"
    )
    assert(
        composition.afterAdapter == nil or type(composition.afterAdapter) == "function",
        "Game composition afterAdapter must be a function"
    )
    composition.adapter = composition.adapter or {}
    composition.afterAdapter = composition.afterAdapter or noAfterAdapter
    composition.inputCapture = composition.inputCapture or {}
    composition.overlay = composition.overlay or {}
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
if settings.taskAutomationPaused == false then
    initialState.menuVisible = false
end
store = Store.new(initialState)
ownStartup(function()
    store:Destroy()
end)
environment.UniversalHubSettings = store:Get().settings

local inputCaptureCreated, inputCaptureResult = pcall(InputCapture.new, {
    releaseMouseOnDisable = composition.inputCapture.releaseMouseOnDisable == true,
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

local adapterCapabilityContext = {
    fireTouchInterestAvailable = type(environment.firetouchinterest) == "function",
    hookFunctionAvailable = type(hookfunction) == "function",
    restoreFunctionAvailable = type(restorefunction) == "function",
    gameId = game.GameId,
    placeId = game.PlaceId,
}
if type(adapterModule.capabilityContext) == "function" then
    local succeeded, nativeContext = pcall(adapterModule.capabilityContext)
    if succeeded and type(nativeContext) == "table" then
        extend(adapterCapabilityContext, nativeContext)
    end
end
local adapterCapabilities = type(adapterModule.capabilitiesFor) == "function"
        and adapterModule.capabilitiesFor(adapterCapabilityContext, features.capabilities)
    or features.capabilities
local function customAsset(path)
    if type(getcustomasset) ~= "function" or type(isfile) ~= "function" or not isfile(path) then
        return nil
    end
    local succeeded, asset = pcall(getcustomasset, path)
    return succeeded and asset or nil
end
local brandIcon = customAsset(root .. "/assets/brand/universal-hub.png")
local gameIcon = customAsset(root .. "/assets/games/" .. adapterDefinition.id .. ".png")
local enemyAudienceIcon = customAsset(root .. "/assets/icons/enemies.png")
local allyAudienceIcon = customAsset(root .. "/assets/icons/allies.png")
local alphaCheckerboard = customAsset(root .. "/assets/ui/alpha-checkerboard.png")
local pageIcons = {}
for page, file in pairs({ Combat = "combat.png", Movement = "movement.png", Visuals = "visuals.png", Tools = "tools.png", Settings = "settings.png" }) do
    pageIcons[page] = customAsset(root .. "/assets/icons/" .. file)
end

local uiParent = (function()
    local success, parent = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return game:GetService("CoreGui")
    end)
    return success and parent or nil
end)()

local overlayContext = {
    capabilities = adapterCapabilities,
    nativeWorldSupported = table.find(adapterCapabilities, "worldRenderer") ~= nil,
    nativeVisualPolicy = NativeVisualPolicy,
    catalog = PresentationCatalog,
    cosmetics = features.cosmetics,
    nativeMenu = assert(configuration.NativeMenu, "Universal Hub loader must stage the native Prism menu"),
    worldOnly = true,
    gameLabel = adapterDefinition.label,
    getCamera = function()
        return Workspace.CurrentCamera
    end,
    uiParent = uiParent,
    guiParent = uiParent,
    players = Players,
    localPlayer = LocalPlayer,
    runService = RunService,
    brandIcon = brandIcon,
    gameIcon = gameIcon,
    enemyAudienceIcon = enemyAudienceIcon,
    allyAudienceIcon = allyAudienceIcon,
    alphaCheckerboard = alphaCheckerboard,
    optionLabels = features.optionLabels,
    pageIcons = pageIcons,
    presentation = presentation,
    presentationHost = PresentationHost,
    presentationParts = {
        cosmetics = CosmeticsPanel,
        standard = StandardPanels,
    },
    presentationRuntime = PresentationRuntime,
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
    setMenuKey = function(value)
        session:setMenuKey(value)
    end,
    setMenuVisible = function(visible)
        session:setMenuVisible(visible)
    end,
    setSetting = function(name, value, persist)
        session:setSetting(name, value, persist)
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
    store = store,
}
extend(overlayContext, composition.overlay)
local worldCreated, worldResult = pcall(function()
    local limnWorld = Overlay.new(overlayContext)
    local nativeCreated, nativeWorld = pcall(NativeWorldRenderer.new, overlayContext)
    if not nativeCreated then
        limnWorld:destroy()
        error(nativeWorld, 0)
    end
    return WorldRenderer.new(overlayContext, limnWorld, nativeWorld)
end)
if not worldCreated then
    failStartup(worldResult)
end
local worldOverlay = worldResult
overlayContext.optionSupport = worldOverlay.optionSupport
local menuCreated, menuResult = pcall(NativeMenu.new, overlayContext)
if not menuCreated then
    worldOverlay:destroy()
    failStartup(menuResult)
end
overlay = HubView.new(worldOverlay, menuResult)
ownStartup(function()
    overlay:destroy()
end)

local adapterContext = {
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
    keyPress = type(keypress) == "function" and keypress or nil,
    keyRelease = type(keyrelease) == "function" and keyrelease or nil,
    fireSignal = type(firesignal) == "function" and firesignal or nil,
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
    rivalsAutoCounterTest = configuration.RivalsAutoCounterTest,
    oh = helpers,
    render = function(observations, mousePosition, utilityObservations)
        overlay:render(observations, mousePosition, utilityObservations)
    end,
    restoreFunction = restorefunction,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    setThirdPerson = setThirdPerson,
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
    teleportBootstrap = configuration.TeleportBootstrap == true,
    wait = task.wait,
    workspace = Workspace,
}
extend(adapterContext, composition.adapter)
local created, result = pcall(adapterModule.new, adapterContext)
if not created then
    failStartup(result)
end
adapter = result
if type(worldOverlay.setPolicy) == "function" then
    worldOverlay:setPolicy(adapter.worldPolicy or {
        isPlayerEligible = adapter.isOpponent,
    })
end
ownStartup(function()
    if type(adapter.stop) == "function" then
        adapter:stop()
    end
end)
if composition.afterAdapter then
    composition.afterAdapter(adapter)
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
        local bindingSettled = os.clock() - (session.menuKeyChangedAt or -math.huge) > 0.2
        if bindingSettled and MenuToggle.shouldToggle(
            input,
            gameProcessedEvent,
            UserInputService,
            store:Get().settings.menuKey
        ) then
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
