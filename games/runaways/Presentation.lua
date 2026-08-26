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
    if type(host.slider) == "function" then
        host:slider("movement", "flySpeed", "Fly Speed", {
            min = 20,
            max = 500,
            step = 10,
            parent = "fly",
        })
    end
    host:option("movement", 2, "speed", "Speed")
    if type(host.slider) == "function" then
        host:slider("movement", "walkSpeed", "Walk Speed", {
            min = 16,
            max = 100,
            step = 2,
            parent = "speed",
        })
    end
end

return Presentation
