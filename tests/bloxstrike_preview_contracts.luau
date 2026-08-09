local Bloxstrike = require("../games/Bloxstrike")
local Preview = require("../games/bloxstrike/Preview")

local installed
local sharedAdapter = {}
local composed = Bloxstrike.new({
    store = {},
    tacticalAdapter = {
        new = function()
            return sharedAdapter
        end,
    },
    bloxstrikePreview = {
        install = function(adapter)
            installed = adapter
        end,
    },
})
assert(composed == sharedAdapter and installed == sharedAdapter)

local function decode(source)
    local values = {
        slot = { Weapon = "CT Knife", Skin = "Stock", Float = 0, StatTrack = false },
        gloves = { SkinIdentifier = "CT Glove_Stock" },
    }
    return assert(values[source], "unknown encoded fixture")
end

local character = {
    GetAttribute = function(_, name)
        return name == "EquippedGloves" and "gloves" or nil
    end,
}
local attributes = {
    Team = "Counter-Terrorists",
    Slot3 = "slot",
}
local player = {
    Character = character,
    GetAttribute = function(_, name)
        return attributes[name]
    end,
}

local stock = Preview.resolveLoadout(player, {}, decode)
assert(stock.knife.baseWeapon == "CT Knife" and stock.knife.weapon == "CT Knife")
assert(stock.knife.skin == "Stock" and stock.knife.wear == 0 and stock.knife.statTrak == false)
assert(stock.glove.weapon == "CT Glove" and stock.glove.skin == "Stock")

local changed = Preview.resolveLoadout(player, {
    skinOverrides = {
        ["CT Knife"] = {
            weapon = "Karambit",
            skin = "Fade",
            wear = 0.12,
            statTrak = true,
        },
    },
    gloveOverride = {
        weapon = "Sports Gloves",
        skin = "Vice",
        wear = 0.2,
    },
    gloveColorOverride = { r = 1, g = 0.25, b = 0.1 },
}, decode)
assert(changed.knife.baseWeapon == "CT Knife" and changed.knife.weapon == "Karambit")
assert(changed.knife.skin == "Fade" and changed.knife.wear == 0.12 and changed.knife.statTrak)
assert(changed.glove.weapon == "Sports Gloves" and changed.glove.skin == "Vice")
assert(changed.glove.wear == 0.2 and changed.gloveColor.r == 1)

attributes.Team = "Spectators"
attributes.Slot3 = "slot"
character.GetAttribute = function()
    return nil
end
local fallback = Preview.resolveLoadout(player, {}, decode)
assert(fallback.knife.weapon == "T Knife", "Spectators must default to the T knife")
assert(fallback.glove.weapon == "T Glove", "Spectators must default to T gloves")

print("bloxstrike-preview-contracts-ok")
