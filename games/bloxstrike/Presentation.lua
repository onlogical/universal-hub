local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            preview = { kind = "character", weaponLabel = "KNIFE" },
        })
    end
    host:aim()
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

    host:section("Combat", "rage", "AIM", 64, true, 2)
    host:option("rage", 1, "silentAim", "Silent Aim")
    host:option("rage", 1, "wallbang", "Wallbang", "silentAim")
    host:option("rage", 2, "rapidFire", "Rapid Fire")
    host:option("rage", 3, "triggerBot", "Trigger Bot")
    host:option("rage", 3, "noSpread", "No Spread")
    host:option("rage", 4, "noRecoil", "No Recoil")
    host:option("rage", 4, "noWeaponSlow", "No Weapon Slow")

    host:section("Combat", "melee", "MELEE", 70, false, 2)
    host:option("melee", 1, "knifeAura", "Knife Aura")
    host:option("melee", 1, "microStep", "Micro Step", "knifeAura")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "spinBot", "Spin Bot")
    host:option("movement", 1, "bhop", "Bunny Hop")

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
    host:option("visuals", 5, "bombTimer", "Bomb Timer")
    host:option("visuals", 6, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
