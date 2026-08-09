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

function VisualSuppression.update(settings, roots, suppressed)
    local active = {}
    for _, entry in ipairs(roots or {}) do
        local root = entry
        local inheritedKind
        if type(entry) == "table" and entry.instance then
            root = entry.instance
            inheritedKind = entry.kind
        end
        local instances = { root }
        if root and root.GetDescendants then
            for _, descendant in ipairs(root:GetDescendants()) do
                table.insert(instances, descendant)
            end
        end
        for _, instance in ipairs(instances) do
            local kind = UtilityPolicy.effectKind(instance) or inheritedKind
            local shouldSuppress = kind == "flash" and settings.noFlash == true
                or kind == "smoke" and settings.noSmoke == true
            if shouldSuppress then
                local property, value = effectStateProperty(instance)
                if property then
                    active[instance] = true
                    if suppressed[instance] == nil then
                        suppressed[instance] = { property = property, value = value }
                    end
                    pcall(function() instance[property] = false end)
                end
            end
        end
    end
    for instance, state in pairs(suppressed) do
        if not active[instance] then
            pcall(function() instance[state.property] = state.value end)
            suppressed[instance] = nil
        end
    end
end

return VisualSuppression
