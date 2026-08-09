return {
    composition = "games/bloxstrike/Composition",
    defaults = {},
    features = {
        capabilities = {
            "silentAim", "triggerBot", "wallbang", "knifeAura", "microStep",
            "spinBot", "bhop", "rapidFire", "bombTimer", "utilityEsp",
            "headshotRate", "missRate", "noSpread", "noRecoil", "noFlash",
            "noSmoke", "noWeaponSlow", "boxes", "chams", "chamsExcludeAccessories",
            "chamsPerPart", "showTeammates", "worldRenderer", "names", "health", "weapon",
        },
    },
    hydroxide = { "targeting" },
    id = "bloxstrike",
    initialState = {},
    label = "Bloxstrike",
    manifest = {
        gameIds = { 7633926880 },
        placeIds = { 114234929420007 },
    },
    module = "games/Bloxstrike",
    presentation = "games/bloxstrike/Presentation",
    sources = {
        "games/Bloxstrike",
        "games/Counterblox",
        "games/bloxstrike/Preview",
        "games/bloxstrike/Composition",
        "games/bloxstrike/Presentation",
    },
}
