local mod = RegisterMod('D4 Rerolls Item Wisps', 1)
local game = Game()

mod.rngShiftIdx = 35

-- filtered to COLLECTIBLE_D4 (includes D100, etc)
function mod:onUseItem(collectible, rng, player, useFlags, activeSlot, varData)
  mod:rerollItemWisps(player, rng)
end

--filtered to ENTITY_PLAYER
function mod:onEntityTakeDmg(entity, amount, dmgFlags, source, countdown)
  local player = entity:ToPlayer()
  
  -- no birthright support for now
  if player:GetPlayerType() == PlayerType.PLAYER_EDEN_B and not mod:hasAnyFlag(dmgFlags, DamageFlag.DAMAGE_FAKE | DamageFlag.DAMAGE_NO_PENALTIES) then
    local rng = RNG()
    rng:SetSeed(player.InitSeed, mod.rngShiftIdx)
    mod:rerollItemWisps(player, rng)
  end
end

function mod:rerollItemWisps(player, rng)
  local playerHash = GetPtrHash(player)
  local hasTmtrainer = mod:hasCollectible(CollectibleType.COLLECTIBLE_TMTRAINER)
  local familiar = nil
  local lastSubType = nil
  local orbitLayer7 = false
  local orbitLayer8 = false
  local orbitLayer9 = false
  
  -- this excludes any wisps with EntityFlag.FLAG_NO_QUERY
  for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.ITEM_WISP, -1, false, false)) do
    familiar = v:ToFamiliar()
    
    if playerHash == GetPtrHash(familiar.Player) then
      if hasTmtrainer then
        -- generate new glitched items, limited to 26 item wisps per player
        -- they don't seem to do anything, but this is how lemegeton behaves in this case
        familiar:Remove()
        player:UseActiveItem(CollectibleType.COLLECTIBLE_LEMEGETON, false, false, true, false, -1, 0)
      else
        -- there's a hard limit of 64 familiars, including item wisps
        -- removing and adding in the same frame uses up multiple slots, limiting you to half
        -- setting SubType updates the sprite, but we have to finish with one AddItemWisp to trigger the new effects
        -- this can still bump up against the limit because item wisps can spawn other familiars
        -- EvaluateItems doesn't seem to work here
        local familiarUpdated = false
        
        -- according to the wiki: Lemegeton has a 25% chance to summon an item from the current room's item pool, or from a random item pool
        if rng:RandomFloat() < 0.25 then
          local room = game:GetRoom()
          local itemPool = game:GetItemPool()
          local itemPoolType = itemPool:GetPoolForRoom(room:GetType(), room:GetSpawnSeed())
          familiarUpdated = mod:updateFamiliar(familiar, itemPoolType, rng, 10)
        end
        
        -- use itemPool over itemConfig so we can respect items that may have been removed from the pool
        local limit = 10
        while not familiarUpdated and limit > 0 do
          local itemPoolType = mod:getRandomItemPoolType(rng)
          familiarUpdated = mod:updateFamiliar(familiar, itemPoolType, rng, 10)
          limit = limit - 1
        end
        if not familiarUpdated then
          familiar.SubType = CollectibleType.COLLECTIBLE_BREAKFAST -- COLLECTIBLE_SAD_ONION
        end
        
        -- reset HitPoints so this is equivalent to Lemegeton/AddItemWisp
        familiar.HitPoints = familiar.MaxHitPoints
        lastSubType = familiar.SubType
        
        if familiar.OrbitLayer == 7 then
          orbitLayer7 = true
        elseif familiar.OrbitLayer == 8 then
          orbitLayer8 = true
        elseif familiar.OrbitLayer == 9 then
          orbitLayer9 = true
        end
      end
    end
  end
  
  if lastSubType then
    familiar:Remove()
    -- adjustOrbitLayer == false : 1 layer, layer == 8 (speed < 0)
    -- adjustOrbitLayer == true : 3 layers, layer == 7 (speed > 0), 8 (speed < 0), 9 (speed > 0)
    player:AddItemWisp(lastSubType, player.Position, not (orbitLayer8 and not orbitLayer7 and not orbitLayer9))
  end
end

function mod:updateFamiliar(familiar, itemPoolType, rng, limit)
  local itemPool = game:GetItemPool()
  local itemConfig = Isaac.GetItemConfig()
  
  while limit > 0 do
    local collectible = itemPool:GetCollectible(itemPoolType, false, rng:Next(), CollectibleType.COLLECTIBLE_NULL)
    local collectibleConfig = itemConfig:GetCollectible(collectible)
    
    if collectibleConfig and collectibleConfig:HasTags(ItemConfig.TAG_SUMMONABLE) then
      familiar.SubType = collectible
      return true
    end
    
    limit = limit - 1
  end
  
  return false
end

function mod:getRandomItemPoolType(rng)
  local isGreedMode = game:IsGreedMode()
  local itemPoolTypes = {
    not isGreedMode and ItemPoolType.POOL_TREASURE or ItemPoolType.POOL_GREED_TREASURE,
    not isGreedMode and ItemPoolType.POOL_SHOP or ItemPoolType.POOL_GREED_SHOP,
    not isGreedMode and ItemPoolType.POOL_BOSS or ItemPoolType.POOL_GREED_BOSS,
    not isGreedMode and ItemPoolType.POOL_DEVIL or ItemPoolType.POOL_GREED_DEVIL,
    not isGreedMode and ItemPoolType.POOL_ANGEL or ItemPoolType.POOL_GREED_ANGEL,
    not isGreedMode and ItemPoolType.POOL_SECRET or ItemPoolType.POOL_GREED_SECRET,
    ItemPoolType.POOL_LIBRARY,
    ItemPoolType.POOL_SHELL_GAME,
    ItemPoolType.POOL_GOLDEN_CHEST,
    ItemPoolType.POOL_RED_CHEST,
    ItemPoolType.POOL_BEGGAR,
    ItemPoolType.POOL_DEMON_BEGGAR,
    not isGreedMode and ItemPoolType.POOL_CURSE or ItemPoolType.POOL_GREED_CURSE,
    ItemPoolType.POOL_KEY_MASTER,
    ItemPoolType.POOL_BATTERY_BUM,
    ItemPoolType.POOL_MOMS_CHEST,
    ItemPoolType.POOL_CRANE_GAME,
    ItemPoolType.POOL_ULTRA_SECRET,
    ItemPoolType.POOL_BOMB_BUM,
    ItemPoolType.POOL_PLANETARIUM,
    ItemPoolType.POOL_OLD_CHEST,
    ItemPoolType.POOL_BABY_SHOP,
    ItemPoolType.POOL_WOODEN_CHEST,
    ItemPoolType.POOL_ROTTEN_BEGGAR,
  }
  
  return itemPoolTypes[rng:RandomInt(#itemPoolTypes) + 1]
end

function mod:hasCollectible(collectible)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    if player:HasCollectible(collectible, false) then
      return true
    end
  end
  
  return false
end

function mod:hasAnyFlag(flags, flag)
  return flags & flag ~= 0
end

mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_D4)
mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDmg, EntityType.ENTITY_PLAYER) -- let other mods "return false"