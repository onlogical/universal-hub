local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3
Color3 = roblox.Color3
local Effects = require("../games/rivals/world/Effects")

local function signal()
    local listeners = {}
    local nextID = 0
    return {
        Connect = function(_self, callback)
            nextID += 1
            local id = nextID
            listeners[id] = callback
            return {
                Disconnect = function()
                    listeners[id] = nil
                end,
            }
        end,
        Fire = function(_self, value)
            for _, callback in pairs(listeners) do
                callback(value)
            end
        end,
    }
end

local added = {}
local removed = {}
local getTaggedCalls = 0
local initialSmoke = {
    Parent = {},
    GetTags = function()
        return { "SmokeCloud" }
    end,
}
local collectionService = {
    GetInstanceAddedSignal = function(_self, tag)
        added[tag] = added[tag] or signal()
        return added[tag]
    end,
    GetInstanceRemovedSignal = function(_self, tag)
        removed[tag] = removed[tag] or signal()
        return removed[tag]
    end,
    GetTagged = function(_self, tag)
        getTaggedCalls += 1
        return tag == "SmokeCloud" and { initialSmoke } or {}
    end,
}

local descendantAdded = signal()
local descendantRemoving = signal()
local traversals = 0
local visualRoot = {
    DescendantAdded = descendantAdded,
    DescendantRemoving = descendantRemoving,
    GetDescendants = function()
        traversals += 1
        return {}
    end,
}
local effects = Effects.new({
    collectionService = collectionService,
    lighting = visualRoot,
    localPlayer = {
        FindFirstChildOfClass = function()
            return nil
        end,
    },
    projectileAim = {},
    workspace = { CurrentCamera = nil },
})
assert(getTaggedCalls == 4, "each utility tag should be seeded exactly once")
assert(#effects.throwableCandidates == 1)
assert(effects:smokeRaycastIgnore()[1] == initialSmoke)
assert(getTaggedCalls == 4, "registry reads must not poll CollectionService")

local fire = { Parent = {} }
added.FireHitbox:Fire(fire)
assert(#effects.throwableCandidates == 2, "added tags should update the registry immediately")
removed.FireHitbox:Fire(fire)
assert(#effects.throwableCandidates == 1, "removed tags should update the registry immediately")

local settings = { noFlash = true, noSmoke = false }
effects:update(settings)
local firstTraversals = traversals
assert(firstTraversals == 1)
effects:update(settings)
assert(traversals == firstTraversals, "unchanged suppression state must not retraverse hierarchies")
local addedFlash = {
    Name = "FlashbangGui",
    Visible = true,
    IsA = function(_self, className)
        return className == "Frame"
    end,
}
descendantAdded:Fire(addedFlash)
assert(addedFlash.Visible == false, "native hierarchy additions should be suppressed directly")
effects:update(settings)
assert(traversals == firstTraversals, "native hierarchy changes must not retraverse the full root")
descendantRemoving:Fire(addedFlash)
assert(addedFlash.Visible == true, "removed hierarchy effects should restore their original state")

effects:stop()
local countAfterStop = #effects.throwableCandidates
added.FireHitbox:Fire(fire)
assert(#effects.throwableCandidates == countAfterStop, "stop must disconnect tag subscriptions")
print("rivals-effects-event-registry-contracts-ok")
