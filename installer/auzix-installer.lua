local root = os.getenv("AUZIX_ROOT") or ""

local function rooted(path)
  if root == "" then
    return path
  end
  return root .. path
end

local jq = os.getenv("AUZIX_JQ") or rooted("/Programs/AuzixPackageTools/current/Commands/jq")
local dialog = os.getenv("AUZIX_DIALOG") or rooted("/Programs/Dialog/current/Commands/dialog")
local executor = os.getenv("AUZIX_INSTALL_EXECUTOR") or rooted("/System/Tools/auzix-install-disk")
local default_plan = rooted("/System/Settings/installer/plans/default.json")
local questions = rooted("/System/Settings/installer/questions.json")

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_ok(command)
  local ok, why, code = os.execute(command)
  if type(ok) == "number" then
    return ok == 0
  end
  return ok == true and (why ~= "exit" or code == 0)
end

local function capture(command)
  local pipe = io.popen(command, "r")
  if not pipe then
    return nil
  end
  local output = pipe:read("*a")
  local ok = pipe:close()
  if not ok then
    return nil
  end
  return output:gsub("%s+$", "")
end

local validation_filter = [[
  . as $p
  | ($p | type == "object")
  and (($p | keys - ["format", "target", "storage", "bootloader", "identity", "execution", "frontend"] | length) == 0)
  and ($p.format == "auzix-install-plan-v1")
  and ($p.target | type == "object")
  and (($p.target | keys - ["disk"] | length) == 0)
  and ($p.target.disk | type == "string" and test("^/dev/([A-Za-z0-9._:+-]+|disk/by-id/[A-Za-z0-9._:+-]+)$"))
  and ($p.storage | type == "object")
  and (($p.storage | keys - ["filesystem"] | length) == 0)
  and ($p.storage.filesystem == "ext4")
  and ($p.bootloader | type == "object")
  and (($p.bootloader | keys - ["mode"] | length) == 0)
  and ($p.bootloader.mode == "grub" or $p.bootloader.mode == "iso")
  and ($p.identity | type == "object")
  and (($p.identity | keys - ["hostname"] | length) == 0)
  and ($p.identity.hostname | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$"))
  and ($p.execution | type == "object")
  and (($p.execution | keys - ["confirmed"] | length) == 0)
  and ($p.execution.confirmed | type == "boolean")
  and ((($p | has("frontend")) | not) or ($p.frontend | IN("default", "tui", "graphical", "automation")))
]]

local function validate(plan)
  if not plan or plan == "" then
    io.stderr:write("auzix-installer: install plan path is required\n")
    return false
  end
  local command = table.concat({
    shell_quote(jq), "-e", shell_quote(validation_filter),
    shell_quote(plan), ">/dev/null"
  }, " ")
  if not command_ok(command) then
    io.stderr:write("auzix-installer: invalid install plan: " .. plan .. "\n")
    return false
  end
  return true
end

local function field(plan, expression)
  return capture(table.concat({
    shell_quote(jq), "-er", shell_quote(expression), shell_quote(plan)
  }, " "))
end

local function summary(plan)
  if not validate(plan) then
    return false
  end
  print("AuziX installation plan")
  print("  disk:       " .. field(plan, ".target.disk"))
  print("  filesystem: " .. field(plan, ".storage.filesystem"))
  print("  bootloader: " .. field(plan, ".bootloader.mode"))
  print("  hostname:   " .. field(plan, ".identity.hostname"))
  print("  confirmed:  " .. field(plan, ".execution.confirmed"))
  return true
end

local function run(plan)
  if not validate(plan) then
    return false
  end
  if field(plan, ".execution.confirmed") ~= "true" then
    io.stderr:write("auzix-installer: plan is not confirmed; refusing destructive execution\n")
    return false
  end

  local disk = field(plan, ".target.disk")
  local bootloader = field(plan, ".bootloader.mode")
  local command = table.concat({
    shell_quote(executor), "--force", "--bootloader", shell_quote(bootloader), shell_quote(disk)
  }, " ")
  print("Executing confirmed install plan for " .. disk)
  return command_ok(command)
end

local function temp_path(name)
  local base = os.getenv("TMPDIR") or rooted("/Work/Temp")
  return base .. "/auzix-installer-" .. name .. "-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function dialog_value(args)
  local output = temp_path("dialog")
  local command = shell_quote(dialog) .. " " .. args .. " 2>" .. shell_quote(output)
  if not command_ok(command) then
    os.remove(output)
    return nil
  end
  local handle = io.open(output, "r")
  if not handle then
    return nil
  end
  local value = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  os.remove(output)
  return value
end

local function discover_disks()
  local sys_block = rooted("/sys/block")
  local pipe = io.popen("find " .. shell_quote(sys_block) .. " -mindepth 1 -maxdepth 1 -type l 2>/dev/null")
  local disks = {}
  if pipe then
    for path in pipe:lines() do
      local name = path:match("([^/]+)$")
      if name and not name:match("^loop") and not name:match("^ram") and not name:match("^sr") then
        table.insert(disks, "/dev/" .. name)
      end
    end
    pipe:close()
  end
  if #disks == 0 then
    table.insert(disks, "/dev/vda")
  end
  return disks
end

local function tui(output_plan)
  if not command_ok("test -x " .. shell_quote(dialog)) then
    io.stderr:write("auzix-installer: dialog frontend is not available\n")
    return false
  end

  local menu = {}
  for _, disk in ipairs(discover_disks()) do
    table.insert(menu, shell_quote(disk))
    table.insert(menu, shell_quote("Erase and install to " .. disk))
  end
  local disk = dialog_value("--title 'AuziX Installer' --menu 'Select the installation disk' 18 72 8 " .. table.concat(menu, " "))
  if not disk then return false end

  local bootloader = dialog_value("--title 'AuziX Installer' --menu 'Select the boot method' 14 72 4 'grub' 'Install BIOS GRUB' 'iso' 'Boot through the live ISO'")
  if not bootloader then return false end

  local hostname = dialog_value("--title 'AuziX Installer' --inputbox 'Hostname' 10 60 'auzix'")
  if not hostname then return false end

  local warning = "This will erase " .. disk .. ". Continue?"
  local confirmed = command_ok(shell_quote(dialog) .. " --title 'AuziX Installer' --yesno " .. shell_quote(warning) .. " 10 68")
  if not confirmed then
    io.stderr:write("auzix-installer: installation cancelled\n")
    return false
  end

  output_plan = output_plan or rooted("/System/State/installer/confirmed-plan.json")
  command_ok("mkdir -p " .. shell_quote(output_plan:match("(.+)/[^/]+$") or "."))
  local create = table.concat({
    shell_quote(jq), "-n",
    "--arg disk", shell_quote(disk),
    "--arg bootloader", shell_quote(bootloader),
    "--arg hostname", shell_quote(hostname),
    shell_quote([[{
      format: "auzix-install-plan-v1",
      target: {disk: $disk},
      storage: {filesystem: "ext4"},
      bootloader: {mode: $bootloader},
      identity: {hostname: $hostname},
      execution: {confirmed: true},
      frontend: "tui"
    }]]),
    ">", shell_quote(output_plan)
  }, " ")
  if not command_ok(create) or not validate(output_plan) then
    return false
  end

  summary(output_plan)
  return run(output_plan)
end

local function usage()
  print([[
Usage:
  auzix-installer validate [PLAN]
  auzix-installer summary [PLAN]
  auzix-installer run PLAN
  auzix-installer tui [OUTPUT_PLAN]
  auzix-installer questions

The run command only accepts a validated, explicitly confirmed plan. The TUI
performs a separate destructive confirmation before creating and running one.
]])
end

math.randomseed(os.time())
local action = arg[1] or "tui"
local plan = arg[2] or default_plan
local ok

if action == "validate" then
  ok = validate(plan)
  if ok then print("valid " .. plan) end
elseif action == "summary" then
  ok = summary(plan)
elseif action == "run" then
  ok = run(arg[2])
elseif action == "tui" then
  ok = tui(arg[2])
elseif action == "questions" then
  ok = command_ok(shell_quote(jq) .. " . " .. shell_quote(questions))
elseif action == "--help" or action == "-h" or action == "help" then
  usage()
  ok = true
else
  usage()
  ok = false
end

os.exit(ok and 0 or 1)
