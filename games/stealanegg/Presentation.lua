local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Tools", { order = 1 })
        host:page("Visuals", { order = 2 })
    end

    host:section("Tools", "survival", "SURVIVAL", 70)
    host:option("survival", 1, "antiHit", "Anti Hit")
    host:option("survival", 2, "lagSafeMovement", "High Ping Mode", "antiHit")
    host:option("survival", 3, "antiTrap", "Anti Trap")

    host:section("Tools", "combat", "COMBAT", 70)
    host:option("combat", 1, "hitAura", "Hit Aura")
    host:option("combat", 2, "hitAuraIgnoreFriends", "Ignore Friends", "hitAura")

    host:section("Tools", "eggs", "EGGS", 70)
    host:option("eggs", 1, "autoFarm", "Auto Farm")
    host:option("eggs", 2, "autoFarmEternal", "Eternal Eggs", "autoFarm")
    host:option("eggs", 3, "autoFarmSecret", "Secret Eggs", "autoFarm")
    host:option("eggs", 4, "autoFarmIndex", "Complete Index", "autoFarm")
    host:option("eggs", 5, "autoFarmIndexServerHopping", "Index Server Hopping", "autoFarmIndex")
    host:option("eggs", 6, "autoFarmServerHopping", "Rare Server Hopping", "autoFarm")
    host:option("eggs", 7, "autoOpenEggs", "Auto Open Eggs")

    host:section("Tools", "server", "SERVER", 70)
    host:slider("server", "serverHopMaxPing", "Maximum Ping", {
        min = 50,
        max = 300,
        step = 10,
        unit = "ms",
    })
    host:slider("server", "serverHopTargetPopulation", "Target Population", {
        min = 1,
        max = 12,
        step = 1,
        unit = " players",
    })
    host:section("Tools", "serverHop", "SERVER HOP", 70)
    if type(host.button) == "function" then
        host:button("serverHop", "serverHop", "Hop Near Target Population", {
            confirm = "Leave this server and hop near the target population?",
            variant = "primary",
        })
    end

    host:section("Tools", "prompts", "PROMPTS", 70)
    host:option("prompts", 1, "instantPrompts", "Instant Prompts")

    host:section("Visuals", "eggRadar", "EGG RADAR", 70)
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
