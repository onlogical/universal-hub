local Noclip = require("../games/duelinggrounds/features/Noclip")

local function part(canCollide)
    local value = {
        CanCollide = canCollide,
        character = nil,
        Parent = true,
    }
    function value:IsA(className)
        return className == "BasePart"
    end
    function value:IsDescendantOf(character)
        return self.character == character
    end
    return value
end

local function character(descendants)
    local value = {
        descendants = descendants,
    }
    for _, descendant in ipairs(descendants) do
        descendant.character = value
    end
    function value:GetDescendants()
        return self.descendants
    end
    return value
end

local runtime = Noclip.new()
local collidable = part(true)
local noncollidable = part(false)
local firstCharacter = character({ collidable, noncollidable })

runtime:update(true, firstCharacter)
assert(collidable.CanCollide == false)
assert(noncollidable.CanCollide == false)

local added = part(true)
added.character = firstCharacter
table.insert(firstCharacter.descendants, added)
runtime:update(true, firstCharacter)
assert(added.CanCollide == false)

added.character = nil
table.remove(firstCharacter.descendants, 3)
runtime:update(true, firstCharacter)
assert(added.CanCollide == true, "removed parts must recover their original collision value")

runtime:update(false, firstCharacter)
assert(collidable.CanCollide == true)
assert(noncollidable.CanCollide == false)

runtime:update(true, firstCharacter)
local replacementPart = part(true)
local replacement = character({ replacementPart })
runtime:update(true, replacement)
assert(collidable.CanCollide == true, "character replacement must restore the old character")
assert(replacementPart.CanCollide == false)

runtime:stop()
assert(replacementPart.CanCollide == true)
runtime:update(true, replacement)
assert(replacementPart.CanCollide == true, "stopped modules must remain inert")

print("duelinggrounds-noclip-contracts-ok")
