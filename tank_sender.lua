--[[
  tank_sender.lua
  Computer at a Create Fluid Tank. Reads via fluid_storage generic peripheral
  and sends data to the central PC via wireless modem.
]]

-- ══════════════ CONFIG ══════════════
-- Enter the number of blocks in your Create Fluid Tank.
-- Each block holds 8 000 mB (8 buckets).
local TANK_BLOCKS = 36
-- ══════════════════════════════════════════
-- Config is auto-saved to .tank_config on update and loaded on restart.
-- ══════════════════════════════════════════

local CAPACITY = TANK_BLOCKS * 8000
local TANK_FLUID_COLOR = nil  -- set by central PC via tank_config
local TANK_FOOT = 3           -- footprint side (1..3), persisted
local TANK_HEIGHT = 4         -- height in blocks, persisted

-- Load persisted config
local function loadConfig()
  local f = fs.open(".tank_config", "r")
  if f then
    local ok, data = pcall(textutils.unserialize, f.readAll())
    f.close()
    if ok and type(data) == "table" then
      if data.blocks and data.blocks > 0 then
        TANK_BLOCKS = data.blocks
        CAPACITY = TANK_BLOCKS * 8000
      end
      if data.foot then TANK_FOOT = data.foot end
      if data.height then TANK_HEIGHT = data.height end
      if data.fluidColor then TANK_FLUID_COLOR = data.fluidColor end
    end
  end
end

-- Persist config to disk
local function saveConfig()
  local f = fs.open(".tank_config", "w")
  if f then
    f.write(textutils.serialize({
      blocks = TANK_BLOCKS,
      foot = TANK_FOOT,
      height = TANK_HEIGHT,
      fluidColor = TANK_FLUID_COLOR,
    }))
    f.close()
  end
end

loadConfig()

-- Find fluid_storage (Create tank)
local tank = peripheral.find("fluid_storage")
if not tank then
  error("Fluid tank not found. Place this computer next to a Create Fluid Tank.")
end

-- Open wireless modem
local modemSide = nil
for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    modemSide = side
    break
  end
end
if not modemSide then
  error("Wireless modem not found.")
end
rednet.open(modemSide)

local label = os.getComputerLabel() or "Tank #" .. os.getComputerID()
print("Tank sender started as: " .. label)
print("Capacity: " .. CAPACITY .. " mB (" .. TANK_BLOCKS .. " blocks)")

-- Main loop: broadcast every 3s, listen for config updates
local function doBroadcast()
  local tanks = tank.tanks()
  for _, t in pairs(tanks) do
    if t then t.capacity = CAPACITY end
  end
   local msg = {
     label = label,
     id = os.getComputerID(),
     blocks = TANK_BLOCKS,
     foot = TANK_FOOT,
     height = TANK_HEIGHT,
     tanks = tanks,
   }
   if TANK_FLUID_COLOR then msg.fluidColor = TANK_FLUID_COLOR end
  rednet.broadcast(msg, "tank_data")
end

doBroadcast()

while true do
  local timer = os.startTimer(3)
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "timer" and p1 == timer then
      break
    elseif event == "rednet_message" then
      local senderId, message, protocol = p1, p2, p3
      if protocol == "tank_config" and message.blocks and message.blocks > 0 then
        TANK_BLOCKS = message.blocks
        CAPACITY = TANK_BLOCKS * 8000
        TANK_FLUID_COLOR = message.fluidColor or TANK_FLUID_COLOR
        if message.foot then TANK_FOOT = message.foot end
        if message.height then TANK_HEIGHT = message.height end
        print("Updated: " .. TANK_BLOCKS .. " blocks (" .. (TANK_FOOT or "?")
          .. "^2 x " .. (TANK_HEIGHT or "?") .. "), " .. CAPACITY .. " mB"
          .. (TANK_FLUID_COLOR and (" color=" .. TANK_FLUID_COLOR) or ""))
        saveConfig()
        doBroadcast()
      end
    end
  end
  doBroadcast()
end
