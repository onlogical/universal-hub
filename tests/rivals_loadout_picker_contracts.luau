local Definition = require("../games/rivals/Definition")
local TaskLoadout = require("../games/rivals/tasks/TaskLoadout")
local TaskPolicy = require("../games/rivals/tasks/TaskPolicy")
local TaskCounterPolicy = require("../games/rivals/tasks/TaskCounterPolicy")
local fs = require("@lune/fs")

assert(table.find(Definition.sources, "games/rivals/tasks/TaskLoadout"))

local source = fs.readFile("games/rivals/tasks/TaskLoadout.lua")
assert(
    string.find(source, "setthreadidentity", 1, true),
    "PickWeapon/Finish must restore executor identity before Instance work"
)
assert(
    string.find(source, "accepted", 1, true),
    "Loadout progress must not depend only on page._chosen_weapons"
)
assert(
    not string.find(source, "findWeaponButton", 1, true),
    "loadout selection must not scrape picker buttons"
)
assert(
    string.find(source, "waiting-slots", 1, true),
    "Finish must wait until every planned slot is filled"
)

local function makePage(options)
    options = options or {}
    local picks = {}
    local finished = 0
    local page = {
        open = true,
        _chosen_weapons = options.chosen or {},
        picks = picks,
        IsOpen = function(self)
            return self.open
        end,
        PickWeapon = function(self, index, name)
            table.insert(picks, { index = index, name = name })
            if options.omitChosen then
                return
            end
            if options.storeObjects then
                self._chosen_weapons[index] = { Name = name }
            elseif options.namedSlots then
                local names = { "Primary", "Secondary", "Melee" }
                self._chosen_weapons[names[index]] = name
            else
                self._chosen_weapons[index] = name
            end
        end,
        Finish = function()
            finished += 1
        end,
    }
    return page, picks, function()
        return finished
    end
end

local function makeLoadout(page, extras)
    extras = extras or {}
    local now = extras.now or 0
    local debug = extras.debug or {}
    local paused = extras.paused == true
    local task = extras.task
    if task == nil then
        task = { kind = "combat", classification = { kind = "pvp" } }
    end
    local loadout = TaskLoadout.new({
        clock = function()
            return now
        end,
        constants = extras.constants or { DEFAULT_WEAPONS = { "Assault Rifle", "Pistol" } },
        getOpponentFighter = extras.getOpponentFighter or function()
            return { Items = {} }
        end,
        getStatus = extras.getStatus or function()
            return { paused = paused, task = task }
        end,
        page = page,
        taskCounterPolicy = TaskCounterPolicy,
        taskDebug = debug,
        taskPolicy = extras.taskPolicy or {
            requiresCombat = function()
                return true
            end,
        },
    })
    return loadout,
        debug,
        function(value)
            now = value
        end,
        function(value)
            paused = value
        end
end

local page, picks, finished = makePage()
local loadout, debug, setNow = makeLoadout(page)

loadout:poll()
assert(debug.loadoutStage == "picking-Assault Rifle")
setNow(1)
loadout:poll()
assert(debug.loadoutStage == "picking-Pistol")
setNow(2)
loadout:poll()
assert(debug.loadoutStage == "submitted" and finished() == 1)
assert(picks[1].name == "Assault Rifle" and picks[2].name == "Pistol")
assert(picks[1].index == 1 and picks[2].index == 2)
assert(#picks == 2, "each configured slot must be picked once before Finish")

page.open = false
loadout:poll()
assert(loadout.wasOpen == false and loadout.plan == nil)

local threePage, threePicks, threeFinished = makePage()
local threeLoadout, threeDebug, setThreeNow = makeLoadout(threePage, {
    constants = { DEFAULT_WEAPONS = { "Assault Rifle", "Pistol", "Knife" } },
})
threeLoadout:poll()
setThreeNow(1)
threeLoadout:poll()
setThreeNow(2)
threeLoadout:poll()
assert(
    threeDebug.loadoutStage == "picking-Knife" and threeFinished() == 0,
    "Finish must not run while melee is still empty"
)
setThreeNow(3)
threeLoadout:poll()
assert(threeDebug.loadoutStage == "submitted" and threeFinished() == 1)
assert(
    #threePicks == 3
        and threePicks[1].name == "Assault Rifle"
        and threePicks[2].name == "Pistol"
        and threePicks[3].name == "Knife",
    "a 1v1 picker must fill primary, secondary, and melee before Finish"
)

local namedPage, namedPicks, namedFinished = makePage({ namedSlots = true, chosen = {} })
local namedLoadout, _, setNamedNow = makeLoadout(namedPage, {
    constants = {
        DEFAULT_WEAPONS = { Primary = "Assault Rifle", Secondary = "Pistol", Melee = "Knife" },
    },
})
namedLoadout:poll()
setNamedNow(1)
namedLoadout:poll()
setNamedNow(2)
namedLoadout:poll()
setNamedNow(3)
namedLoadout:poll()
assert(
    namedFinished() == 1 and #namedPicks == 3,
    "named DEFAULT_WEAPONS maps must still fill every 1v1 slot"
)

local objectPage, objectPicks, objectFinished = makePage({ storeObjects = true })
local objectLoadout, _, setObjectNow = makeLoadout(objectPage)
objectLoadout:poll()
setObjectNow(1)
objectLoadout:poll()
setObjectNow(2)
objectLoadout:poll()
assert(
    objectFinished() == 1 and #objectPicks == 2,
    "chosen weapon objects must count as filled slots"
)

local hiddenPage, hiddenPicks, hiddenFinished = makePage({ omitChosen = true })
local hiddenLoadout, hiddenDebug, setHiddenNow = makeLoadout(hiddenPage)
hiddenLoadout:poll()
assert(hiddenDebug.loadoutStage == "picking-Assault Rifle" and hiddenFinished() == 0)
setHiddenNow(1)
hiddenLoadout:poll()
assert(
    hiddenDebug.loadoutStage == "picking-Pistol" and hiddenFinished() == 0,
    "missing _chosen_weapons must not Finish after only the primary pick"
)
setHiddenNow(2)
hiddenLoadout:poll()
assert(hiddenDebug.loadoutStage == "submitted" and hiddenFinished() == 1)
assert(
    #hiddenPicks == 2 and hiddenPicks[2].name == "Pistol",
    "successful PickWeapon must advance even when the page hides _chosen_weapons"
)

local pausedPage, pausedPicks, pausedFinished = makePage()
local status = { paused = false, task = { classification = { kind = "pvp" } } }
local pausedLoadout, _, setPausedNow = makeLoadout(pausedPage, {
    getStatus = function()
        return status
    end,
    constants = { DEFAULT_WEAPONS = { "Assault Rifle", "Pistol", "Knife" } },
})
pausedLoadout:poll()
assert(#pausedPicks == 1)
status.paused = true
status.task = nil
status.state = "paused"
setPausedNow(1)
pausedLoadout:poll()
assert(
    pausedFinished() == 0 and #pausedPicks == 1,
    "private 1v1 must leave the picker to the player"
)

local privatePage, privatePicks, privateFinished = makePage()
local privateLoadout, privateDebug = makeLoadout(privatePage, {
    getStatus = function()
        return { paused = true, state = "paused", task = nil }
    end,
})
privateLoadout:poll()
assert(#privatePicks == 0 and privateFinished() == 0)
assert(
    privateDebug.loadoutStage == "player-pick",
    "a paused private match must not select the default build"
)

local sprayPage, sprayPicks = makePage()
local sprayLoadout, _, setSprayNow = makeLoadout(sprayPage, {
    getOpponentFighter = function()
        return { Items = { { Info = { MaxAbsorption = 500 } } } }
    end,
})
sprayLoadout:poll()
setSprayNow(1)
sprayLoadout:poll()
assert(sprayPicks[2] and sprayPicks[2].name == "Spray")

assert(type(TaskPolicy.requiresCombat) == "function")

print("rivals-loadout-picker-contracts-ok")
