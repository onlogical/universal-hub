local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
Enum = roblox.Enum
Vector3 = roblox.Vector3
local Movement = require("../games/rivals/Movement")
local adapterSource = fs.readFile("games/rivals/Adapter.lua")

local moves = {}
local humanoid = { Move=function(_, direction, relative) table.insert(moves,{direction=direction,relative=relative}) end }
local root = { Position=Vector3.new(0,0,0) }
local fighter = { Entity={Humanoid=humanoid,RootPart=root} }
local captured = false
local now = 0
local movement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={}, getFighter=function()return fighter end,
 getSettings=function()return {}end, isActive=function()return false end, isTaskActive=function()return true end, isInCombat=function()return true end,
 isInputCaptured=function()return captured end, userInputService={}, clock=function()return now end, spawn=function(fn) fn() end,
})
movement:updateTaskCombat(Vector3.new(30,0,0))
assert(#moves==1 and moves[1].direction.X > 0.7 and math.abs(moves[1].direction.Z) > 0.3 and moves[1].relative==false, "task combat must approach distant opponents diagonally through Humanoid:Move")
now=2
movement:updateTaskCombat(Vector3.new(5,0,0))
assert(moves[2].direction.X < 0 and math.abs(moves[2].direction.Z) > 0.1, "task combat must back-strafe instead of standing inside melee range")
captured=true
movement:updateTaskCombat(Vector3.new(30,0,0))
assert(moves[#moves].direction.Magnitude==0, "input capture must release owned task movement")
captured=false
movement:updateTaskCombat(Vector3.new(30,0,0))
movement:stop()
assert(moves[#moves].direction.Magnitude==0, "pause/unload must stop task movement immediately")
local wallMoves = {}
local wallMovement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={}, getFighter=function()return fighter end,
 getSettings=function()return {}end, isActive=function()return true end, isTaskActive=function()return true end,
 isInCombat=function()return true end, isInputCaptured=function()return false end, userInputService={},
 spawn=function(fn)fn()end, taskObstacleProbe=function(_origin, direction) return direction.X > 0.2 end,
})
humanoid.Move=function(_,direction) table.insert(wallMoves,direction) end
wallMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(#wallMoves==1 and math.abs(wallMoves[1].X)<0.1 and math.abs(wallMoves[1].Z)>0.9, "blocked approaches must steer laterally along the wall")
local hazardMoves = {}
humanoid.Move=function(_,direction) table.insert(hazardMoves,direction) end
local hazardMovement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={}, getFighter=function()return fighter end,
 getSettings=function()return {}end, isActive=function()return true end, isTaskActive=function()return true end,
 isInCombat=function()return true end, isInputCaptured=function()return false end, userInputService={}, spawn=function(fn)fn()end,
})
hazardMovement:updateTaskCombat(Vector3.new(30,0,0), {{label="GRENADE",tone="danger",worldPosition=Vector3.new(3,0,0)}})
assert(hazardMoves[1].X < 0, "nearby grenades and fire must repel task movement before detonation")
hazardMovement:updateTaskCombat(nil, {{label="THROWABLE",tone="danger",worldPosition=Vector3.new(3,0,0)}})
assert(hazardMoves[#hazardMoves].X < 0, "task movement must evade throwables even during target-acquisition gaps")
local rifleMoves = {}
humanoid.Move=function(_,direction) table.insert(rifleMoves,direction) end
fighter.EquippedItem = { Info={Type="Gun",IsRaycast=true,ShootCooldown=0.1,MaxAmmo=20} }
local rifleMovement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={}, getFighter=function()return fighter end,
 getSettings=function()return {}end, isActive=function()return true end, isTaskActive=function()return true end,
 isInCombat=function()return true end, isInputCaptured=function()return false end, userInputService={}, spawn=function(fn)fn()end,
 taskLineOfSightBlocked=function() return false end,
})
rifleMovement:updateTaskCombat(Vector3.new(40,0,0))
assert(rifleMoves[1].X < 0 and math.abs(rifleMoves[1].Z) > 0.9, "assault rifles must hold the falloff edge and strafe instead of rushing")
rifleMovement.taskLineOfSightBlocked=function() return true end
rifleMovement:updateTaskCombat(Vector3.new(40,0,0))
assert(rifleMoves[2].X > 0 and math.abs(rifleMoves[2].Z) > rifleMoves[2].X, "assault rifles must slice around blocked corners with lateral commitment")
rifleMovement.taskLineOfSightBlocked=function() return false end
rifleMovement:updateTaskCombat(Vector3.new(40,0,0), nil, {avoidSniperPeek=true,pushSniper=true})
assert(rifleMoves[3].X < 0 and math.abs(rifleMoves[3].Z) > 0.5, "task combat must retreat-strafe instead of walking into an aimed-down sniper's sightline")
rifleMovement.taskLineOfSightBlocked=function() return true end
rifleMovement:updateTaskCombat(Vector3.new(40,0,0), nil, {avoidSniperPeek=true,pushSniper=true})
assert(rifleMoves[4].X < 0, "task combat must deepen cover instead of peeking while a sniper remains scoped")
rifleMovement.taskLineOfSightBlocked=function() return false end
rifleMovement:updateTaskCombat(Vector3.new(40,0,0), nil, {rushUnarmed=true})
assert(rifleMoves[5].X > 0.9, "task combat must rush an opponent who has not equipped a starting weapon")
assert(adapterSource:find("rushUnarmed = opponentFighter ~= nil and opponentItem == nil", 1, true), "task tactics must rush only a known opponent who has not equipped a starting weapon")

local crouchStates = {}
local crouchNow = 0
humanoid.Move=function() end
local crouchMovement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={SetCrouching=function(_,v)table.insert(crouchStates,v)end}, getFighter=function()return fighter end,
 getSettings=function()return{}end,isActive=function()return true end,isTaskActive=function()return true end,isInCombat=function()return true end,
 isInputCaptured=function()return false end,userInputService={},spawn=function(fn)fn()end,clock=function()return crouchNow end,
 taskLineOfSightBlocked=function()return false end,
})
crouchMovement:updateTaskCombat(Vector3.new(40,0,0))
crouchNow=0.3 crouchMovement:updateTaskCombat(Vector3.new(40,0,0))
assert(crouchStates[1]==true and crouchStates[2]==false,"ranged assault-rifle combat must crouch-spam through MechanicsController")
crouchNow=1 crouchMovement:updateTaskCombat(Vector3.new(40,0,0),{{label="GRENADE",tone="danger",worldPosition=Vector3.new(3,0,0)}})
assert(crouchStates[#crouchStates]==false,"hazard evasion must release owned crouching")

local mobilityNow = 0
local slides, highJumps = 0, 0
fighter.CanSlide=function()return true end
local mobilityMovement = Movement.new({
 controlsController={ToggleInput=function()end}, mechanicsController={Slide=function()slides+=1 end,HighJump=function()highJumps+=1 end,StopSliding=function()end},
 getFighter=function()return fighter end,getSettings=function()return{}end,isActive=function()return true end,isTaskActive=function()return true end,
 isInCombat=function()return true end,isInputCaptured=function()return false end,userInputService={},spawn=function(fn)fn()end,clock=function()return mobilityNow end,
 taskLineOfSightBlocked=function()return false end,
})
mobilityMovement:updateTaskCombat(Vector3.new(40,0,0), nil, {avoidSniperPeek=true,pushSniper=true})
mobilityNow=0.2 mobilityMovement:updateTaskCombat(Vector3.new(40,0,0), nil, {avoidSniperPeek=true,pushSniper=true})
assert(slides==1 and highJumps==1,"exposed task combat must use fast slide/high-jump evasion against an aimed-down sniper")

local parkourActions={}
local parkourNow=0
local parkourGrounded=true
fighter.IsGrounded=function()return parkourGrounded end
local parkourMovement=Movement.new({
 controlsController={ToggleInput=function()end},mechanicsController={
  Jump=function()table.insert(parkourActions,"jump")end,
  JumpRequest=function()table.insert(parkourActions,"jump-request")end,
  HighJump=function()table.insert(parkourActions,"high")end,
  DoubleJumpRequest=function()table.insert(parkourActions,"double-request")end,
 },getFighter=function()return fighter end,getSettings=function()return{}end,isActive=function()return true end,
 isTaskActive=function()return true end,isInCombat=function()return true end,isInputCaptured=function()return false end,
 userInputService={},clock=function()return parkourNow end,spawn=function(fn)fn()end,
 taskParkourProbe=function()return{low=true,middle=false,high=false,landing=true}end,
})
parkourMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(parkourActions[1]=="jump","low parkour obstacles must use MechanicsController:Jump")
parkourNow=1 parkourMovement.taskParkourProbe=function()return{low=true,middle=true,high=false,landing=true}end
parkourMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(parkourActions[#parkourActions]=="high","mantle-height obstacles with verified landings must use HighJump")
parkourNow=2 parkourMovement.taskParkourProbe=function()return{low=false,middle=false,high=false,landing=false}end
local actionsBeforeEdge=#parkourActions
parkourMovement:updateTaskCombat(Vector3.new(30,0,0))
parkourGrounded=false parkourNow=2.4 parkourMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(#parkourActions==actionsBeforeEdge,"farm navigation must never jump or double-jump toward an unverified landing")


local infiniteHeld=false
local infiniteCalls=0
local infiniteCaptured=false
local infiniteMovement=Movement.new({
 controlsController={ToggleInput=function()end},mechanicsController={DoubleJump=function()infiniteCalls+=1 end},
 getFighter=function()return fighter end,getSettings=function()return{}end,isActive=function()return true end,isInCombat=function()return true end,
 isInputCaptured=function()return infiniteCaptured end,userInputService={IsKeyDown=function()return infiniteHeld end},spawn=function(fn)fn()end,
})
infiniteHeld=true infiniteMovement:updateInfiniteJump({infiniteJump=true}) infiniteMovement:updateInfiniteJump({infiniteJump=true})
assert(infiniteCalls==1,"Infinite Jump must fire once per physical jump press, not every frame")
infiniteHeld=false infiniteMovement:updateInfiniteJump({infiniteJump=true}) infiniteHeld=true infiniteCaptured=true infiniteMovement:updateInfiniteJump({infiniteJump=true})
assert(infiniteCalls==1,"Infinite Jump must respect hub input capture")


local committedActions={}
local committedNow=0
local committedGrounded=true
local committedRoot={Position=Vector3.new(0,0,0),AssemblyLinearVelocity=Vector3.new(0,0,0)}
local committedFighter={Entity={Humanoid=humanoid,RootPart=committedRoot},EquippedItem={Info={MaxDoubleJumps=1}},IsGrounded=function()return committedGrounded end}
local committedMovement=Movement.new({
 controlsController={ToggleInput=function()end},mechanicsController={
  JumpRequest=function()table.insert(committedActions,"jump")end,
  DoubleJumpRequest=function()table.insert(committedActions,"double")end,
 },getFighter=function()return committedFighter end,getSettings=function()return{}end,isActive=function()return true end,
 isTaskActive=function()return true end,isInCombat=function()return true end,isInputCaptured=function()return false end,
 userInputService={},clock=function()return committedNow end,spawn=function(fn)fn()end,
 taskParkourProbe=function()return{low=false,middle=false,high=false,landing=true,jumpLanding=Vector3.new(8,0,0),jumpConfidence=1}end,
})
committedMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(committedActions[1]=="jump" and committedMovement.taskParkourCommit~=nil,"verified Baritone-style landing plans must commit one native jump")
committedGrounded=false committedNow=.25 committedRoot.Position=Vector3.new(2,1,0) committedRoot.AssemblyLinearVelocity=Vector3.new(0,3,0)
committedMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(#committedActions==1,"committed jumps must not double-jump while ascending")
committedNow=.5 committedRoot.Position=Vector3.new(4,1,0) committedRoot.AssemblyLinearVelocity=Vector3.new(0,-2,0)
committedMovement:updateTaskCombat(Vector3.new(30,0,0)) committedMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(committedActions[2]=="double" and #committedActions==2,"weapon-provided double jumps must use the native request once while descending")
committedGrounded=true committedNow=.8 committedRoot.Position=Vector3.new(8,0,0)
committedMovement:updateTaskCombat(Vector3.new(30,0,0))
assert(committedMovement.taskParkourCommit==nil,"committed parkour must finish only on the verified landing")


local wallNow=0
local wallCalls=0
local wallTaskActive=false
local wallMovement=Movement.new({
 controlsController={ToggleInput=function()end},mechanicsController={},getFighter=function()return fighter end,getSettings=function()return{}end,
 isActive=function()return true end,isTaskActive=function()return wallTaskActive end,isInCombat=function()return true end,
 isInputCaptured=function()return false end,userInputService={},clock=function()return wallNow end,spawn=function(fn)fn()end,
 movementDirection=function()return Vector3.new(1,0,0)end,wallPhase=function()wallCalls+=1 return true end,
})
wallMovement:updateWallPhase({wallPhase=true}) wallMovement:updateWallPhase({wallPhase=true})
assert(wallCalls==1,"Wall Noclip must use a bounded cooldown instead of phasing every frame")
wallNow=1 wallTaskActive=true wallMovement:updateWallPhase({wallPhase=true})
assert(wallCalls==2,"physical movement input must allow Wall Noclip even while farming is active")

print("rivals-task-movement-contracts-ok")
