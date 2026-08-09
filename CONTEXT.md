# Universal Hub Domain Context

## RIVALS

- **Native match mode** — replicated match state exposed by the active `ClientDuel`. Specialized behavior must read fields such as `IsGunGame`; place IDs are registration metadata, not runtime mode state.
- **Item capability** — behavior evidenced by a live item’s `Info`, `Data`, methods, and replicated implementation shape. Display names never select combat behavior.
- **World utility** — a replicated world object identified by native CollectionService tags or explicit replicated attributes. Names and guessed workspace containers are not utility identity.
- **Gun Game runtime** — owns opt-in pickup discovery, throttling, and synthesized touch lifecycle while native `IsGunGame` is true.
- **Observation runtime** — owns Hydroxide player observation, shooting-range entities, native health, weapon labels, and distance filtering.
- **Hook runtime** — owns optional Shot Aim and Always Scoped hook lifecycles. Hook seams are required only when those capabilities are declared.
- **Visual suppression** — owns reversible mutation of exact client-visible flash and smoke effect instances.
- **Trajectory renderer** — owns Limn trajectory primitives and their cleanup.

## Architectural invariants

- Prism/React owns the menu; Limn owns world rendering.
- Runtime adapters publish no operational enemy/lobby telemetry through Store.
- Unknown native state disables specialized behavior; it does not trigger a place-, name-, or numeric fallback.
- Disabled capabilities perform no executor hook work.
