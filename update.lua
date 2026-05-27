-- update.lua
-- Force-updates project files from dev server.
-- Usage: update

local host = "http://localhost:8000"
local files = {
  "startup.lua",
  "tank_sender.lua",
  "silo_sender.lua",
  "steam_engine.lua",
  "stress_sender.lua",
  "debug.lua",
  "ccdebug.lua",
  "sniff.lua",
  "test_target.lua",
}

for _, file in ipairs(files) do
  if fs.exists(file) then
    fs.delete(file)
  end
  local url = host .. "/" .. file
  write("Downloading " .. file .. "... ")
  shell.run("wget " .. url .. " " .. file)
  if fs.exists(file) then
    print("OK")
  else
    print("FAILED — dev server running?")
  end
end

print("")
print("Run: startup.lua")
