local root = os.getenv("AUZIX_ROOT") or ""

local function rooted(path)
  if root == "" then
    return path
  end
  return root .. path
end

local package_tool = os.getenv("AUZIX_PKG") or rooted("/System/Tools/auzix-pkg")
local dialog = os.getenv("AUZIX_DIALOG") or rooted("/Programs/Dialog/current/Commands/dialog")

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

local function temp_path()
  local base = os.getenv("TMPDIR") or rooted("/Work/Temp")
  if not command_ok("mkdir -p " .. shell_quote(base)) then
    return nil
  end
  return base .. "/auzix-package-setup-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function dialog_value(args)
  local output = temp_path()
  if not output then
    return nil
  end
  local ok = command_ok(shell_quote(dialog) .. " " .. args .. " 2>" .. shell_quote(output))
  if not ok then
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

local function available_packages()
  local output = capture(shell_quote(package_tool) .. " list available")
  if output == nil then
    return nil
  end
  local packages = {}
  for line in output:gmatch("[^\n]+") do
    local name, version, kind, size = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t?(.*)$")
    if name and version then
      table.insert(packages, {
        name = name,
        description = table.concat({version, kind or "package", size or ""}, " ")
      })
    end
  end
  return packages
end

local function tui()
  if not command_ok("test -x " .. shell_quote(dialog)) then
    io.stderr:write("auzix-package-setup: dialog is not available\n")
    return false
  end
  if not command_ok("test -x " .. shell_quote(package_tool)) then
    io.stderr:write("auzix-package-setup: auzix-pkg is not available\n")
    return false
  end

  if not command_ok(shell_quote(package_tool) .. " refresh") then
    command_ok(shell_quote(dialog) .. " --title 'AuziX Package Setup' --msgbox 'Repository refresh failed.' 8 56")
    return false
  end

  local packages = available_packages()
  if not packages then
    return false
  end
  if #packages == 0 then
    command_ok(shell_quote(dialog) .. " --title 'AuziX Package Setup' --msgbox 'No packages are currently available.' 8 56")
    return true
  end

  local menu = {}
  for _, package in ipairs(packages) do
    table.insert(menu, shell_quote(package.name))
    table.insert(menu, shell_quote(package.description))
  end
  local selected = dialog_value(
    "--title 'AuziX Package Setup' --menu 'Available packages' 20 78 12 " ..
    table.concat(menu, " ")
  )
  if not selected then
    return false
  end

  local prompt = "Install " .. selected .. " and its dependencies?"
  if not command_ok(
    shell_quote(dialog) .. " --title 'AuziX Package Setup' --yesno " ..
    shell_quote(prompt) .. " 9 64"
  ) then
    return false
  end

  print("Installing " .. selected)
  if not command_ok(shell_quote(package_tool) .. " install " .. shell_quote(selected)) then
    command_ok(shell_quote(dialog) .. " --title 'AuziX Package Setup' --msgbox 'Package installation failed.' 8 56")
    return false
  end
  command_ok(
    shell_quote(dialog) .. " --title 'AuziX Package Setup' --msgbox " ..
    shell_quote(selected .. " was installed.") .. " 8 56"
  )
  return true
end

local function usage()
  print([[
Usage:
  auzix-package-setup
  auzix-package-setup tui
  auzix-package-setup refresh
  auzix-package-setup install PACKAGE

The interactive frontend delegates repository and transaction work to auzix-pkg.
]])
end

math.randomseed(os.time())
local action = arg[1] or "tui"
local ok

if action == "tui" then
  ok = tui()
elseif action == "refresh" then
  ok = command_ok(shell_quote(package_tool) .. " refresh")
elseif action == "install" and arg[2] then
  ok = command_ok(shell_quote(package_tool) .. " install " .. shell_quote(arg[2]))
elseif action == "help" or action == "--help" or action == "-h" then
  usage()
  ok = true
else
  usage()
  ok = false
end

os.exit(ok and 0 or 1)
