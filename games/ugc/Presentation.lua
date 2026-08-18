local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            views = {
                { id = "preview", label = "Preview" },
                { id = "colors", label = "ESP Colors" },
            },
            preview = { kind = "character" },
        })
    end
    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        treatment = "style",
        options = {
            { label = "Classic", value = "limn", when = { worldRenderer = "limn" }, patch = { { "worldRenderer", "limn" } } },
            { label = "Highlights", value = "native", when = { worldRenderer = "native" }, patch = { { "worldRenderer", "native" } } },
        },
    })
    host:section("Visuals", "visuals", "PLAYERS", 70, false, 1, { treatment = "grid" })
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
    host:option("visuals", 20, "showEnemies", "Players", "audience")

    host:section("Combat", "defense", "DEFENSE", 70)
    host:option("defense", 1, "autoDodge", "Auto Dodge")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "wallPhase", "Wall Phase")
end

return Presentation
