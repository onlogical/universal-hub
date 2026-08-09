local Skill=require("../games/rivals/TaskSkillRuntime")
local localHum={Health=150,MaxHealth=150} local enemyHum={Health=150,MaxHealth=150}
local char={FindFirstChildOfClass=function()return enemyHum end}
local target={character=char,health=150,maxHealth=150}
local s=Skill.new() local base=s:rates()
for _,health in ipairs({125,100,75}) do localHum.Health=health s:update(localHum,target,0.1) end
for _=1,20 do s:update(localHum,target,0.1) end
local hard=s:rates()
assert(hard.headshotRate>base.headshotRate and hard.missRate<base.missRate,"task aim must respond to a stronger opponent with slightly stronger ephemeral rates")
localHum.Health=140
for _,health in ipairs({110,70,30}) do enemyHum.Health=health target.health=health s:update(localHum,target,0.1) end
for _=1,30 do s:update(localHum,target,0.1) end
local easy=s:rates()
assert(easy.headshotRate<hard.headshotRate and easy.missRate>hard.missRate,"task aim must ease off against a weaker opponent")

local function player(attrs) return {GetAttribute=function(_,name)return attrs[name]end} end
local localPlayer=player({Level=25,StatisticDuelsWinStreak=1})
local rankedEnemy=player({DisplayELO=2100,Level=180,StatisticDuelsWinStreak=7})
local ranked=Skill.new({localPlayer=localPlayer})
local rankedRates=ranked:update(localHum,{player=rankedEnemy,character=char,health=150,maxHealth=150},0.1)
assert(rankedRates.ready==true and rankedRates.statsReady==true and rankedRates.stats.elo==2100,"replicated ELO, level, and duel streak must arm adaptation immediately")
assert(rankedRates.headshotRate>base.headshotRate and rankedRates.missRate<base.missRate,"stronger replicated player stats must select stronger ephemeral aim rates")
assert(rankedRates.headshotRate<=50 and rankedRates.missRate>=20,"adaptive task aim must remain modest rather than producing near-perfect rounds")
print("rivals-task-skill-runtime-contracts-ok")
