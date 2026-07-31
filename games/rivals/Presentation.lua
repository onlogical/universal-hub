local Presentation = {}

function Presentation.mount(host)
    host:aim()
    host:rate("aimSmoothness", "Aim Smoothness")
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:section("rage", "AIM")
    host:option("rage", 1, "silentAim", "Camera Aim")
    host:option("rage", 1, "shotAim", "Silent Aim")
    host:option("rage", 2, "humanAim", "Human Aim", "silentAim")
    host:option("rage", 3, "triggerBot", "Trigger Bot")
    host:option("rage", 3, "alwaysScoped", "Always Scoped")

    host:section("movement", "MOVEMENT")
    host:option("movement", 1, "bhop", "Bunny Hop")

    host:section("world", "WORLD")
    host:option("world", 1, "autoPickup", "Auto Pickup")

    host:section("visuals", "VISUALS")
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Weapons")
    host:option("visuals", 3, "noFlash", "No Flash")
    host:option("visuals", 4, "noSmoke", "No Smoke")
    host:option("visuals", 5, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
