local Swap=require("../games/rivals/tasks/TaskWeaponSwap")
local released=0 local equipped
local empty={Info={Class="Primary",ShootDamage=12},Data={Ammo=0}} local rifle={Info={Class="Secondary",ShootDamage=12},Data={Ammo=18}}
local fighter={EquippedItem=empty,GetEquippedItems=function()return{empty,rifle}end,EquipItem=function(self,item) equipped=item self.EquippedItem=item return true end}
local swap=Swap.new({clock=function()return 1 end,release=function()released+=1 end,weaponPolicy={automationPolicy=function(i)return{cameraAim=i.Info.ShootDamage~=nil}end,damageAtDistance=function(i)return i.Info.ShootDamage end}})
assert(swap:update(true,fighter)==true and equipped==rifle and released==1,"empty task weapons must release fire and switch through Fighter:EquipItem")
local notEmpty={Info={ShootDamage=12},Data={Ammo=1}} fighter.EquippedItem=notEmpty equipped=nil
assert(swap:update(true,fighter)==false and equipped==nil,"task weapon swapping must not interrupt a weapon that still has ammo")

local primary={Info={Class="Primary",ShootDamage=12,MaxAmmo=20},Data={Ammo=2}}
local secondary={Info={Class="Secondary",ShootDamage=20},Data={Ammo=8}}
local utility={Info={Class="Utility",ShootDamage=5}}
fighter.EquippedItem=primary fighter.GetEquippedItems=function()return{primary,false,utility,secondary}end equipped=nil
swap.nextAt=0
assert(swap:update(true,fighter,{health=100},40)==true and equipped==secondary,"task combat must switch to a secondary whose available clip can finish when the primary remainder cannot")
local healthyPrimary={Info={Class="Primary",ShootDamage=12,MaxAmmo=20},Data={Ammo=10}}
fighter.EquippedItem=healthyPrimary fighter.GetEquippedItems=function()return{healthyPrimary,secondary}end equipped=nil
swap.nextAt=0
assert(swap:update(true,fighter,{health=100},40)==false and equipped==nil,"task combat must keep a primary whose remaining clip can finish")

local dictPrimary={Info={Class="Primary",ShootDamage=12},Data={Ammo=0}}
local dictSecondary={Info={Class="Secondary",ShootDamage=20},Data={Ammo=8}}
fighter.EquippedItem=dictPrimary fighter.GetEquippedItems=function()return{[dictPrimary]=true,[dictSecondary]=true}end equipped=nil
swap.nextAt=0
assert(swap:update(true,fighter,{health=100},40)==true and equipped==dictSecondary,"native GetEquippedItems item-to-boolean dictionaries must resolve their item keys")

local loadoutPrimary={Info={Class="Primary",ShootDamage=12},Data={Ammo=0}}
local loadoutSecondary={Info={Class="Secondary",ShootDamage=20},Data={Ammo=8}}
fighter.EquippedItem=loadoutPrimary fighter.Items={loadoutPrimary,loadoutSecondary} fighter.GetEquippedItems=function()return{[loadoutPrimary]=true}end equipped=nil
swap.nextAt=0
assert(swap:update(true,fighter,{health=100},40)==true and equipped==loadoutSecondary,"fighter.Items must supply the full native loadout when GetEquippedItems only reports the current item")
fighter.Items=nil

local blindPrimary={Info={Class="Primary",ShootDamage=12,MaxAmmo=20},Data={Ammo=6}}
local blindSecondary={Info={Class="Secondary",ShootDamage=12,MaxAmmo=13},Data={Ammo=13}}
fighter.EquippedItem=blindPrimary fighter.Items={blindPrimary,blindSecondary} equipped=nil swap.nextAt=0
assert(swap:update(true,fighter,nil,nil)==false and equipped==nil,"unknown target health must not invent a full-health finish check")
print("rivals-task-weapon-swap-contracts-ok")
