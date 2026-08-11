-- Pinball Pokédex ↔ mGBA live bridge.
-- Load in mGBA: Tools ▸ Scripting (paste the one-liner, or dofile this file).
-- Reads live game state to a JSON file the app watches. It can ALSO toggle the e-Reader bonus flags
-- (gMain.eReaderBonuses) on request from the app — the only thing it writes to the game.
--
-- Addresses from the WhenGryphonsFly/pokepinballrs decompilation (branch `clean`).

local SELECTED_FIELD = 0x0200B0C4
local GAME_PTR       = 0x020314E0
local DEX_COUNT      = 0x02031528
local SRAM_FLAGS     = 0x0E000004   -- pokedexFlags in SRAM (= .sav offset 0x4)
local EREADER        = 0x0200B0C7   -- gMain.eReaderBonuses[5]: [guests, rateUp, dxMode, ruin, bonusStage]
local NUM_SPECIES    = 205
local OFF_AREA, OFF_CURSPECIES, OFF_TARGET, OFF_CAUGHT = 0x035, 0x598, 0x59A, 0x5F0
-- gCurrentPinballGame->forceSpecialMons. The game READS this in catch_hatch_picker.c and never
-- writes it (a leftover dev flag), so setting it forces the next Catch 'Em Mode to a special mon —
-- Latios on Ruby / Latias on Sapphire while uncaught, else a random guest.
local OFF_FORCE = 0x12B

local AREAS = {[0]="Forest (Ruby)", [1]="Forest (Sapphire)", [2]="Plains (Ruby)", [3]="Plains (Sapphire)",
  [4]="Ocean (Ruby)", [5]="Ocean (Sapphire)", [6]="Cave (Ruby)", [7]="Cave (Sapphire)",
  [8]="Safari Zone", [9]="Volcano", [10]="Lake", [11]="Wilderness", [12]="Ruins (Ruby)", [13]="Ruins (Sapphire)"}

local OUT = "/tmp/pinball_pokedex_state.json"
local CMD = "/tmp/pinball_pokedex_cmd.json"
local function inEwram(p) return p ~= nil and p >= 0x02000000 and p < 0x02040000 end

local caughtList, prevCount, prevActive = {}, -1, false
local lastCmdSeq = -1

-- Apply a one-shot command from the app: idx 0-4 sets gMain.eReaderBonuses[idx], idx 5 sets
-- forceSpecialMons on the live game. Only ever writes those bytes, and only when the app bumps
-- `seq`, so it can't fight the game every frame.
local function applyCommand(ptr, active)
  local f = io.open(CMD, "r"); if not f then return end
  local s = f:read("*a"); f:close()
  local seq = tonumber(s:match('"seq"%s*:%s*(%-?%d+)'))
  local idx = tonumber(s:match('"idx"%s*:%s*(%d+)'))
  local val = tonumber(s:match('"val"%s*:%s*(%d+)'))
  if not (seq and idx and val and seq > lastCmdSeq) then return end
  if idx >= 0 and idx <= 4 then
    emu:write8(EREADER + idx, val ~= 0 and 1 or 0)
    lastCmdSeq = seq
  elseif idx == 5 and active then      -- forceSpecialMons; needs a game in progress
    emu:write8(ptr + OFF_FORCE, val ~= 0 and 1 or 0)
    lastCmdSeq = seq
  end
end

local function snapshot(ptr, active)
  local field = emu:read8(SELECTED_FIELD)
  local dexCount = emu:read16(DEX_COUNT)
  local area, caught, species, target, force = -1, 0, 0, -1, 0
  if active then
    area    = emu:read8(ptr + OFF_AREA)
    caught  = emu:read16(ptr + OFF_CAUGHT)
    species = emu:read16(ptr + OFF_CURSPECIES)
    target  = emu:read16(ptr + OFF_TARGET)
    force   = emu:read8(ptr + OFF_FORCE)
  end
  local er = string.format("[%d,%d,%d,%d,%d]",
    emu:read8(EREADER), emu:read8(EREADER + 1), emu:read8(EREADER + 2), emu:read8(EREADER + 3), emu:read8(EREADER + 4))
  local hex = {}
  for i = 0, NUM_SPECIES - 1 do hex[i + 1] = string.format("%02x", emu:read8(SRAM_FLAGS + i)) end
  local json = string.format(
    '{"active":%s,"field":%d,"area":%d,"areaName":"%s","caughtThisGame":%d,"registered":%d,"currentSpecies":%d,"target":%d,"caught":"%s","ereader":%s,"force":%d,"dex":"%s"}',
    tostring(active), field, area, AREAS[area] or "-", caught, dexCount, species, target,
    table.concat(caughtList, ","), er, force, table.concat(hex))
  local f = io.open(OUT, "w")
  if f then f:write(json); f:close() end
end

if not _PPB_LOADED then
  _PPB_LOADED = true
  local n = 0
  callbacks:add("frame", function()
    local ptr = emu:read32(GAME_PTR)
    local active = inEwram(ptr)
    if active then
      local count = emu:read16(ptr + OFF_CAUGHT)
      if not prevActive then caughtList = {}; prevCount = count end
      if prevCount >= 0 and count > prevCount then caughtList[#caughtList + 1] = emu:read16(ptr + OFF_TARGET); prevCount = count end
    else
      caughtList = {}; prevCount = -1
    end
    prevActive = active
    n = n + 1
    if n % 15 == 0 then applyCommand(ptr, active); snapshot(ptr, active) end   -- ~4×/sec
  end)
  console:log("Pinball Pokédex bridge loaded (live dex + catch tracking + e-Reader toggles) -> " .. OUT)
else
  console:log("Pinball Pokédex bridge already running")
end
