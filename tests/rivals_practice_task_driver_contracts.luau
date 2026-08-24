local Driver = require("../games/rivals/tasks/PracticeTaskDriver")

local fighter = { Data = { IsInShootingRange = false }, EquippedItem = nil }
local calls, pending, releases = {}, {}, 0
local function action(name, callback)
    return function(...)
        table.insert(calls, { name, ... })
        if callback then
            callback(...)
        end
        return true
    end
end
local driver = Driver.new({
    getFighter = function()
        return fighter
    end,
    actions = {
        enterRange = action("enterRange"),
        slide = action("slide"),
        equip = action("equip"),
        secondary = action("secondary"),
        primary = action("primary"),
        releaseAll = function()
            releases += 1
        end,
    },
    delay = function(_, callback)
        local h = { callback = callback }
        table.insert(pending, h)
        return h
    end,
    cancelDelay = function(handle)
        handle.cancelled = true
    end,
    maxAttempts = 2,
})

driver:setTask({ name = "Beginner1", progress = 0 })
assert(calls[1][1] == "enterRange" and driver:status().state == "waiting-native")
fighter.Data.IsInShootingRange = true
driver:setTask({ name = "Beginner2", progress = 0 })
assert(driver:isCombatActive() and driver:status().state == "target-combat")

driver:setTask({ name = "Beginner3", progress = 0 })
assert(calls[#calls][1] == "slide")
driver:setTask({ name = "Beginner4", progress = 0 })
assert(calls[#calls][1] == "equip" and calls[#calls][2] == "Scythe")
fighter.EquippedItem = { Name = "Scythe" }
driver:setTask({ name = "Beginner5", progress = 0 })
assert(calls[#calls][1] == "secondary")
driver:setTask({ name = "Beginner6", progress = 0 })
assert(calls[#calls][1] == "equip" and calls[#calls][2] == "Grenade")
fighter.EquippedItem = { Name = "Grenade" }
driver:setTask({ name = "Beginner6", progress = 0 })
assert(calls[#calls][1] == "primary")

driver:pause()
assert(driver:status().state == "paused" and not driver:isCombatActive())
local callsAtPause = #calls
for _, h in ipairs(pending) do
    if not h.cancelled then
        h.callback()
    end
end
assert(#calls == callsAtPause, "stale practice retries must be generation-cancelled")
driver:resume()
assert(#calls == callsAtPause and driver:status().state == "retry-exhausted")
driver:stop()
assert(driver:status().state == "stopped" and releases >= 8)

local unsupported = Driver.new({
    getFighter = function()
        return fighter
    end,
    actions = { releaseAll = function() end },
})
unsupported:setTask({ name = "Beginner3", progress = 0 })
assert(unsupported:status().state == "unsupported-boundary")
print("rivals-practice-task-driver-contracts-ok")
