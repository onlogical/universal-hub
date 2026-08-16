local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            preview = { kind = "character" },
        })
    end
    host:aim()
    host:rate("aimSmoothness", "Aim Smoothness")
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        options = {
            {
                label = "Classic",
                value = "limn",
                when = { worldRenderer = "limn" },
                patch = { { "worldRenderer", "limn" } },
            },
            {
                label = "Highlights",
                value = "native",
                when = { worldRenderer = "native" },
                patch = { { "worldRenderer", "native" } },
            },
        },
    })

    host:segmented("Combat", {
        id = "aimMode",
        label = "Aim Type",
        emphasis = "prominent",
        related = {
            { id = "humanAim", kind = "toggle", label = "Human Aim", when = "camera" },
        },
        options = {
            {
                label = "Off",
                value = "off",
                when = { silentAim = false, shotAim = false },
                patch = { { "silentAim", false }, { "shotAim", false } },
            },
            {
                label = "Camera",
                value = "camera",
                when = { silentAim = true, shotAim = false },
                patch = { { "shotAim", false }, { "silentAim", true } },
            },
            {
                label = "Silent",
                value = "silent",
                when = { shotAim = true },
                patch = { { "silentAim", false }, { "shotAim", true } },
            },
        },
    })


    host:section("Combat", "trigger", "Trigger Bot", 64)
    host:option("trigger", 1, "triggerBot", "Trigger Bot")
    host:option("trigger", 2, "alwaysScoped", "Always Scoped")

    host:section("Rage", "rage", "RAGE", 70)
    host:option("rage", 1, "teleportBehind", "Warp")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "bhop", "Bunny Hop")
    host:option("movement", 2, "infiniteJump", "Infinite Jump")
    host:option("movement", 3, "wallNoclip", "Wall Noclip")

    host:section("Settings", "taskFarming", "TASK FARMING", 70)
    host:option("taskFarming", 1, "taskAutomationPaused", "Pause Task Farming")
    if type(host.keybind) == "function" then
        host:keybind("taskFarming", "taskAutomationEmergencyKey", "Emergency stop", "End")
    end

    host:section("Tools", "world", "WORLD", 70)
    host:option("world", 1, "autoPickup", "Auto Pickup")

    host:section("Visuals", "visuals", "VISUALS", 70)
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "chamsExcludeAccessories", "Ignore Accessories", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 2, "chamsPerPart", "Part Highlights", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 3, "names", "Names")
    host:option("visuals", 3, "health", "Health")
    host:option("visuals", 4, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
    host:option("visuals", 4, "noFlash", "No Flash")
    host:option("visuals", 5, "noSmoke", "No Smoke")
    host:option("visuals", 6, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
