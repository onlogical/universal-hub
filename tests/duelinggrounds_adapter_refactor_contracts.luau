local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local Definition = require("../games/duelinggrounds/Definition")
local CombatPipeline = require("../games/duelinggrounds/features/CombatPipeline")
local Noclip = require("../games/duelinggrounds/features/Noclip")
local Sampler = require("../games/duelinggrounds/recording/Sampler")
local WinTitles = require("../games/duelinggrounds/features/WinTitles")

local function includes(values, expected)
    return table.find(values, expected) ~= nil
end

local phases = {}
local function phase(name)
    return function(frame)
        assert(frame.id == 7)
        table.insert(phases, name)
    end
end
CombatPipeline.run({
    record = phase("record"),
    defend = phase("defend"),
    relocate = phase("relocate"),
    attack = phase("attack"),
    move = phase("move"),
    effects = phase("effects"),
    render = phase("render"),
}, { id = 7 })
assert(
    table.concat(phases, ",") == "record,defend,relocate,attack,move,effects,render",
    "The combat pipeline must preserve phase ordering"
)

local function model(attributes, humanoidHealth)
    return {
        FindFirstChildOfClass = function(_self, className)
            if className == "Humanoid" then
                return {
                    Health = humanoidHealth,
                }
            end
            return nil
        end,
        GetAttribute = function(_self, name)
            return attributes[name]
        end,
    }
end

local localModel = model({
    Health = 87,
    Posture = 23,
}, 999)
local targetModel = model({
    Health = 41,
    Posture = 68,
}, 999)
local sample = Sampler.sample({
    localHandler = {
        OriginalModel = localModel,
        CanPerformUltimate = function()
            return false
        end,
    },
    targetModel = targetModel,
}, {
    combatStyle = "offensive",
}, 0.25)
assert(
    sample.selfHealth == 87
        and sample.selfPosture == 23
        and sample.targetHealth == 41
        and sample.targetPosture == 68,
    "Recording must read Dueling Grounds native Health and Posture attributes"
)

local collidablePart = {
    CanCollide = true,
    Parent = {},
}
function collidablePart:IsA(className)
    return className == "BasePart"
end
function collidablePart:IsDescendantOf(character)
    return character ~= nil
end
local character = {
    GetDescendants = function()
        return { collidablePart }
    end,
}
local noclip = Noclip.new()
noclip:update(true, character)
assert(collidablePart.CanCollide == false, "Noclip must own collision while enabled")
noclip:stop()
assert(collidablePart.CanCollide == true, "Stopping Noclip must restore collision")
noclip:stop()
assert(collidablePart.CanCollide == true, "Noclip stop must be idempotent")

local titleLabel = {
    Parent = {},
    Text = "Veteran",
}
function titleLabel:IsA(className)
    return className == "TextLabel"
end
local titleCharacter = {}
function titleCharacter:FindFirstChild(name)
    return name == "PlayerTitleLabel" and titleLabel or nil
end
local titlePlayer = {
    Character = titleCharacter,
}
function titlePlayer:GetAttribute(name)
    return ({
        TitleDisplayName = "Duelist",
        TotalWins = 12,
    })[name]
end
local players = {
    GetPlayers = function()
        return { titlePlayer }
    end,
}
local winTitles = WinTitles.new()
winTitles:update(true, players)
assert(titleLabel.Text == "Duelist (12 Wins)", "Win Titles must own its active label text")
winTitles:stop()
assert(titleLabel.Text == "Veteran", "Stopping Win Titles must restore the original label text")
winTitles:stop()
assert(titleLabel.Text == "Veteran", "Win Titles stop must be idempotent")

local expectedExtractedSources = {
    "games/duelinggrounds/features/Noclip",
    "games/duelinggrounds/features/WinTitles",
    "games/duelinggrounds/features/combat/EnemyPolicy",
    "games/duelinggrounds/recording/Sampler",
}
for _, source in ipairs(expectedExtractedSources) do
    assert(
        includes(Definition.sources, source),
        "Dueling Grounds Definition.sources must stage extracted module " .. source
    )
end

print("duelinggrounds-adapter-refactor-contracts-ok")
