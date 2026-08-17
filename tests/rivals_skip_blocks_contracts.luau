local fs = require("@lune/fs")
local Definition = require("../games/rivals/Definition")
local SkipBlocks = require("../games/rivals/features/SkipBlocks")
local TriggerBot = require("../games/rivals/features/TriggerBot")

assert(table.find(Definition.sources, "games/rivals/features/SkipBlocks"))
assert(Definition.features.optionLabels.skipDeflect == "Katana Stop")
assert(fs.readFile("games/rivals/Presentation.lua"):find('skipDeflect", "Katana Stop"', 1, true))

local rifle = { Info = { ShootDamage = 25 } }
local target = { player = {} }
local ctx = {
    isDeflecting = function()
        return true
    end,
    fighterFor = function()
        return { EquippedItem = { _deflect_hash = 1, Info = { DeflectDuration = 1, DeflectCooldown = 4 } } }
    end,
    taskCounterPolicy = {
        shouldForceSpray = function()
            return false
        end,
    },
}
assert(SkipBlocks.shouldBlock(rifle, target, ctx) == true)
assert(TriggerBot.shouldHoldForDeflect(target, rifle, ctx) == true)

ctx.taskCounterPolicy.shouldForceSpray = function()
    return true
end
assert(SkipBlocks.shouldBlock(rifle, target, ctx) == false, "True-damage spray may still fire through a deflector")

ctx.isDeflecting = function()
    return false
end
ctx.taskCounterPolicy.shouldForceSpray = function()
    return false
end
assert(SkipBlocks.shouldBlock(rifle, target, ctx) == false)

assert(SkipBlocks.isFiring({ Data = { IsShooting = true } }) == true)
assert(SkipBlocks.isFiring({
    Get = function()
        return true
    end,
}) == true)
assert(SkipBlocks.isFiring({ Data = { IsShooting = false } }) == false)

local released = 0
assert(SkipBlocks.update(rifle, target, {
    isDeflecting = function()
        return true
    end,
    fighterFor = ctx.fighterFor,
    taskCounterPolicy = {
        shouldForceSpray = function()
            return false
        end,
    },
    fireHeld = true,
    releaseFire = function()
        released += 1
    end,
}) == true)
assert(released == 1, "Katana Stop must release a held shot into a deflect")

local hooked = 0
local originalCalls = 0
local item = {
    StartShooting = function()
        originalCalls += 1
    end,
}
local runtime = SkipBlocks.new({
    getFighter = function()
        return { EquippedItem = item }
    end,
    hookFunction = function(targetFunction, replacement)
        hooked += 1
        assert(targetFunction == item.StartShooting)
        item.StartShooting = function(...)
            return replacement(...)
        end
        return function()
            originalCalls += 1
        end
    end,
    restoreFunction = function()
        hooked = 0
    end,
    isEnabled = function()
        return true
    end,
    shouldBlock = function()
        return true
    end,
})
runtime:refreshHook()
assert(hooked == 1)
item:StartShooting()
assert(originalCalls == 0, "Katana Stop must swallow StartShooting while the target is deflecting")
runtime:stop()

print("rivals-skip-blocks-contracts-ok")
