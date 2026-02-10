local mod = RegisterMod('Mega Satan in Greed Mode', 1)
local json = require('json')
local music = MusicManager()
local game = Game()

mod.onGameStartHasRun = false
mod.triggerMegaSatanDoorSpawn = false
mod.megaSatan2DeathAnimLastFrame = 129 -- default

mod.state = {}
mod.state.megaSatanDoorOpened = false -- applies to the last floor so no danger of returning to the floor with glowing hourglass
mod.state.applyToChallenges = false
mod.state.spawnMegaSatanDoorEarly = false

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue and type(state.megaSatanDoorOpened) == 'boolean' then
        mod.state.megaSatanDoorOpened = state.megaSatanDoorOpened
      end
      for _, v in ipairs({ 'applyToChallenges', 'spawnMegaSatanDoorEarly' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
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
    mod.state.megaSatanDoorOpened = false
  else
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
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  local currentDimension = mod:getCurrentDimension()
  
  -- new level, reseed, etc
  if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and currentDimension == 0 and room:IsFirstVisit() then
    mod.state.megaSatanDoorOpened = false
    
    if stage == LevelStage.STAGE7_GREED then
      mod:loadMegaSatanRoom()
    end
  elseif stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX and room:IsClear() then
    mod:spawnMegaSatanDoorExit()
  end
  
  if not mod.state.applyToChallenges and mod:isAnyChallenge() then
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
  if not game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
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
    local door = mod:getDoorByTargetRoomIdx(GridRooms.ROOM_MEGA_SATAN_IDX)
    if door and door.State == DoorState.STATE_OPEN then
      mod.state.megaSatanDoorOpened = true
    end
  end
end

-- filtered to PICKUP_BIGCHEST
function mod:onPickupInit(pickup)
  if not game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
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
-- waiting for MC_POST_NPC_DEATH/MC_PRE_SPAWN_CLEAN_AWARD crashes the game with: RNG Seed is zero!
-- it's not clear which seed this is, i don't see any exposed in the api that are set to zero
-- this is likely related to the rng that determines if we go directly to a cutscene or if a chest + void portal spawns
function mod:onNpcUpdate(entityNpc)
  if not game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  -- mega satan 2 head
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX and entityNpc.Variant == 0 and entityNpc.HitPoints <= 0 then
    local sprite = entityNpc:GetSprite()
    if sprite:IsPlaying('Death') and sprite:GetFrame() + sprite.PlaybackSpeed - 1 >= mod.megaSatan2DeathAnimLastFrame then
      local centerIdx = room:GetGridIndex(room:GetCenterPos())
      
      entityNpc:Remove()
      room:SetClear(true)
      music:Play(Music.MUSIC_BOSS_OVER) -- override MUSIC_SATAN_BOSS
      mod:addActiveCharges(1)
      mod:spawnBigChest(REPENTANCE_PLUS and room:GetCenterPos() or room:GetGridPosition(centerIdx))
      mod:spawnGreedDonationMachine(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth())))
      mod:spawnGoldenPenny(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
      mod:spawnMegaSatanDoorExit()
      
      if not mod:isAnyChallenge() then
        mod:doRepentogonPostMegaSatan2Logic()
      end
      
      Isaac.RunCallbackWithParam(ModCallbacks.MC_POST_NPC_DEATH, EntityType.ENTITY_MEGA_SATAN_2, entityNpc)
    end
  end
end

function mod:doRepentogonPostMegaSatan2Logic()
  if REPENTOGON then
    local gameData = Isaac.GetPersistentGameData()
    gameData:IncreaseEventCounter(EventCounter.MEGA_SATAN_KILLS, 1)
    game:RecordPlayerCompletion(CompletionType.MEGA_SATAN)
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

function mod:spawnMegaSatanDoor()
  if not game:IsGreedMode() or (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  if not mod:getDoorByTargetRoomIdx(GridRooms.ROOM_MEGA_SATAN_IDX) then
    if stage == LevelStage.STAGE7_GREED then
      if mod.state.spawnMegaSatanDoorEarly and level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and mod:getCurrentDimension() == 0 then
        mod:spawnMegaSatanDoorNotTop()
      elseif not mod.state.spawnMegaSatanDoorEarly and room:IsCurrentRoomLastBoss() then
        mod:spawnMegaSatanDoorTop()
      end
    end
  end
end

function mod:spawnMegaSatanDoorTop()
  local room = game:GetRoom()
  
  -- UP0 only
  if room:TrySpawnMegaSatanRoomDoor(true) then
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

function mod:spawnMegaSatanDoorNotTop()
  local room = game:GetRoom()
  
  -- usually left, but could be right or down (random)
  if room:TrySpawnBlueWombDoor(false, true, true) then -- TrySpawnBossRushDoor
    local door = mod:getDoorByTargetRoomIdx(GridRooms.ROOM_BLUE_WOOM_IDX)
    if door then
      local sprite = door:GetSprite()
      door:SetVariant(DoorVariant.DOOR_LOCKED_KEYFAMILIAR)
      door.TargetRoomType = RoomType.ROOM_BOSS
      door.TargetRoomIndex = GridRooms.ROOM_MEGA_SATAN_IDX
      door.OpenAnimation = 'Open' -- Opened by default which doesn't show the opening animation
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
end

function mod:spawnMegaSatanDoorExit()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  
  -- this goes to DOWN0 because it's the only available door slot
  if room:GetDoor(DoorSlot.DOWN0) == nil and room:TrySpawnBlueWombDoor(false, true, true) then -- TrySpawnBossRushDoor
    local door = room:GetDoor(DoorSlot.DOWN0)
    if door then
      local sprite = door:GetSprite()
      door.TargetRoomType = RoomType.ROOM_DEFAULT -- ROOM_BOSS
      door.TargetRoomIndex = level:GetPreviousRoomIndex() -- GetStartingRoomIndex
      sprite:Load('gfx/grid/door_24_megasatandoor.anm2', true)
      sprite:Play('Opened', true)
    end
  end
end

-- return first occurrence
function mod:getDoorByTargetRoomIdx(idx)
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    if door and door.TargetRoomIndex == idx then
      return door
    end
  end
  
  return nil
end

function mod:loadMegaSatanRoom()
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(GridRooms.ROOM_MEGA_SATAN_IDX, -1)
  
  if roomDesc.Data == nil or roomDesc.Data.Type ~= RoomType.ROOM_BOSS or roomDesc.Data.StageID ~= 0 or roomDesc.Data.Variant ~= 5000 then
    if REPENTOGON then
      local seeds = game:GetSeeds()
      local seed = seeds:GetStageSeed(level:GetStage())
      local data = RoomConfigHolder.GetRoomByStageTypeAndVariant(StbType.SPECIAL_ROOMS, RoomType.ROOM_BOSS, 5000, -1)
      roomDesc.Data = data
      roomDesc.SpawnSeed = seed
      roomDesc.AwardSeed = seed
      roomDesc.DecorationSeed = seed
    else
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
  
  local getNextFreeBaseGridRoomOrig = StageAPI.GetNextFreeBaseGridRoom
  
  if type(getNextFreeBaseGridRoomOrig) == 'function' then
    StageAPI.GetNextFreeBaseGridRoom = function(priorityList, taken, nextIsBoss)
      local level = game:GetLevel()
      local stage = level:GetStage()
      local idx = GridRooms.ROOM_MEGA_SATAN_IDX
      
      if game:IsGreedMode() and stage == LevelStage.STAGE7_GREED and not StageAPI.IsIn(taken, idx) then
        table.insert(taken, idx)
      end
      
      return getNextFreeBaseGridRoomOrig(priorityList, taken, nextIsBoss)
    end
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
  return Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL or
         (REPENTOGON and game:GetSeeds():IsCustomRun() and DailyChallenge.GetChallengeParams():GetEndStage() > 0)
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