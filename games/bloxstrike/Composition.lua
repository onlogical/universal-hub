local Composition = {}

Composition.dependencies = {
    bloxstrikePreview = "games/bloxstrike/Preview",
    tacticalAdapter = "games/Counterblox",
}

function Composition.bind(context, dependencies)
    assert(type(context) == "table" and type(context.getAdapter) == "function")
    assert(type(dependencies) == "table")
    local function adapter()
        return context.getAdapter()
    end
    return {
        adapter = {
            bloxstrikePreview = assert(dependencies.bloxstrikePreview),
            tacticalAdapter = assert(dependencies.tacticalAdapter),
        },
        overlay = {
            getWeaponPreviewKey = function(state)
                local current = adapter()
                return current and current:weaponPreviewKey(state) or "bloxstrike-weapon-pending"
            end,
            getWeaponPreviewSubject = function(state)
                local current = adapter()
                return current and current:weaponPreviewSubject(state) or nil
            end,
            getPreviewKey = function(state)
                local current = adapter()
                return current and current:previewKey(state) or "bloxstrike-pending"
            end,
            getPreviewSubject = function(state)
                local current = adapter()
                return current and current:previewSubject(state) or nil
            end,
            cycleGlove = function(direction)
                adapter():cycleGlove(direction)
            end,
            previousGlove = function()
                adapter():cycleGlove(-1)
            end,
            nextGlove = function()
                adapter():cycleGlove(1)
            end,
            cycleSkin = function(direction)
                adapter():cycleSkin(direction)
            end,
            previousSkin = function()
                adapter():cycleSkin(-1)
            end,
            nextSkin = function()
                adapter():cycleSkin(1)
            end,
            cycleCosmeticWeapon = function(direction)
                adapter():cycleCosmeticWeapon(direction)
            end,
            previousCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(-1)
            end,
            nextCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(1)
            end,
            resetSkin = function()
                adapter():resetSkin()
            end,
            resetGlove = function()
                adapter():resetGlove()
            end,
            setGloveWear = function(alpha)
                adapter():setGloveWear(alpha)
            end,
            setGloveColor = function(color)
                adapter():setGloveColor(color)
            end,
            setWear = function(alpha)
                adapter():setWear(alpha)
            end,
            toggleStatTrak = function()
                adapter():toggleStatTrak()
            end,
        },
    }
end

return Composition
