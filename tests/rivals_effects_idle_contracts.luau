local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3
Color3 = roblox.Color3
local Effects = require("../games/rivals/world/Effects")

local traversals = 0
local root = {
    GetDescendants = function()
        traversals += 1
        return {}
    end,
}
local effects = Effects.new({
    lighting = root,
    localPlayer = {
        FindFirstChildOfClass = function()
            return root
        end,
    },
    playerGui = root,
    projectileAim = {},
    workspace = { CurrentCamera = root },
})
effects:update({ noFlash = false, noSmoke = false })
assert(
    traversals == 0,
    "disabled visual suppression must not traverse Lighting, Camera, or PlayerGui"
)
effects:stop()

local function signal()
    local listeners = {}
    return {
        Connect = function(_self, callback)
            table.insert(listeners, callback)
            return { Disconnect = function() end }
        end,
        Fire = function(_self, value)
            for _, callback in ipairs(listeners) do
                callback(value)
            end
        end,
    }
end

local smokeTraversals = 0
local smokeWrites = 0
local smokeEnabled = true
local smokeEffect = setmetatable({}, {
    __index = function(_self, member)
        if member == "Enabled" then
            return smokeEnabled
        end
        if member == "IsA" then
            return function(_instance, className)
                return className == "ParticleEmitter"
            end
        end
        return nil
    end,
    __newindex = function(_self, member, value)
        if member == "Enabled" then
            smokeWrites += 1
            smokeEnabled = value
        else
            rawset(_self, member, value)
        end
    end,
})
local smokeAdded = signal()
local smokeRemoving = signal()
local smokeRoot = {
    Parent = {},
    DescendantAdded = smokeAdded,
    DescendantRemoving = smokeRemoving,
    GetTags = function()
        return { "SmokeCloud" }
    end,
    GetDescendants = function()
        smokeTraversals += 1
        return { smokeEffect }
    end,
    IsA = function()
        return false
    end,
}
smokeEffect.Parent = smokeRoot
local globalTraversals = 0
local globalRoot = {
    GetDescendants = function()
        globalTraversals += 1
        return {}
    end,
}
local smokeEffects = Effects.new({
    collectionService = {
        GetTagged = function(_self, tag)
            return tag == "SmokeCloud" and { smokeRoot } or {}
        end,
    },
    lighting = globalRoot,
    localPlayer = {
        FindFirstChildOfClass = function()
            return globalRoot
        end,
    },
    playerGui = globalRoot,
    projectileAim = {},
    workspace = { CurrentCamera = globalRoot },
})
local noSmoke = { noFlash = false, noSmoke = true }
smokeEffects:update(noSmoke)
assert(globalTraversals == 0, "No Smoke must never traverse global Flash roots")
assert(
    smokeTraversals == 1 and smokeWrites == 1 and smokeEnabled == false,
    "No Smoke should traverse and suppress each tagged smoke root once"
)
smokeEffects:update(noSmoke)
assert(
    globalTraversals == 0 and smokeTraversals == 1 and smokeWrites == 1,
    "unchanged No Smoke must perform zero traversal and zero property writes"
)
smokeEffects:update({ noFlash = false, noSmoke = false })
assert(smokeEnabled == true, "disabling No Smoke must restore the native effect state")
smokeEffects:stop()

print("rivals-effects-idle-contracts-ok")
