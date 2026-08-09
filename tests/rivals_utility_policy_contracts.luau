local fs = require("@lune/fs")
local UtilityPolicy = require("../games/rivals/UtilityPolicy")

local effectsSource = fs.readFile("games/rivals/Effects.lua")
assert(not effectsSource:find("string.find", 1, true))
assert(not effectsSource:find("THROWABLE_CONTAINERS", 1, true))

local function candidate(name, tags, attributes)
    return {
        Name = name,
        Parent = {},
        GetTags = function()
            return tags or {}
        end,
        GetAttribute = function(_self, key)
            return attributes and attributes[key]
        end,
    }
end

local tripmine = candidate("anything", { "SubspaceTripmine" })
local descriptor = UtilityPolicy.descriptor(tripmine)
assert(descriptor.label == "TRIPMINE" and descriptor.markerStyle == "wireframeCube")
assert(UtilityPolicy.descriptor(candidate("grenade", {})) == nil)
assert(UtilityPolicy.descriptor(candidate("Effects", {})) == nil)
assert(UtilityPolicy.descriptor(candidate("replicated", {}, { ThrowableOrientation = true })).label == "THROWABLE")
assert(UtilityPolicy.effectKind(candidate("Flashbang", {})) == "flash")
assert(UtilityPolicy.effectKind(candidate("flash-ish", {})) == nil)
assert(UtilityPolicy.effectKind(candidate("cloud", { "SmokeCloud" })) == "smoke")

print("rivals-utility-policy-contracts-ok")
