local Presentation = {}

function Presentation.mount(host)
    host:section("Tools", "survival", "SURVIVAL", 70)
    host:option("survival", 1, "antiHit", "Anti Hit")

    host:section("Tools", "combat", "COMBAT", 70)
    host:option("combat", 1, "hitAura", "Hit Aura")
    host:option("combat", 2, "hitAuraIgnoreFriends", "Ignore Friends", "hitAura")

    host:section("Tools", "eggs", "EGGS", 70)
    host:option("eggs", 1, "autoOpenEggs", "Auto Open Eggs")

    host:section("Tools", "prompts", "PROMPTS", 70)
    host:option("prompts", 1, "instantPrompts", "Instant Prompts")
end

return Presentation
