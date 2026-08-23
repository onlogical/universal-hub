local Presentation = {}

function Presentation.mount(host)
    host:section("Tools", "survival", "SURVIVAL", 70)
    host:option("survival", 1, "antiHit", "Anti Hit")

    host:section("Tools", "prompts", "PROMPTS", 70)
    host:option("prompts", 1, "instantPrompts", "Instant Prompts")
end

return Presentation
