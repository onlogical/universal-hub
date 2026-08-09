local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame
local ObservationRuntime = require("../games/rivals/ObservationRuntime")

local near = { character = {}, player = { team = "enemy" }, position = Vector3.new(0, 0, -10) }
near.character.FindFirstChildOfClass = function() return { Health = 80, MaxHealth = 100 } end
local far = { character = {}, player = { team = "enemy" }, position = Vector3.new(0, 0, -2001) }
far.character.FindFirstChildOfClass = near.character.FindFirstChildOfClass
local teammate = { character = {}, player = { team = "team" }, position = Vector3.new(0, 0, -12) }
teammate.character.FindFirstChildOfClass = near.character.FindFirstChildOfClass
local targeting = {
    observePlayers = function(options)
        local result = {}
        for _, observation in ipairs({ near, far, teammate }) do
            if options.isEligible(observation.player, observation.character) then
                table.insert(result, observation)
            end
        end
        return result
    end,
    observeCharacter = function() return nil end,
}
local workspace = {
    CurrentCamera = { CFrame = CFrame.identity },
    FindFirstChild = function() return nil end,
}
local runtime = ObservationRuntime.new({
    equippedWeapon = function() return "native item" end,
    getFighter = function() return nil end,
    getPlayerTone = function(player) return player.team end,
    isOpponent = function(player) return player.team == "enemy" end,
    targeting = targeting,
    workspace = workspace,
})
local observations = runtime:update(Vector2.zero)
assert(#observations == 1 and observations[1] == near)
assert(near.health == 80 and near.maxHealth == 100 and near.weapon == "native item")
local opponents, visual = runtime:update(Vector2.zero, true, false)
assert(#opponents == 1 and opponents[1] == near,
    "Combat observations must remain opponents-only when teammate ESP is enabled")
assert(#visual == 1 and visual[1] == teammate and teammate.tone == "team",
    "Allies audience mode must render teammates without mixing enemy ESP")
local _, everyone = runtime:update(Vector2.zero, true, true)
assert(#everyone == 2 and table.find(everyone, near) and table.find(everyone, teammate),
    "Multi-select audience mode must combine enemies and allies")
local _, nobody = runtime:update(Vector2.zero, false, false)
assert(#nobody == 0, "Clearing both audience choices must render no player ESP")
near.character.FindFirstChildOfClass = function() return nil end
observations = runtime:update(Vector2.zero)
assert(observations[1].health == nil and observations[1].maxHealth == nil, "missing native health must remain unknown")

print("rivals-observation-runtime-contracts-ok")
