local DefensiveStyle = {}

function DefensiveStyle.preferences()
    return {
        allowOffense = false,
        counterAllowed = false,
        movement = {
            orbitDistanceScale = 1.2,
        },
    }
end

return DefensiveStyle
