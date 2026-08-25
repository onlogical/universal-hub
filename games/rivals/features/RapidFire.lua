local RapidFire = {}
RapidFire.__index = RapidFire

local COOLDOWN_KEYS = {
    "ShootCooldown",
    "AttackCooldown",
    "ChargeReleaseCooldown",
}

function RapidFire.new(weaponPolicy)
    return setmetatable({
        item = nil,
        originals = {},
        weaponPolicy = weaponPolicy,
    }, RapidFire)
end

function RapidFire:restore()
    local info = self.item and self.item.Info
    if type(info) == "table" then
        for key, value in pairs(self.originals) do
            info[key] = value
        end
    end
    self.item = nil
    table.clear(self.originals)
end

function RapidFire:update(settings, item, canFire, fireHeld, fire)
    local info = item and item.Info
    if settings.rapidFire ~= true or type(info) ~= "table" then
        self:restore()
        return
    end

    if self.item ~= item then
        self:restore()
        for _, key in ipairs(COOLDOWN_KEYS) do
            local cooldown = info[key]
            if type(cooldown) == "number" and cooldown > 0 then
                self.originals[key] = cooldown
            end
        end
        if next(self.originals) == nil then
            return
        end
        self.item = item
    end

    local rate =
        math.clamp(type(settings.fireRate) == "number" and settings.fireRate or 200, 100, 500)
    for key, cooldown in pairs(self.originals) do
        info[key] = cooldown * 100 / rate
    end

    if
        canFire
        and fireHeld
        and (not self.weaponPolicy.holdToFire(item) or self.weaponPolicy.repeatShootingInput(item))
        and type(fire) == "function"
    then
        fire()
    end
end

function RapidFire:stop()
    self:restore()
end

return RapidFire
