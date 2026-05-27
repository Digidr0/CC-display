--[[
  silo_sender.lua
  Computer at a Create Connected Item Silo. Reads inventory, aggregates items
  and sends data to the central PC via wireless modem.
]]

-- Find item silo peripheral
local silo = peripheral.find("create_connected:item_silo")
if not silo then
  error("Item Silo not found. Place this computer next to a Create Connected Item Silo.")
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

local label = os.getComputerLabel() or "Silo #" .. os.getComputerID()
local totalSlots = silo.size()

print("Silo sender started as: " .. label)
print("Total slots: " .. totalSlots)

-- Aggregate items: group by name, sum count, count occupied slots
local function aggregateItems(rawList)
  local items = {}       -- { [name] = { name, count, slots } }
  local usedSlots = 0

  for slot, detail in pairs(rawList) do
    if detail then
      usedSlots = usedSlots + 1
      local name = detail.name or "unknown"
      if not items[name] then
        items[name] = { name = name, count = 0, slots = 0 }
      end
      items[name].count = items[name].count + (detail.count or 0)
      items[name].slots = items[name].slots + 1
    end
  end

  return items, usedSlots
end

-- Main loop
while true do
  local raw = silo.list()
  local items, usedSlots = aggregateItems(raw)

  -- Convert to sorted array (most items first)
  local sorted = {}
  for _, v in pairs(items) do
    sorted[#sorted + 1] = v
  end
  table.sort(sorted, function(a, b) return a.count > b.count end)

  rednet.broadcast({
    label = label,
    id = os.getComputerID(),
    storageType = "item_silo",
    totalSlots = totalSlots,
    usedSlots = usedSlots,
    items = sorted,
  }, "item_data")

  sleep(3)
end
