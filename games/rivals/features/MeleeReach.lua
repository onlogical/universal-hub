local MeleeReach = {}
MeleeReach.__index = MeleeReach

local REACH_KEYS = {
    "AttackReach",
    "HeavyAttackReach",
    "BladeReach",
}

function MeleeReach.new()
    return setmetatable({
        item = nil,
        originals = {},
    }, MeleeReach)
end

function MeleeReach:restore()
    local info = self.item and self.item.Info
    if type(info) == "table" then
        for key, value in pairs(self.originals) do
            info[key] = value
        end
    end
    self.item = nil
    table.clear(self.originals)
end

function MeleeReach:update(settings, item)
    local info = item and item.Info
    if settings.meleeReach ~= true or type(info) ~= "table" then
        self:restore()
        return
    end

    if self.item ~= item then
        self:restore()
        for _, key in ipairs(REACH_KEYS) do
            local reach = info[key]
            if type(reach) == "number" and reach > 0 then
                self.originals[key] = reach
            end
        end
        if next(self.originals) == nil then
            return
        end
        self.item = item
    end

    local scale = math.clamp(
        type(settings.meleeReachScale) == "number" and settings.meleeReachScale or 200,
        100,
        300
    )
    for key, reach in pairs(self.originals) do
        info[key] = reach * scale / 100
    end
end

function MeleeReach:stop()
    self:restore()
end

return MeleeReach
