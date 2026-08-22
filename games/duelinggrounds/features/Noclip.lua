local Noclip = {}
Noclip.__index = Noclip

function Noclip.new()
    return setmetatable({
        character = nil,
        originals = {},
        stopped = false,
    }, Noclip)
end

function Noclip:_restore()
    for part, canCollide in pairs(self.originals) do
        if part.Parent then
            part.CanCollide = canCollide
        end
    end
    table.clear(self.originals)
end

function Noclip:update(enabled, character)
    if self.stopped then
        return
    end
    if self.character ~= character then
        self:_restore()
        self.character = character
    end
    if enabled ~= true or not character then
        self:_restore()
        return
    end

    for part in pairs(self.originals) do
        if not part:IsDescendantOf(character) then
            if part.Parent then
                part.CanCollide = self.originals[part]
            end
            self.originals[part] = nil
        end
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if self.originals[descendant] == nil then
                self.originals[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

function Noclip:stop()
    if self.stopped then
        return
    end
    self:_restore()
    self.character = nil
    self.stopped = true
end

return Noclip
