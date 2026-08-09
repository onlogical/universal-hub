local UtilityPolicy = {}

local TAG_DESCRIPTORS = {
    FireHitbox = { label = "FIRE", tone = "danger" },
    JumpPadHitbox = { label = "JUMP PAD", tone = "accent" },
    SmokeCloud = { label = "SMOKE", tone = "smoke" },
    SubspaceTripmine = {
        label = "TRIPMINE",
        markerStyle = "wireframeCube",
        tone = "danger",
    },
}

UtilityPolicy.TAGS = {
    "FireHitbox",
    "JumpPadHitbox",
    "SmokeCloud",
    "SubspaceTripmine",
}

local function method(instance, name)
    if not instance then
        return nil
    end
    local succeeded, value = pcall(function()
        return instance[name]
    end)
    return succeeded and type(value) == "function" and value or nil
end

local function hasTag(instance, tag)
    local hasTagMethod = method(instance, "HasTag")
    if hasTagMethod then
        local succeeded, tagged = pcall(hasTagMethod, instance, tag)
        return succeeded and tagged == true
    end
    local getTags = method(instance, "GetTags")
    if getTags then
        local succeeded, tags = pcall(getTags, instance)
        return succeeded and type(tags) == "table" and table.find(tags, tag) ~= nil
    end
    return false
end

local function attribute(instance, name)
    local getAttribute = method(instance, "GetAttribute")
    if not getAttribute then
        return nil
    end
    local succeeded, value = pcall(getAttribute, instance, name)
    return succeeded and value or nil
end

function UtilityPolicy.descriptor(instance)
    local current = instance
    for _depth = 1, 3 do
        if not current then
            break
        end
        for tag, descriptor in pairs(TAG_DESCRIPTORS) do
            if hasTag(current, tag) then
                return descriptor, current
            end
        end
        if attribute(current, "ThrowableOrientation") ~= nil then
            return { label = "THROWABLE", tone = "accent" }, current
        end
        current = current.Parent
    end
    return nil
end

function UtilityPolicy.effectKind(instance)
    if hasTag(instance, "SmokeCloud") then
        return "smoke"
    end
    if instance and (instance.Name == "Flashbang" or instance.Name == "FlashbangGui") then
        return "flash"
    end
    return nil
end

return UtilityPolicy
