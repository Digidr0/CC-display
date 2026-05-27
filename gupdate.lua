-- gupdate.lua
-- Bulk-updates ALL project files from GitHub.
-- Usage: gupdate

local base = "https://raw.githubusercontent.com/Digidr0/CC-display/main"
local files = {
  "startup.lua",
  "tank_sender.lua",
  "engine_sender.lua",
  "silo_sender.lua",
  "stress_sender.lua",
  "barrel_sniffer.lua",
  "debug.lua",
  "sniff.lua",
  "update.lua",
  "gupdate.lua",
}

for _, file in ipairs(files) do
  if fs.exists(file) then
    fs.delete(file)
  end
  local url = base .. "/" .. file
  write("Downloading " .. file .. "... ")
  shell.run("wget " .. url .. " " .. file)
  if fs.exists(file) then
    print("OK")
  else
    print("FAILED — no internet?")
  end
end

print("")
print("Run: startup")
