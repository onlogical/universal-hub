local CombatPipeline = {}

function CombatPipeline.run(phases, frame)
    phases.record(frame)
    phases.defend(frame)
    phases.relocate(frame)
    phases.attack(frame)
    phases.move(frame)
    phases.effects(frame)
    phases.render(frame)
end

return CombatPipeline
