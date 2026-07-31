local Composition = {}

function Composition.bind(context)
    assert(type(context) == "table" and type(context.getAdapter) == "function")
    local function adapter()
        return context.getAdapter()
    end
    return {
        overlay = {
            cycleGlove = function(direction)
                adapter():cycleGlove(direction)
            end,
            cycleSkin = function(direction)
                adapter():cycleSkin(direction)
            end,
            cycleCosmeticWeapon = function(direction)
                adapter():cycleCosmeticWeapon(direction)
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
