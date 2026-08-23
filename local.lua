local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local bootStartedAt = os.clock()
local teleportBootstrap = environment.UniversalHubTeleportBootstrap == true
environment.UniversalHubTeleportBootstrap = nil
local jobId = game.JobId
local activeFlight = environment.UniversalHubLoaderFlight
if type(activeFlight) == "table" and activeFlight.jobId == jobId then
    return
end

local owner = {}
environment.UniversalHubLoaderFlight = {
    jobId = jobId,
    owner = owner,
}

local function ownsFlight()
    local current = environment.UniversalHubLoaderFlight
    return type(current) == "table" and current.owner == owner
end

local function releaseFlight()
    if ownsFlight() then
        environment.UniversalHubLoaderFlight = nil
    end
end

local configuration

local function hideStaleMenu()
    if type(gethui) ~= "function" then return end
    local succeeded, hiddenUi = pcall(gethui)
    local staleMenu = succeeded and hiddenUi and hiddenUi:FindFirstChild("UniversalHubNative")
    if staleMenu then
        pcall(function()
            staleMenu.Enabled = false
        end)
    end
end

if teleportBootstrap then hideStaleMenu() end

local function loadWorkspaceModule(path, chunkName)
    if type(loadfile) == "function" then
        local chunk, compileError = loadfile(path, chunkName or path)
        return assert(chunk, compileError)()
    end
    local chunk, compileError = loadstring(readfile(path), chunkName or path)
    return assert(chunk, compileError)()
end

local function loadCompiledMenu()
    local Menu = loadWorkspaceModule(configuration.MenuPath, "ui/dist/Menu.lua")
    assert(
        type(Menu) == "table" and type(Menu.mountUniversalHubMenu) == "function",
        "Universal Hub requires the compiled Prism menu"
    )
    configuration.Menu = Menu
    return Menu
end

local function loadHub()
    local timing = configuration.BootTiming
    local phaseStartedAt = os.clock()
    loadCompiledMenu()
    timing.menuSeconds = os.clock() - phaseStartedAt

    phaseStartedAt = os.clock()
    local Limn = loadWorkspaceModule(configuration.LimnPath, "limn/dist/Limn.lua")
    assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")
    timing.limnSeconds = os.clock() - phaseStartedAt

    phaseStartedAt = os.clock()
    local helpersPath = configuration.HydroxideRoot .. "/modules/Helpers.lua"
    local Helpers = loadWorkspaceModule(helpersPath, "hydroxide/modules/Helpers.lua")
    assert(
        type(Helpers) == "table" and type(Helpers.load) == "function",
        "Universal Hub requires Hydroxide Helpers.load"
    )
    timing.hydroxideSeconds = os.clock() - phaseStartedAt

    configuration.Limn = Limn
    configuration.HydroxideHelpers = Helpers
    if not ownsFlight() then
        return
    end

    timing.preInitSeconds = os.clock() - timing.startedAt
    return loadWorkspaceModule(configuration.LocalRoot .. "/init.lua", "universal-hub/init.lua")
end

local function waitForNativeGameReady()
    if game.GameId ~= 6035872082 then return end
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
    local deadline = os.clock() + (teleportBootstrap and 30 or 3)
    while loadingScreen == nil and os.clock() < deadline do
        RunService.Heartbeat:Wait()
        loadingScreen = playerGui:FindFirstChild("LoadingScreen")
    end
    if loadingScreen == nil then
        assert(not teleportBootstrap, "RIVALS native loading screen readiness was not observed")
        return
    end
    hideStaleMenu()
    while loadingScreen.Parent ~= nil and loadingScreen.Enabled == true do
        RunService.Heartbeat:Wait()
    end
    -- Let RIVALS finish the controller callbacks scheduled by the same state change.
    RunService.Heartbeat:Wait()
    RunService.Heartbeat:Wait()
end

local function completeBootstrap()
    if not ownsFlight() then
        return
    end

    local succeeded, result = pcall(function()
        waitForNativeGameReady()
        return loadHub()
    end)
    releaseFlight()
    if not succeeded then
        error(result, 0)
    end
    return result
end

local function startBootstrap()
    configuration = environment.UniversalHubConfig or {}
    configuration.BootTiming = {
        mode = "local",
        startedAt = bootStartedAt,
    }
    configuration.TeleportBootstrap = teleportBootstrap
    configuration.LocalRoot = configuration.LocalRoot or "universal-hub/local"
    configuration.HydroxideRoot = configuration.HydroxideRoot or "hydroxide/local"
    configuration.LimnPath = configuration.LimnPath or "limn/dist/Limn.lua"
    configuration.MenuPath = configuration.MenuPath
        or (configuration.LocalRoot .. "/ui/dist/Menu.lua")
    local menuStampPath = configuration.MenuPath:gsub("%.lua$", ".provenance")
    if type(isfile) ~= "function" or not isfile(menuStampPath) then
        menuStampPath = configuration.MenuPath
    end
    configuration.MenuStampPath = menuStampPath
    configuration.ReloadMenu = loadCompiledMenu
    if type(configuration.RivalsAutoCounterTest) ~= "table" then
        configuration.RivalsAutoCounterTest = {
            enabled = false,
            holdDuration = 0.45,
            startDelay = 0.25,
            verticalOffset = 1000,
        }
    end
    configuration.HotReload = configuration.HotReload ~= false
    local importCache = {}
    configuration.Forget = function(path)
        importCache[path] = nil
    end
    configuration.Import = function(path)
        assert(
            type(path) == "string"
                and path:match("^[%w_/%-]+$") ~= nil
                and not path:find("//", 1, true),
            "Invalid local hub module path"
        )
        if importCache[path] ~= nil then
            return importCache[path]
        end
        local file = path .. ".lua"
        local source = readfile(configuration.LocalRoot .. "/" .. file)
        local chunk, compileError = loadstring(source, file)
        local result = assert(chunk, compileError)()
        importCache[path] = result
        return result
    end
    local hydroxideModules = {
        ["modules/Closure"] = true,
        ["modules/Lifecycle"] = true,
        ["modules/Targeting"] = true,
    }
    local hydroxideCache = {}
    configuration.HydroxideImport = function(path)
        assert(hydroxideModules[path] == true, "Unknown Hydroxide helper module: " .. tostring(path))
        if hydroxideCache[path] ~= nil then
            return hydroxideCache[path]
        end
        local file = path .. ".lua"
        local source = readfile(configuration.HydroxideRoot .. "/" .. file)
        local chunk, compileError = loadstring(source, "hydroxide/" .. file)
        local result = assert(chunk, compileError)()
        hydroxideCache[path] = assert(result, "Hydroxide helper module returned nil: " .. path)
        return hydroxideCache[path]
    end
    environment.UniversalHubConfig = configuration

    local synapse = environment.syn
    local queue = type(environment.queue_on_teleport) == "function"
            and environment.queue_on_teleport
        or type(environment.queueonteleport) == "function" and environment.queueonteleport
        or type(synapse) == "table" and type(synapse.queue_on_teleport) == "function"
            and synapse.queue_on_teleport
    if queue then
        pcall(queue, ([[
getgenv().UniversalHubTeleportBootstrap = true
local path = %q
local chunk, compileError = loadstring(readfile(path), path)
assert(chunk, compileError)()
]]):format(configuration.LocalRoot .. "/local.lua", configuration.LocalRoot .. "/local.lua"))
    end

    if not game:IsLoaded() then
        task.spawn(function()
            local succeeded, result = pcall(function()
                game.Loaded:Wait()
                return completeBootstrap()
            end)
            if not succeeded then
                releaseFlight()
                error(result, 0)
            end
            return result
        end)
        return
    end

    return completeBootstrap()
end

local succeeded, result = pcall(startBootstrap)
if not succeeded then
    releaseFlight()
    error(result, 0)
end
return result
