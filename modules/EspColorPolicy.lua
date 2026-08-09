local EspColorPolicy = {}

EspColorPolicy.RELATIONSHIPS = table.freeze({ "enemy", "teammate" })
EspColorPolicy.TARGETS = table.freeze({ "outline", "fill", "name", "weapon", "healthLow", "healthHigh" })

local PREFIX = table.freeze({
    enemy = "espEnemy",
    teammate = "espTeammate",
})

local function title(value)
    return value:sub(1, 1):upper() .. value:sub(2)
end

function EspColorPolicy.relationship(tone)
    if tone == "team" or tone == "teammate" or tone == "ally" or tone == "allies" then
        return "teammate"
    end
    return "enemy"
end

function EspColorPolicy.settingName(relationship, target)
    local prefix = PREFIX[EspColorPolicy.relationship(relationship)]
    if target == "fillAlpha" then
        return prefix .. "FillAlpha"
    end
    for _, candidate in ipairs(EspColorPolicy.TARGETS) do
        if candidate == target then
            return prefix .. title(target) .. "Color"
        end
    end
    return nil
end

local function channel(value)
    return math.clamp(math.floor(value + 0.5), 0, 255)
end

function EspColorPolicy.parseHex(value)
    if type(value) ~= "string" then return nil end
    local source = value:gsub("^#", "")
    if #source == 3 then
        source = source:sub(1, 1):rep(2) .. source:sub(2, 2):rep(2) .. source:sub(3, 3):rep(2)
    end
    if #source ~= 6 or source:find("[^%x]") then return nil end
    return Color3.fromRGB(
        tonumber(source:sub(1, 2), 16),
        tonumber(source:sub(3, 4), 16),
        tonumber(source:sub(5, 6), 16)
    )
end

function EspColorPolicy.toHex(color)
    return ("#%02X%02X%02X"):format(channel(color.R * 255), channel(color.G * 255), channel(color.B * 255))
end

function EspColorPolicy.color(settings, target, fallback, relationship)
    local setting = EspColorPolicy.settingName(relationship, target)
    local value = setting and settings and settings[setting]
    if value ~= nil then
        return EspColorPolicy.parseHex(value) or fallback
    end
    -- Only previously saved configs lack relationship-specific keys. Once a
    -- relationship is changed or reset, its explicit value suppresses legacy.
    local legacy = "esp" .. title(target) .. "Color"
    return EspColorPolicy.parseHex(settings and settings[legacy]) or fallback
end

function EspColorPolicy.fillAlpha(settings, fallback, relationship)
    local setting = EspColorPolicy.settingName(relationship, "fillAlpha")
    local value = setting and settings and settings[setting]
    if value ~= nil then
        if type(value) == "number" and value >= 0 and value <= 1 then return value, true end
        return fallback, false
    end
    value = settings and settings.espFillAlpha
    if type(value) == "number" and value >= 0 and value <= 1 then return value, true end
    return fallback, false
end

function EspColorPolicy.healthColor(settings, fraction, fallbackLow, fallbackHigh, relationship)
    local low = EspColorPolicy.color(settings, "healthLow", fallbackLow, relationship)
    local high = EspColorPolicy.color(settings, "healthHigh", fallbackHigh, relationship)
    return low:Lerp(high, math.sqrt(math.clamp(fraction, 0, 1)))
end

return table.freeze(EspColorPolicy)
