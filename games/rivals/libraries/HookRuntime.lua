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

local ScopedAccuracy = importDependency("games/rivals/features/ScopedAccuracy", "../features/ScopedAccuracy")
local ShotPresentation = importDependency("games/rivals/features/ShotPresentation", "../features/ShotPresentation")
local HookRuntime = {}
HookRuntime.__index = HookRuntime

local function supports(capabilities, capability)
    return table.find(capabilities or {}, capability) ~= nil
end

local NullPresentation = {}
function NullPresentation:refreshHook() end
function NullPresentation:clear() end
function NullPresentation:update() return false end
function NullPresentation:getPresentedTarget() return nil end
function NullPresentation:stop() end

local NullScoped = {}
function NullScoped:refreshHook() end
function NullScoped:stop() end

function HookRuntime.new(options)
    local wantsShotAim = supports(options.capabilities, "shotAim")
    local wantsScoped = supports(options.capabilities, "alwaysScoped")
    if wantsShotAim or wantsScoped then
        assert(options.hookFunction, "enabled RIVALS hook features require hookfunction")
        assert(options.restoreFunction, "enabled RIVALS hook features require restorefunction")
    end
    local presentation = NullPresentation
    if wantsShotAim then
        presentation = ShotPresentation.new(options.shotPresentation)
    end
    local scoped = NullScoped
    if wantsScoped then
        scoped = ScopedAccuracy.new(options.scopedAccuracy)
    end
    return setmetatable({ presentation = presentation, scoped = scoped }, HookRuntime)
end

function HookRuntime:refresh()
    self.presentation:refreshHook()
    self.scoped:refreshHook()
end

function HookRuntime:stop()
    self.presentation:stop()
    self.scoped:stop()
end

return HookRuntime
