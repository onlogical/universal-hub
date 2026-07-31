local fs = require("@lune/fs")

local initSource = fs.readFile("init.lua")
for _, forbidden in ipairs({
    'adapterDefinition.id == "town"',
    '"games/town/CheckpointStore"',
    "TownCopyCheckpointRoot",
    "cancelPlotCopy = function",
    "cleanupPlotCopyCheckpoint = function",
    "confirmPlotCopy = function",
    "copyPlot = function",
    "cycleCosmeticWeapon = function",
    "cycleGlove = function",
    "cycleSkin = function",
    "discardPlotCopy = function",
    "reportPlotCopyError = function",
    "resetGlove = function",
    "resetSkin = function",
    "resumePlotCopy = function",
    "retryPlotCopyCleanup = function",
    "setGloveColor = function",
    "setGloveWear = function",
    "setWear = function",
    "toggleStatTrak = function",
}) do
    assert(
        not initSource:find(forbidden, 1, true),
        "Init must not own selected-game startup/actions: " .. forbidden
    )
end
assert(
    initSource:find("import(adapterDefinition.composition)", 1, true),
    "Init must import only the selected optional composition module"
)

local Compatibility = require("../games/Compatibility")
assert(type(Compatibility.Compose) == "function")

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local CounterbloxDefinition = require("../games/counterblox/Definition")
local RivalsDefinition = require("../games/rivals/Definition")
local TownDefinition = require("../games/town/Definition")
assert(CounterbloxDefinition.composition == "games/counterblox/Composition")
assert(table.find(CounterbloxDefinition.sources, CounterbloxDefinition.composition))
assert(RivalsDefinition.composition == nil)
assert(TownDefinition.composition == "games/town/Composition")
assert(table.find(TownDefinition.sources, TownDefinition.composition))

local CounterbloxComposition = require("../games/counterblox/Composition")
local cosmeticCalls = {}
local cosmeticAdapter = {}
for _, name in ipairs({
    "cycleGlove",
    "cycleSkin",
    "cycleCosmeticWeapon",
    "resetSkin",
    "resetGlove",
    "setGloveWear",
    "setGloveColor",
    "setWear",
    "toggleStatTrak",
}) do
    cosmeticAdapter[name] = function(_, ...)
        table.insert(cosmeticCalls, {
            arguments = { ... },
            name = name,
        })
    end
end
local counterblox = CounterbloxComposition.bind({
    getAdapter = function()
        return cosmeticAdapter
    end,
})
counterblox.overlay.cycleGlove(-1)
counterblox.overlay.cycleSkin(1)
counterblox.overlay.cycleCosmeticWeapon(-1)
counterblox.overlay.resetSkin()
counterblox.overlay.resetGlove()
counterblox.overlay.setGloveWear(0.25)
counterblox.overlay.setGloveColor({ r = 1 })
counterblox.overlay.setWear(0.75)
counterblox.overlay.toggleStatTrak()
for index, expected in ipairs({
    { name = "cycleGlove", value = -1 },
    { name = "cycleSkin", value = 1 },
    { name = "cycleCosmeticWeapon", value = -1 },
    { name = "resetSkin" },
    { name = "resetGlove" },
    { name = "setGloveWear", value = 0.25 },
    { name = "setGloveColor", value = { r = 1 } },
    { name = "setWear", value = 0.75 },
    { name = "toggleStatTrak" },
}) do
    assert(cosmeticCalls[index].name == expected.name)
    assert(deepEqual(cosmeticCalls[index].arguments[1], expected.value))
end

local TownComposition = require("../games/town/Composition")
assert(deepEqual(TownComposition.dependencies, {
    checkpointStore = "games/town/CheckpointStore",
}))
local checkpointOptions
local pruneCount = 0
local checkpoint = {
    available = true,
    prune = function()
        pruneCount += 1
    end,
}
local files = {
    delete = function() end,
    isFile = function() end,
    list = function() end,
    makeFolder = function() end,
    read = function() end,
    write = function() end,
}
local queued = {}
local storePatches = {}
local adapterCalls = {}
local adapter = {
    listPlotOwners = function()
        return { "Alpha", "Zulu" }
    end,
}
for _, name in ipairs({
    "copyPlot",
    "cancelCopy",
    "confirmCopy",
    "discardCopy",
    "resumeCopy",
    "retryCopyCleanup",
    "cleanupCopyCheckpoint",
}) do
    adapter[name] = function(_, ...)
        table.insert(adapterCalls, {
            arguments = { ... },
            name = name,
        })
    end
end
local town = TownComposition.bind({
    config = function(name, fallback)
        assert(name == "TownCopyCheckpointRoot")
        assert(fallback == "universal-hub/private/town-copy")
        return "custom/checkpoints"
    end,
    decode = function(value)
        return value
    end,
    encode = function(value)
        return value
    end,
    files = files,
    getAdapter = function()
        return adapter
    end,
    getStore = function()
        return {
            Patch = function(_, patch)
                table.insert(storePatches, patch)
            end,
        }
    end,
    spawn = function(callback)
        table.insert(queued, callback)
    end,
    userId = 42,
}, {
    checkpointStore = {
        new = function(options)
            checkpointOptions = options
            return checkpoint
        end,
    },
})
assert(town.adapter.checkpoint == checkpoint)
assert(town.inputCapture.releaseMouseOnDisable == true)
assert(pruneCount == 1)
assert(
    checkpointOptions.root == "custom/checkpoints"
        and checkpointOptions.userId == 42
        and checkpointOptions.deleteFile == files.delete
        and checkpointOptions.isFile == files.isFile
        and checkpointOptions.listFiles == files.list
        and checkpointOptions.makeFolder == files.makeFolder
        and checkpointOptions.readFile == files.read
        and checkpointOptions.writeFile == files.write,
    "Town composition must preserve checkpoint construction inputs"
)
assert(deepEqual(town.overlay.listPlotOwners(), { "Alpha", "Zulu" }))
assert(town.overlay.copyPlot("Alpha", "copy_Alpha") == true)
assert(town.overlay.cancelPlotCopy() == true)
assert(town.overlay.confirmPlotCopy() == true)
assert(town.overlay.discardPlotCopy() == true)
assert(town.overlay.resumePlotCopy() == true)
assert(town.overlay.retryPlotCopyCleanup() == true)
assert(town.overlay.cleanupPlotCopyCheckpoint() == true)
assert(#queued == 7 and #adapterCalls == 0, "Town actions must preserve deferred adapter timing")
for _, callback in ipairs(queued) do
    callback()
end
for index, expected in ipairs({
    { arguments = { "Alpha", "copy_Alpha" }, name = "copyPlot" },
    { arguments = {}, name = "cancelCopy" },
    { arguments = {}, name = "confirmCopy" },
    { arguments = {}, name = "discardCopy" },
    { arguments = {}, name = "resumeCopy" },
    { arguments = {}, name = "retryCopyCleanup" },
    { arguments = {}, name = "cleanupCopyCheckpoint" },
}) do
    assert(adapterCalls[index].name == expected.name)
    assert(deepEqual(adapterCalls[index].arguments, expected.arguments))
end
town.overlay.reportPlotCopyError("blocked")
assert(deepEqual(storePatches[#storePatches], {
    plotCopy = {
        active = false,
        confirmedProgress = 0,
        context = "blocked",
        error = "blocked",
        phase = "Copy blocked",
        state = "error",
    },
}))
local inspected = 0
town.afterAdapter({
    inspectCopyRecovery = function()
        inspected += 1
    end,
})
assert(inspected == 1)
town.afterAdapter({
    inspectCopyRecovery = function()
        error("inspection failed")
    end,
})
assert(deepEqual(storePatches[#storePatches], {
    plotCopy = {
        active = false,
        context = "Recovery inspection failed before any Town mutation",
        error = "Persistent copy recovery could not be inspected",
        phase = "Copy blocked",
        state = "error",
    },
}))

adapter = nil
local unavailableTown = TownComposition.bind({
    config = function(_, fallback)
        return fallback
    end,
    decode = function(value)
        return value
    end,
    encode = function(value)
        return value
    end,
    files = files,
    getAdapter = function()
        return nil
    end,
    getStore = function()
        return {
            Patch = function() end,
        }
    end,
    spawn = function()
        error("Unavailable actions must not spawn")
    end,
    userId = 42,
}, {
    checkpointStore = {
        new = function()
            return { available = false }
        end,
    },
})
for _, case in ipairs({
    { callback = "copyPlot", arguments = { "Alpha", "save" }, message = "Plot copying is not ready" },
    { callback = "cancelPlotCopy", arguments = {}, message = "Plot copy cancellation is not ready" },
    { callback = "confirmPlotCopy", arguments = {}, message = "Plot copy confirmation is not ready" },
    { callback = "discardPlotCopy", arguments = {}, message = "Plot copy discard is not ready" },
    { callback = "resumePlotCopy", arguments = {}, message = "Plot copy resume is not ready" },
    { callback = "retryPlotCopyCleanup", arguments = {}, message = "Plot copy cleanup is not ready" },
    {
        callback = "cleanupPlotCopyCheckpoint",
        arguments = {},
        message = "Local copy recovery cleanup is not ready",
    },
}) do
    local accepted, message = unavailableTown.overlay[case.callback](table.unpack(case.arguments))
    assert(accepted == false and message == case.message)
end

for _, path in ipairs({
    "games/counterblox/Composition.lua",
    "games/town/Composition.lua",
}) do
    local source = fs.readFile(path)
    for _, forbidden in ipairs({
        "Drawing",
        "DrawingImmediate",
        "Limn",
        "Canvas",
        "Element",
        "game:GetService",
    }) do
        assert(not source:find(forbidden, 1, true), path .. " must receive a narrow context")
    end
end

print("game-composition-contracts-ok")
