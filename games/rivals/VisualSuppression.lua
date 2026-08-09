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

local UtilityPolicy = importDependency("games/rivals/UtilityPolicy", "./UtilityPolicy")
local VisualSuppression = {}

local VISUAL_EFFECT_CLASSES = {
    Beam = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    Frame = true,
    ImageLabel = true,
    ParticleEmitter = true,
    Smoke = true,
}

local function effectStateProperty(instance)
    local supported = false
    if instance.IsA then
        for className in pairs(VISUAL_EFFECT_CLASSES) do
            if instance:IsA(className) then
                supported = true
                break
            end
        end
    end
    if not supported then
        return nil
    end
    local enabledOk, enabled = pcall(function() return instance.Enabled end)
    if enabledOk and type(enabled) == "boolean" then
        return "Enabled", enabled
    end
    local visibleOk, visible = pcall(function() return instance.Visible end)
    if visibleOk and type(visible) == "boolean" then
        return "Visible", visible
    end
    return nil
end

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        pcall(connection.Disconnect, connection)
    end
end

local function restore(instance, state, suppressed)
    disconnect(state.connection)
    local succeeded, current = pcall(function()
        return instance[state.property]
    end)
    if not succeeded or current ~= state.value then
        pcall(function()
            instance[state.property] = state.value
        end)
    end
    suppressed[instance] = nil
end

local function suppress(instance, kind, suppressed)
    local property, value = effectStateProperty(instance)
    if not property then
        return false
    end

    local state = suppressed[instance]
    if not state then
        state = {
            kind = kind,
            property = property,
            value = value,
        }
        suppressed[instance] = state
        local methodOk, getPropertyChangedSignal = pcall(function()
            return instance.GetPropertyChangedSignal
        end)
        if methodOk and type(getPropertyChangedSignal) == "function" then
            local signalOk, signal = pcall(getPropertyChangedSignal, instance, property)
            if signalOk and signal and type(signal.Connect) == "function" then
                local connectionOk, connection = pcall(signal.Connect, signal, function()
                    local readOk, current = pcall(function()
                        return instance[property]
                    end)
                    if readOk and current == true then
                        pcall(function()
                            instance[property] = false
                        end)
                    end
                end)
                if connectionOk then
                    state.connection = connection
                end
            end
        end
    end

    local readOk, current = pcall(function()
        return instance[property]
    end)
    if readOk and current ~= false then
        pcall(function()
            instance[property] = false
        end)
    end
    return true
end

local function visit(settings, roots, suppressed, active)
    for _, entry in ipairs(roots or {}) do
        local root = entry
        local inheritedKind
        if type(entry) == "table" and entry.instance then
            root = entry.instance
            inheritedKind = entry.kind
        end
        local instances = { root }
        if root and root.GetDescendants then
            local succeeded, descendants = pcall(root.GetDescendants, root)
            if succeeded then
                for _, descendant in ipairs(descendants or {}) do
                    table.insert(instances, descendant)
                end
            end
        end
        for _, instance in ipairs(instances) do
            local kind = UtilityPolicy.effectKind(instance) or inheritedKind
            local shouldSuppress = kind == "flash" and settings.noFlash == true
                or kind == "smoke" and settings.noSmoke == true
            if shouldSuppress and suppress(instance, kind, suppressed) and active then
                active[instance] = true
            end
        end
    end
end

-- Applies only the supplied roots and retains all existing registrations. This is
-- used by event callbacks so a single added effect never forces a broad rescan.
function VisualSuppression.apply(settings, roots, suppressed)
    visit(settings, roots, suppressed)
end

function VisualSuppression.restoreRoots(roots, suppressed)
    local selected = {}
    for _, entry in ipairs(roots or {}) do
        local root = entry
        if type(entry) == "table" and entry.instance then
            root = entry.instance
        end
        selected[root] = true
    end
    for instance, state in pairs(suppressed) do
        local current = instance
        local matches = false
        for _depth = 1, 64 do
            if not current then
                break
            end
            if selected[current] then
                matches = true
                break
            end
            current = current.Parent
        end
        if matches then
            restore(instance, state, suppressed)
        end
    end
end

function VisualSuppression.update(settings, roots, suppressed)
    local active = {}
    visit(settings, roots, suppressed, active)
    for instance, state in pairs(suppressed) do
        if not active[instance] then
            restore(instance, state, suppressed)
        end
    end
end

return VisualSuppression
