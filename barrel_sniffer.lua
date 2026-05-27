--[[
  barrel_sniffer.lua
  Computer next to a Create barrel that receives items.
  Polls the barrel every 0.3s, detects new/changed items,
  broadcasts to central monitor via wireless.

  To name this barrel:
    label set "Input #1"
]]

local PROTOCOL = "barrel_flow"

-- ── Find barrel ──

local barrel = peripheral.find("minecraft:barrel")
if not barrel then
  error("Barrel (minecraft:barrel) not found nearby.")
end

-- ── Open wireless modem ──

local modemSide = nil
for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    modemSide = side
    break
  end
end
if not modemSide then
  error("Wireless modem not found. Attach a Wireless Modem to this computer.")
end
rednet.open(modemSide)

local label = os.getComputerLabel() or "Barrel #" .. os.getComputerID()
print("Barrel sniffer started as: " .. label)

-- ── Main loop ──

local prev = {}

while true do
  local current = barrel.list()
  local changes = {}

  for slot, item in pairs(current) do
    local prevItem = prev[slot]
    if not prevItem then
      changes[#changes + 1] = { name = item.name, count = item.count }
    elseif item.name ~= prevItem.name then
      changes[#changes + 1] = { name = item.name, count = item.count }
    elseif item.count > prevItem.count then
      local delta = item.count - prevItem.count
      changes[#changes + 1] = { name = item.name, count = delta }
    end
  end

  if #changes > 0 then
    rednet.broadcast({
      label = label,
      id = os.getComputerID(),
      items = changes,
    }, PROTOCOL)
  end

  prev = current
  sleep(0.3)
end
