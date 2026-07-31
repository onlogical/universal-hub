local Presentation = {}

function Presentation.mount(host)
    host:aim()
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:section("rage", "AIM", 64, true)
    host:option("rage", 1, "silentAim", "Silent Aim")
    host:option("rage", 1, "wallbang", "Wallbang", "silentAim")
    host:option("rage", 2, "rapidFire", "Rapid Fire")
    host:option("rage", 3, "triggerBot", "Trigger Bot")
    host:option("rage", 3, "noSpread", "No Spread")
    host:option("rage", 4, "noRecoil", "No Recoil")
    host:option("rage", 4, "noWeaponSlow", "No Weapon Slow")

    host:section("melee", "MELEE", 70)
    host:option("melee", 1, "knifeAura", "Knife Aura")
    host:option("melee", 1, "microStep", "Micro Step", "knifeAura")

    host:section("movement", "MOVEMENT", 70)
    host:option("movement", 1, "spinBot", "Spin Bot")
    host:option("movement", 1, "bhop", "Bunny Hop")

    host:section("visuals", "VISUALS", 70)
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Weapons")
    host:option("visuals", 4, "bombTimer", "Bomb Timer")
    host:option("visuals", 5, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
