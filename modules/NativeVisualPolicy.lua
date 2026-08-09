local NativeVisualPolicy = {
    FILL_TRANSPARENCY = 0.42,
    OUTLINE_THICKNESS = 2,
    COLORS = {
        danger = Color3.fromRGB(255, 118, 87),
        signal = Color3.fromRGB(98, 214, 173),
        text = Color3.fromRGB(243, 243, 244),
        secondary = Color3.fromRGB(190, 192, 195),
        team = Color3.fromRGB(101, 157, 214),
        track = Color3.fromRGB(39, 41, 46),
    },
}

return table.freeze(NativeVisualPolicy)
