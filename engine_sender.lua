--[[
  engine_sender.lua
  Computer at a Create Steam Engine (boiler).
  Reads from CCCBridge Target Block, parses progress bars,
  sends percentages to central monitor via wireless modem.

  To name this boiler:
    label set "My Boiler"

  Bar chars (CC → Create mapping):
    167 (§)  → filled   (█)
    127 (DEL) → half     (▓)
    21  (CTRL) → empty   (░)
]]

local PROTOCOL = "steam_data"

-- ── Find Target Block ──

local target = peripheral.find("create_target")
if not target then
  error("Target Block (create_target) not found. Place a CCCBridge Target Block near the computer and connect it to a Display Link pointed at a Steam Engine.")
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

local label = os.getComputerLabel() or "Steam Engine #" .. os.getComputerID()
print("Steam Engine sender started as: " .. label)

-- ── Bar parser ──
-- Counts bar chars in the line. Bar is made of bytes 167, 127, 21.
-- Returns percentage 0-100.

local function parseBar(raw)
  local score = 0
  local total = 0
  for i = 1, #raw do
    local b = string.byte(raw, i)
    if b == 167 then        -- § → full block
      score = score + 1
      total = total + 1
    elseif b == 127 then    -- DEL → half block
      score = score + 0.5
      total = total + 1
    elseif b == 21 then     -- Ctrl-U → empty block
      total = total + 1
    end
  end
  if total == 0 then return 0 end
  return math.floor((score / total) * 100 + 0.5)
end

-- ── Status line parser ──
-- "статус котла: 9 ур." → 9

local function parseStatus(raw)
  local _, _, num = raw:find("(%d+)")
  return tonumber(num) or 0
end

-- ── Main loop ──

while true do
  -- Don't resize — read at the Display Link's native size
  local w, h = target.getSize()

  local lines = {}
  for y = 1, h do
    lines[y] = target.getLine(y)
  end

  local boilerLevel = parseStatus(lines[1] or "")
  local pct1 = parseBar(lines[2] or "")
  local pct2 = parseBar(lines[3] or "")
  local pct3 = parseBar(lines[4] or "")

  rednet.broadcast({
    label = label,
    id = os.getComputerID(),
    level = boilerLevel,
    volume_pct = pct1,
    water_pct  = pct2,
    heat_pct   = pct3,
    raw = lines,
  }, PROTOCOL)

  sleep(3)
end
