local BabyStyle = {}

function BabyStyle.preferences()
    return {
        allowOffense = false,
        counterAllowed = false,
        escapeCorners = true,
        movement = {
            approachDistance = 22,
            orbitDistance = 20,
            retreatDistance = 18,
            orbitInterval = 1.1,
        },
    }
end

return BabyStyle
