local fs = require("@lune/fs")
local ModePolicy = require("../games/rivals/ModePolicy")

local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(not adapterSource:find("133215910299950", 1, true))
assert(not adapterSource:find("isGunGamePlace", 1, true))
assert(not adapterSource:find("game.PlaceId", 1, true))

local function replica(data, getter)
    return {
        Data = data,
        Get = getter,
    }
end

assert(ModePolicy.resolve(replica({ IsGunGame = true })) == "gun-game")
assert(ModePolicy.resolve(replica({ IsGunGame = false })) == "standard")
assert(ModePolicy.resolve(replica({})) == nil)
assert(ModePolicy.resolve(nil) == nil)
assert(
    ModePolicy.resolve(replica({ IsGunGame = false }, function(_self, key)
        return key == "IsGunGame" and true or nil
    end)) == "gun-game",
    "the live replicated getter must be authoritative over the backing data table"
)
local gunGame = replica({ IsGunGame = true })
local standard = replica({ IsGunGame = false })
local controller = {
    GetDuel = function(_self, player)
        return player == "gun-game-player" and gunGame or standard
    end,
}
assert(ModePolicy.fromController(controller, "gun-game-player") == "gun-game")
assert(ModePolicy.fromController(controller, "standard-player") == "standard")
assert(ModePolicy.fromController({}, "gun-game-player") == nil)
assert(ModePolicy.fromController({ GetDuel = function() error("not ready") end }) == nil)
assert(ModePolicy.controllerIsGunGame(controller, "gun-game-player") == true)
assert(ModePolicy.controllerIsGunGame(controller, "standard-player") == false)

print("rivals-mode-policy-contracts-ok")
