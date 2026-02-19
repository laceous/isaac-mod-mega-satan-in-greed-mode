local mod = RegisterMod('Mega Satan in Greed Mode', 1)
local json = require('json')
local music = MusicManager()
local sfx = SFXManager()
local game = Game()

mod.onGameStartHasRun = false
mod.triggerMegaSatanDoorSpawn = false
mod.megaSatan2DeathAnimLastFrame = 129 -- default

if REPENTOGON then
  mod.sprite = Sprite()
  mod.font = Font()
end

mod.state = {}
mod.state.megaSatanDoorOpened = false -- applies to the last floor so no danger of returning to the floor with glowing hourglass
mod.state.applyToChallenges = false
mod.state.spawnMegaSatanDoorEarly = false
mod.state.allowDeliriumUltraGreedAppear = false
mod.state.spawnFoolCard = false

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue and type(state.megaSatanDoorOpened) == 'boolean' then
        mod.state.megaSatanDoorOpened = state.megaSatanDoorOpened
      end
      for _, v in ipairs({ 'applyToChallenges', 'spawnMegaSatanDoorEarly', 'allowDeliriumUltraGreedAppear', 'spawnFoolCard' }) do
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
    state.allowDeliriumUltraGreedAppear = mod.state.allowDeliriumUltraGreedAppear
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
  
  if not (not mod.state.applyToChallenges and mod:isAnyChallenge()) then
    if stage == LevelStage.STAGE7_GREED and currentDimension == 0 then
      if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() then
        mod:spawnMegaSatanDoor()
        mod:spawnDeliriumRoom()
      elseif room:IsCurrentRoomLastBoss() and room:IsClear() then
        mod:spawnMegaSatanDoor()
      elseif room:GetType() ~= RoomType.ROOM_BOSS and room:GetRoomShape() == RoomShape.ROOMSHAPE_1x1 and roomDesc.GridIndex >= 0 then
        mod:spawnDeliriumRoom() -- fallback if red rooms took all the door slots in the starting room
      end
    end
  end
  
  if stage == LevelStage.STAGE7_GREED then
    mod:doUniqueDeliriumBossDoorIntegration()
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
  local stage = level:GetStage()
  
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
    
    if game.Difficulty == Difficulty.DIFFICULTY_GREED then
      if mod.state.spawnFoolCard and room:GetFrameCount() > 0 then
        mod:spawnFoolCard(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
      end
    else -- DIFFICULTY_GREEDIER
      mod:spawnStairs(room:GetGridPosition(room:GetGridIndex(pickup.Position) + (1 * room:GetGridWidth())))
    end
  end
end

-- filtered to ENTITY_MEGA_SATAN_2 / ENTITY_DELIRIUM / ENTITY_ULTRA_GREED
-- waiting for MC_POST_NPC_DEATH/MC_PRE_SPAWN_CLEAN_AWARD crashes the game with: RNG Seed is zero!
-- it's not clear which seed this is, i don't see any exposed in the api that are set to zero
-- this is likely related to the rng that determines if we go directly to a cutscene or if a chest + void portal spawns
function mod:onNpcUpdate(entityNpc)
  if not game:IsGreedMode() then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if entityNpc.Type == EntityType.ENTITY_MEGA_SATAN_2 then
    -- mega satan 2 head
    if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX and entityNpc.Variant == 0 and entityNpc.HitPoints <= 0 then
      local sprite = entityNpc:GetSprite()
      if sprite:IsPlaying('Death') and sprite:GetFrame() + sprite.PlaybackSpeed - 1 >= mod.megaSatan2DeathAnimLastFrame then
        local centerIdx = room:GetGridIndex(room:GetCenterPos())
        
        entityNpc:Remove()
        room:SetClear(true)
        mod:addActiveCharges(1)
        mod:spawnBigChest(REPENTANCE_PLUS and room:GetCenterPos() or room:GetGridPosition(centerIdx))
        mod:spawnGreedDonationMachine(room:GetGridPosition(centerIdx + (1 * room:GetGridWidth())))
        mod:spawnStairs(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth())))
        mod:spawnGoldenPenny(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
        mod:spawnMegaSatanDoorExit()
        
        -- override MUSIC_SATAN_BOSS
        music:Play(room:GetDecorationSeed() % 2 == 0 and Music.MUSIC_JINGLE_BOSS_OVER or Music.MUSIC_JINGLE_BOSS_OVER2, Options.MusicVolume)
        music:Queue(Music.MUSIC_BOSS_OVER)
        
        if not mod:isAnyChallenge() then
          mod:doRepentogonPostMegaSatan2Logic()
        end
        
        Isaac.RunCallbackWithParam(ModCallbacks.MC_POST_NPC_DEATH, EntityType.ENTITY_MEGA_SATAN_2, entityNpc)
      end
    end
  elseif entityNpc.Type == EntityType.ENTITY_DELIRIUM then
    if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 then
      if not game:HasHallucination() and room:GetFrameCount() % 600 == 0 then
        game:ShowHallucination(math.random(10, 100), BackdropType.NUM_BACKDROPS) -- rng
      end
    end
  else -- ENTITY_ULTRA_GREED
    if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 and roomDesc.Data.StageID == 0 and roomDesc.Data.Type == RoomType.ROOM_BOSS and roomDesc.Data.Variant == 3414 then
      mod:doUltraGreedInNormalModeIntegration(entityNpc:GetSprite())
      
      if not mod.state.allowDeliriumUltraGreedAppear and entityNpc.State == NpcState.STATE_APPEAR_CUSTOM then
        entityNpc.State = 510 -- spin
      end
    end
  end
end

function mod:onPreSpawnAward(rng, pos)
  if not game:IsGreedMode() then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 and roomDesc.Data.StageID == 0 and roomDesc.Data.Type == RoomType.ROOM_BOSS and roomDesc.Data.Variant == 3414 then
    local centerIdx = room:GetGridIndex(room:GetCenterPos())
    
    mod:spawnBigChest(REPENTANCE_PLUS and room:GetCenterPos() or room:GetGridPosition(centerIdx))
    mod:spawnGreedDonationMachine(room:GetGridPosition(centerIdx + (2 * room:GetGridWidth())))
    mod:spawnDeliriumRoomPrizes(rng, centerIdx + (3 * room:GetGridWidth()))
    
    if not mod:isAnyChallenge() then
      mod:doRepentogonPostDeliriumLogic()
    end
    
    -- alt: just stop ultra greed sounds (427-440)
    sfx:StopLoopingSounds()
    
    return true
  end
end

function mod:onRender()
  local hud = game:GetHUD()
  local seeds = game:GetSeeds()
  
  if not game:IsGreedMode() or not hud:IsVisible() or seeds:HasSeedEffect(SeedEffect.SEED_NO_HUD) then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and room:GetType() == RoomType.ROOM_BOSS and room:IsClear() then
    if roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX or
       (roomDesc.GridIndex >= 0 and roomDesc.Data.StageID == 0 and roomDesc.Data.Variant == 3414)
    then
      if not mod.sprite:IsLoaded() then
        mod.sprite:Load('gfx/ui/hudpickups.anm2', true)
      end
      if not mod.font:IsLoaded() then
        mod.font:Load('font/pftempestasevencondensed.fnt')
      end
      
      local coords = Vector(19, 72)
      if REPENTANCE_PLUS then
        coords = coords + Vector(0, 2)
      end
      if game:AchievementUnlocksDisallowed() then -- rgon
        coords = coords + Vector(13, 0)
      end
      coords = coords + game.ScreenShakeOffset + (Options.HUDOffset * Vector(20, 12))
      
      -- https://bindingofisaacrebirth.wiki.gg/wiki/Greed_Donation_Machine#Jam_Chance
      local percent = nil
      local coins = mod:getCoinsDonated(game:GetPlayer(0):GetPlayerType())
      if coins then
        percent = math.floor(0.2 * math.min(100, math.exp(0.023 * coins) - 1) + 0.5)
        if game.Difficulty == Difficulty.DIFFICULTY_GREEDIER then
          percent = math.min(1, percent)
        end
      end
      
      if percent then
        mod.sprite:SetFrame('Idle', 9)
        mod.sprite:Render(coords)
        mod.font:DrawString(percent .. '%', coords.X + 16, coords.Y, KColor.White, 0, false)
      end
    end
  end
end

function mod:onDeliriumTransform(delirium, t, v, force)
  if game:IsGreedMode() then
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    local stage = level:GetStage()
    
    -- don't transform into the ultra greed door
    if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 and t == EntityType.ENTITY_ULTRA_DOOR then
      return { EntityType.ENTITY_ULTRA_GREED, 0 }
    end
  end
end

function mod:onDeliriumPostTransform(delirium)
  if game:IsGreedMode() then
    local level = game:GetLevel()
    local roomDesc = level:GetCurrentRoomDesc()
    local stage = level:GetStage()
    
    if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 and delirium.BossType == EntityType.ENTITY_ULTRA_GREED then
      mod:doUltraGreedInNormalModeIntegration(delirium:GetSprite())
      
      -- spin rather than appear so the camera doesn't move away from the player
      if not mod.state.allowDeliriumUltraGreedAppear then
        delirium.State = 510
      end
    end
  end
end

-- rgon supports counts for modded players, it's not currently exposed in the api, we can't assume 100% like in vanilla
function mod:getCoinsDonated(playerType)
  if REPENTOGON then
    local tbl = {
      [PlayerType.PLAYER_ISAAC] = EventCounter.GREED_MODE_COINS_DONATED_WITH_ISAAC,
      [PlayerType.PLAYER_MAGDALENE] = EventCounter.GREED_MODE_COINS_DONATED_WITH_MAGDALENE,
      [PlayerType.PLAYER_CAIN] = EventCounter.GREED_MODE_COINS_DONATED_WITH_CAIN,
      [PlayerType.PLAYER_JUDAS] = EventCounter.GREED_MODE_COINS_DONATED_WITH_JUDAS,
      [PlayerType.PLAYER_BLACKJUDAS] = EventCounter.GREED_MODE_COINS_DONATED_WITH_JUDAS,
      [PlayerType.PLAYER_BLUEBABY] = EventCounter.GREED_MODE_COINS_DONATED_WITH_BLUE,
      [PlayerType.PLAYER_EVE] = EventCounter.GREED_MODE_COINS_DONATED_WITH_EVE,
      [PlayerType.PLAYER_SAMSON] = EventCounter.GREED_MODE_COINS_DONATED_WITH_SAMSON,
      [PlayerType.PLAYER_AZAZEL] = EventCounter.GREED_MODE_COINS_DONATED_WITH_AZAZEL,
      [PlayerType.PLAYER_LAZARUS] = EventCounter.GREED_MODE_COINS_DONATED_WITH_LAZARUS,
      [PlayerType.PLAYER_LAZARUS2] = EventCounter.GREED_MODE_COINS_DONATED_WITH_LAZARUS,
      [PlayerType.PLAYER_EDEN] = EventCounter.GREED_MODE_COINS_DONATED_WITH_EDEN,
      [PlayerType.PLAYER_THELOST] = EventCounter.GREED_MODE_COINS_DONATED_WITH_THE_LOST,
      [PlayerType.PLAYER_LILITH] = EventCounter.GREED_MODE_COINS_DONATED_WITH_LILITH,
      [PlayerType.PLAYER_KEEPER] = EventCounter.GREED_MODE_COINS_DONATED_WITH_KEEPER,
      [PlayerType.PLAYER_APOLLYON] = EventCounter.GREED_MODE_COINS_DONATED_WITH_APOLLYON,
      [PlayerType.PLAYER_THEFORGOTTEN] = EventCounter.GREED_MODE_COINS_DONATED_WITH_FORGOTTEN,
      [PlayerType.PLAYER_THESOUL] = EventCounter.GREED_MODE_COINS_DONATED_WITH_FORGOTTEN,
      [PlayerType.PLAYER_BETHANY] = EventCounter.GREED_MODE_COINS_DONATED_WITH_BETHANY,
      [PlayerType.PLAYER_JACOB] = EventCounter.GREED_MODE_COINS_DONATED_WITH_JACOB_AND_ESAU,
      [PlayerType.PLAYER_ESAU] = EventCounter.GREED_MODE_COINS_DONATED_WITH_JACOB_AND_ESAU,
      [PlayerType.PLAYER_ISAAC_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_ISAAC,
      [PlayerType.PLAYER_MAGDALENE_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_MAGDALENE,
      [PlayerType.PLAYER_CAIN_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_CAIN,
      [PlayerType.PLAYER_JUDAS_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_JUDAS,
      [PlayerType.PLAYER_BLUEBABY_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_BLUE_BABY,
      [PlayerType.PLAYER_EVE_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_EVE,
      [PlayerType.PLAYER_SAMSON_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_SAMSON,
      [PlayerType.PLAYER_AZAZEL_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_AZAZEL,
      [PlayerType.PLAYER_LAZARUS_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_LAZARUS,
      [PlayerType.PLAYER_LAZARUS2_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_LAZARUS,
      [PlayerType.PLAYER_EDEN_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_EDEN,
      [PlayerType.PLAYER_THELOST_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_THE_LOST,
      [PlayerType.PLAYER_LILITH_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_LILITH,
      [PlayerType.PLAYER_KEEPER_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_KEEPER,
      [PlayerType.PLAYER_APOLLYON_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_APOLLYON,
      [PlayerType.PLAYER_THEFORGOTTEN_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_THE_FORGOTTEN,
      [PlayerType.PLAYER_THESOUL_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_THE_FORGOTTEN,
      [PlayerType.PLAYER_BETHANY_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_BETHANY,
      [PlayerType.PLAYER_JACOB_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_JACOB_AND_ESAU,
      [PlayerType.PLAYER_JACOB2_B] = EventCounter.GREED_MODE_COINS_DONATED_WITH_T_JACOB_AND_ESAU,
    }
    local counter = tbl[playerType]
    if counter then
      local gameData = Isaac.GetPersistentGameData()
      return gameData:GetEventCounter(counter)
    end
  end
  return nil
end

function mod:doRepentogonPostMegaSatan2Logic()
  if REPENTOGON then
    local gameData = Isaac.GetPersistentGameData()
    gameData:IncreaseEventCounter(EventCounter.MEGA_SATAN_KILLS, 1)
    game:RecordPlayerCompletion(CompletionType.MEGA_SATAN)
  end
end

function mod:doRepentogonPostDeliriumLogic()
  if REPENTOGON then
    local gameData = Isaac.GetPersistentGameData()
    gameData:IncreaseEventCounter(EventCounter.DELIRIUM_KILLS, 1)
    game:RecordPlayerCompletion(CompletionType.DELIRIUM)
  end
end

function mod:spawnBigChest(pos)
  Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_BIGCHEST, 0, pos, Vector.Zero, nil)
end

function mod:spawnStairs(pos)
  local room = game:GetRoom()
  
  local stairs = Isaac.GridSpawn(GridEntityType.GRID_STAIRS, 3, pos, true)
  if stairs:GetType() ~= GridEntityType.GRID_STAIRS then
    mod:removeGridEntity(room:GetGridIndex(pos), 0, false, true)
    Isaac.GridSpawn(GridEntityType.GRID_STAIRS, 3, pos, true)
  end
end

function mod:removeGridEntity(gridIdx, pathTrail, keepDecoration, update)
  local room = game:GetRoom()
  
  if REPENTOGON then
    room:RemoveGridEntityImmediate(gridIdx, pathTrail, keepDecoration)
  else
    room:RemoveGridEntity(gridIdx, pathTrail, keepDecoration)
    if update then
      room:Update()
    end
  end
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
  
  local hasDoorSlotAvail = false
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    if room:IsDoorSlotAllowed(i) and room:GetDoor(i) == nil then
      hasDoorSlotAvail = true
      break
    end
  end
  if not hasDoorSlotAvail then
    return -- TrySpawnBlueWombDoor will overwrite doors if they already exist
  end
  
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

function mod:spawnDeliriumRoomPrizes(rng, gridIdx)
  local room = game:GetRoom()
  
  local firstChoices = { Card.CARD_HUMANITY, Card.CARD_SOUL_KEEPER, Card.CARD_DIAMONDS_2, Card.CARD_ACE_OF_DIAMONDS, Card.CARD_JUSTICE, Card.CARD_REVERSE_FOOL, Card.CARD_REVERSE_STARS, Card.CARD_GET_OUT_OF_JAIL }
  local firstChoice = firstChoices[rng:RandomInt(#firstChoices) + 1]
  if firstChoice == Card.CARD_HUMANITY then
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_SOUL_KEEPER then
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_DIAMONDS_2 then
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_ACE_OF_DIAMONDS then
    local secondChoices = { Card.CARD_HIEROPHANT, Card.CARD_LOVERS, Card.CARD_JUSTICE, Card.CARD_QUEEN_OF_HEARTS }
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, secondChoices[rng:RandomInt(#secondChoices) + 1], room:GetGridPosition(gridIdx + 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_JUSTICE then
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_REVERSE_JUSTICE, room:GetGridPosition(gridIdx + 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_REVERSE_FOOL then
    local secondChoices = { Card.CARD_REVERSE_HERMIT, Card.CARD_ACE_OF_DIAMONDS }
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, secondChoices[rng:RandomInt(#secondChoices) + 1], room:GetGridPosition(gridIdx + 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_REVERSE_STARS then
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_REVERSE_HERMIT, room:GetGridPosition(gridIdx + 1), Vector.Zero, nil)
  elseif firstChoice == Card.CARD_GET_OUT_OF_JAIL then
    -- one last chance to open mega satan door
    Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, firstChoice, room:GetGridPosition(gridIdx - 1), Vector.Zero, nil)
  end
end

function mod:spawnDeliriumRoom()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local rooms = level:GetRooms()
  
  if not (rooms:Get(level:GetLastBossRoomListIndex()).Clear or level:GetRoomByIdx(GridRooms.ROOM_MEGA_SATAN_IDX, -1).Clear) then
    return
  end
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    if room.Data.StageID == 0 and room.Data.Type == RoomType.ROOM_BOSS and room.Data.Variant == 3414 then
      return
    end
  end
  
  if REPENTOGON then
    -- this is a 1x1 room, prefer down if possible
    for _, v in ipairs({ DoorSlot.DOWN0, DoorSlot.RIGHT0, DoorSlot.LEFT0, DoorSlot.UP0 }) do
      if room:IsDoorSlotAllowed(v) and room:GetDoor(v) == nil then
        local data = RoomConfigHolder.GetRoomByStageTypeAndVariant(StbType.SPECIAL_ROOMS, RoomType.ROOM_BOSS, 3414, -1)
        if level:TryPlaceRoomAtDoor(data, roomDesc, v, 0, true, true) then
          if MinimapAPI then -- normal map is fine, but minimapi needs a refresh
            MinimapAPI:ClearMap()
            MinimapAPI:LoadDefaultMap()
          end
          return
        end
      end
    end
  else
    -- this is complete jank, putting a 2x2 room in a 1x1 space, but it works
    for _, v in ipairs({ { slot = DoorSlot.DOWN0, add = 13 }, { slot = DoorSlot.RIGHT0, add = 1 }, { slot = DoorSlot.LEFT0, add = -1 }, { slot = DoorSlot.UP0, add = -13 } }) do
      if room:IsDoorSlotAllowed(v.slot) and room:GetDoor(v.slot) == nil then
        if level:MakeRedRoomDoor(roomDesc.GridIndex, v.slot) then
          local redRoomDesc = level:GetRoomByIdx(roomDesc.GridIndex + v.add, -1)
          redRoomDesc.Flags = redRoomDesc.Flags & ~RoomDescriptor.FLAG_RED_ROOM
          
          Isaac.ExecuteCommand('goto s.boss.3414')
          local dbg = level:GetRoomByIdx(GridRooms.ROOM_DEBUG_IDX, -1)
          redRoomDesc.Data = dbg.Data
          
          game:StartRoomTransition(roomDesc.GridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.FADE, nil, -1)
          
          if MinimapAPI then
            MinimapAPI:ClearMap()
            MinimapAPI:LoadDefaultMap()
          end
          return
        end
      end
    end
  end
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

function mod:doUniqueDeliriumBossDoorIntegration()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    if door then
      local targetRoomDesc = level:GetRoomByIdx(door.TargetRoomIndex, -1)
      if (roomDesc.Data.StageID == 0 and roomDesc.Data.Type == RoomType.ROOM_BOSS and roomDesc.Data.Variant == 3414) or
         (targetRoomDesc.Data.StageID == 0 and targetRoomDesc.Data.Type == RoomType.ROOM_BOSS and targetRoomDesc.Data.Variant == 3414)
      then
        -- this fails gracefully if the anm2 file doesn't exist
        local sprite = door:GetSprite()
        sprite:Load('gfx/grid/door_bossdeliriumdoor.anm2', false) -- gfx/grid/Door_10_BossRoomDoor.anm2
        sprite:Play('Close', false)
        sprite:LoadGraphics()
      end
    end
  end
end

function mod:doUltraGreedInNormalModeIntegration(sprite)
  local pngUltraGreedBody = nil -- gfx/bosses/afterbirthplus/deliriumforms/afterbirth/boss_ultragreed_body.png
  local pngUltraGreed = nil     -- gfx/bosses/afterbirthplus/deliriumforms/afterbirth/boss_ultragreed.png
  
  -- check for mods otherwise ReplaceSpritesheet will turn the entity invisible
  if GreedInNormal then
    pngUltraGreedBody = 'gfx/bosses/deliriumforms/boss_ultragreed_body.png'
    pngUltraGreed = 'gfx/bosses/deliriumforms/boss_ultragreed.png'
  elseif Isaac.GetEntityTypeByName('Deli Ultra Greed') > 0 then -- 420
    pngUltraGreedBody = 'gfx/bosses/afterbirth/boss_fake_ultragreed_body.png'
    pngUltraGreed = 'gfx/bosses/afterbirth/boss_fake_ultragreed.png'
  end
  
  if pngUltraGreedBody and pngUltraGreed and string.lower(sprite:GetFilename()) == 'gfx/406.000_ultragreed.anm2' then
    sprite:ReplaceSpritesheet(0, pngUltraGreedBody)
    for i = 1, 8 do
      sprite:ReplaceSpritesheet(i, pngUltraGreed)
    end
    sprite:LoadGraphics()
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
  for _, v in ipairs({
                      { title = nil          , field = 'applyToChallenges'            , txtTrue = 'Apply to challenges'               , txtFalse = 'Do not apply to challenges'               , trigger = true , info = { 'Should the settings below', 'be applied to challenges?' } },
                      { title = 'Mega Satan' , field = 'spawnMegaSatanDoorEarly'      , txtTrue = 'Spawn door before ultra greed'     , txtFalse = 'Spawn door after ultra greed'             , trigger = true , info = { 'Before: Fight mega satan instead of ultra greed', 'After: Fight mega satan after ultra greed' } },
                      { title = 'Delirium'   , field = 'allowDeliriumUltraGreedAppear', txtTrue = 'Allow ultra greed appear animation', txtFalse = 'Do not allow ultra greed appear animation', trigger = false, info = { 'Ultra greed\'s appear animation hijacks the camera', 'This might be ok if you\'re zoomed out' } },
                      { title = 'Ultra Greed', field = 'spawnFoolCard'                , txtTrue = 'Spawn fool card'                   , txtFalse = 'Do not spawn fool card'                   , trigger = false, info = { 'Spawn 0 - The Fool after defeating ultra greed?', 'Only applies to greed mode (not greedier)' } },
                    })
  do
    if v.title then
      ModConfigMenu.AddSpace(category, 'Settings')
      ModConfigMenu.AddTitle(category, 'Settings', v.title)
    end
    ModConfigMenu.AddSetting(
      category,
      'Settings',
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.field]
        end,
        Display = function()
          return mod.state[v.field] and v.txtTrue or v.txtFalse
        end,
        OnChange = function(b)
          mod.state[v.field] = b
          if v.trigger then
            mod.triggerMegaSatanDoorSpawn = true
          end
          mod:save(true)
        end,
        Info = v.info
      }
    )
  end
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, mod.onPickupInit, PickupVariant.PICKUP_BIGCHEST)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_MEGA_SATAN_2)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_DELIRIUM)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)
if REPENTOGON then
  mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
  mod:AddCallback(DeliriumCallbacks.TRANSFORMATION , mod.onDeliriumTransform)
  mod:AddCallback(DeliriumCallbacks.POST_TRANSFORMATION , mod.onDeliriumPostTransform)
else
  mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_ULTRA_GREED)
end

mod:doStageApiOverride()
mod:setupModConfigMenu()