local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Tools", { order = 1 })
        host:page("Visuals", { order = 2 })
    end

    host:section("Tools", "survival", "SURVIVAL", 70)
    host:option("survival", 1, "antiHit", "Anti Hit")
    host:option("survival", 2, "antiTrap", "Anti Trap")

    host:section("Tools", "combat", "COMBAT", 70)
    host:option("combat", 1, "hitAura", "Hit Aura")
    host:option("combat", 2, "hitAuraIgnoreFriends", "Ignore Friends", "hitAura")

    host:section("Tools", "eggs", "EGGS", 70)
    host:option("eggs", 1, "autoOpenEggs", "Auto Open Eggs")

    host:section("Tools", "prompts", "PROMPTS", 70)
    host:option("prompts", 1, "instantPrompts", "Instant Prompts")

    host:section("Visuals", "highlights", "HIGHLIGHTS", 70, false, 2, { treatment = "grid" })
    host:option("highlights", 1, "eggEsp", "Eggs")
    host:option("highlights", 2, "trapEsp", "Traps")
    host:section("Visuals", "eggFilters", "EGG FILTERS", 70)
    if type(host.slider) == "function" then
        host:slider("eggFilters", "eggEspMinimumRarity", "Min Rarity", {
            min = 1,
            max = 10,
            step = 1,
            parent = "eggEsp",
        })
        host:slider("eggFilters", "eggEspMinimumSize", "Min Size", {
            min = 0.5,
            max = 3,
            step = 0.1,
            unit = "x",
            parent = "eggEsp",
        })
    end
end

return Presentation
