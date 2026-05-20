#!/usr/bin/env lua
--[[
==============================================================================
  SATURNITY RESTORE
  "I love you to the moon and to Saturn"

  Reverts all changes made by optimize.lua
  Reads disabled.list to know exactly what we touched.
==============================================================================
]]

local VERSION = "1.0.1"

-- ============================================================
-- AUTO-UPDATE CONFIG
-- ============================================================
local REPO_USER   = "lucivaantarez"
local REPO_NAME   = "opt"
local REPO_BRANCH = "main"
local RAW_BASE    = "https://raw.githubusercontent.com/"..REPO_USER.."/"..REPO_NAME.."/"..REPO_BRANCH
local SELF_NAME   = "restore.lua"
local SELF_URL    = RAW_BASE.."/"..SELF_NAME
local VERSION_URL = RAW_BASE.."/VERSION-restore"

-- ============================================================
-- PATHS
-- ============================================================
local HOME           = os.getenv("HOME") or "/data/data/com.termux/files/home"
local PREFIX         = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
local TMP_DIR        = os.getenv("TMPDIR") or (PREFIX.."/tmp")
local SATURNITY_DIR  = HOME.."/saturnity"
local LOG_DIR        = SATURNITY_DIR.."/logs"
local LOG_FILE       = LOG_DIR.."/restore.log"
local FAIL_LOG       = LOG_DIR.."/restore_failures.log"
local DISABLED_LIST  = SATURNITY_DIR.."/disabled.list"
local PROP_BACKUP    = SATURNITY_DIR.."/local.prop.backup"

-- ============================================================
-- COLORS
-- ============================================================
local C = {
    reset  = "\27[0m",   bold = "\27[1m",
    pink   = "\27[38;5;213m",
    purple = "\27[38;5;141m",
    cyan   = "\27[38;5;87m",
    green  = "\27[38;5;120m",
    yellow = "\27[38;5;228m",
    red    = "\27[38;5;203m",
    gray   = "\27[38;5;245m",
    saturn = "\27[38;5;177m",
}

-- Settings we wrote (to reset back to default)
local SETTINGS_RESET = {
    {ns="global", key="window_animation_scale",     val="1.0"},
    {ns="global", key="transition_animation_scale", val="1.0"},
    {ns="global", key="animator_duration_scale",    val="1.0"},
    {ns="global", key="hide_error_dialogs",         val="0"},
    {ns="secure", key="show_first_crash_dialog",    val="1"},
    {ns="global", key="stay_on_while_plugged_in",   val="0"},
    {ns="global", key="auto_sync",                  val="1"},
    {ns="secure", key="adaptive_battery_management_enabled", val="1"},
    {ns="global", key="ota_disable_automatic_update", val="0"},
}

-- Persist props we set (revert)
local PROPS_RESET = {
    {key="persist.logd.size",                 val="256K"},
    {key="persist.traced.enable",             val="1"},
    {key="persist.debug.atrace.boottrace",    val="0"},
    {key="persist.sys.purgeable_assets",      val="0"},
    {key="persist.sys.lmk.kill_heaviest_task",val="false"},
    {key="persist.sys.lmk.use_minfree_levels",val="false"},
}

-- 8 clones (to clear standby/appops back to default)
local ROBLOX_CLONES = {
    "com.roblox.client",
    "com.roblox.clienr",
    "com.roblox.cliens",
    "com.roblox.clienv",
    "com.roblox.clienw",
    "com.roblox.clienx",
    "com.roblox.clieny",
    "com.roblox.clienz",
}

-- ============================================================
-- UTILITIES
-- ============================================================

local function mkdirp(p) os.execute("mkdir -p '"..p.."' 2>/dev/null") end

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function read_file(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function write_file(p, d)
    local f = io.open(p, "w")
    if not f then return false end
    f:write(d)
    f:close()
    return true
end

local function append_file(p, d)
    local f = io.open(p, "a")
    if not f then return false end
    f:write(d)
    f:close()
    return true
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function timestamp() return os.date("%Y-%m-%d %H:%M:%S") end

local function shell(cmd)
    local to = TMP_DIR.."/.sat_o_"..os.time()..math.random(1000,9999)
    local te = TMP_DIR.."/.sat_e_"..os.time()..math.random(1000,9999)
    local ok = os.execute(cmd.." >"..to.." 2>"..te)
    local out = read_file(to) or ""
    local err = read_file(te) or ""
    os.remove(to); os.remove(te)
    local code = (type(ok) == "number") and ok or (ok and 0 or 1)
    return trim(out), trim(err), code
end

local function sush(cmd)
    local esc = cmd:gsub("'", [['\'']])
    return shell("su -c '"..esc.."'")
end

-- ============================================================
-- LOGGING
-- ============================================================

local stats = { ok = 0, warn = 0, fail = 0, skip = 0 }

local function log(level, msg)
    local color = C.gray
    if     level == "OK"    then color = C.green;  stats.ok   = stats.ok   + 1
    elseif level == "WARN"  then color = C.yellow; stats.warn = stats.warn + 1
    elseif level == "FAIL"  then color = C.red;    stats.fail = stats.fail + 1
    elseif level == "SKIP"  then color = C.gray;   stats.skip = stats.skip + 1
    elseif level == "INFO"  then color = C.cyan
    elseif level == "PHASE" then color = C.pink..C.bold
    elseif level == "FATAL" then color = C.red..C.bold
    end
    print(string.format("%s[%s]%s %s", color, level, C.reset, msg))
    append_file(LOG_FILE, string.format("[%s] [%-5s] %s\n", timestamp(), level, msg))
    if level == "FAIL" or level == "FATAL" then
        append_file(FAIL_LOG, string.format("[%s] [%s] %s\n", timestamp(), level, msg))
    end
end

local function log_cmd_failure(cmd, code, err)
    local d = string.format("  Cmd : %s\n  Exit: %d\n  Err : %s",
                            cmd, code, err ~= "" and err or "(empty)")
    append_file(LOG_FILE, d.."\n")
    append_file(FAIL_LOG, d.."\n")
end

-- ============================================================
-- BANNER + CONFIRM
-- ============================================================

local function banner()
    print(C.saturn..[[
   _____       _                  _ _
  / ____|     | |                (_) |
 | (___   __ _| |_ _   _ _ __ _ __ _| |_ _   _
  \___ \ / _` | __| | | | '__| '_ \| | __| | | |
  ____) | (_| | |_| |_| | |  | | | | | |_| |_| |
 |_____/ \__,_|\__|\__,_|_|  |_| |_|_|\__|\__, |
                                           __/ |
              RESTORE                     |___/   v]]..VERSION..C.reset)
    print(C.purple.."  Reverting Saturnity optimizations..."..C.reset)
    print(C.gray..string.rep("─", 56)..C.reset)
end

local function confirm(yes_flag)
    if yes_flag then
        log("INFO", "--yes flag detected, skipping confirmation")
        return true
    end
    io.write(C.yellow.."⚠  This will undo all Saturnity tweaks. Continue? [y/N]: "..C.reset)
    io.flush()
    local ans = io.read("*l") or ""
    ans = trim(ans):lower()
    return ans == "y" or ans == "yes"
end

-- ============================================================
-- AUTO-UPDATE
-- ============================================================

local function check_update()
    log("INFO", "Checking for updates...")
    local out, _, code = shell("curl -fsSL --max-time 6 "..VERSION_URL)
    if code ~= 0 or out == "" then
        log("WARN", "Update check failed — continuing with v"..VERSION)
        return
    end
    local remote = trim(out)
    if remote == VERSION then
        log("OK", "Already on latest version (v"..VERSION..")")
        return
    end
    log("INFO", "New restore.lua version: v"..remote)
    local self_path = arg[0]
    if not self_path or self_path == "" then
        log("WARN", "Cannot self-update — continuing")
        return
    end
    local _, _, dc = shell("curl -fsSL --max-time 15 -o '"..self_path..".new' "..SELF_URL)
    if dc ~= 0 then
        log("FAIL", "Download failed — continuing with v"..VERSION)
        return
    end
    os.execute("mv -f '"..self_path..".new' '"..self_path.."'")
    os.execute("chmod +x '"..self_path.."' 2>/dev/null")
    log("OK", "Updated to v"..remote.." — relaunching")
    os.execute("lua '"..self_path.."' --no-update-check --yes")
    os.exit(0)
end

-- ============================================================
-- PRE-FLIGHT
-- ============================================================

local function check_root()
    local out, _, code = shell("su -c 'id -u'")
    if code ~= 0 or out ~= "0" then
        log("FATAL", "Root not available")
        return false
    end
    log("OK", "Root verified")
    return true
end

local function setup_dirs()
    mkdirp(SATURNITY_DIR)
    mkdirp(LOG_DIR)
    mkdirp(TMP_DIR)
    write_file(FAIL_LOG, "")
    append_file(LOG_FILE, "\n========== "..timestamp().." | restore.lua v"..VERSION.." ==========\n")
end

-- ============================================================
-- PHASE 1 — RE-ENABLE PACKAGES
-- ============================================================

local function phase_reenable()
    log("PHASE", "Phase 1: Re-enable disabled packages")
    if not file_exists(DISABLED_LIST) then
        log("WARN", "disabled.list not found — nothing recorded to restore")
        return
    end
    local count = 0
    local kept = {}
    for line in io.lines(DISABLED_LIST) do
        local pkg = trim(line)
        if pkg ~= "" then
            count = count + 1
            local cmd = "pm enable "..pkg
            local _, err, code = sush(cmd)
            if code == 0 then
                log("OK", "Enabled "..pkg)
            else
                log("FAIL", "Could not enable "..pkg)
                log_cmd_failure(cmd, code, err)
                table.insert(kept, pkg)
            end
        end
    end
    log("INFO", "Processed "..count.." packages")
    -- rewrite list with only failures (so re-running restore retries them)
    if #kept > 0 then
        write_file(DISABLED_LIST, table.concat(kept, "\n").."\n")
        log("WARN", #kept.." packages still in disabled.list (will retry on next restore)")
    else
        os.remove(DISABLED_LIST)
        log("OK", "Cleared disabled.list")
    end
end

-- ============================================================
-- PHASE 2 — RESET SETTINGS
-- ============================================================

local function phase_reset_settings()
    log("PHASE", "Phase 2: Reset settings")
    for _, t in ipairs(SETTINGS_RESET) do
        local cmd = string.format("settings put %s %s %s", t.ns, t.key, t.val)
        local _, err, code = sush(cmd)
        if code == 0 then
            log("OK", string.format("%s.%s = %s", t.ns, t.key, t.val))
        else
            log("FAIL", "reset "..t.ns.."."..t.key)
            log_cmd_failure(cmd, code, err)
        end
    end
end

-- ============================================================
-- PHASE 3 — RESET PROPERTIES
-- ============================================================

local function phase_reset_props()
    log("PHASE", "Phase 3: Reset persistent properties")
    for _, p in ipairs(PROPS_RESET) do
        local cmd = string.format("setprop %s %s", p.key, p.val)
        local _, err, code = sush(cmd)
        if code == 0 then
            log("OK", string.format("%s = %s", p.key, p.val))
        else
            log("FAIL", "setprop "..p.key)
            log_cmd_failure(cmd, code, err)
        end
    end
    -- restore /data/local.prop from backup OR clear it
    if file_exists(PROP_BACKUP) then
        local data = read_file(PROP_BACKUP)
        local tmp = TMP_DIR.."/.sat_restore_prop"
        write_file(tmp, data)
        local _, err, code = sush("cp "..tmp.." /data/local.prop && chmod 644 /data/local.prop")
        os.remove(tmp)
        if code == 0 then
            log("OK", "Restored /data/local.prop from backup")
        else
            log("FAIL", "Could not restore /data/local.prop")
            log_cmd_failure("restore prop", code, err)
        end
    else
        local _, _, code = sush("rm -f /data/local.prop")
        if code == 0 then
            log("OK", "Removed /data/local.prop (no backup existed)")
        else
            log("WARN", "Could not remove /data/local.prop")
        end
    end
end

-- ============================================================
-- PHASE 4 — RESET VOLATILE TWEAKS
-- ============================================================

local function phase_reset_volatile()
    log("PHASE", "Phase 4: Reset volatile tweaks")
    -- governor → schedutil (Android 10 default)
    local cpu_count_out = sush("ls /sys/devices/system/cpu/ | grep -c '^cpu[0-9]'")
    local cpu_count = tonumber(cpu_count_out) or 0
    local restored = 0
    for i = 0, cpu_count - 1 do
        local path = "/sys/devices/system/cpu/cpu"..i.."/cpufreq/scaling_governor"
        local _, _, code = sush("[ -w "..path.." ] && echo schedutil > "..path)
        if code == 0 then restored = restored + 1 end
    end
    log("OK", "CPU governor → schedutil on "..restored.."/"..cpu_count.." cores")
    -- vm defaults
    sush("echo 0 > /proc/sys/vm/overcommit_memory")
    sush("echo 60 > /proc/sys/vm/swappiness")
    sush("echo 100 > /proc/sys/vm/vfs_cache_pressure")
    log("OK", "VM tweaks reverted to defaults")
end

-- ============================================================
-- PHASE 5 — CLEAR CLONE STANDBY OVERRIDES
-- ============================================================

local function phase_reset_clones()
    log("PHASE", "Phase 5: Clear clone overrides")
    for _, pkg in ipairs(ROBLOX_CLONES) do
        sush("appops set "..pkg.." RUN_IN_BACKGROUND default")
        log("OK", pkg.." background → default")
    end
end

-- ============================================================
-- SUMMARY
-- ============================================================

local function summary()
    print()
    print(C.saturn..string.rep("═", 56)..C.reset)
    print(C.bold..C.pink.."  🪐 SATURNITY RESTORE — SUMMARY"..C.reset)
    print(C.saturn..string.rep("═", 56)..C.reset)
    print(string.format("  %sSuccess%s : %d", C.green,  C.reset, stats.ok))
    print(string.format("  %sSkipped%s : %d", C.gray,   C.reset, stats.skip))
    print(string.format("  %sWarning%s : %d", C.yellow, C.reset, stats.warn))
    print(string.format("  %sFailed %s : %d", C.red,    C.reset, stats.fail))
    print(C.saturn..string.rep("═", 56)..C.reset)
    print(C.gray.."  Logs : "..LOG_FILE..C.reset)
    if stats.fail > 0 then
        print(C.red.."  Failures: "..FAIL_LOG..C.reset)
    end
    print(C.purple.."  Restore complete. 🪐"..C.reset)
    print()
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    local skip_update, yes_flag = false, false
    for _, a in ipairs(arg) do
        if a == "--no-update-check" then skip_update = true end
        if a == "--yes" or a == "-y" then yes_flag = true end
    end

    banner()
    setup_dirs()

    if not skip_update then check_update() end
    if not confirm(yes_flag) then
        print(C.gray.."Cancelled."..C.reset)
        os.exit(0)
    end
    if not check_root() then os.exit(1) end

    phase_reenable()
    phase_reset_settings()
    phase_reset_props()
    phase_reset_volatile()
    phase_reset_clones()

    summary()
    log("INFO", "Restore complete — exiting")
    os.exit(0)
end

main()
