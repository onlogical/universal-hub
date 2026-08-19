local WinTitles = require("../games/duelinggrounds/features/WinTitles")

local function label(text)
    local value = {
        Text = text,
        Parent = true,
    }
    function value:IsA(className)
        return className == "TextLabel"
    end
    return value
end

local function player(titleLabel, title, wins)
    local attributes = {
        TitleDisplayName = title,
        TotalWins = wins,
    }
    return {
        Character = {
            FindFirstChild = function(_self, name, recursive)
                assert(recursive == true)
                return name == "PlayerTitleLabel" and titleLabel or nil
            end,
        },
        GetAttribute = function(_self, name)
            return attributes[name]
        end,
    }
end

local roster = {}
local players = {
    GetPlayers = function()
        return roster
    end,
}
local runtime = WinTitles.new()
local customLabel = label("Original custom text")
local emptyLabel = label("Original empty text")
local numericLabel = label("Original numeric text")
local existingLabel = label("Original existing text")
local customPlayer = player(customLabel, "Champion", 12)

roster = {
    customPlayer,
    player(emptyLabel, "", 2),
    player(numericLabel, "4 Wins", 4),
    player(existingLabel, "Champion (7 Wins)", 7),
}
runtime:update(true, players)
assert(customLabel.Text == "Champion (12 Wins)")
assert(emptyLabel.Text == "Original empty text")
assert(numericLabel.Text == "Original numeric text")
assert(existingLabel.Text == "Original existing text", "existing win suffixes must not be duplicated")

runtime:update(false, players)
assert(customLabel.Text == "Original custom text", "disable must restore owned label text")

runtime:update(true, players)
roster = {}
runtime:update(true, players)
assert(customLabel.Text == "Original custom text", "removal must restore owned label text")

roster = { customPlayer }
runtime:update(true, players)
runtime:stop()
assert(customLabel.Text == "Original custom text")
runtime:update(true, players)
assert(customLabel.Text == "Original custom text", "stopped modules must remain inert")

print("duelinggrounds-win-titles-contracts-ok")
