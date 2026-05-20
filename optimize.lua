#!/usr/bin/env lua
--[[
==============================================================================
  SATURNITY OPTIMIZER
  "I love you to the moon and to Saturn"

  Target  : Android 10 (Redfinger Cloud Phone, rooted, Termux inside)
  Purpose : Debloat + persistent tuning for 8 Roblox clones
  Author  : Lana (@lucivaantarez / Saturnity)
  Repo    : https://github.com/lucivaantarez/opt

  Safe to re-run. Idempotent. Bot-farm aware. Auto-exits when done.

  v1.0.2 changes:
   - Removed Phase 4 (kernel writes blocked by Redfinger host)
   - Pre-scan all installed packages once (faster, fixes substring bug)
   - Auto-generate missing.list so ghosts get skipped silently next run
   - Compact output mode for narrow terminals (auto-detected)
   - --rescan flag to refresh missing.list
==============================================================================
]]

local VERSION = "1.0.2"

-- ============================================================
-- AUTO-UPDATE CONFIG
-- ============================================================
local REPO_USER   = "lucivaantarez"
local REPO_NAME   = "opt"
local REPO_BRANCH = "main"
local RAW_BASE    = "https://raw.githubusercontent.com/"..REPO_USER.."/"..REPO_NAME.."/"..REPO_BRANCH
local SELF_NAME   = "optimize.lua"
local SELF_URL    = RAW_BASE.."/"..SELF_NAME
local VERSION_URL = RAW_BASE.."/VERSION"

-- ============================================================
-- PATHS
-- ============================================================
local HOME           = os.getenv("HOME") or "/data/data/com.termux/files/home"
local PREFIX         = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
local TMP_DIR        = os.getenv("TMPDIR") or (PREFIX.."/tmp")
local SATURNITY_DIR  = HOME.."/saturnity"
local LOG_DIR        = SATURNITY_DIR.."/logs"
local LOG_FILE       = LOG_DIR.."/optimize.log"
local FAIL_LOG       = LOG_DIR.."/failures.log"
local DISABLED_LIST  = SATURNITY_DIR.."/disabled.list"
local MISSING_LIST   = SATURNITY_DIR.."/missing.list"
local PROP_BACKUP    = SATURNITY_DIR.."/local.prop.backup"

-- ============================================================
-- NEON COLORS
-- ============================================================
local C = {
    reset  = "\27[0m",   bold   = "\27[1m",   dim   = "\27[2m",
    pink   = "\27[38;5;213m",
    purple = "\27[38;5;141m",
    cyan   = "\27[38;5;87m",
    green  = "\27[38;5;120m",
    yellow = "\27[38;5;228m",
    red    = "\27[38;5;203m",
    blue   = "\27[38;5;111m",
    gray   = "\27[38;5;245m",
    saturn = "\27[38;5;177m",
}

-- ============================================================
-- 8 ROBLOX CLONES (PROTECTED — NEVER DISABLE)
-- ============================================================
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
-- DEBLOAT TARGETS (AUDITED SAFE)
-- ============================================================
local DEBLOAT_PACKAGES = {
    -- Theme / icon-pack bloat
    "com.android.theme.icon_pack.filled.android",
    "com.android.theme.icon_pack.filled.systemui",
    "com.android.theme.icon_pack.filled.themepicker",
    "com.android.theme.icon_pack.filled.settings",
    "com.android.theme.icon_pack.filled.launcher",
    "com.android.theme.icon_pack.circular.android",
    "com.android.theme.icon_pack.circular.systemui",
    "com.android.theme.icon_pack.circular.settings",
    "com.android.theme.icon_pack.circular.launcher",
    "com.android.theme.icon_pack.rounded.android",
    "com.android.theme.icon_pack.rounded.systemui",
    "com.android.theme.icon_pack.rounded.settings",
    "com.android.theme.icon_pack.rounded.launcher",
    "com.android.theme.icon.squircle",
    "com.android.theme.icon.roundedrect",
    "com.android.theme.color.purple",
    "com.android.theme.color.orchid",
    "com.android.theme.color.ocean",
    "com.android.theme.color.space",
    "com.android.theme.color.cinnamon",
    "com.android.theme.color.black",
    "com.android.theme.color.green",
    "com.android.theme.font.notoserifsource",
    "com.android.systemui.navbar.gestural",
    "com.android.systemui.navbar.gestural_extra_wide_back",
    "com.android.systemui.navbar.gestural_narrow_back",
    "com.android.systemui.navbar.gestural_wide_back",
    "com.android.systemui.navbar.twobutton",
    "com.android.systemui.navbar.threebutton",
    -- Telephony stack (cloud Android = no SIM)
    "com.android.dialer",
    "com.android.contacts",
    "com.android.providers.contacts",
    "com.android.telecom",
    "com.android.server.telecom",
    "com.android.mms",
    "com.android.mms.service",
    "com.android.smspush",
    "com.android.providers.blockednumber",
    "com.android.carrierconfig",
    "com.android.carrierdefaultapp",
    "com.android.cellbroadcastreceiver",
    -- Provisioning / backup
    "com.android.managedprovisioning",
    "com.android.onetimeinitializer",
    "com.android.backupconfirm",
    "com.android.sharedstoragebackup",
    "com.android.statementservice",
    "com.android.dynsystem",
    -- Misc bloat
    "com.android.email",
    "com.android.calendar",
    "com.android.gallery3d",
    "com.android.chrome",
    "com.android.egg",
    "com.android.dreams.basic",
    "com.android.dreams.phototable",
    "com.android.wallpaper.livepicker",
    "com.android.wallpaperbackup",
    "com.android.bips",
    "com.android.printspooler",
    "com.android.printservice.recommendation",
    "com.android.bluetoothmidiservice",
    "com.android.nfc",
    "com.android.providers.userdictionary",
    "com.android.providers.partnerbookmarks",
    "com.android.bookmarkprovider",
    "com.android.captiveportallogin",
    "com.android.musicfx",
    "com.android.settings.intelligence",
    "com.android.companiondevicemanager",
    "com.google.android.apps.nbu.files",
    "com.google.android.tts",
    "com.google.android.partnersetup",
    "com.google.android.gms.location.fused",
}

-- ============================================================
-- UTILITIES
-- ============================================================

local function mkdirp(path)
    os.execute("mkdir -p '"..path.."' 2>/dev/null")
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function append_file(path, data)
    local f = io.open(path, "a")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Run a shell command, capture stdout, stderr, exit code
local function shell(cmd)
    local tmp_out = TMP_DIR.."/.sat_out_"..os.time()..math.random(1000,9999)
    local tmp_err = TMP_DIR.."/.sat_err_"..os.time()..math.random(1000,9999)
    local full = cmd.." >"..tmp_out.." 2>"..tmp_err
    local ok, _, code = os.execute(full)
    local out = read_file(tmp_out) or ""
    local err = read_file(tmp_err) or ""
    os.remove(tmp_out)
    os.remove(tmp_err)
    if type(ok) == "number" then code = ok end
    return trim(out), trim(err), code or 0
end

-- Run as root
local function sush(cmd)
    local escaped = cmd:gsub("'", [['\'']])
    return shell("su -c '"..escaped.."'")
end

-- ============================================================
-- TERMINAL WIDTH DETECTION + COMPACT MODE
-- ============================================================

local TERM_COLS = 80
local COMPACT   = false

local function detect_terminal()
    local out = shell("stty size 2>/dev/null || tput cols 2>/dev/null || echo 80")
    -- stty size returns "rows cols"
    local rows, cols = out:match("^(%d+)%s+(%d+)$")
    if cols then
        TERM_COLS = tonumber(cols)
    else
        local n = tonumber(out:match("(%d+)"))
        if n then TERM_COLS = n end
    end
    COMPACT = TERM_COLS < 60
end

-- Shorten package name for compact display (log file always gets full name)
local function display_pkg(pkg)
    if not COMPACT then return pkg end
    local s = pkg
    s = s:gsub("^com%.google%.android%.", "g/")
    s = s:gsub("^com%.android%.", "")
    return s
end

-- ============================================================
-- LOGGING
-- ============================================================

local stats = { ok = 0, warn = 0, fail = 0, skip = 0 }

local function log_raw(line)
    append_file(LOG_FILE, line.."\n")
end

local function log(level, msg, msg_full)
    -- msg_full is the long version for the log file (defaults to msg)
    msg_full = msg_full or msg
    local ts = timestamp()
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
    log_raw(string.format("[%s] [%-5s] %s", ts, level, msg_full))
    if level == "FAIL" or level == "FATAL" then
        append_file(FAIL_LOG, string.format("[%s] [%s] %s\n", ts, level, msg_full))
    end
end

local function log_cmd_failure(cmd, code, err)
    local detail = string.format("  Command : %s\n  Exitcode: %d\n  Stderr  : %s",
                                 cmd, code, err ~= "" and err or "(empty)")
    log_raw(detail)
    append_file(FAIL_LOG, detail.."\n")
end

-- ============================================================
-- BANNER
-- ============================================================

local function banner()
    if COMPACT then
        print(C.saturn..C.bold.."  🪐 SATURNITY  v"..VERSION..C.reset)
        print(C.purple.."  to the moon and to Saturn"..C.reset)
        print(C.gray..string.rep("─", math.min(TERM_COLS, 40))..C.reset)
    else
        print(C.saturn..[[
   _____       _                  _ _
  / ____|     | |                (_) |
 | (___   __ _| |_ _   _ _ __ _ __ _| |_ _   _
  \___ \ / _` | __| | | | '__| '_ \| | __| | | |
  ____) | (_| | |_| |_| | |  | | | | | |_| |_| |
 |_____/ \__,_|\__|\__,_|_|  |_| |_|_|\__|\__, |
                                           __/ |
                                          |___/   v]]..VERSION..C.reset)
        print(C.purple.."  \"I love you to the moon and to Saturn\""..C.reset)
        print(C.gray..string.rep("─", 56)..C.reset)
    end
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
    log("INFO", "New version available: v"..remote.." (current v"..VERSION..")")
    log("INFO", "Updating...")
    local self_path = arg[0]
    if not self_path or self_path == "" then
        log("WARN", "Cannot self-update (unknown path) — continuing")
        return
    end
    local _, _, dl_code = shell("curl -fsSL --max-time 15 -o '"..self_path..".new' "..SELF_URL)
    if dl_code ~= 0 then
        log("FAIL", "Download failed — continuing with v"..VERSION)
        return
    end
    os.execute("mv -f '"..self_path..".new' '"..self_path.."'")
    os.execute("chmod +x '"..self_path.."' 2>/dev/null")
    log("OK", "Updated to v"..remote.." — relaunching")
    os.execute("lua '"..self_path.."' --no-update-check")
    os.exit(0)
end

-- ============================================================
-- PRE-FLIGHT
-- ============================================================

local function check_root()
    local out, _, code = shell("su -c 'id -u'")
    if code ~= 0 or out ~= "0" then
        log("FATAL", "Root not available. Cannot continue.")
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
    append_file(LOG_FILE, "\n========== "..timestamp().." | optimize.lua v"..VERSION.." ==========\n")
end

local function ram_info()
    local out = shell("cat /proc/meminfo | grep -E 'MemTotal|MemAvailable'")
    local total, avail = 0, 0
    for k, v in out:gmatch("(%w+):%s+(%d+)") do
        if k == "MemTotal"     then total = tonumber(v) / 1024 end
        if k == "MemAvailable" then avail = tonumber(v) / 1024 end
    end
    return total, avail
end

-- ============================================================
-- PACKAGE PRE-SCAN (NEW — fixes substring bug, much faster)
-- ============================================================

-- installed[pkg] = true if exact package exists on device
-- disabled[pkg]  = true if exact package is currently disabled
local installed = {}
local disabled  = {}

local function scan_packages()
    log("INFO", "Scanning installed packages...")
    -- all installed (enabled + disabled)
    local out_all = sush("pm list packages")
    for line in out_all:gmatch("[^\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg then installed[trim(pkg)] = true end
    end
    -- disabled set
    local out_dis = sush("pm list packages -d")
    for line in out_dis:gmatch("[^\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg then disabled[trim(pkg)] = true end
    end
    local n = 0; for _ in pairs(installed) do n = n + 1 end
    log("OK", string.format("Found %d installed packages", n))
end

-- ============================================================
-- MISSING LIST (NEW — silently skip ghosts on future runs)
-- ============================================================

local missing_known = {}   -- pkgs known not to exist on this device
local missing_new   = {}   -- newly detected ghosts (to append)

local function load_missing_list()
    if not file_exists(MISSING_LIST) then return end
    for line in io.lines(MISSING_LIST) do
        local pkg = trim(line)
        if pkg ~= "" and not pkg:match("^#") then
            missing_known[pkg] = true
        end
    end
end

local function save_missing_list()
    if #missing_new == 0 then return end
    -- merge with known, dedupe, write
    local set = {}
    for pkg, _ in pairs(missing_known) do set[pkg] = true end
    for _, pkg in ipairs(missing_new)  do set[pkg] = true end
    local sorted = {}
    for pkg, _ in pairs(set) do table.insert(sorted, pkg) end
    table.sort(sorted)
    local content = "# Saturnity missing-packages cache\n"
    content = content.."# Auto-generated. Packages here do not exist on this device.\n"
    content = content.."# Delete this file to force a full rescan.\n"
    for _, pkg in ipairs(sorted) do content = content..pkg.."\n" end
    write_file(MISSING_LIST, content)
end

-- ============================================================
-- PHASE 1 — DEBLOAT
-- ============================================================

local newly_disabled_count = 0

local function phase_debloat()
    log("PHASE", "Phase 1: Debloat")
    local existing_in_list = {}
    if file_exists(DISABLED_LIST) then
        for line in io.lines(DISABLED_LIST) do
            existing_in_list[trim(line)] = true
        end
    end
    -- Roblox clone safety set
    local protected = {}
    for _, p in ipairs(ROBLOX_CLONES) do protected[p] = true end

    local newly_disabled = {}
    local silent_ghosts  = 0

    for _, pkg in ipairs(DEBLOAT_PACKAGES) do
        if protected[pkg] then
            log("WARN", "REFUSED protected pkg: "..display_pkg(pkg), "REFUSED protected pkg: "..pkg)
        elseif missing_known[pkg] then
            -- Known ghost from previous run — silent skip
            silent_ghosts = silent_ghosts + 1
        elseif not installed[pkg] then
            -- New ghost — log once + add to missing.list
            log("SKIP", display_pkg(pkg).." (not installed)", pkg.." (not installed)")
            table.insert(missing_new, pkg)
        elseif disabled[pkg] then
            log("SKIP", display_pkg(pkg).." (already disabled)", pkg.." (already disabled)")
            if not existing_in_list[pkg] then table.insert(newly_disabled, pkg) end
        else
            local cmd = "pm disable-user --user 0 "..pkg
            local _, err, code = sush(cmd)
            if code == 0 then
                log("OK", "Disabled "..display_pkg(pkg), "Disabled "..pkg)
                if not existing_in_list[pkg] then table.insert(newly_disabled, pkg) end
                newly_disabled_count = newly_disabled_count + 1
            else
                log("FAIL", "Could not disable "..display_pkg(pkg), "Could not disable "..pkg)
                log_cmd_failure(cmd, code, err)
            end
        end
    end

    if silent_ghosts > 0 then
        log("INFO", string.format("Skipped %d packages not on this device", silent_ghosts))
    end

    -- append newly_disabled to disabled.list
    if #newly_disabled > 0 then
        local fp = io.open(DISABLED_LIST, "a")
        if fp then
            for _, p in ipairs(newly_disabled) do fp:write(p.."\n") end
            fp:close()
        end
    end
end

-- ============================================================
-- PHASE 2 — SETTINGS (PERSISTENT)
-- ============================================================

local SETTINGS_TWEAKS = {
    {ns="global", key="window_animation_scale",     val="0"},
    {ns="global", key="transition_animation_scale", val="0"},
    {ns="global", key="animator_duration_scale",    val="0"},
    {ns="global", key="hide_error_dialogs",         val="1"},
    {ns="secure", key="show_first_crash_dialog",    val="0"},
    {ns="global", key="stay_on_while_plugged_in",   val="3"},
    {ns="global", key="auto_sync",                  val="0"},
    {ns="secure", key="adaptive_battery_management_enabled", val="0"},
    {ns="global", key="ota_disable_automatic_update", val="1"},
}

local function phase_settings()
    log("PHASE", "Phase 2: Settings tweaks")
    for _, t in ipairs(SETTINGS_TWEAKS) do
        local cmd = string.format("settings put %s %s %s", t.ns, t.key, t.val)
        local _, err, code = sush(cmd)
        if code == 0 then
            log("OK", string.format("%s.%s = %s", t.ns, t.key, t.val))
        else
            log("FAIL", string.format("settings %s.%s", t.ns, t.key))
            log_cmd_failure(cmd, code, err)
        end
    end
end

-- ============================================================
-- PHASE 3 — PERSISTENT PROPERTIES
-- ============================================================

local PERSIST_PROPS = {
    {key="persist.logd.size",                 val="64K"},
    {key="persist.traced.enable",             val="0"},
    {key="persist.debug.atrace.boottrace",    val="0"},
    {key="persist.sys.purgeable_assets",      val="1"},
    {key="persist.sys.lmk.kill_heaviest_task",val="true"},
    {key="persist.sys.lmk.use_minfree_levels",val="true"},
}

local LOCAL_PROP_ENTRIES = {
    "ro.lmk.kill_heaviest_task=true",
    "ro.lmk.use_minfree_levels=true",
    "debug.hwui.renderer=skiagl",
    "debug.sf.disable_backpressure=1",
    "debug.sf.nobootanimation=1",
    "dalvik.vm.usejit=true",
    "dalvik.vm.usejitprofiles=true",
    "pm.dexopt.bg-dexopt=nothing",
}

local function phase_props()
    log("PHASE", "Phase 3: Persistent properties")
    for _, p in ipairs(PERSIST_PROPS) do
        local cmd = string.format("setprop %s %s", p.key, p.val)
        local _, err, code = sush(cmd)
        if code == 0 then
            log("OK", string.format("%s = %s", p.key, p.val))
        else
            log("FAIL", "setprop "..p.key)
            log_cmd_failure(cmd, code, err)
        end
    end
    log("INFO", "Writing /data/local.prop")
    local existing = sush("cat /data/local.prop 2>/dev/null")
    if existing and existing ~= "" and not file_exists(PROP_BACKUP) then
        write_file(PROP_BACKUP, existing)
        log("OK", "Backed up existing /data/local.prop")
    end
    local kept = {}
    if existing and existing ~= "" then
        for line in existing:gmatch("[^\n]+") do
            local is_ours = false
            for _, entry in ipairs(LOCAL_PROP_ENTRIES) do
                local k = entry:match("^([^=]+)=")
                if k and line:find("^"..k:gsub("%.","%%%."), 1) then
                    is_ours = true; break
                end
            end
            if not is_ours and trim(line) ~= "" then
                table.insert(kept, line)
            end
        end
    end
    local content = "# Saturnity v"..VERSION.." managed entries\n"
    for _, e in ipairs(LOCAL_PROP_ENTRIES) do content = content..e.."\n" end
    if #kept > 0 then
        content = content.."\n# Pre-existing entries\n"
        for _, l in ipairs(kept) do content = content..l.."\n" end
    end
    local tmp = TMP_DIR.."/.sat_local.prop"
    write_file(tmp, content)
    local _, err, code = sush("cp "..tmp.." /data/local.prop && chmod 644 /data/local.prop")
    os.remove(tmp)
    if code == 0 then
        log("OK", "/data/local.prop written ("..#LOCAL_PROP_ENTRIES.." entries)")
    else
        log("FAIL", "writing /data/local.prop")
        log_cmd_failure("cp /data/local.prop", code, err)
    end
end

-- ============================================================
-- PHASE 4 — ROBLOX CLONE PROTECTION
-- ============================================================

local function phase_clone_protection()
    log("PHASE", "Phase 4: Roblox clone protection")
    for _, pkg in ipairs(ROBLOX_CLONES) do
        if not installed[pkg] then
            log("WARN", display_pkg(pkg).." not installed", pkg.." not installed")
        else
            local _, _, c1 = sush("appops set "..pkg.." RUN_IN_BACKGROUND allow")
            if c1 == 0 then
                log("OK", display_pkg(pkg).." background allowed", pkg.." background allowed")
            else
                log("WARN", "appops "..display_pkg(pkg), "appops "..pkg)
            end
            local _, _, c2 = sush("am set-inactive "..pkg.." false")
            if c2 == 0 then
                log("OK", display_pkg(pkg).." marked active", pkg.." marked active")
            end
            sush("am set-standby-bucket "..pkg.." active")
        end
    end
end

-- ============================================================
-- SUMMARY
-- ============================================================

local function print_summary(ram_before, ram_after)
    local line_w = math.min(TERM_COLS, 56)
    local sep = string.rep("═", line_w)
    print()
    print(C.saturn..sep..C.reset)
    print(C.bold..C.pink.."  🪐 SATURNITY — SUMMARY"..C.reset)
    print(C.saturn..sep..C.reset)
    print(string.format("  %sSuccess%s : %d", C.green,  C.reset, stats.ok))
    print(string.format("  %sSkipped%s : %d", C.gray,   C.reset, stats.skip))
    print(string.format("  %sWarning%s : %d", C.yellow, C.reset, stats.warn))
    print(string.format("  %sFailed %s : %d", C.red,    C.reset, stats.fail))
    print(C.saturn..string.rep("─", line_w)..C.reset)
    print(string.format("  RAM before : %s%.0f MB%s", C.cyan, ram_before, C.reset))
    print(string.format("  RAM after  : %s%.0f MB%s", C.cyan, ram_after,  C.reset))
    local diff = ram_after - ram_before
    local color = diff >= 0 and C.green or C.red
    print(string.format("  Net change : %s%+.0f MB%s", color, diff, C.reset))
    print(C.saturn..sep..C.reset)
    print(C.gray.."  Logs : "..LOG_FILE..C.reset)
    if stats.fail > 0 then
        print(C.red.."  Failures: "..FAIL_LOG..C.reset)
    end
    if newly_disabled_count > 0 then
        print()
        print(C.yellow..C.bold.."  ⏰ Reboot Redfinger to fully free RAM"..C.reset)
        print(C.gray.."     ("..newly_disabled_count.." new packages disabled — RAM"..C.reset)
        print(C.gray.."      gains apply after reboot)"..C.reset)
    end
    print(C.purple.."  \"To the moon and to Saturn 🪐\""..C.reset)
    print()
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    local skip_update, do_rescan = false, false
    for _, a in ipairs(arg) do
        if a == "--no-update-check" then skip_update = true end
        if a == "--rescan"          then do_rescan   = true end
    end

    detect_terminal()
    banner()
    setup_dirs()

    if do_rescan then
        os.remove(MISSING_LIST)
        log("INFO", "Cleared missing.list (--rescan)")
    end

    if not skip_update then check_update() end
    if not check_root() then os.exit(1) end

    load_missing_list()
    scan_packages()

    local ram_total, ram_before = ram_info()
    log("INFO", string.format("Device RAM: %.0f MB total, %.0f MB available", ram_total, ram_before))

    phase_debloat()
    phase_settings()
    phase_props()
    phase_clone_protection()

    save_missing_list()

    local _, ram_after = ram_info()
    print_summary(ram_before, ram_after)
    log("INFO", "Optimization complete — exiting cleanly")
    os.exit(0)
end

main()
