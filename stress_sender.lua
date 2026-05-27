--[[
  stress_sender.lua
  Computer at a Create Speedometer / Stressometer.
  Reads stress and capacity, sends via wireless modem.
]]

local PROTOCOL = "stress_data"

-- Find Stressometer
local meter = peripheral.find("Create_Stressometer")
if not meter then
  error("Create_Stressometer not found. Place this computer next to a Create Stressometer or Speedometer.")
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

local label = os.getComputerLabel() or "Stress #" .. os.getComputerID()
print("Stress sender started as: " .. label)

while true do
  local stress = meter.getStress()
  local capacity = meter.getStressCapacity()
  local pct = capacity > 0 and math.floor(stress / capacity * 100 + 0.5) or 0

  rednet.broadcast({
    label = label,
    id = os.getComputerID(),
    stress = stress,
    capacity = capacity,
    pct = pct,
  }, PROTOCOL)

  sleep(3)
end
