local mod = RegisterMod('Mega Satan in Greed Mode', 1)
local game = Game()

mod.ultraGreedRoomIdx = 45
mod.megaSatan2DeathAnimLastFrame = 129 -- default

function mod:onGameStart()
  if not game:IsGreedMode() then
    return
  end
  
  mod.megaSatan2DeathAnimLastFrame = mod:getMegaSatan2DeathAnimLastFrame()
end

function mod:onNewRoom()
  if not game:IsGreedMode() then
    return
  end
  
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex >= 0 then
    mod:loadMegaSatanRoom()
  end
end

-- filtered to PICKUP_BIGCHEST
function mod:onPickupInit(pickup)
  if not game:IsGreedMode() then
    return
  end
  
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == mod.ultraGreedRoomIdx then
    mod:spawnMegaSatanDoor()
  end
end

-- filtered to ENTITY_MEGA_SATAN_2
-- waiting for MC_POST_NPC_DEATH crashes the game with: "RNG Seed is zero!"
-- it's not clear which seed this is, i don't see any exposed in the api that are set to zero
function mod:onNpcUpdate(entityNpc)
  if not game:IsGreedMode() then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  if stage == LevelStage.STAGE7_GREED and roomDesc.GridIndex == GridRooms.ROOM_MEGA_SATAN_IDX and entityNpc.Variant == 0 and entityNpc.HitPoints <= 0 then
    local sprite = entityNpc:GetSprite()
    if sprite:IsPlaying('Death') and sprite:GetFrame() >= mod.megaSatan2DeathAnimLastFrame then
      local centerIdx = room:GetGridIndex(room:GetCenterPos())
      
      entityNpc:Remove()
      room:SetClear(true)
      mod:addActiveCharges(1)
      mod:spawnBigChest(room:GetGridPosition(centerIdx))
      mod:spawnGreedDonationMachine(room:GetGridPosition(centerIdx + (2 * 15)))
      mod:spawnGoldenPenny(Isaac.GetFreeNearPosition(Isaac.GetRandomPosition(), 3))
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

function mod:spawnMegaSatanDoor()
  local room = game:GetRoom()
  room:TrySpawnMegaSatanRoomDoor(true)
end

function mod:loadMegaSatanRoom()
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(GridRooms.ROOM_MEGA_SATAN_IDX)
  
  if roomDesc.Data == nil or roomDesc.Data.Type ~= RoomType.ROOM_BOSS or roomDesc.Data.Variant ~= 5000 then
    local roomIdx = level:GetCurrentRoomIndex()
    
    Isaac.ExecuteCommand('goto s.boss.5000') -- mega satan room copied from non-greed mode
    local dbg = level:GetRoomByIdx(GridRooms.ROOM_DEBUG_IDX)
    roomDesc.Data = dbg.Data
    roomDesc.SpawnSeed = dbg.SpawnSeed
    roomDesc.AwardSeed = dbg.AwardSeed
    roomDesc.DecorationSeed = dbg.DecorationSeed
    
    game:StartRoomTransition(roomIdx, Direction.NO_DIRECTION, RoomTransitionAnim.FADE)
  end
end

function mod:addActiveCharges(num)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    for _, slot in ipairs({ ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET }) do -- SLOT_POCKET2
      for j = num, 1, -1 do
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

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, mod.onPickupInit, PickupVariant.PICKUP_BIGCHEST)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_MEGA_SATAN_2)