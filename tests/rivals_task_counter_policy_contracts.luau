local Counter=require("../games/rivals/TaskCounterPolicy")
local now=0
local c=Counter.new({clock=function()return now end})
local shield={Info={Name="Riot Shield"}}
local katana={Info={Name="Katana"}}
local rifle={Info={Name="Assault Rifle"}}
local spray={Name="Spray"}

assert(Counter.hasShieldOrKatana({rifle,shield}) and Counter.hasShieldOrKatana({katana})
    and Counter.hasShieldOrKatana({[shield]=true}))
assert(Counter.shouldSelectSpray({shield}) == true and Counter.shouldSelectSpray({katana}) == true,
    "Riot Shield or Katana in the opponent loadout must make Spray available as our secondary")
assert(Counter.shouldForceSpray(spray, katana) == true
    and Counter.shouldForceSpray(spray, rifle) == false
    and Counter.shouldForceSpray({Name="Handgun"}, katana) == false,
    "Spray may bypass deflection only while the opponent actually holds a defensive item")

assert(c:update(katana)==false)
now=1.0
assert(c:update(katana)==false, "brief Katana holds must not force a weaker weapon")
now=1.3
assert(c:update(katana)==true, "a sustained defensive hold may activate Spray counterplay")
now=1.5
assert(c:update(rifle)==true, "counter release should resist one-frame equipped-item noise")
now=2.3
assert(c:update(rifle)==false, "returning to an offensive weapon must release Spray counterplay")

print("rivals-task-counter-policy-contracts-ok")
