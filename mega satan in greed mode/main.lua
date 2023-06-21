local mod = RegisterMod('Mega Satan in Greed Mode', 1)
local json = require('json')
local game = Game()

mod.onGameStartHasRun = false
mod.triggerMegaSatanDoorSpawn = false
mod.megaSatan2DeathAnimLastFrame = 129 -- default

mod.state = {}
mod.state.megaSatanDoorSpawned = nil -- nil, early, late
mod.state.megaSatanDoorOpened = false -- applies to the last floor so no danger of returning to the floor with glowing hourglass
mod.state.applyToChallenges = false
mod.state.spawnMegaSatanDoorEarly = false
mod.state.spawnFoolCard = false

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue then
        if state.megaSatanDoorSpawned == 'early' or state.megaSatanDoorSpawned == 'late' then
          mod.state.megaSatanDoorSpawned = state.megaSatanDoorSpawned
        end
        if type(state.megaSatanDoorOpened) == 'boolean' then
          mod.state.megaSatanDoorOpened = state.megaSatanDoorOpened
        end
      end
      if type(state.applyToChallenges) == 'boolean' then
        mod.state.applyToChallenges = state.applyToChallenges
      end
      if type(state.spawnMegaSatanDoorEarly) == 'boolean' then
        mod.state.spawnMegaSatanDoorEarly = state.spawnMegaSatanDoorEarly
      end
      if type(state.spawnFoolCard) == 'boolean' then
        mod.state.spawnFoolCard = state.spawnFoolCard
      end
    end
  end
  
  mod.megaSatan2DeathAnimLastFrame = mod:getMegaSatan2DeathAnimLastFrame()
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit(shouldSave)
  if shouldSave then
    mod:save()
    mod.state.megaSatanDoorSpawned = nil
    mod.state.megaSatanDoorOpened = false
  else
    mod.state.megaSatanDoorSpawned = nil
    mod.state.megaSatanDoorOpened = false
    mod:save()
  end
  
  mod.onGameStartHasRun = false
  mod.triggerMegaSatanDoorSpawn = false
end

function mod:save(settingsOnly)
  if settingsOnly then
    local _, state
    if mod:HasData() then
      _, state = pcall(json.decode, mod:LoadData())
    end
    if type(state) ~= 'table' then
      state = {}
    end
    
    state.applyToChallenges = mod.state.applyToChallenges
    state.spawnMegaSatanDoorEarly = mod.state.spawnMegaSatanDoorEarly
    state.spawnFoolCard = mod.state.spawnFoolCard
    
    mod:SaveData(json.encode(state))
  else
    mod:SaveData(json.encode(mod.state))
  end
end

function mod:onNewRoom()
  if not game:IsGreedMode() then
    return
  end
  
  if not mod.onGameStartHasRun then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  local currentDimension = mod:getCurrentDimension()
  
  -- new level, reseed, etc
  if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and currentDimension == 0 and room:IsFirstVisit() then
    mod.state.megaSatanDoorSpawned = nil
    mod.state.megaSatanDoorOpened = false
    
    if stage == LevelStage.STAGE7_GREED then
      mod:loadMegaSatanRoom()
    end
  end
  
  if not mod.state.megaSatanDoorSpawned and not mod.state.applyToChallenges and mod:isAnyChallenge() then
    return
  end
  
  if stage == LevelStage.STAGE7_GREED and
     (
       (level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and currentDimension == 0) or
       (room:IsCurrentRoomLastBoss() and room:IsClear())
     )
  then
    mod:spawnMegaSatanDoor()
  end
end

function mod:onUpdate()
  if not game:IsGreedMode() or (not mod.state.megaSatanDoorSpawned and not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    mod.triggerMegaSatanDoorSpawn = false
    return
  end
  
  if mod.triggerMegaSatanDoorSpawn then
    mod:spawnMegaSatanDoor()
    mod.triggerMegaSatanDoorSpawn = false
  end
  
  if mod.state.megaSatanDoorOpened then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  local slot = nil
  
  if stage == LevelStage.STAGE7_GREED then
    if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and mod:getCurrentDimension() == 0 then
      slot = DoorSlot.LEFT0
    elseif room:IsCurrentRoomLastBoss() then
      slot = DoorSlot.UP0
    end
    
    if slot then
      local door = room:GetDoor(slot)
      if door and door.TargetRoomIndex == GridRooms.ROOM_MEGA_SATAN_IDX and door.State == DoorState.STATE_OPEN then
        mod.state.megaSatanDoorOpened = true
      end
    end
  end
end

-- filtered to PICKUP_BIGCHEST
function mod:onPickupInit(pickup)
  if not game:IsGreedMode() or (not mod.state.megaSatanDoorSpawned and not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and room:IsCurrentRoomLastBoss() then
    mod:spawnMegaSatanDoor()
  end
end

-- filtered to ENTITY_MEGA_SATAN_2
-- waiting for MC_POST_NPC_DEATH crashes the game with: RNG Seed is zero!
-- it's not clear which seed this is, i don't see any exposed in the api that are set to zero
-- this is likely related to the rng that determines if we go directly to a cutscene or if a chest + void portal spawns
function mod:onNpcUpdate(entityNpc)
  if not game:IsGreedMode() or (not mod.state.megaSatanDoorSpawned and not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  -- mega satan 2 head
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX and entityNpc.Variant == 0 and entityNpc.HitPoints <= 0 then
    local sprite = entityNpc:GetSprite()
    if sprite:IsPlaying('Death') and sprite:GetFrame() >= mod.megaSatan2DeathAnimLastFrame then
      local centerIdx = room:GetGridIndex(room:GetCenterPos())
      
      entityNpc:Remove()
      room:SetClear(true)
      mod:addActiveCharges(1)
      mod:spawnBigChest(room:GetGridPosition(centerIdx))
      mod:spawnGreedDonationMachine(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth())))
      mod:spawnGoldenPenny(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
      
      if mod.state.spawnFoolCard then
        mod:spawnFoolCard(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
      end
    end
  end
end

function mod:spawnBigChest(pos)
  Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_BIGCHEST, 0, pos, Vector.Zero, nil)
end

function mod:spawnGreedDonationMachine(pos)
  game:SetStateFlag(GameStateFlag.STATE_GREED_SLOT_JAMMED, false)
  Isaac.Spawn(EntityType.ENTITY_SLOT, 11, 0, pos, Vector.Zero, nil)
end

function mod:spawnGoldenPenny(pos)
  Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, CoinSubType.COIN_GOLDEN, pos, Vector.Zero, nil)
end

function mod:spawnFoolCard(pos)
  Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_FOOL, pos, Vector.Zero, nil)
end

function mod:spawnMegaSatanDoor()
  if not game:IsGreedMode() or (not mod.state.megaSatanDoorSpawned and not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED then
    if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and mod:getCurrentDimension() == 0 then
      if mod.state.spawnMegaSatanDoorEarly or mod.state.megaSatanDoorSpawned == 'early' then
        if mod.state.megaSatanDoorSpawned ~= 'late' then
          mod:spawnMegaSatanDoorLeft()
        end
      end
    elseif room:IsCurrentRoomLastBoss() then
      if not mod.state.spawnMegaSatanDoorEarly or mod.state.megaSatanDoorSpawned == 'late' then
        if mod.state.megaSatanDoorSpawned ~= 'early' then
          mod:spawnMegaSatanDoorTop()
        end
      end
    end
  end
end

function mod:spawnMegaSatanDoorTop()
  local room = game:GetRoom()
  if room:TrySpawnMegaSatanRoomDoor(true) then
    mod.state.megaSatanDoorSpawned = 'late'
    
    if mod.state.megaSatanDoorOpened then
      local door = room:GetDoor(DoorSlot.UP0)
      if door and door.TargetRoomIndex == GridRooms.ROOM_MEGA_SATAN_IDX then
        local sprite = door:GetSprite()
        door.State = DoorState.STATE_OPEN
        sprite:Play('Opened')
      end
    else
      mod:doDevilKeysIntegration()
    end
  end
end

-- it's possible to spawn a GRID_DOOR/DOOR_LOCKED_KEYFAMILIAR on its own, but the key doesn't interact with it
function mod:spawnMegaSatanDoorLeft()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local currentRoomDesc = level:GetCurrentRoomDesc() -- starting room / empty room
  local leftRoomIdx = level:GetCurrentRoomIndex() - 1 -- 84 - 1 = 83
  local leftRoomDesc = level:GetRoomByIdx(leftRoomIdx, -1)
  local leftSlot = DoorSlot.LEFT0
  
  if leftRoomDesc.Data == nil then
    if level:MakeRedRoomDoor(level:GetCurrentRoomIndex(), leftSlot) then
      leftRoomDesc = level:GetRoomByIdx(leftRoomIdx, -1)
      if not (leftRoomDesc.Data.Type == currentRoomDesc.Data.Type and leftRoomDesc.Data.Variant == currentRoomDesc.Data.Variant) then
        leftRoomDesc.Data = currentRoomDesc.Data -- small chance it's a special room, override to a normal room
      end
    end
  end
  
  local door = room:GetDoor(leftSlot)
  if door then
    mod.state.megaSatanDoorSpawned = 'early'
    
    local sprite = door:GetSprite()
    door:SetVariant(DoorVariant.DOOR_LOCKED_KEYFAMILIAR)
    door:SetRoomTypes(currentRoomDesc.Data.Type, RoomType.ROOM_BOSS)
    door.TargetRoomIndex = GridRooms.ROOM_MEGA_SATAN_IDX
    sprite:Load('gfx/grid/door_24_megasatandoor.anm2', true)
    
    if mod.state.megaSatanDoorOpened then
      door.State = DoorState.STATE_OPEN
      sprite:Play('Opened')
    else
      door.State = DoorState.STATE_CLOSED
      sprite:Play('Closed')
      mod:doDevilKeysIntegration()
    end
  end
end

function mod:loadMegaSatanRoom()
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(GridRooms.ROOM_MEGA_SATAN_IDX, -1)
  
  if roomDesc.Data == nil or roomDesc.Data.Type ~= RoomType.ROOM_BOSS or roomDesc.Data.Variant ~= 5000 then
    local roomIdx = level:GetCurrentRoomIndex()
    
    Isaac.ExecuteCommand('goto s.boss.5000') -- mega satan room copied from non-greed mode
    local dbg = level:GetRoomByIdx(GridRooms.ROOM_DEBUG_IDX, -1)
    roomDesc.Data = dbg.Data
    roomDesc.SpawnSeed = dbg.SpawnSeed
    roomDesc.AwardSeed = dbg.AwardSeed
    roomDesc.DecorationSeed = dbg.DecorationSeed
    
    game:StartRoomTransition(roomIdx, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, -1)
  end
end

function mod:doDevilKeysIntegration()
  if not DevilKeysMod then
    return
  end
  
  DevilKeysMod.Data.SpawnFullNormalKey = true
  
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    player:EvaluateItems()
  end
end

function mod:doStageApiOverride()
  if not StageAPI or not StageAPI.Loaded then
    return
  end
  
  local GetNextFreeBaseGridRoom_Old = StageAPI.GetNextFreeBaseGridRoom
  
  StageAPI.GetNextFreeBaseGridRoom = function(priorityList, taken, nextIsBoss)
    local level = game:GetLevel()
    local stage = level:GetStage()
    local idx = GridRooms.ROOM_MEGA_SATAN_IDX
    
    if game:IsGreedMode() and stage == LevelStage.STAGE7_GREED and not StageAPI.IsIn(taken, idx) then
      table.insert(taken, idx)
    end
    
    return GetNextFreeBaseGridRoom_Old(priorityList, taken, nextIsBoss)
  end
end

function mod:getCurrentDimension()
  local level = game:GetLevel()
  return mod:getDimension(level:GetCurrentRoomDesc())
end

function mod:getDimension(roomDesc)
  local level = game:GetLevel()
  local ptrHash = GetPtrHash(roomDesc)
  
  -- 0: main dimension
  -- 1: secondary dimension, used by downpour mirror dimension and mines escape sequence
  -- 2: death certificate dimension
  for i = 0, 2 do
    if ptrHash == GetPtrHash(level:GetRoomByIdx(roomDesc.SafeGridIndex, i)) then
      return i
    end
  end
  
  return -1
end

function mod:addActiveCharges(num)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }) do -- SLOT_POCKET2
      for j = 1, num do
        if player:NeedsCharge(slot) then
          player:SetActiveCharge(player:GetActiveCharge(slot) + player:GetBatteryCharge(slot) + 1, slot)
        end
      end
    end
  end
end

function mod:getMegaSatan2DeathAnimLastFrame()
  local sprite = Sprite()
  sprite:Load('gfx/275.000_megasatan2head.anm2', true)
  sprite:SetAnimation('Death', true)
  sprite:SetLastFrame()
  return sprite:GetFrame()
end

function mod:isAnyChallenge()
  return Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  if not ModConfigMenu then
    return
  end
  
  local category = 'Mega Satan in Greed' -- Mode
  for _, v in ipairs({ 'Settings' }) do
    ModConfigMenu.RemoveSubcategory(category, v)
  end
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.applyToChallenges
      end,
      Display = function()
        return (mod.state.applyToChallenges and 'Apply' or 'Do not apply') .. ' to challenges'
      end,
      OnChange = function(b)
        mod.state.applyToChallenges = b
        mod.triggerMegaSatanDoorSpawn = true
        mod:save(true)
      end,
      Info = { 'Should the settings below', 'be applied to challenges?' }
    }
  )
  ModConfigMenu.AddSpace(category, 'Settings')
  ModConfigMenu.AddTitle(category, 'Settings', 'Mega Satan')
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.spawnMegaSatanDoorEarly
      end,
      Display = function()
        return 'Spawn door ' .. (mod.state.spawnMegaSatanDoorEarly and 'before' or 'after') .. ' ultra greed'
      end,
      OnChange = function(b)
        mod.state.spawnMegaSatanDoorEarly = b
        mod.triggerMegaSatanDoorSpawn = true
        mod:save(true)
      end,
      Info = { 'Before: Fight mega satan instead of ultra greed', 'After: Fight mega satan after ultra greed' }
    }
  )
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.spawnFoolCard
      end,
      Display = function()
        return (mod.state.spawnFoolCard and 'Spawn' or 'Do not spawn') .. ' fool card'
      end,
      OnChange = function(b)
        mod.state.spawnFoolCard = b
        mod:save(true)
      end,
      Info = { 'Do you want to spawn 0 - The Fool', 'after defeating Mega Satan?' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, mod.onPickupInit, PickupVariant.PICKUP_BIGCHEST)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_MEGA_SATAN_2)

mod:doStageApiOverride()
mod:setupModConfigMenu()