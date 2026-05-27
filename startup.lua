--[[
  base-gui — startup.lua
  Central PC: receives tank data via wireless modem, displays on right-side monitor.
]]

-- ── Peripherals ──

local monitor = peripheral.wrap("right")
if not monitor then
  error("Right-side monitor not found. Attach a monitor to the right side of the computer.")
end

-- Find wireless modem on any side
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

-- ── Monitor setup ──

monitor.setTextScale(0.5)
monitor.clear()

local w, h = monitor.getSize()

local tl, tr, bl, br = "+", "+", "+", "+"
local hz, vt = "-", "|"
local title = " base observer "

-- Store incoming data
local tankData = {}   -- fluid tanks: { [computerId] = { label, tanks } }
local siloData = {}   -- item silos: { [computerId] = { label, items, ... } }
local steamData = nil -- steam engine: { label, level, volume_pct, water_pct, heat_pct }
local stressData = nil -- stressometer: { label, stress, capacity, pct }

-- Detail view state
local selectedSiloId = nil  -- computer ID of silo in detail view, nil for normal
local siloClickZones = {}   -- { { yStart, yEnd, info } } for click detection
local selectedTankId = nil  -- computer ID of tank in detail view, nil for normal
local tankClickZones = {}   -- { { yStart, yEnd, info } } for click detection
local tankFootprint = {}    -- { [computerId] = 1|2|3 } footprint size
local tankHeight = {}       -- { [computerId] = height } height in blocks
local tankFluidColor = {}   -- { [computerId] = color_slot } fluid fill color

local COLOR_SWATCHES = {
  { slot = colors.magenta,   name = "Gold" },
  { slot = colors.brown,     name = "Brown" },
  { slot = colors.orange,    name = "Orange" },
  { slot = colors.lime,      name = "Lime" },
  { slot = colors.blue,      name = "Dark blue" },
  { slot = colors.purple,    name = "Slate blue" },
  { slot = colors.red,       name = "Red" },
  { slot = colors.lightBlue, name = "Aqua" },
  { slot = colors.pink,      name = "Slate" },
  { slot = colors.gray,      name = "Gray" },
  { slot = colors.lightGray, name = "Light gray" },
  { slot = colors.white,     name = "White" },
  { slot = colors.green,     name = "Dark green" },
  { slot = colors.cyan,      name = "Dark brown" },
  { slot = colors.black,     name = "Black" },
}

-- Barrel flow (bottom right notifications)
local barrelFlowEvents = {}  -- { text, label, time }[], most recent first

-- ── Color setup ──

local hasColor = monitor.isColor()
local WHITE = colors.white
local GRAY = colors.gray
local LIGHT_GRAY = colors.lightGray
local BLUE = colors.blue
local GREEN = colors.green


-- ── Frame drawing ──

local function drawFrame()
  if hasColor then monitor.setTextColor(WHITE) end
  -- Top
  monitor.setCursorPos(1, 1)
  monitor.write(tl)
  local titleStart = math.floor((w - #title) / 2) + 1
  for x = 2, titleStart - 1 do
    monitor.setCursorPos(x, 1)
    monitor.write(hz)
  end
  monitor.setCursorPos(titleStart, 1)
  monitor.write(title)
  for x = titleStart + #title, w - 1 do
    monitor.setCursorPos(x, 1)
    monitor.write(hz)
  end
  monitor.setCursorPos(w, 1)
  monitor.write(tr)

  -- Sides
  for y = 2, h - 1 do
    monitor.setCursorPos(1, y)
    monitor.write(vt)
    monitor.setCursorPos(w, y)
    monitor.write(vt)
  end

  -- Bottom
  monitor.setCursorPos(1, h)
  monitor.write(bl)
  for x = 2, w - 1 do
    monitor.setCursorPos(x, h)
    monitor.write(hz)
  end
  monitor.setCursorPos(w, h)
  monitor.write(br)
end

-- ── Helpers ──

local function formatAmount(mb)
  if mb >= 1000000 then
    return string.format("%.1fK B", mb / 1000)
  elseif mb >= 1000 then
    return string.format("%.1f B", mb / 1000)
  else
    return mb .. " mB"
  end
end

local function shortName(name)
  if not name then return "empty" end
  -- Strip namespace like "minecraft:lava" -> "lava"
  local _, _, short = name:find(":(.+)$")
  if short then return short end
  if #name > 16 then return name:sub(1, 16) end
  return name
end

-- ── Custom palette ──

if hasColor then
  -- Storage bar blue (#34414e = RGB 52/255, 65/255, 78/255)
  monitor.setPaletteColor(colors.blue, 52/255, 65/255, 78/255)
  -- Storage fill blue-gray (#485b6e = RGB 72/255, 91/255, 110/255)
  monitor.setPaletteColor(colors.purple, 72/255, 91/255, 110/255)
  -- Tank liquid fill (#9b8149) — moved to magenta to free orange for boiler
  monitor.setPaletteColor(colors.magenta, 155/255, 129/255, 73/255)
  -- Tank border (#9f5c44 = RGB 159/255, 92/255, 68/255)
  monitor.setPaletteColor(colors.brown, 159/255, 92/255, 68/255)
  -- Boiler fill (#a25c42 = RGB 162/255, 92/255, 66/255)
  monitor.setPaletteColor(colors.orange, 162/255, 92/255, 66/255)
  -- Stress gold (#ebbd64 = RGB 235/255, 189/255, 100/255)
  monitor.setPaletteColor(colors.lime, 235/255, 189/255, 100/255)
  -- Burner background (#475a6d = RGB 71/255, 90/255, 109/255)
  monitor.setPaletteColor(colors.pink, 71/255, 90/255, 109/255)
  -- Boiler border text (#3f2014 = RGB 63/255, 32/255, 20/255)
  monitor.setPaletteColor(colors.cyan, 63/255, 32/255, 20/255)
  -- Dark green for tank fluid color
  monitor.setPaletteColor(colors.green, 30/255, 80/255, 30/255)
end

-- Convert CC bit-flag color (e.g. colors.white=1) to blit index (0..15)
local function colorIdx(bitFlag)
  local idx = 0
  while bitFlag > 1 do bitFlag = bitFlag / 2; idx = idx + 1 end
  return idx
end

-- ── Tank ASCII art ──

local TANK_W = 17   -- outer width (было 19 — сужено для 3-колоночного лэйаута)
local TANK_INNER = 13  -- fillable width (between inner borders)
local TANK_ROWS = 14   -- fillable rows (between top/bottom inner borders)
local TANK_H = TANK_ROWS + 4  -- total tank height: 2 top + rows + inner bottom + outer bottom

local BG_FILL = colors.magenta   -- liquid fill (#9b8149 via palette)
local TANK_BORDER = colors.brown -- tank frame (#9f5c44 via palette)
local BG_EMPTY = colors.black

local function drawTank(x, y, fluidName, amount, capacity, fluidColor)
  local pct = capacity and math.min(amount / capacity, 1.0) or 0
  local fill = fluidColor or BG_FILL

  -- Calculate fill
  local fillRows = math.floor(pct * TANK_ROWS)
  local remainder = (pct * TANK_ROWS) - fillRows  -- 0..1, fraction for top fill row

  local tankBottom = y + TANK_H - 1
  if tankBottom >= h then return y end  -- skip if won't fit

  -- Row 1: outer top border
  monitor.setBackgroundColor(BG_EMPTY)
  monitor.setCursorPos(x, y)
  monitor.write(tl .. hz .. string.rep(hz, TANK_INNER) .. hz .. tr)
  y = y + 1

  -- Row 2: inner top border
  monitor.setCursorPos(x, y)
  monitor.write(vt .. tl .. string.rep(hz, TANK_INNER) .. tr .. vt)
  y = y + 1

  -- Rows 3..TANK_ROWS+2: fill area
  for row = 1, TANK_ROWS do
    local rowFromBottom = TANK_ROWS - row + 1  -- 1 = very bottom row
    monitor.setCursorPos(x, y)

      if rowFromBottom <= fillRows then
        if rowFromBottom == fillRows and remainder > 0.01 and fill == BG_FILL then
          -- Top fill row: partially filled with blit gradient
          local fillCount = math.floor(remainder * TANK_INNER)
          local base = colorIdx(BG_FILL)
          local empty = colorIdx(BG_EMPTY)
          local animT = (math.sin(os.clock() * 2) + 1) / 2  -- 0..1
          local bgStr = ""
          for ci = 1, TANK_INNER do
            if ci <= fillCount then
              local ratio = (ci - 1) / math.max(1, fillCount - 1)
              local blend = ratio * animT * 0.5
              local idx = base - blend * base
              if idx < 0 then idx = 0 end
              if idx > 15 then idx = 15 end
              bgStr = bgStr .. string.char(math.floor(idx + 0.5))
            else
              bgStr = bgStr .. string.char(empty)
            end
          end
          local fg = string.rep(string.char(colorIdx(colors.white)), TANK_INNER)
          monitor.write(vt .. vt)
          monitor.blit(string.rep(" ", TANK_INNER), fg, bgStr)
        else
          -- Fully filled row
        monitor.write(vt .. vt)
        monitor.setBackgroundColor(fill)
        monitor.write(string.rep(" ", TANK_INNER))
        monitor.setBackgroundColor(BG_EMPTY)
      end
    else
      -- Empty row
      monitor.setBackgroundColor(BG_EMPTY)
      monitor.write(vt .. vt)
      monitor.write(string.rep(" ", TANK_INNER))
    end

    monitor.write(vt .. vt)
    monitor.setBackgroundColor(BG_EMPTY)
    y = y + 1
  end

  -- Inner bottom border
  monitor.setCursorPos(x, y)
  monitor.write(vt .. bl .. string.rep(hz, TANK_INNER) .. br .. vt)
  y = y + 1

  -- Outer bottom border with info
  local info
  if capacity then
    info = formatAmount(amount) .. "/" .. formatAmount(capacity)
  else
    info = formatAmount(amount)
  end
  local infoLen = #info
  local padTotal = TANK_INNER - infoLen - 2  -- убрать по 1 чёрточке слева и справа
  local padLeft = math.floor(padTotal / 2)
  local padRight = padTotal - padLeft

  monitor.setCursorPos(x, y)
  monitor.write(bl .. hz .. string.rep(hz, padLeft) .. info .. string.rep(hz, padRight) .. hz .. br)
  y = y + 1

  return y
end

-- ── Steam Engine boiler visual ──

local STEAM_W = 15        -- outer width (было 17 — для отступов между колонками)
local STEAM_INNER = 11     -- inner fillable width
local STEAM_ROWS = 13      -- fill rows
-- boiler box = 1(top) + 13(fill) + 1(burners) + 1(bottom+info) = 16 rows
-- + label row = 17 rows (y=2..18)

local STEAM_BORDER = colors.orange   -- custom palette: bright orange
local STEAM_WATER = colors.lightBlue  -- water fill
local STEAM_VOLUME = colors.white     -- steam/volume fill
local BURNER_BG = colors.pink        -- #475a6d burner background

-- Interpolate burner color by heat percent
-- 0%→red  25%→purple  50%→blue  75%→cyan-blue  100%→bright cyan
local function getBurnerColor(hpct)
  local stops = {
    { t=0,   r=1.00, g=0.10, b=0.10 },
    { t=0.25, r=0.70, g=0.10, b=0.80 },
    { t=0.50, r=0.10, g=0.30, b=1.00 },
    { t=0.75, r=0.10, g=0.60, b=1.00 },
    { t=1.00, r=0.00, g=0.85, b=0.90 },
  }
  local t = math.max(0, math.min(1, hpct / 100))
  local a, b2 = stops[1], stops[#stops]
  for i = 1, #stops - 1 do
    if t >= stops[i].t and t <= stops[i+1].t then
      a, b2 = stops[i], stops[i+1]
      break
    end
  end
  local span = b2.t - a.t
  local frac = span > 0 and (t - a.t) / span or 1
  if hasColor then
    monitor.setPaletteColor(colors.yellow,
      a.r + (b2.r - a.r) * frac,
      a.g + (b2.g - a.g) * frac,
      a.b + (b2.b - a.b) * frac
    )
  end
  return colors.yellow
end

-- ── Boiler gradient (disabled — CC-Tweaked limits to 16 indexed colors) ──
-- Gradient would require 15 different palette slots, only 5 are boiler-only.
-- For simplicity, boiler uses a solid fill color (#C8641E via colors.orange).
-- To re-enable: set 5+ palette slots at init, use blit with different indices per row.

local function getGradientHex(t)
  local ci = 1 + t * (#GRADIENT_COLORS - 1)
  local idx = math.floor(ci)
  local frac = ci - idx
  local c1 = GRADIENT_COLORS[idx]
  local c2 = idx < #GRADIENT_COLORS and GRADIENT_COLORS[idx + 1] or c1
  return lerpHex(c1, c2, frac)
end

local FIRE_COLORS = { colors.orange, colors.brown }  -- #C8641E and #9f5c44

local function drawSteamBoiler(x, y, label, volume_pct, water_pct, heat_pct)
  -- 17 rows total: top(1) + fill(13) + bottom(1) + fire(1) + burners(1)
  -- + label = 18 rows
  if y + 18 >= h then return y end

  local my = y
  local BOILER_ROWS = 17

  local volFill = math.floor(math.min(volume_pct / 100, 1) * STEAM_ROWS)
  local watFill = math.floor(math.min(water_pct / 100, 1) * STEAM_ROWS)
  local heatFillCount = math.floor(math.min(heat_pct / 100, 1) * STEAM_ROWS)
  local heatColor = getBurnerColor(heat_pct)

  local BORDER_COLOR = colors.cyan     -- #3f2014 border text (palette-customized, permanent)

  for ri = 0, BOILER_ROWS - 1 do
    -- ri 0..14: gradient rows (top + fill + bottom)
    -- ri 15:    fire row (black bg, between boiler and burners)
    -- ri 16:    burner row (black bg)

    if ri == BOILER_ROWS - 1 then
      -- Burners on black background below the boiler (5 burners)
      monitor.setBackgroundColor(BG_EMPTY)
      monitor.setCursorPos(x, my)
      monitor.write(string.rep(" ", STEAM_W))
      if hasColor then
        monitor.setBackgroundColor(BURNER_BG)
        monitor.setTextColor(heatColor)
      end
      for _, bp in ipairs({1, 4, 7, 10, 13}) do
        monitor.setCursorPos(x + bp, my)
        monitor.write("##")
      end

    elseif ri == BOILER_ROWS - 2 then
      -- Fire row on black background between boiler and burners (5 fires)
      monitor.setBackgroundColor(BG_EMPTY)
      monitor.setCursorPos(x, my)
      monitor.write(string.rep(" ", STEAM_W))
      if hasColor then
        for _, fp in ipairs({1, 4, 7, 10, 13}) do
          local fi = math.random(1, 2)
          monitor.setTextColor(FIRE_COLORS[fi])
          monitor.setBackgroundColor(BG_EMPTY)
          monitor.setCursorPos(x + fp, my)
          monitor.write("##")
        end
      end

    else
      -- Gradient row (top, fill, or bottom)
      -- Solid #C8641E (colors.orange palette set at init)
      monitor.setBackgroundColor(STEAM_BORDER)
      monitor.setCursorPos(x, my)
      monitor.write(string.rep(" ", STEAM_W))

      if ri >= 1 and ri <= STEAM_ROWS then
        -- Fill row: centered bars + side borders
        local rowFromBottom = STEAM_ROWS - (ri - 1)

        if rowFromBottom <= volFill then
          if hasColor then monitor.setBackgroundColor(STEAM_VOLUME) end
          monitor.setCursorPos(x + 5, my)
          monitor.write(" ")
        end
        if rowFromBottom <= watFill then
          if hasColor then monitor.setBackgroundColor(STEAM_WATER) end
          monitor.setCursorPos(x + 7, my)
          monitor.write(" ")
        end
        if rowFromBottom <= heatFillCount then
          if hasColor then monitor.setBackgroundColor(heatColor) end
          monitor.setCursorPos(x + 9, my)
          monitor.write(" ")
        end

        -- Side borders on top of gradient (|)
        if hasColor then
          monitor.setBackgroundColor(STEAM_BORDER)  -- reset to gradient bg
          monitor.setTextColor(BORDER_COLOR)
        end
        monitor.setCursorPos(x, my)
        monitor.write("|")
        monitor.setCursorPos(x + STEAM_W - 1, my)
        monitor.write("|")

      elseif ri == STEAM_ROWS + 1 then
        -- Bottom gradient row: border (└─⋯─┘) + info text on top
        if hasColor then monitor.setTextColor(BORDER_COLOR) end
        monitor.setCursorPos(x, my)
        monitor.write("+")
        monitor.setCursorPos(x + STEAM_W - 1, my)
        monitor.write("+")
        monitor.setCursorPos(x + 1, my)
        monitor.write(string.rep("-", STEAM_W - 2))

        -- Info text drawn over the bottom border
        local info = math.floor(volume_pct) .. "%/" .. math.floor(water_pct) .. "%"
        local padLeft = math.floor((STEAM_INNER - #info) / 2)
        if hasColor then monitor.setTextColor(WHITE) end
        monitor.setCursorPos(x + 2 + padLeft, my)
        monitor.write(info)

      elseif ri == 0 then
        -- Top gradient row: border (┌─⋯─┐)
        if hasColor then monitor.setTextColor(BORDER_COLOR) end
        monitor.setCursorPos(x, my)
        monitor.write("+")
        monitor.setCursorPos(x + STEAM_W - 1, my)
        monitor.write("+")
        monitor.setCursorPos(x + 1, my)
        monitor.write(string.rep("-", STEAM_W - 2))
      end
    end

    monitor.setBackgroundColor(BG_EMPTY)
    my = my + 1
  end

  return my
end

-- ── Normalize incoming data to { label, tanks[n] = { name, amount, capacity } } ──

local function normalize(info)
  if info.tanks then
    -- Already from fluid_storage — use as-is
    -- Attach redstonePct fallback to each tank
    for _, t in pairs(info.tanks) do
      if t and not t.capacity and info.redstonePct then
        t.capacity = t.amount / info.redstonePct
      end
    end
    return info
  end

  -- From create_target (CCCBridge) — wrap into tanks[] format
  local fluidName = "fluid"
  if info.fullText and #info.fullText > 0 then
    -- Try to extract a name (first line before any numbers/slashes)
    for _, line in ipairs(info.raw or {}) do
      if line and #line > 0 then
        local cleaned = line:gsub("%s*[%d%.]+%s*/%s*[%d%.]+.*$", "")
        cleaned = cleaned:match("^%s*(.-)%s*$")
        if cleaned and #cleaned > 0 and not tonumber(cleaned) then
          fluidName = cleaned
          break
        end
      end
    end
  end

  return {
    label = info.label,
    id = info.id,
    tanks = {{
      name = fluidName,
      amount = info.amount or 0,
      capacity = info.capacity,
      raw = info.raw,
    }},
  }
end

-- ── Storage tower drawing ──

local BG_BAR = colors.blue       -- custom #34414e via palette
local BG_STORAGE_FILL = colors.purple  -- custom #485b6e via palette
local RED_SQ_BG = colors.red

local function drawStorageTower(cx, cy, siloInfos)
  -- siloInfos: array of { label, usedSlots, totalSlots, items }
  if #siloInfos == 0 then return cy end

  -- Adaptive widths based on screen width
  local nameW = math.floor((w - 2) / 3)
  local barW = math.floor((w - 2) / 3)
  local countW = w - cx - nameW - barW - 6  -- remaining for count + margins
  if countW < 6 then countW = 6 end
  local maxItems = math.max(1, math.min(10, h - cy - 4))  -- items per silo based on remaining height

  siloClickZones = {}

  local totalItems = 0
  local totalUsed = 0
  local totalMax = 0

  for idx, info in ipairs(siloInfos) do
    if cy >= h - 3 then break end
    local compStartY = cy
    local used = info.usedSlots or 0
    local total = info.totalSlots or 1
    totalUsed = totalUsed + used
    totalMax = totalMax + total
    for _, item in ipairs(info.items or {}) do
      totalItems = totalItems + item.count
    end

    -- Header: label + fill pct
    local label = info.label or ("#" .. (info.id or idx))
    local pctStr = math.floor(math.min(used / total, 1) * 100) .. "%"
    local headerW = w - cx
    if hasColor then
      monitor.setBackgroundColor(BG_STORAGE_FILL)
      monitor.setTextColor(WHITE)
    end
    monitor.setCursorPos(cx, cy)
    monitor.write(" " .. label)
    local fillBarLen = math.max(0, headerW - #label - #pctStr - 4)
    if fillBarLen > 0 then
      local fill = math.floor(math.min(used / total, 1) * fillBarLen)
      monitor.setBackgroundColor(BG_BAR)
      monitor.write(string.rep(" ", fill))
      monitor.setBackgroundColor(BG_EMPTY)
      monitor.write(string.rep(" ", fillBarLen - fill))
    end
    monitor.setBackgroundColor(BG_STORAGE_FILL)
    monitor.write(" " .. pctStr .. " ")
    monitor.setBackgroundColor(BG_EMPTY)
    cy = cy + 1

    -- Item rows
    local sorted = info.items or {}
    local maxItemCount = #sorted > 0 and sorted[1].count or 1
    local shown = 0
    for _, item in ipairs(sorted) do
      if cy >= h - 1 then break end
      if shown >= maxItems then break end
      local iname = shortName(item.name) or "?"
      if #iname > nameW then iname = iname:sub(1, nameW) end

      monitor.setCursorPos(cx + 1, cy)
      if hasColor then monitor.setTextColor(WHITE) end
      monitor.write(iname)
      local pad = nameW - #iname
      if pad > 0 then monitor.write(string.rep(" ", pad)) end

      local countStr = tostring(item.count)
      monitor.write(string.rep(" ", countW - #countStr))
      if hasColor then monitor.setTextColor(LIGHT_GRAY) end
      monitor.write(countStr)

      local fill = math.floor(math.min(item.count / maxItemCount, 1) * barW)
      if hasColor then
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", fill))
        monitor.setBackgroundColor(BG_EMPTY)
        if barW - fill > 0 then monitor.write(string.rep(" ", barW - fill)) end
      else
        monitor.write(string.rep(" ", barW))
      end
      cy = cy + 1
      shown = shown + 1
    end
    cy = cy + 1  -- spacer between silos

    siloClickZones[#siloClickZones + 1] = { yStart = compStartY, yEnd = cy, info = info }
  end

  return cy
end

-- ── Stress gauge animation ──

local SHAFT_LEN = 7
local STRESS_GOLD = colors.lime
local SHAFT_SPEED = 3

local function getShaftPos(phase)
  local t = os.clock()
  local pos = (math.sin(t * SHAFT_SPEED + phase) + 1) / 2  -- 0..1
  return 1 + math.floor(pos * (SHAFT_LEN - 1))
end

local function renderStress()
  if not stressData then return end

  local gaugeY = h - 4
  local sx = 4

  for row = 0, 2 do
    local y = gaugeY + row
    local ypos = getShaftPos(row * 1.7)

    -- Draw shaft: gold ── track with gray block
    monitor.setCursorPos(sx, y)
    if hasColor then
      monitor.setTextColor(STRESS_GOLD)
      monitor.setBackgroundColor(BG_EMPTY)
    end

    -- Before the block
    if ypos > 1 then
      monitor.write(string.rep(hz, ypos - 1))
    end
    -- The oscillating block (gray)
    if hasColor then monitor.setBackgroundColor(colors.gray) end
    monitor.write(" ")
    -- After the block
    if hasColor then
      monitor.setBackgroundColor(BG_EMPTY)
      monitor.setTextColor(STRESS_GOLD)
    end
    if ypos < SHAFT_LEN then
      monitor.write(string.rep(hz, SHAFT_LEN - ypos))
    end
    monitor.setBackgroundColor(BG_EMPTY)

    -- Content right of shaft
    if row == 0 then
      -- Label
      if hasColor then monitor.setTextColor(GRAY) end
      monitor.write(" " .. (stressData.label or "Stress"))
    elseif row == 1 then
      -- Progress bar (red for load, gold for remaining), процент внутри
      local barW = 15
      local fill = math.floor(math.min(stressData.pct / 100, 1) * barW)
      local pctStr = tostring(stressData.pct) .. "%"
      local pctLen = #pctStr
      local pctStart = 1  -- left-aligned within bar
      monitor.write(" ")
      if hasColor then monitor.setTextColor(WHITE) end
      for ci = 1, barW do
        if hasColor then
          monitor.setBackgroundColor(ci <= fill and colors.red or STRESS_GOLD)
        end
        if ci >= pctStart and ci < pctStart + pctLen then
          monitor.write(pctStr:sub(ci - pctStart + 1, ci - pctStart + 1))
        else
          monitor.write(" ")
        end
      end
      monitor.setBackgroundColor(BG_EMPTY)
    else
      -- Info text: "stress / capacity SU"
      if hasColor then monitor.setTextColor(LIGHT_GRAY) end
      local info = stressData.stress .. " / " .. stressData.capacity .. " SU"
      monitor.write(" " .. info)
    end

    monitor.setBackgroundColor(BG_EMPTY)
  end
end

-- ── Silo detail view ──

local BACK_BTN_Y = 2  -- top of detail view (right panel)

local function drawSiloDetail(info)
  -- Full-screen detail for a single silo
  -- info: { label, usedSlots, totalSlots, items }

  -- Clear all content
  for cy = 2, h - 1 do
    monitor.setCursorPos(2, cy)
    monitor.write(string.rep(" ", w - 2))
  end

  local pct = math.min((info.usedSlots or 0) / (info.totalSlots or 1), 1.0)
  local label = info.label or "Storage"

  -- ── Left panel: expanded storage visual ──
  local LX, LY = 2, 2
  local L_W = 24
  local L_INNER = 22
  local L_ROWS = 12
  local L_TOTAL = L_ROWS * L_INNER

  -- Label as colored bar
  if hasColor then
    monitor.setBackgroundColor(BG_STORAGE_FILL)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(LX, LY)
  monitor.write(string.rep(" ", L_W))
  local shortL = #label > (L_W - 2) and label:sub(1, L_W - 2) or label
  local labelOff = math.floor((L_W - #shortL) / 2)
  monitor.setCursorPos(LX + labelOff, LY)
  monitor.write(shortL)
  monitor.setBackgroundColor(BG_EMPTY)
  LY = LY + 1

  -- Top border
  monitor.setBackgroundColor(BG_EMPTY)
  monitor.setTextColor(WHITE)
  monitor.setCursorPos(LX, LY)
  monitor.write("+" .. string.rep("-", L_INNER) .. "+")
  LY = LY + 1

  -- Fill rows
  local filledCells = math.floor(pct * L_TOTAL)
  for row = 1, L_ROWS do
    local rowFromBottom = L_ROWS - row + 1
    local startCell = (rowFromBottom - 1) * L_INNER
    local fillInRow = math.min(math.max(0, filledCells - startCell), L_INNER)
    local emptyInRow = L_INNER - fillInRow

    monitor.setCursorPos(LX, LY)
    monitor.setBackgroundColor(BG_BAR)
    monitor.setTextColor(WHITE)
    monitor.write("|")

    if fillInRow > 0 then
      monitor.setBackgroundColor(BG_STORAGE_FILL)
      monitor.write(string.rep(" ", fillInRow))
    end
    if emptyInRow > 0 then
      monitor.setBackgroundColor(BG_BAR)
      monitor.write(string.rep(" ", emptyInRow))
    end

    monitor.setBackgroundColor(BG_BAR)
    monitor.write("|")
    monitor.setBackgroundColor(BG_EMPTY)
    LY = LY + 1
  end

  -- Bottom border with percentage
  local pctStr = math.floor(pct * 100) .. "%"
  local pad = L_INNER - #pctStr
  monitor.setBackgroundColor(BG_EMPTY)
  monitor.setTextColor(WHITE)
  monitor.setCursorPos(LX, LY)
  monitor.write("+" .. string.rep("-", math.floor(pad / 2)) .. pctStr
    .. string.rep("-", pad - math.floor(pad / 2)) .. "+")

  -- ── Right panel: back button + top 10 items + stats ──
  local RX, RY = 27, 2
  local maxNameW = 13

  -- Back button at top
  if hasColor then
    monitor.setBackgroundColor(BG_STORAGE_FILL)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(RX, RY)
  monitor.write("[ < Back ]")
  monitor.setBackgroundColor(BG_EMPTY)
  RY = RY + 2

  -- Header
  if hasColor then monitor.setTextColor(WHITE) end
  monitor.setCursorPos(RX, RY)
  monitor.write("=== Top Items ===")
  RY = RY + 2

  -- Items (top 10 by count)
  local items = info.items or {}
  local maxCount = #items > 0 and items[1].count or 1
  for i = 1, math.min(10, #items) do
    local item = items[i]
    local name = shortName(item.name) or "?"
    if #name > maxNameW then name = name:sub(1, maxNameW) end

    local barW = 3
    local fill = math.floor(math.min(item.count / maxCount, 1) * barW)
    local empty = barW - fill

    if hasColor then monitor.setTextColor(WHITE) end
    monitor.setCursorPos(RX, RY)
    monitor.write(string.format("%2d. %-13s%4d ", i, name, item.count))

    if hasColor then
      monitor.setBackgroundColor(colors.gray)
      monitor.write(string.rep(" ", fill))
      monitor.setBackgroundColor(BG_EMPTY)
      if empty > 0 then monitor.write(string.rep(" ", empty)) end
    end
    monitor.setBackgroundColor(BG_EMPTY)
    RY = RY + 1
  end

  RY = RY + 1  -- spacer

  -- Stats: slots usage
  local used = info.usedSlots or 0
  local total = info.totalSlots or 1
  local slotPct = math.min(used / total, 1.0)
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, RY)
  monitor.write("Slots: " .. used .. "/" .. total .. " ")

  local slotBarW = 6
  local sFill = math.floor(slotPct * slotBarW)
  local sEmpty = slotBarW - sFill
  if hasColor then
    monitor.setBackgroundColor(BG_STORAGE_FILL)
    monitor.write(string.rep(" ", sFill))
    monitor.setBackgroundColor(BG_EMPTY)
    if sEmpty > 0 then monitor.write(string.rep(" ", sEmpty)) end
  end
  monitor.setBackgroundColor(BG_EMPTY)
  RY = RY + 1

  -- Total items
  local totalItems = 0
  for _, item in ipairs(items) do
    totalItems = totalItems + item.count
  end
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, RY)
  monitor.write("Items: " .. totalItems)

end

-- ── Tank detail view ──

local TANK_BTN_BACK_X1 = 27
local TANK_BTN_BACK_X2 = 36
-- Footprint presets row
local TANK_BTN_F1_X1 = 27
local TANK_BTN_F1_X2 = 31
local TANK_BTN_F2_X1 = 33
local TANK_BTN_F2_X2 = 37
local TANK_BTN_F3_X1 = 39
local TANK_BTN_F3_X2 = 43
local TANK_FOOT_Y = 14
-- Height +/- row
local TANK_BTN_HMINUS_X1 = 37
local TANK_BTN_HMINUS_X2 = 39
local TANK_BTN_HPLUS_X1  = 41
local TANK_BTN_HPLUS_X2  = 43
local TANK_HEIGHT_Y = 15
local TANK_COLOR_Y = 10

local function drawTankDetail(info)
  local tank = info.tanks and info.tanks[1]
  if not tank then return end

  local label = info.label or "Tank"
  local amount = tank.amount or 0
  local capacity = tank.capacity
  local pct = capacity and math.min(amount / capacity, 1.0) or 0

  -- Init footprint/height from sender or capacity
  if not tankFootprint[info.id] then
    local blocks = info.blocks or math.max(1, math.floor((capacity or 0) / 1296))
    local foot = math.floor(math.sqrt(blocks))
    if foot < 1 then foot = 1 end
    if foot > 3 then foot = 3 end
    tankFootprint[info.id] = foot
    tankHeight[info.id] = math.max(1, math.floor(blocks / (foot * foot)))
  end
  local foot = tankFootprint[info.id]
  local height = tankHeight[info.id]
  local totalBlocks = foot * foot * height
  if not tankFluidColor[info.id] then
    tankFluidColor[info.id] = info.fluidColor or BG_FILL
  end
  local fColor = tankFluidColor[info.id]

  -- Clear all content
  for cy = 2, h - 1 do
    monitor.setCursorPos(2, cy)
    monitor.write(string.rep(" ", w - 2))
  end

  -- ── Left panel: large tank visual ──
  local LX, LY = 2, 2
  local L_W = 24
  local L_INNER = 22
  local L_ROWS = 12

  -- Label as colored bar
  if hasColor then
    monitor.setBackgroundColor(BG_STORAGE_FILL)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(LX, LY)
  monitor.write(string.rep(" ", L_W))
  local shortL = #label > (L_W - 2) and label:sub(1, L_W - 2) or label
  local labelOff = math.floor((L_W - #shortL) / 2)
  monitor.setCursorPos(LX + labelOff, LY)
  monitor.write(shortL)
  monitor.setBackgroundColor(BG_EMPTY)
  LY = LY + 1

  -- Top border
  monitor.setBackgroundColor(BG_EMPTY)
  monitor.setTextColor(WHITE)
  monitor.setCursorPos(LX, LY)
  monitor.write("+" .. string.rep("-", L_INNER) .. "+")
  LY = LY + 1

  -- Fill rows
  local fillRows = math.floor(pct * L_ROWS)
  local remainder = (pct * L_ROWS) - fillRows

  for row = 1, L_ROWS do
    local rowFromBottom = L_ROWS - row + 1
    monitor.setCursorPos(LX, LY)
    monitor.write("|")

    if rowFromBottom <= fillRows then
      if rowFromBottom == fillRows and remainder > 0.01 and fColor == BG_FILL then
        local fillC = math.floor(remainder * L_INNER)
        local base = colorIdx(BG_FILL)
        local empty = colorIdx(BG_EMPTY)
        local animT = (math.sin(os.clock() * 2) + 1) / 2
        local bgStr = ""
        for ci = 1, L_INNER do
          if ci <= fillC then
            local ratio = (ci - 1) / math.max(1, fillC - 1)
            local blend = ratio * animT * 0.5
            local idx = base - blend * base
            if idx < 0 then idx = 0 end
            if idx > 15 then idx = 15 end
            bgStr = bgStr .. string.char(math.floor(idx + 0.5))
          else
            bgStr = bgStr .. string.char(empty)
          end
        end
        local fg = string.rep(string.char(colorIdx(colors.white)), L_INNER)
        monitor.blit(string.rep(" ", L_INNER), fg, bgStr)
      else
        monitor.setBackgroundColor(fColor)
        monitor.write(string.rep(" ", L_INNER))
        monitor.setBackgroundColor(BG_EMPTY)
      end
    else
      monitor.write(string.rep(" ", L_INNER))
    end

    monitor.write("|")
    monitor.setBackgroundColor(BG_EMPTY)
    LY = LY + 1
  end

  -- Bottom border with percentage
  local pctStr = math.floor(pct * 100) .. "%"
  local pad = L_INNER - #pctStr
  monitor.setBackgroundColor(BG_EMPTY)
  monitor.setTextColor(WHITE)
  monitor.setCursorPos(LX, LY)
  monitor.write("+" .. string.rep("-", math.floor(pad / 2)) .. pctStr
    .. string.rep("-", pad - math.floor(pad / 2)) .. "+")

  -- ── Right panel: back + info + +/─ ──
  local RX, RY = 27, 2

  local BG_BTN = colors.orange

  -- Back button (filled orange)
  if hasColor then
    monitor.setBackgroundColor(BG_BTN)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(RX, RY)
  monitor.write("[ < Back ]")
  monitor.setBackgroundColor(BG_EMPTY)
  RY = RY + 2

  -- Header
  if hasColor then monitor.setTextColor(WHITE) end
  monitor.setCursorPos(RX, RY)
  monitor.write("=== " .. label .. " ===")
  RY = RY + 2

  -- Fluid name
  if hasColor then monitor.setTextColor(LIGHT_GRAY) end
  monitor.setCursorPos(RX, RY)
  monitor.write(shortName(tank.name or "Fluid"))
  RY = RY + 1

  -- Amount / capacity
  if hasColor then monitor.setTextColor(WHITE) end
  monitor.setCursorPos(RX, RY)
  if capacity then
    monitor.write(formatAmount(amount) .. " / " .. formatAmount(capacity))
  else
    monitor.write(formatAmount(amount))
  end
  RY = RY + 2

  -- Fluid color label
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, RY)
  monitor.write("Fluid color:")
  RY = RY + 1

  -- Color swatches (8 swatches, 2 rows × 4)
  local cw = 2       -- chars per swatch
  local cg = 3       -- gap between swatch starts
  for i, sw in ipairs(COLOR_SWATCHES) do
    local row = math.floor((i - 1) / 4)
    local col = (i - 1) % 4
    if hasColor then
      monitor.setBackgroundColor(sw.slot)
    end
    monitor.setCursorPos(RX + col * cg, RY + row)
    monitor.write(string.rep(" ", cw))
  end
  monitor.setBackgroundColor(BG_EMPTY)
  -- Highlight selected swatch
  local selIdx = nil
  for i, sw in ipairs(COLOR_SWATCHES) do
    if sw.slot == fColor then selIdx = i; break end
  end
  if selIdx then
    local row = math.floor((selIdx - 1) / 4)
    local col = (selIdx - 1) % 4
    if hasColor then monitor.setTextColor(WHITE) end
    monitor.setCursorPos(RX + col * cg, RY + row)
    monitor.write("<>")
  end
  monitor.setBackgroundColor(BG_EMPTY)
  RY = RY + 2

  -- Footprint label + buttons at fixed y
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, TANK_FOOT_Y - 1)
  monitor.write("Footprint:")
  if hasColor then
    monitor.setBackgroundColor(BG_BTN)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(RX, TANK_FOOT_Y)     monitor.write("[1x1]")
  monitor.setCursorPos(RX + 6, TANK_FOOT_Y) monitor.write("[2x2]")
  monitor.setCursorPos(RX + 12, TANK_FOOT_Y) monitor.write("[3x3]")
  monitor.setBackgroundColor(BG_EMPTY)

  -- Height row with +/- buttons at fixed y
  RY = TANK_HEIGHT_Y
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, RY)
  monitor.write("Height: " .. height)
  if hasColor then
    monitor.setBackgroundColor(BG_BTN)
    monitor.setTextColor(WHITE)
  end
  monitor.setCursorPos(RX + 10, RY) monitor.write("[-]")
  monitor.setCursorPos(RX + 14, RY) monitor.write("[+]")
  monitor.setBackgroundColor(BG_EMPTY)

  -- Total blocks
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(RX, RY + 2)
  monitor.write("Blocks: " .. totalBlocks)
end

-- ── Content rendering ──

local function renderContent()
  if selectedSiloId then
    local info = siloData[selectedSiloId]
    if info then
      drawSiloDetail(info)
      return
    else
      selectedSiloId = nil  -- silo no longer connected
    end
  end

  if selectedTankId then
    local info = tankData[selectedTankId]
    if info then
      drawTankDetail(info)
      return
    else
      selectedTankId = nil
    end
  end

  -- Clear content area (between top and bottom border)
  for cy = 2, h - 1 do
    monitor.setCursorPos(2, cy)
    monitor.write(string.rep(" ", w - 2))
  end

  local tankY = 2
  local leftColY = 2

  -- Draw steam engine boiler visual (center)
  if steamData then
    if hasColor then monitor.setTextColor(WHITE) end
    monitor.setCursorPos(16, 2)
    monitor.write("> " .. steamData.label)

    drawSteamBoiler(16, 3, steamData.label,
      steamData.volume_pct, steamData.water_pct, steamData.heat_pct)
  end

  -- Draw fluid tanks (right side, independent y)
  tankClickZones = {}
  for _, info in pairs(tankData) do
    if hasColor then monitor.setTextColor(WHITE) end
    monitor.setCursorPos(34, tankY)
    monitor.write("> " .. (info.label or "?"))
    local zoneStart = tankY
    tankY = tankY + 1

    for _, t in pairs(info.tanks) do
      if t then
        if hasColor then monitor.setTextColor(TANK_BORDER) end
        local tColor = tankFluidColor[info.id]
        tankY = drawTank(34, tankY, t.name or "?", t.amount or 0, t.capacity, tColor)

        if hasColor then monitor.setTextColor(LIGHT_GRAY) end
        monitor.setCursorPos(34, tankY)
        if t.raw then
          local firstLine = ""
          for _, line in ipairs(t.raw) do
            if line and #line > 0 then firstLine = line; break end
          end
          if #firstLine > 0 then monitor.write(firstLine) end
        else
          monitor.write(shortName(t.name))
        end
        tankY = tankY + 2
      end
    end
    tankClickZones[#tankClickZones + 1] = { yStart = zoneStart, yEnd = tankY, info = info }
    if tankY >= h - 1 then break end
  end

  -- Draw storage tower on the left side
  local siloList = {}
  for _, info in pairs(siloData) do
    siloList[#siloList + 1] = info
  end
  table.sort(siloList, function(a, b) return (a.label or "") < (b.label or "") end)

  if #siloList > 0 then
    drawStorageTower(2, leftColY, siloList)
  end

  -- Animated stress gauge (bottom 3 rows, left side)
  renderStress()

  -- Barrel flow bordered box (right side, left margin from stress gauge)
  local now = os.clock()
  local fX, fY = 30, h - 6  -- y=13..17 (5 rows: border+3content+border), column 29 empty
  local fOuter = 22         -- 30..51
  local fInner = fOuter - 2 -- 20 chars between borders
  -- Prune expired
  for id, ev in pairs(barrelFlowEvents) do
    if now - ev.time > 2.0 then barrelFlowEvents[id] = nil end
  end
  -- Sort by time descending (most recent first)
  local sorted = {}
  for id, ev in pairs(barrelFlowEvents) do
    sorted[#sorted + 1] = ev
  end
  table.sort(sorted, function(a, b) return a.time > b.time end)
  -- Always draw the block; white rows always, text only if event exists
  if hasColor then
    monitor.setBackgroundColor(colors.white)
    monitor.setTextColor(colors.orange)
  end
  -- Top border
  monitor.setCursorPos(fX, fY)
  monitor.write("+" .. string.rep("-", fInner) .. "+")
  -- 3 content rows (always white bg; text if event at that rank)
  for i = 1, 3 do
    local my = fY + i
    monitor.setCursorPos(fX, my)
    local ev = sorted[i]
    if ev then
      monitor.write("| ")
      local line = ev.label .. ": " .. ev.itemName
      local maxText = fInner - 2
      if #line > maxText then line = line:sub(1, maxText) end
      monitor.write(line)
      local fill = maxText - #line
      if fill > 0 then monitor.write(string.rep(" ", fill)) end
      monitor.write(" |")
    else
      monitor.write("|" .. string.rep(" ", fInner) .. "|")
    end
  end
  -- Bottom border
  monitor.setCursorPos(fX, fY + 4)
  monitor.write("+" .. string.rep("-", fInner) .. "+")
  monitor.setBackgroundColor(BG_EMPTY)

  -- Connection counters
  local tankCount = 0
  for _ in pairs(tankData) do tankCount = tankCount + 1 end
  local siloCount = 0
  for _ in pairs(siloData) do siloCount = siloCount + 1 end
  local steamCount = steamData and 1 or 0
  local stressCount = stressData and 1 or 0
  local status = "[" .. tankCount .. " tank(s), " .. siloCount .. " silo(s), "
    .. steamCount .. " steam, " .. stressCount .. " stress]"
  if hasColor then monitor.setTextColor(GRAY) end
  monitor.setCursorPos(w - #status - 1, h)
  monitor.write(status)
end

-- ── Main loop ──

drawFrame()
renderContent()

local animTimer = os.startTimer(0.1)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "rednet_message" then
    local senderId, message, protocol = p1, p2, p3
    if protocol == "tank_data" then
      tankData[senderId] = normalize(message)
      if not tankFluidColor[senderId] and message.fluidColor then
        tankFluidColor[senderId] = message.fluidColor
      end
      if message.foot and message.height and not tankFootprint[senderId] then
        tankFootprint[senderId] = message.foot
        tankHeight[senderId] = message.height
      end
      renderContent()
    elseif protocol == "item_data" then
      siloData[senderId] = message
      renderContent()
    elseif protocol == "steam_data" then
      steamData = message
      renderContent()
    elseif protocol == "stress_data" then
      stressData = message
      renderContent()
    elseif protocol == "barrel_flow" then
      for _, item in ipairs(message.items or {}) do
        local itemName = shortName(item.name or "?")
        barrelFlowEvents[message.id] = { itemName = itemName, label = message.label or "?", time = os.clock() }
      end
      renderContent()
    end
  elseif event == "monitor_touch" then
    local _, tx, ty = p1, p2, p3
    if selectedSiloId then
      -- Silo detail view: check back button
      if ty == BACK_BTN_Y and tx >= 27 and tx <= 37 then
        selectedSiloId = nil
        renderContent()
      end
    elseif selectedTankId then
      -- Tank detail view: back, color, footprint, height +/-
      if ty == BACK_BTN_Y and tx >= TANK_BTN_BACK_X1 and tx <= TANK_BTN_BACK_X2 then
        selectedTankId = nil
        renderContent()
      elseif ty >= TANK_COLOR_Y and ty <= TANK_COLOR_Y + 3 then
        -- Color swatch click
        local cg = 3
        for i, sw in ipairs(COLOR_SWATCHES) do
          local row = math.floor((i - 1) / 4)
          local col = (i - 1) % 4
          local sx = 27 + col * cg
          if ty == TANK_COLOR_Y + row and tx >= sx and tx <= sx + 1 then
            tankFluidColor[selectedTankId] = sw.slot
            local fc = tankFootprint[selectedTankId] or 1
            local hc = tankHeight[selectedTankId] or 1
            rednet.send(selectedTankId, { blocks = fc * fc * hc, foot = fc, height = hc, fluidColor = sw.slot }, "tank_config")
            renderContent()
            break
          end
        end
      elseif ty == TANK_FOOT_Y then
        local f, h
        if tx >= TANK_BTN_F1_X1 and tx <= TANK_BTN_F1_X2 then
          tankFootprint[selectedTankId] = 1
          f, h = 1, tankHeight[selectedTankId] or 1
        elseif tx >= TANK_BTN_F2_X1 and tx <= TANK_BTN_F2_X2 then
          tankFootprint[selectedTankId] = 2
          f, h = 2, tankHeight[selectedTankId] or 1
        elseif tx >= TANK_BTN_F3_X1 and tx <= TANK_BTN_F3_X2 then
          tankFootprint[selectedTankId] = 3
          f, h = 3, tankHeight[selectedTankId] or 1
        end
        if f then
          local fc = tankFluidColor[selectedTankId] or BG_FILL
          rednet.send(selectedTankId, { blocks = f * f * h, foot = f, height = h, fluidColor = fc }, "tank_config")
          renderContent()
        end
      elseif ty == TANK_HEIGHT_Y then
        local ch = tankHeight[selectedTankId] or 1
        local changed = false
        if tx >= TANK_BTN_HMINUS_X1 and tx <= TANK_BTN_HMINUS_X2 then
          tankHeight[selectedTankId] = math.max(1, ch - 1)
          changed = true
        elseif tx >= TANK_BTN_HPLUS_X1 and tx <= TANK_BTN_HPLUS_X2 then
          tankHeight[selectedTankId] = ch + 1
          changed = true
        end
        if changed then
          local f2 = tankFootprint[selectedTankId] or 1
          local h2 = tankHeight[selectedTankId] or 1
          local fc2 = tankFluidColor[selectedTankId] or BG_FILL
          rednet.send(selectedTankId, { blocks = f2 * f2 * h2, foot = f2, height = h2, fluidColor = fc2 }, "tank_config")
          renderContent()
        end
      end
    else
      -- Normal view: find clicked silo (storage column x=2..11)
      if tx >= 2 and tx <= 11 then
        for _, zone in ipairs(siloClickZones) do
          if ty >= zone.yStart and ty < zone.yEnd then
            selectedSiloId = zone.info.id
            renderContent()
            break
          end
        end
      elseif tx >= 34 and tx <= 50 then
        for _, zone in ipairs(tankClickZones) do
          if ty >= zone.yStart and ty < zone.yEnd then
            selectedTankId = zone.info.id
            renderContent()
            break
          end
        end
      end
    end
  elseif event == "timer" and p1 == animTimer then
    animTimer = os.startTimer(0.1)
    renderContent()
  end
end
