local Runtime = require("../games/rivals/TaskFarmRuntime")
local function signal()
 local callbacks = {}; local s = {}
 function s:Connect(fn) table.insert(callbacks, fn); local c = { connected = true }; function c:Disconnect() if not self.connected then return end; self.connected=false; for i,v in ipairs(callbacks) do if v==fn then table.remove(callbacks,i); break end end end; return c end
 function s:Fire() for _, fn in ipairs(table.clone(callbacks)) do fn() end end
 function s:count() return #callbacks end
 return s
end
local signals, records = {}, { { Name="Beginner7", Progress=0, Completed=false } }
local data = { Get=function(_, key) if key=="Tasks" then return records elseif key=="Wins" then return 0 end end, GetDataChangedSignal=function(_, key) signals[key]=signals[key] or signal(); return signals[key] end }
local fighterSignal, duelSignal = signal(), signal()
local fighter = { Data={ IsInDuel=false, IsInShootingRange=false }, Get=function(self,k)return self.Data[k]end, GetDataChangedSignal=function()return fighterSignal end }
local duel = { Data={Status="Waiting"}, Get=function(self,k)return self.Data[k]end, GetDataChangedSignal=function()return duelSignal end }
local queued, timers, activity = {}, {}, {}
local queueResults = { "Retry", "Success", "Success" }
local runtime = Runtime.new({ taskLibrary={TASKS_DATA_NAMES={"Tasks"},Info={Beginner7={Title="Play a duel",Goal=1}}}, playerDataController=data,
 matchmakingController={QueueInto=function(_,q)table.insert(queued,q); return table.remove(queueResults, 1) end}, fighterController={LocalFighter=fighter}, duelController={GetDuel=function()return duel end},
 constants={BEGINNER_QUEUE_NAME="beginner",BEGINNER_QUEUE_WINS=5}, delay=function(_,fn)table.insert(timers,fn)end, maxQueueAttempts=2,
 onActivityChanged=function(active)table.insert(activity,active)end })
assert(#queued==1 and queued[1]=="beginner" and #timers==1)
timers[1](); assert(#queued==2, "one failed request retries through the public controller boundary")
assert(#timers==1 and runtime:status().state == "queued", "a successful queue response must stop retrying")
runtime:pause("test"); local stale=timers[1]; stale(); assert(#queued==2)
runtime:resume(); assert(#queued==2, "resume must not duplicate an accepted queue request")
fighter.Data.IsInDuel=true; duel.Data.Status="RoundStarted"; fighterSignal:Fire(); assert(runtime:isCombatActive())
assert(activity[#activity] == true, "RoundStarted must wake Adapter frame ownership")
runtime:stop(); assert(not runtime:isCombatActive() and runtime:status().state=="stopped")
assert(activity[#activity] == false, "stop must publish combat deactivation")
assert(signals.Tasks:count()==0 and signals.BeginnerTasksCompleted:count()==0)

local veteranQueue
fighter.Data.IsInDuel=false
local veteranSignals = {}
local veteranData = {
 Get=function(_, key) if key=="Tasks" then return records end end,
 GetStatistic=function(_, key) assert(key=="StatisticDuelsWon"); return 10 end,
 GetDataChangedSignal=function(_, key) veteranSignals[key]=veteranSignals[key] or signal(); return veteranSignals[key] end,
}
local veteran = Runtime.new({ taskLibrary={TASKS_DATA_NAMES={"Tasks"},Info={Beginner7={Title="Play a duel",Goal=1}}},
 playerDataController=veteranData, matchmakingController={QueueInto=function(_,q)veteranQueue=q; return "Success" end},
 fighterController={LocalFighter=fighter}, duelController={GetDuel=function()return nil end},
 constants={BEGINNER_QUEUE_NAME="beginner",BEGINNER_QUEUE_WINS=5}, paused=false })
assert(veteranQueue=="1v1" and veteran:status().state=="queued", "native duel-win statistics must route veterans to 1v1")
veteran:stop()

fighter.Data.IsInDuel=true
duel.Data.Status="GameOver"
local requeueName
local requeueSignals={}
local requeueData={
 Get=function(_,key) if key=="Tasks" then return records end end,
 GetDataChangedSignal=function(_,key) requeueSignals[key]=requeueSignals[key] or signal(); return requeueSignals[key] end,
}
local gameOverRuntime=Runtime.new({ taskLibrary={TASKS_DATA_NAMES={"Tasks"},Info={Beginner7={Title="Play a duel",Goal=1}}},
 playerDataController=requeueData, matchmakingController={QueueInto=function(_,name) requeueName=name; return "Success" end},
 fighterController={LocalFighter=fighter}, duelController={GetDuel=function() return duel end},
 constants={BEGINNER_QUEUE_NAME="beginner",BEGINNER_QUEUE_WINS=5} })
assert(requeueName=="beginner" and gameOverRuntime:status().state=="queued", "GameOver must requeue incomplete PvP work through MatchmakingController")
gameOverRuntime:stop()

local practiceCalls = {}
local practice = {
 setChanged=function(self, callback) self.changed=callback end,
 setTask=function(self, task) self.task=task; table.insert(practiceCalls, task and task.name or "clear") end,
 resume=function() end,
 pause=function(self) self.paused=true end,
 stop=function(self) self.stopped=true end,
 status=function(self) return { state="target-combat" } end,
 isCombatActive=function() return true end,
}
local practiceSignals = {}
local practiceData = {
 Get=function(_, key) if key=="Tasks" then return { {Name="Beginner2",Progress=0,Completed=false} } end end,
 GetDataChangedSignal=function(_, key) practiceSignals[key]=practiceSignals[key] or signal(); return practiceSignals[key] end,
}
fighter.Data.IsInShootingRange=true
local practiceRuntime = Runtime.new({ taskLibrary={TASKS_DATA_NAMES={"Tasks"},Info={Beginner2={Title="Break targets",Goal=5}}},
 playerDataController=practiceData, matchmakingController={QueueInto=function() error("practice tasks must not queue") end},
 fighterController={LocalFighter=fighter}, duelController={GetDuel=function() return nil end}, practiceDriver=practice })
assert(practiceCalls[1]=="Beginner2" and practiceRuntime:isCombatActive())
assert(practiceRuntime:status().state=="target-combat" and practiceRuntime:status().practice.state=="target-combat")
practiceRuntime:pause("test"); assert(practice.paused)
practiceRuntime:stop(); assert(practice.stopped)
print("rivals-task-farm-runtime-contracts-ok")
