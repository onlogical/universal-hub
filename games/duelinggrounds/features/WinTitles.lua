local WinTitles = {}
WinTitles.__index = WinTitles

local function hasWinTitle(title)
    return string.match(title, "%(%d+ Wins?%)$") ~= nil
        or string.match(title, "^%d+ Wins?$") ~= nil
end

function WinTitles.new()
    return setmetatable({
        originals = {},
        stopped = false,
    }, WinTitles)
end

function WinTitles:_restore(label)
    if label.Parent then
        label.Text = self.originals[label]
    end
    self.originals[label] = nil
end

function WinTitles:update(enabled, players)
    if self.stopped then
        return
    end

    local active = {}
    for _, player in ipairs(players:GetPlayers()) do
        local character = player.Character
        local label = character and character:FindFirstChild("PlayerTitleLabel", true)
        local title = player:GetAttribute("TitleDisplayName")
        if label and label:IsA("TextLabel") and type(title) == "string" then
            active[label] = true
            if self.originals[label] == nil then
                self.originals[label] = label.Text
            end
            local wins = player:GetAttribute("TotalWins")
            if enabled == true
                and title ~= ""
                and not hasWinTitle(title)
                and type(wins) == "number"
            then
                label.Text = ("%s (%d Wins)"):format(title, wins)
            else
                label.Text = self.originals[label]
            end
        end
    end

    for label in pairs(self.originals) do
        if not active[label] then
            self:_restore(label)
        end
    end
end

function WinTitles:stop()
    if self.stopped then
        return
    end
    for label in pairs(self.originals) do
        self:_restore(label)
    end
    self.stopped = true
end

return WinTitles
