--[[
  debug.lua
  Writes all peripheral data to debug_log.txt.
  After running: edit debug_log.txt
]]

local logFile = fs.open("debug_log.txt", "w")

local function log(...)
  local args = {...}
  local line = ""
  for i, v in ipairs(args) do
    if i > 1 then line = line .. " " end
    line = line .. tostring(v)
  end
  logFile.writeLine(line)
  print(line)
end

local function dumpTable(t, indent)
  indent = indent or ""
  if type(t) ~= "table" then
    log(indent .. tostring(t))
    return
  end
  for k, v in pairs(t) do
    local key = tostring(k)
    if type(v) == "table" then
      log(indent .. "[" .. key .. "] = {")
      dumpTable(v, indent .. "  ")
      log(indent .. "}")
    elseif type(v) == "string" then
      log(indent .. "[" .. key .. "] = \"" .. v .. "\"")
    else
      log(indent .. "[" .. key .. "] = " .. tostring(v))
    end
  end
end

log("===== PERIPHERAL SCAN =====")
log("")

local names = peripheral.getNames()
if #names == 0 then
  log("No peripherals found!")
else
  for _, name in ipairs(names) do
    log("--- Peripheral: " .. name)
    log("    Type: " .. (peripheral.getType(name) or "unknown"))
    local methods = peripheral.getMethods(name) or {}
    log("    Methods (" .. #methods .. "):")
    for _, m in ipairs(methods) do
      log("      - " .. m)
    end
    log("")
  end
end

log("========== DATA TICK ==========")

for _, name in ipairs(peripheral.getNames()) do
  local pType = peripheral.getType(name)
  local obj = peripheral.wrap(name)
  log("")
  log("[" .. name .. "] (" .. pType .. ")")

  if pType == "fluid_storage" then
    local ok, result = pcall(function() return obj.tanks() end)
    if ok then
      for i, tank in pairs(result) do
        if tank then
          log("  tank[" .. i .. "]:")
          for k, v in pairs(tank) do
            log("    " .. k .. " = " .. tostring(v))
          end
        else
          log("  tank[" .. i .. "]: nil (empty slot)")
        end
      end
    else
      log("  ERROR: " .. tostring(result))
    end

  elseif pType == "create_source" or pType == "create_target" then
    -- CCCBridge blocks
    local methods = peripheral.getMethods(name) or {}
    for _, m in ipairs(methods) do
      if m ~= "resize" and m ~= "setCursorPos" and m ~= "write"
         and m ~= "clear" and m ~= "clearLine" and m ~= "scroll" then
        local ok, result = pcall(function() return obj[m]() end)
        if ok then
          local str = tostring(result)
          if #str > 200 then str = str:sub(1, 200) .. "..." end
          log("  " .. m .. "() = " .. str)
        end
      end
    end
    -- getLine dump
    local ok, h = pcall(function() return obj.getSize() end)
    if ok then
      for line = 1, h do
        local ok2, text = pcall(function() return obj.getLine(line) end)
        if ok2 and text and #text > 0 then
          log("  line " .. line .. " = \"" .. text .. "\"")
        end
      end
    end
    -- resize + dump (CCCBridge terminal scanning)
    local resizeOk = pcall(function() obj.resize(32, 8) end)
    if resizeOk then
      log("  resize(32, 8) ok")
      local dumpOk, dumpResult = pcall(function()
        local raw = obj.dump()
        local lines = {}
        if type(raw) == "table" then
          for _, line in ipairs(raw) do
            table.insert(lines, line)
          end
        else
          -- Try as iterator function
          for line in raw do
            table.insert(lines, line)
          end
        end
        return lines
      end)
      if dumpOk then
        log("  dump() returned " .. #dumpResult .. " lines:")
        for i, line in ipairs(dumpResult) do
          log("    [" .. i .. "] = \"" .. line .. "\"")
        end
      else
        log("  dump() ERROR: " .. tostring(dumpResult))
      end
    else
      log("  resize(32, 8) not available")
    end

  elseif pType == "modem" then
    -- Skip

  else
    -- Unknown: try calling every method once
    local methods = peripheral.getMethods(name) or {}
    for _, m in ipairs(methods) do
      if m ~= "write" and m ~= "clear" and m ~= "setCursorPos"
         and m ~= "getCursorPos" and m ~= "clearLine" and m ~= "scroll"
         and m ~= "getSize" and m ~= "resize" then
        local ok, result = pcall(function() return obj[m]() end)
        if ok then
          local str = tostring(result)
          if #str > 200 then str = str:sub(1, 200) .. "..." end
          log("  " .. m .. "() = " .. str)
        end
      end
    end
  end
end

logFile.close()

print("")
print("========================================")
print(" Debug log written to debug_log.txt")
print(" Open it with:  edit debug_log.txt")
print(" Scroll with arrows, exit with Ctrl+W")
print("========================================")
