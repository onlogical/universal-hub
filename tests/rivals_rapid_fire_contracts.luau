local RapidFire = require("../games/rivals/features/RapidFire")

local held = false
local repeatInput = false
local fires = 0
local policy = {
    holdToFire = function()
        return held
    end,
    repeatShootingInput = function()
        return repeatInput
    end,
}
local rapidFire = RapidFire.new(policy)
local item = { Info = { ShootCooldown = 0.1 } }

rapidFire:update({ rapidFire = true, fireRate = 200 }, item, true, false, function()
    fires += 1
end)
assert(item.Info.ShootCooldown == 0.05 and fires == 0)

rapidFire:update({ rapidFire = true, fireRate = 200 }, item, true, true, function()
    fires += 1
end)
assert(fires == 1, "holding primary fire must automatically repeat a semi-auto secondary")

held = true
rapidFire:update({ rapidFire = true, fireRate = 300 }, item, true, true, function()
    fires += 1
end)
assert(math.abs(item.Info.ShootCooldown - 1 / 30) < 1e-6)
assert(fires == 1, "native automatic holds must not receive synthetic semi-auto clicks")

repeatInput = true
rapidFire:update({ rapidFire = true, fireRate = 500 }, item, true, true, function()
    fires += 1
end)
assert(item.Info.ShootCooldown == 0.02)
assert(fires == 2, "Burst Rifle-style native input must repeat while primary fire is held")

local replacement = { Info = { ShootCooldown = 0.2 } }
rapidFire:update({ rapidFire = true, fireRate = 999 }, replacement, false, true, function()
    fires += 1
end)
assert(item.Info.ShootCooldown == 0.1, "equipping another weapon must restore the old cooldown")
assert(math.abs(replacement.Info.ShootCooldown - 0.04) < 1e-6, "fire rate must clamp at 500%")

rapidFire:update({ rapidFire = false }, replacement, false, false)
assert(replacement.Info.ShootCooldown == 0.2, "disabling Rapid Fire must restore native cooldown")

rapidFire:update({ rapidFire = true, fireRate = 200 }, item, false, false)
rapidFire:stop()
assert(item.Info.ShootCooldown == 0.1, "stopping the adapter must restore native cooldown")

held = false
local fist = { Info = { AttackCooldown = 0.35 } }
local fistFires = 0
rapidFire:update({ rapidFire = true, fireRate = 200 }, fist, true, true, function()
    fistFires += 1
end)
assert(fist.Info.AttackCooldown == 0.175, "Fists must scale their native AttackCooldown")
assert(fistFires == 1, "holding primary fire must repeat Fists attacks")
rapidFire:update({ rapidFire = false }, fist, false, false)
assert(fist.Info.AttackCooldown == 0.35, "disabling Rapid Fire must restore Fists cooldown")

local bow = {
    Info = {
        ShootCooldown = 0.25,
        ChargeReleaseCooldown = 1,
    },
}
rapidFire:update({ rapidFire = true, fireRate = 500 }, bow, false, false)
assert(bow.Info.ShootCooldown == 0.05)
assert(bow.Info.ChargeReleaseCooldown == 0.2, "Bow release debounce must scale with Fire Rate")
rapidFire:update({ rapidFire = false }, bow, false, false)
assert(bow.Info.ShootCooldown == 0.25 and bow.Info.ChargeReleaseCooldown == 1)

print("rivals-rapid-fire-contracts-ok")
