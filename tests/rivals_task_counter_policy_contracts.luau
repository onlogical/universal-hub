local Counter=require("../games/rivals/TaskCounterPolicy")
local now=0 local c=Counter.new({clock=function()return now end})
local shield={Info={Name="Riot Shield"}} local katana={Info={Name="Katana"}} local rifle={Info={Name="Assault Rifle"}}
assert(Counter.hasShieldOrKatana({rifle,shield})==true and Counter.hasShieldOrKatana({katana})==true and Counter.hasShieldOrKatana({[shield]=true})==true)
assert(Counter.shouldForceSpray({Name="Spray"},{katana})==true and Counter.shouldForceSpray({Name="Handgun"},{katana})==false,"only Spray should bypass defensive Katana/Riot behavior")
assert(c:update({shield})==false) now=.6 assert(c:update({shield})==true,"counter loadouts must require a stable threat before selecting Spray")
now=1 c:update({rifle}) assert(c.active==true) now=2.3 assert(c:update({rifle})==false,"counter switching must use longer release hysteresis to avoid oscillation")
print("rivals-task-counter-policy-contracts-ok")
