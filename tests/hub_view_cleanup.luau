local HubView = require("../modules/HubView")

local worldDestroyCount = 0
local view = HubView.new({
    destroy = function()
        worldDestroyCount += 1
    end,
    render = function() end,
}, {
    destroy = function()
        error("simulated Prism unmount failure")
    end,
})

view:destroy()
assert(worldDestroyCount == 1, "World cleanup must survive a Prism unmount failure")
view:destroy()
assert(worldDestroyCount == 1, "Hub cleanup must remain idempotent")

Color3 = {
    fromRGB = function()
        return {}
    end,
}
local HubMenu = require("../ui/Menu")
local guiDestroyCount = 0
local menu = setmetatable({
    context = {
        publishPreviewObservation = function()
            error("simulated preview cleanup failure")
        end,
        setInputCaptured = function()
            error("simulated input cleanup failure")
        end,
    },
    destroyed = false,
    gui = {
        Destroy = function()
            guiDestroyCount += 1
        end,
    },
    handle = {
        destroy = function()
            error("simulated Prism unmount failure")
        end,
    },
    unsubscribe = function()
        error("simulated store cleanup failure")
    end,
    whatsNew = {
        destroy = function()
            error("simulated notice cleanup failure")
        end,
    },
}, HubMenu)
menu:destroy()
assert(guiDestroyCount == 1, "GUI cleanup must survive earlier teardown failures")
assert(menu.handle == nil and menu.gui == nil and menu.whatsNew == nil and menu.unsubscribe == nil)

print("hub-view-cleanup-ok")
