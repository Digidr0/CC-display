-- sniff.lua
-- читает Target Block, пишет байты в sniff_log.txt
-- запуск: sniff  |  открыть: edit sniff_log.txt

local logFile = fs.open("sniff_log.txt", "w")

local function log(txt)
  logFile.writeLine(txt)
  print(txt)
end

local target = peripheral.find("create_target")
if not target then
  log("No create_target found!")
  logFile.close()
  return
end

local w, h = target.getSize()
log("Target Block: " .. w .. " x " .. h)
log("")

for y = 1, h do
  local raw = target.getLine(y)
  local hex = {}
  local ascii = {}
  for i = 1, #raw do
    local b = string.byte(raw, i)
    table.insert(hex, string.format("%02X", b))
    if b >= 32 and b <= 126 then
      table.insert(ascii, string.char(b))
    elseif b == 32 then
      table.insert(ascii, " ")
    else
      table.insert(ascii, ".")
    end
  end
  log("L" .. y .. " hex: " .. table.concat(hex, " "))
  log("L" .. y .. " asc: " .. table.concat(ascii, ""))
  log("")
end

logFile.close()
print("")
print("sniff_log.txt written")
