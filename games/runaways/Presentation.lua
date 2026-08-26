local Presentation = {}

function Presentation.mount(host)
    host:section("Visuals", "visuals", "PLAYERS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Held Items")
    host:option("visuals", 20, "showEnemies", "Players", "audience")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "fly", "Fly")
    host:number("movement", "flySpeed", "Fly Speed", { min = 0, parent = "fly" })
    host:option("movement", 2, "speed", "Speed")
    host:number("movement", "walkSpeed", "Walk Speed", { min = 0, parent = "speed" })
    host:option("movement", 3, "vehicleFly", "Vehicle Fly")
    host:number("movement", "vehicleFlySpeed", "Vehicle Fly Speed", {
        min = 0,
        parent = "vehicleFly",
    })

    host:section("Combat", "combat", "MELEE", 70)
    host:option("combat", 1, "meleeKnockback", "Melee Knockback")
    host:number("combat", "meleeKnockbackForce", "Knockback Force", {
        min = 0,
        parent = "meleeKnockback",
    })
end

return Presentation
