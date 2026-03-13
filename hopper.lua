#!/data/data/com.termux/files/usr/bin/lua
-- ============================================================
--  ROBLOX SERVER HOPPER v6
--  Standalone | lua hopper.lua
-- ============================================================

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- PATHS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local HOME        = os.getenv("HOME") or "/data/data/com.termux/files/home"
local CONFIG_FILE = HOME .. "/.hopper_config.lua"
local LOG_FILE    = "/sdcard/hopper_log.txt"
local STATE_FILE  = "/sdcard/.hopper_state"
local STOP_FILE   = "/sdcard/.hopper_stop"
local LOOP_FILE   = "/sdcard/.hopper_loop.lua"
local PID_FILE    = "/sdcard/.hopper_pid"
local AE_BAK_FILE = "/sdcard/.auto_1.lua.bak"
local W           = 52

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LOOP CODE (injected raw ke generated script)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local LOOP_CODE = [=[
local function sleep(sec)
    if sec and sec > 0 then os.execute("sleep " .. math.floor(sec)) end
end
local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'","'\\''") .. "' >/dev/null 2>&1")
end
local function file_exists(p)
    local f = io.open(p,"r"); if f then f:close(); return true end; return false
end
local function write_state(s)
    local f = io.open(STATE_FILE,"w"); if f then f:write(s); f:close() end
end
local function log(msg)
    local f = io.open(LOG_FILE,"a")
    if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
end
local function is_running(pkg)
    local h = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- ─── COOKIE INJECT (per-client) ──────────────────────────────
local function inject_cookie(pkg, cookie)
    if not cookie or cookie == "" then return end
    local dir  = "/data/data/" .. pkg .. "/shared_prefs"
    local file = dir .. "/RobloxSharedPreferences.xml"
    local src  = "/tmp/hcookie_" .. pkg:gsub("[^%w]","_") .. ".xml"
    local f = io.open(src,"w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">' .. cookie .. "</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. src .. "' '" .. file .. "'")
    su_exec("chmod 660 '" .. file .. "'")
    os.remove(src)
    log("Cookie injected: " .. pkg)
end

-- ─── AUTOEXEC ────────────────────────────────────────────────
local function inject_autoexec()
    if not AUTOEXEC_SCRIPT or AUTOEXEC_SCRIPT == "" then return end
    local dir = AUTOEXEC_PATH:match("^(.+)/[^/]+$")
    if dir then su_exec("mkdir -p '" .. dir .. "'") end
    su_exec("cp '" .. AUTOEXEC_PATH .. "' '" .. AE_BAK_FILE .. "' 2>/dev/null")
    local f = io.open(AUTOEXEC_PATH,"w")
    if f then f:write(AUTOEXEC_SCRIPT); f:close()
    else
        local esc = AUTOEXEC_SCRIPT:gsub("'","'\\''")
        su_exec("echo '" .. esc .. "' > '" .. AUTOEXEC_PATH .. "'")
    end
    su_exec("chmod 644 '" .. AUTOEXEC_PATH .. "'")
    log("Autoexec injected")
end

local function restore_autoexec()
    if not AUTOEXEC_RESTORE or AUTOEXEC_RESTORE == "" then return end
    local f = io.open(AUTOEXEC_PATH,"w")
    if f then f:write(AUTOEXEC_RESTORE); f:close()
    else
        local esc = AUTOEXEC_RESTORE:gsub("'","'\\''")
        su_exec("echo '" .. esc .. "' > '" .. AUTOEXEC_PATH .. "'")
    end
    su_exec("chmod 644 '" .. AUTOEXEC_PATH .. "'")
    su_exec("rm -f '" .. AE_BAK_FILE .. "' 2>/dev/null")
    log("Autoexec restored")
end

-- ─── LAUNCH ──────────────────────────────────────────────────
local function launch_client(c, ps_index, cnum)
    if not ps_links[ps_index] then
        log("ERROR: PS index " .. tostring(ps_index) .. " out of range")
        return
    end
    su_exec("am force-stop " .. c.pkg)
    os.execute("sleep 1")
    inject_cookie(c.pkg, c.cookie)
    local raw = ps_links[ps_index]
    local dp  = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://","")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. c.pkg
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    log("Client " .. cnum .. " -> PS " .. ps_index)
end

-- ─── MAIN LOOP ───────────────────────────────────────────────
math.randomseed(os.time())
log("--- Hopper Started ---")

for _, c in ipairs(clients) do
    su_exec("am force-stop " .. c.pkg)
end
inject_autoexec()
sleep(1)

local hop_count = 0

while true do
    for ci, c in ipairs(clients) do
        hop_count = hop_count + 1
        local ps_idx = c.ps_idx_list[c.curr_ptr]
        local wait   = math.random(DELAY_MIN, DELAY_MAX)
        local epoch  = os.time()

        write_state(hop_count .. "|" .. ci .. "|" .. #clients
            .. "|" .. wait .. "|" .. epoch .. "|ok")

        launch_client(c, ps_idx, ci)

        c.curr_ptr = c.curr_ptr + 1
        if c.curr_ptr > #(c.ps_idx_list) then c.curr_ptr = 1 end

        if ci < #clients then sleep(LAUNCH_DELAY) end
    end

    local function watchdog(duration)
        local elapsed = 0
        while duration == 0 or elapsed < duration do
            if file_exists(STOP_FILE) then return end
            os.execute("sleep 10")
            elapsed = elapsed + 10
            for i, c in ipairs(clients) do
                if not is_running(c.pkg) then
                    log("Crash client " .. i .. ", reopening")
                    local ptr = c.curr_ptr - 1
                    if ptr < 1 then ptr = #c.ps_idx_list end
                    launch_client(c, c.ps_idx_list[ptr], i)
                    write_state("crash|" .. i .. "|" .. #clients
                        .. "|0|" .. os.time() .. "|crash")
                end
            end
            write_state("hop|0|" .. #clients .. "|0|" .. os.time() .. "|watchdog")
        end
    end

    if DELAY_MIN == 0 then watchdog(0); break
    else
        local wait_total = math.random(DELAY_MIN, DELAY_MAX) * 60
        local wait_adj   = wait_total - ((#clients - 1) * LAUNCH_DELAY)
        if wait_adj < 0 then wait_adj = 0 end
        watchdog(wait_adj)
    end
end

restore_autoexec()
log("--- Hopper Stopped ---")
]=]

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CORE HELPERS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function sleep(sec)
    if sec and sec > 0 then os.execute("sleep " .. math.floor(sec)) end
end

local function clean(s)
    if not s then return "" end
    s = s:gsub("\27%[[%d;]*[A-Za-z]",""):gsub("%c","")
    return s:gsub("^%s+",""):gsub("%s+$","")
end

local function trunc(s, max)
    s = tostring(s or "-")
    if #s <= max then return s end
    return s:sub(1, max-2) .. ".."
end

local function pad(s, len)
    s = tostring(s or "")
    if #s >= len then return s:sub(1, len) end
    return s .. string.rep(" ", len - #s)
end

local function sanitize_pkg(pkg)
    if not pkg then return nil end
    local s = pkg:gsub("[^%w%._]","")
    return s ~= "" and s or nil
end

local function is_valid_ps_link(link)
    if not link or link == "" then return false end
    if not link:match("^https?://") and not link:match("^intent://") then return false end
    if not link:lower():match("code=") then return false end
    if link:match("[;|`$%(%){}%z]") then return false end
    return true
end

local function escape_lua_str(s)
    return s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('%z','')
end

local function file_exists(p)
    local f = io.open(p,"r"); if f then f:close(); return true end; return false
end

local function write_file(p, c)
    local f = io.open(p,"w"); if not f then return false end
    f:write(c); f:close(); return true
end

local function read_file(p)
    local f = io.open(p,"r"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function log_main(msg)
    local f = io.open(LOG_FILE,"a")
    if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CONFIG
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local CFG = {}

local function config_defaults()
    return {
        pkg_prefix       = "com.roblox.",
        delay_min        = 3,
        delay_max        = 7,
        launch_delay     = 20,
        hb_max_fail      = 3,
        autoexec_path    = "/storage/emulated/0/RonixExploit/autoexec/auto_1.lua",
        autoexec_script  = "",
        autoexec_restore = "",
        ps_links         = {},
        client_ps_map    = {},
        -- accounts[pkg] = {cookie="", name="", id=""}
        accounts         = {},
    }
end

local function serialize(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "string"  then return string.format("%q", v)
    elseif t == "number" or t == "boolean" then return tostring(v)
    elseif t == "table" then
        local inner = ind .. "  "
        local parts = {}
        if #v > 0 then
            for _, item in ipairs(v) do
                table.insert(parts, inner .. serialize(item, inner))
            end
        else
            for k, val in pairs(v) do
                local key = type(k)=="string"
                    and "["..string.format("%q",k).."]"
                    or  "["..tostring(k).."]"
                table.insert(parts, inner..key.." = "..serialize(val, inner))
            end
        end
        return "{\n"..table.concat(parts,",\n").."\n"..ind.."}"
    end
    return "nil"
end

local function save_config()
    write_file(CONFIG_FILE, "return "..serialize(CFG).."\n")
    os.execute("chmod 600 '"..CONFIG_FILE.."'")
end

local function load_config()
    CFG = config_defaults()
    if not file_exists(CONFIG_FILE) then return end
    local ok, loaded = pcall(dofile, CONFIG_FILE)
    if ok and type(loaded) == "table" then
        for k, v in pairs(loaded) do CFG[k] = v end
    end
    -- Pastikan accounts selalu table
    if type(CFG.accounts) ~= "table" then CFG.accounts = {} end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ROOT HELPERS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function su_cmd(cmd)
    local full = "su -c '"..cmd:gsub("'","'\\''").."' 2>&1"
    local h = io.popen(full); if not h then return "" end
    local r = h:read("*a"); h:close(); return clean(r)
end

local function su_exec(cmd)
    os.execute("su -c '"..cmd:gsub("'","'\\''").."' >/dev/null 2>&1")
end

local function is_running_host(pkg)
    local h = io.popen("su -c 'pidof "..pkg.."' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TERMINAL / UI
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local C = {
    reset="\27[0m", bold="\27[1m", dim="\27[2m",
    red="\27[31m", green="\27[32m", yellow="\27[33m",
    cyan="\27[36m", gray="\27[90m", white="\27[97m",
}
local function cc(code, text) return code..text..C.reset end
local function p(text) io.write((text or "").."\n"); io.flush() end
local function hr()  p(cc(C.yellow, string.rep("━", W))) end
local function sep() p(cc(C.dim,    string.rep("─", W))) end
local function clear_screen() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end
local function center(text)
    local pad_n = math.max(0, math.floor((W - #text) / 2))
    return string.rep(" ", pad_n) .. text
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- INPUT
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function ask(prompt)
    if prompt and prompt ~= "" then
        io.write(cc(C.cyan,"  ❯ ")..prompt..": ")
    else
        io.write(cc(C.cyan,"  ❯ "))
    end
    io.flush()
    local tty = io.open("/dev/tty","r")
    local r
    if tty then r = tty:read("*l"); tty:close()
    else r = io.read("*l") end
    if r == nil then sleep(1); return nil end
    return r:gsub("^%s+",""):gsub("%s+$","")
end

local function read_key(timeout)
    local h = io.popen("bash -c 'read -t "..(timeout or 1)
        .." -n 1 key < /dev/tty 2>/dev/null && echo $key' 2>/dev/null")
    if not h then sleep(timeout or 1); return nil end
    local key = h:read("*l"); h:close()
    return (key and key ~= "") and key or nil
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DETECTION
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function detect_packages()
    local prefix = CFG.pkg_prefix or "com.roblox."
    local h = io.popen("pm list packages 2>/dev/null")
    if not h then return {} end
    local out = h:read("*a") or ""; h:close()
    local pkgs = {}
    for line in out:gmatch("[^\r\n]+") do
        local pkg = sanitize_pkg(clean(line:match("package:(.+)")))
        if pkg and pkg:sub(1, #prefix) == prefix then
            table.insert(pkgs, pkg)
        end
    end
    table.sort(pkgs)
    return pkgs
end

local function fetch_account(cookie)
    if not cookie or cookie == "" then return nil, nil end
    local h = io.popen('curl -s --max-time 10 '
        ..'-H "Cookie: .ROBLOSECURITY='..cookie..'" '
        ..'"https://users.roblox.com/v1/users/authenticated"')
    if not h then return nil, nil end
    local res = h:read("*a"); h:close()
    local name = res:match('"name":"([^"]+)"')
    local id   = res:match('"id":(%d+)')
    return name, id
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SELECTION PARSER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function parse_selection(input, max_val)
    local sel, seen = {}, {}
    local s, e = input:match("^(%d+)%-(%d+)$")
    if s and e then
        for i = tonumber(s), math.min(tonumber(e), max_val) do
            if not seen[i] then table.insert(sel, i); seen[i]=true end
        end
        return sel
    end
    for n in input:gmatch("(%d+)") do
        local num = tonumber(n)
        if num and num>=1 and num<=max_val and not seen[num] then
            table.insert(sel, num); seen[num]=true
        end
    end
    return sel
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- PACKAGE TABLE (dashboard)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Kolom: Package | UserId | Username | State
-- Lebar: W = 52
-- [pkg 18] | [id 12] | [name 10] | [state 7]
local COL_PKG  = 18
local COL_ID   = 10
local COL_NAME = 10
local COL_ST   = 6

local function pkg_short(pkg)
    -- Tampilkan hanya bagian setelah prefix
    local prefix = CFG.pkg_prefix or "com.roblox."
    local short  = pkg:sub(#prefix + 1)
    return trunc(short ~= "" and short or pkg, COL_PKG)
end

local function draw_pkg_table(pkgs, active_set)
    -- Header
    p(cc(C.dim, " "
        ..pad("Package", COL_PKG).." "
        ..pad("UserId", COL_ID).." "
        ..pad("Username", COL_NAME).." "
        .."State"))
    p(cc(C.dim, string.rep("-", W)))

    if #pkgs == 0 then
        p(cc(C.red,"  Tidak ada package dengan prefix: "..CFG.pkg_prefix))
        return
    end

    for _, pkg in ipairs(pkgs) do
        local acc   = CFG.accounts[pkg] or {}
        local name  = acc.name or "-"
        local uid   = acc.id   or "-"
        local running = is_running_host(pkg)

        local state_str, state_col
        if active_set and active_set[pkg] then
            state_str = "● hop"
            state_col = C.yellow
        elseif running then
            state_str = "● run"
            state_col = C.green
        else
            state_str = "○ off"
            state_col = C.gray
        end

        local line = " "
            .. cc(C.cyan, pad(pkg_short(pkg), COL_PKG)) .. " "
            .. pad(trunc(uid, COL_ID), COL_ID) .. " "
            .. pad(trunc(name, COL_NAME), COL_NAME) .. " "
            .. cc(state_col, state_str)

        p(line)
    end
    p(cc(C.dim, string.rep("-", W)))
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD HEADER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function draw_header(status, pkgs, active_set, extra)
    clear_screen()
    hr()
    p(cc(C.bold, center("🎮 ROBLOX SERVER HOPPER v6")))
    hr()
    print("")

    -- Info bar singkat
    local ps_count = #CFG.ps_links
    local delay_str = CFG.delay_min.."-"..CFG.delay_max.."m"
    local ae_str = CFG.autoexec_script ~= "" and cc(C.green,"✓") or cc(C.dim,"–")

    p(string.format("  %sPrefix%s  %-18s %sPS%s %d  %sDelay%s %s  %sAE%s %s",
        C.dim, C.reset, CFG.pkg_prefix,
        C.dim, C.reset, ps_count,
        C.dim, C.reset, delay_str,
        C.dim, C.reset, ae_str))

    -- Status
    local status_badge
    if status == "running"  then status_badge = cc(C.green, cc(C.bold,"● RUNNING"))
    elseif status == "stopped"  then status_badge = cc(C.red,    "● STOPPED")
    elseif status == "starting" then status_badge = cc(C.yellow, "● STARTING...")
    elseif status == "stopping" then status_badge = cc(C.yellow, "● STOPPING...")
    else status_badge = status or "" end

    p("  "..status_badge..(extra and ("  "..cc(C.dim, extra)) or ""))
    print("")

    -- Package table
    pkgs = pkgs or detect_packages()
    draw_pkg_table(pkgs, active_set)
    print("")
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MAIN MENU
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function main_menu()
    local pkgs      = detect_packages()
    draw_header("stopped", pkgs)

    local can_start = #pkgs > 0 and #CFG.ps_links > 0

    p(cc(C.bold,"  1.").." Set package prefix   "..cc(C.dim,"("..CFG.pkg_prefix..")"))
    p(cc(C.bold,"  2.").." Kelola PS links       "..cc(C.dim,"("..#CFG.ps_links.." link)"))
    p(cc(C.bold,"  3.").." Per-client PS map     "..cc(C.dim, next(CFG.client_ps_map) and "(✓ set)" or "(– kosong)"))
    p(cc(C.bold,"  4.").." Set delay             "..cc(C.dim,"("..CFG.delay_min.."-"..CFG.delay_max.."m | launch "..CFG.launch_delay.."s)"))
    p(cc(C.bold,"  5.").." Kelola akun / cookie  "..cc(C.dim,"("..#pkgs.." package)"))
    p(cc(C.bold,"  6.").." Set autoexec")
    p(cc(C.bold,"  7.").." Heartbeat             "..cc(C.dim,"(max fail: "..CFG.hb_max_fail.."x)"))
    p(cc(C.bold,"  8.").." Lihat config")
    print("")

    if can_start then
        p(cc(C.green, cc(C.bold,"  9. ▶  START HOPPER")))
    else
        p(cc(C.dim,"  9.    START HOPPER"))
        if #pkgs == 0 then p(cc(C.red,"     ⚠  Tidak ada package dengan prefix: "..CFG.pkg_prefix)) end
        if #CFG.ps_links == 0 then p(cc(C.red,"     ⚠  Tambahkan PS link dulu")) end
    end

    p(cc(C.bold,"  0.").." Keluar")
    print("")

    local ch = ask("")
    if     ch == "1" then return "menu_prefix"
    elseif ch == "2" then return "menu_ps"
    elseif ch == "3" then return "menu_ps_map"
    elseif ch == "4" then return "menu_delay"
    elseif ch == "5" then return "menu_accounts"
    elseif ch == "6" then return "menu_autoexec"
    elseif ch == "7" then return "menu_heartbeat"
    elseif ch == "8" then return "menu_config"
    elseif ch == "9" then return can_start and "start" or "main"
    elseif ch == "0" then return "exit"
    end
    return "main"
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: PACKAGE PREFIX
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_prefix()
    draw_header("stopped")
    p(cc(C.bold,"  SET PACKAGE PREFIX")); print("")
    p(cc(C.dim,"  Prefix dipakai untuk filter package di 'pm list packages'"))
    p(cc(C.dim,"  Contoh: com.roblox.  /  com.winter.  /  com.byfron."))
    print("")
    p("  Prefix saat ini: "..cc(C.cyan, CFG.pkg_prefix))
    print("")

    -- Tampilkan package yang terdeteksi dengan prefix saat ini
    local pkgs = detect_packages()
    p(cc(C.dim, "  Package terdeteksi ("..#pkgs.."):"))
    for i, pkg in ipairs(pkgs) do
        p(string.format("    %s[%d]%s %s", C.cyan, i, C.reset, pkg))
    end
    print("")

    local inp = ask("Prefix baru (Enter=batal)")
    if not inp or inp == "" then return end

    -- Validasi: harus ada titik di akhir
    if inp:sub(-1) ~= "." then inp = inp .. "." end

    CFG.pkg_prefix = inp
    -- Bersihkan ps_map dari package yang mungkin tidak valid lagi
    CFG.client_ps_map = {}
    save_config()

    print("")
    p(cc(C.dim,"  Mencari package baru..."))
    local new_pkgs = detect_packages()
    p("  "..cc(C.green,"[+]").." Prefix diset: "..cc(C.bold, inp))
    p("  "..cc(C.green,"[+]").." "..#new_pkgs.." package ditemukan")
    sleep(2)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: PS LINKS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_ps()
    while true do
        draw_header("stopped")
        p(cc(C.bold,"  PRIVATE SERVER LINKS")); print("")
        if #CFG.ps_links == 0 then
            p(cc(C.dim,"  Belum ada link"))
        else
            for i, link in ipairs(CFG.ps_links) do
                p(string.format("  %s[%2d]%s %s", C.cyan, i, C.reset, trunc(link, W-7)))
            end
        end
        print("")
        sep()
        p("  "..cc(C.bold,"a").." Tambah  "
            ..cc(C.bold,"d").." Hapus  "
            ..cc(C.bold,"c").." Hapus semua  "
            ..cc(C.bold,"b").." Kembali")
        sep(); print("")
        local opt = ask("")

        if opt == "a" then
            draw_header("stopped")
            p(cc(C.bold,"  TAMBAH PS LINKS")); print("")
            p("  Paste links — "..cc(C.bold,"1 link per baris"))
            p(cc(C.dim,"  Harus 'https://' + mengandung 'code='"))
            p(cc(C.dim,"  Baris kosong atau 'done' untuk selesai"))
            print("")
            local added, skipped = 0, 0
            while true do
                local line = ask("")
                if not line or line == "" or line == "done" then break end
                if is_valid_ps_link(line) then
                    table.insert(CFG.ps_links, line)
                    added = added + 1
                    p("    "..cc(C.green,"✓").." ["..added.."] Ditambahkan")
                else
                    skipped = skipped + 1
                    p("    "..cc(C.red,"✗").." Tidak valid (butuh https:// + code=)")
                end
            end
            if added > 0 then save_config() end
            p("\n  "..cc(C.green,"[+]").." "..added.." ditambahkan"
                ..(skipped>0 and ", "..skipped.." dilewati" or ""))
            sleep(1)

        elseif opt == "d" then
            if #CFG.ps_links == 0 then p(cc(C.red,"  Tidak ada link")); sleep(1)
            else
                local n = ask("Hapus nomor (0=batal)")
                local idx = tonumber(n)
                if idx and idx > 0 and idx <= #CFG.ps_links then
                    table.remove(CFG.ps_links, idx)
                    for pkg, plist in pairs(CFG.client_ps_map) do
                        local new = {}
                        for _, pidx in ipairs(plist) do
                            if pidx <= #CFG.ps_links then table.insert(new, pidx) end
                        end
                        CFG.client_ps_map[pkg] = new
                    end
                    save_config()
                    p("  "..cc(C.green,"[+]").." Link #"..idx.." dihapus")
                else p(cc(C.dim,"  Dibatalkan")) end
                sleep(1)
            end

        elseif opt == "c" then
            local conf = ask("Ketik 'hapus' untuk konfirmasi")
            if conf == "hapus" then
                CFG.ps_links = {}; CFG.client_ps_map = {}
                save_config()
                p("  "..cc(C.green,"[+]").." Semua link dihapus"); sleep(1)
            end

        elseif opt == "b" then break
        end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: PER-CLIENT PS MAP
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_ps_map()
    draw_header("stopped")
    p(cc(C.bold,"  PER-CLIENT PS MAPPING")); print("")
    p(cc(C.dim,"  Kosong = semua PS berurutan"))
    print("")

    if #CFG.ps_links == 0 then p(cc(C.red,"  ⚠  Tambahkan PS link dulu!")); sleep(2); return end
    local pkgs = detect_packages()
    if #pkgs == 0 then p(cc(C.red,"  ⚠  Tidak ada package!")); sleep(2); return end

    p("  Total PS: "..cc(C.cyan, #CFG.ps_links)); print("")
    for i, link in ipairs(CFG.ps_links) do
        p(string.format("  %s[%2d]%s %s", C.dim, i, C.reset, trunc(link, W-7)))
    end
    print("")

    for i, pkg in ipairs(pkgs) do
        local cur = CFG.client_ps_map[pkg] or {}
        local cur_str = #cur > 0 and table.concat(cur,",") or cc(C.dim,"semua")
        p(string.format("  %s[%d]%s %s", C.cyan, i, C.reset, pkg))
        p(cc(C.dim,"       Saat ini: ")..cur_str)
        local inp = ask("PS untuk client "..i.." (e.g 1-5, 1,2 atau Enter=semua)")
        if inp and inp ~= "" then
            local sel = parse_selection(inp, #CFG.ps_links)
            if #sel > 0 then
                CFG.client_ps_map[pkg] = sel
                p(cc(C.green,"    ✓").." Diset: "..table.concat(sel,","))
            else p(cc(C.dim,"    Tidak valid, skip")) end
        else
            CFG.client_ps_map[pkg] = {}
            p(cc(C.dim,"    → Semua PS"))
        end
        print("")
    end
    save_config()
    p("  "..cc(C.green,"[+]").." PS map disimpan"); sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: DELAY
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_delay()
    draw_header("stopped")
    p(cc(C.bold,"  SET DELAY")); print("")
    p("  Hop delay   : "..cc(C.cyan, CFG.delay_min.."-"..CFG.delay_max.." menit (random)"))
    p("  Launch delay: "..cc(C.cyan, CFG.launch_delay.." detik antar client"))
    print("")
    local mn = ask("Hop min menit (Enter=batal)")
    if not mn or mn == "" then return end
    local mx = ask("Hop max menit")
    local ld = ask("Launch delay detik (Enter=pakai saat ini)")
    mn = tonumber(mn); mx = tonumber(mx)
    if mn and mx and mn >= 1 and mx >= mn then
        CFG.delay_min = mn; CFG.delay_max = mx
        if ld and ld ~= "" and tonumber(ld) then CFG.launch_delay = tonumber(ld) end
        save_config()
        p("\n  "..cc(C.green,"[+]").." Delay diset")
    else p("\n  "..cc(C.red,"[!]").." Tidak valid") end
    sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: ACCOUNTS / COOKIE (per-package)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_accounts()
    local pkgs = detect_packages()
    while true do
        draw_header("stopped", pkgs)
        p(cc(C.bold,"  KELOLA AKUN / COOKIE")); print("")
        p(cc(C.dim,"  Set .ROBLOSECURITY cookie per-package"))
        print("")

        if #pkgs == 0 then
            p(cc(C.red,"  ⚠  Tidak ada package!")); sleep(2); return
        end

        for i, pkg in ipairs(pkgs) do
            local acc = CFG.accounts[pkg] or {}
            local has = acc.cookie and acc.cookie ~= ""
            p(string.format("  %s[%d]%s %-20s %s",
                C.cyan, i, C.reset,
                pkg_short(pkg),
                has and (cc(C.green,"✓ ")..cc(C.bold,(acc.name or "?"))) or cc(C.red,"✗ belum diset")))
        end
        print("")
        sep()
        p("  "..cc(C.bold,"1-"..#pkgs).." Set cookie  "
            ..cc(C.bold,"r").." Refresh semua  "
            ..cc(C.bold,"c").." Clear semua  "
            ..cc(C.bold,"0").." Kembali")
        sep(); print("")
        local opt = ask("")

        if opt == "0" then break
        elseif opt == "r" then
            -- Refresh semua akun
            print("")
            for _, pkg in ipairs(pkgs) do
                local acc = CFG.accounts[pkg] or {}
                if acc.cookie and acc.cookie ~= "" then
                    p(cc(C.dim,"  Fetching: "..pkg_short(pkg).."..."))
                    local name, id = fetch_account(acc.cookie)
                    if name then
                        acc.name = name; acc.id = id
                        CFG.accounts[pkg] = acc
                        p("  "..cc(C.green,"✓").." "..name.." (ID: "..id..")")
                    else
                        p("  "..cc(C.red,"✗").." Gagal — cookie mungkin expired")
                    end
                end
            end
            save_config(); sleep(2)

        elseif opt == "c" then
            local conf = ask("Ketik 'hapus' untuk clear semua cookie")
            if conf == "hapus" then
                CFG.accounts = {}; save_config()
                p("  "..cc(C.green,"[+]").." Semua cookie dihapus"); sleep(1)
            end

        else
            local idx = tonumber(opt)
            if idx and idx >= 1 and idx <= #pkgs then
                local pkg = pkgs[idx]
                local acc = CFG.accounts[pkg] or {}
                clear_screen()
                hr()
                p(cc(C.bold, center("SET COOKIE")))
                hr()
                print("")
                p("  Package: "..cc(C.cyan, pkg))
                if acc.name then
                    p("  Akun   : "..cc(C.bold, acc.name).." (ID: "..(acc.id or "?")..")")
                end
                print("")
                p("  Paste "..cc(C.bold,".ROBLOSECURITY")..":"); print("")
                local cookie = ask("")
                if not cookie or cookie == "" then
                    p(cc(C.dim,"  Dibatalkan")); sleep(1)
                else
                    if not cookie:match("_|WARNING") then
                        p(cc(C.yellow,"  [!] Tidak diawali '_|WARNING'"))
                        local f = ask("Tetap simpan? (y/n)")
                        if f ~= "y" then goto continue_acc end
                    end
                    acc.cookie = cookie
                    p(cc(C.dim,"  Fetching akun info..."))
                    local name, id = fetch_account(cookie)
                    if name then
                        acc.name = name; acc.id = id
                        p("  "..cc(C.green,"✓").." "..cc(C.bold,name).." (ID: "..id..")")
                    else
                        acc.name = nil; acc.id = nil
                        p("  "..cc(C.yellow,"[!]").." Gagal fetch — disimpan tanpa info akun")
                    end
                    CFG.accounts[pkg] = acc
                    save_config()
                    sleep(2)
                end
                ::continue_acc::
            end
        end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: AUTOEXEC
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_autoexec()
    draw_header("stopped")
    p(cc(C.bold,"  SET AUTOEXEC")); print("")
    p(cc(C.dim,"  Diinjek sebelum setiap Roblox launch"))
    p(cc(C.dim,"  Backup ke /sdcard/.auto_1.lua.bak"))
    print("")
    p("  Path   : "..cc(C.cyan, CFG.autoexec_path))
    p("  Script : "..(CFG.autoexec_script ~= "" and cc(C.green,"✓ Set") or cc(C.red,"✗ Kosong")))
    p("  Restore: "..(CFG.autoexec_restore ~= "" and cc(C.green,"✓ Set") or cc(C.dim,"– Kosong")))
    print("")
    p("  "..cc(C.bold,"1.")..cc(C.bold," Path  ")
        ..cc(C.bold,"2.")..cc(C.bold," Script  ")
        ..cc(C.bold,"3.")..cc(C.bold," Restore  ")
        ..cc(C.bold,"4.")..cc(C.bold," Test inject  ")
        ..cc(C.bold,"0.")..cc(C.bold," Kembali"))
    print("")
    local opt = ask("")
    if opt == "1" then
        local np = ask("Path baru (Enter=batal)")
        if np and np ~= "" then CFG.autoexec_path = np; save_config()
            p("  "..cc(C.green,"[+]").." Path diupdate"); sleep(1) end
    elseif opt == "2" then
        p(cc(C.dim,"  Paste script (1 baris):"))
        local s = ask("")
        if s and s ~= "" then CFG.autoexec_script = s; save_config()
            p("  "..cc(C.green,"[+]").." Script disimpan"); sleep(1) end
    elseif opt == "3" then
        p(cc(C.dim,"  Paste restore script (1 baris):"))
        local s = ask("")
        if s and s ~= "" then CFG.autoexec_restore = s; save_config()
            p("  "..cc(C.green,"[+]").." Restore script disimpan"); sleep(1) end
    elseif opt == "4" then
        if CFG.autoexec_script == "" then
            p(cc(C.red,"  [!] Script belum diset!"))
        else
            local dir = CFG.autoexec_path:match("^(.+)/[^/]+$")
            if dir then su_exec("mkdir -p '"..dir.."'") end
            su_exec("cp '"..CFG.autoexec_path.."' '"..AE_BAK_FILE.."' 2>/dev/null")
            local ok = write_file(CFG.autoexec_path, CFG.autoexec_script)
            if ok then su_exec("chmod 644 '"..CFG.autoexec_path.."'") end
            p(ok and "  "..cc(C.green,"[+] Berhasil inject!")
                  or "  "..cc(C.red, "[!] Gagal inject"))
        end
        sleep(2)
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: HEARTBEAT
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_heartbeat()
    draw_header("stopped")
    p(cc(C.bold,"  HEARTBEAT / WATCHDOG")); print("")
    p(cc(C.dim,"  Cek pidof setiap 10 detik"))
    p(cc(C.dim,"  Crash → relaunch ke PS yang sama"))
    print("")
    p("  Max fail: "..cc(C.cyan, CFG.hb_max_fail.."x")); print("")
    local f = ask("Max fail baru (Enter=batal)")
    if not f or f == "" then return end
    f = tonumber(f)
    if f and f >= 1 then
        CFG.hb_max_fail = f; save_config()
        p("\n  "..cc(C.green,"[+]").." Max fail: "..f.."x")
    else p("\n  "..cc(C.red,"[!]").." Tidak valid") end
    sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: VIEW CONFIG
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_config()
    draw_header("stopped")
    p(cc(C.bold,"  CONFIG LENGKAP")); print("")

    local function row(lbl, val)
        p(string.format("  %s%-16s%s %s", C.dim, lbl, C.reset, tostring(val or "-")))
    end
    row("Prefix",       CFG.pkg_prefix)
    row("Delay",        CFG.delay_min.."-"..CFG.delay_max.."m | launch "..CFG.launch_delay.."s")
    row("HB fail",      CFG.hb_max_fail.."x")
    row("Autoexec",     CFG.autoexec_script ~= "" and "✓ Set" or "– Kosong")
    row("AE Restore",   CFG.autoexec_restore ~= "" and "✓ Set" or "– Kosong")
    row("AE Path",      trunc(CFG.autoexec_path, W-20))
    row("PS Links",     #CFG.ps_links.." link")
    print("")

    for i, link in ipairs(CFG.ps_links) do
        p(string.format("  %s[%2d]%s %s", C.cyan, i, C.reset, trunc(link, W-9)))
    end

    print("")
    p(cc(C.bold,"  Akun per-package:"))
    local pkgs = detect_packages()
    for _, pkg in ipairs(pkgs) do
        local acc = CFG.accounts[pkg] or {}
        local has = acc.cookie and acc.cookie ~= ""
        p(string.format("  %s%-20s%s %s",
            C.cyan, pkg_short(pkg), C.reset,
            has and (cc(C.green,"✓ ")..(acc.name or "?").." (ID: "..(acc.id or "?")..")")
                 or cc(C.red,"✗ no cookie")))
    end

    if next(CFG.client_ps_map) then
        print("")
        p(cc(C.bold,"  Per-client PS map:"))
        for pkg, plist in pairs(CFG.client_ps_map) do
            if #plist > 0 then
                p(string.format("  %s%-20s%s → {%s}",
                    C.cyan, pkg_short(pkg), C.reset, table.concat(plist,",")))
            end
        end
    end
    print("")
    ask("Enter untuk kembali")
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LIVE MONITOR
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function time_str_to_sec(ts)
    local h, m, s = ts:match("(%d+):(%d+):(%d+)")
    if not h then return 0 end
    return tonumber(h)*3600 + tonumber(m)*60 + tonumber(s)
end

local function format_elapsed(sec)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec/3600)
    local m = math.floor((sec%3600)/60)
    local s = sec % 60
    if h > 0 then return string.format("%dh%dm", h, m)
    elseif m > 0 then return string.format("%dm%ds", m, s)
    else return string.format("%ds", s) end
end

local function parse_log()
    local visits, crashes = {}, {}
    local f = io.open(LOG_FILE,"r")
    if not f then return visits, crashes end
    for line in f:lines() do
        local ts, cn, ps = line:match("^(%d+:%d+:%d+) Client (%d+) %-> PS (%d+)")
        if ts and cn and ps then
            local c = tonumber(cn)
            if not visits[c] then visits[c] = {} end
            table.insert(visits[c], {
                ps=tonumber(ps), time_sec=time_str_to_sec(ts), time_str=ts
            })
        end
        local cts, ccn = line:match("^(%d+:%d+:%d+) Crash client (%d+)")
        if cts and ccn then crashes[tonumber(ccn)] = cts end
    end
    f:close()
    return visits, crashes
end

local function build_ps_summary(client_visits, now_sec)
    local ps_data = {}
    if not client_visits or #client_visits == 0 then return ps_data end
    local n = #client_visits
    for i, v in ipairs(client_visits) do
        local dur
        if i < n then
            dur = client_visits[i+1].time_sec - v.time_sec
            if dur < 0 then dur = dur + 86400 end
        else
            dur = now_sec - v.time_sec
            if dur < 0 then dur = dur + 86400 end
        end
        local is_cur = (i == n)
        if not ps_data[v.ps] then
            ps_data[v.ps] = {joined=v.time_str, elapsed_sec=dur, hops=1, is_current=is_cur}
        else
            local d = ps_data[v.ps]
            d.joined = v.time_str; d.elapsed_sec = d.elapsed_sec + dur
            d.hops = d.hops + 1
            if is_cur then d.is_current = true end
        end
    end
    return ps_data
end

local function monitor_live(clients_data, hopper_pid)
    while true do
        clear_screen()
        hr()
        p(cc(C.bold, center("HOPPER MONITOR")))
        hr()
        print("")

        local visits, crashes = parse_log()
        local now_str = os.date("%H:%M:%S")
        local now_sec = time_str_to_sec(now_str)

        -- Package status table (dari dashboard) di atas
        p(cc(C.dim, " "
            ..pad("Package", COL_PKG).." "
            ..pad("Username", COL_NAME+2).." "
            ..pad("PS", 4).." "
            ..pad("Elapsed", 9).." "
            .."Hops"))
        p(cc(C.dim, string.rep("-", W)))

        for i, c in ipairs(clients_data) do
            local ps_data    = build_ps_summary(visits[i], now_sec)
            local crash_mark = crashes[i] and cc(C.red," !") or ""
            local acc        = CFG.accounts[c.pkg] or {}

            -- Tampilkan hanya PS aktif per client di baris pertama
            local cur_ps, cur_d
            for _, ps_idx in ipairs(c.ps_idx_list) do
                local d = ps_data[ps_idx]
                if d and d.is_current then cur_ps = ps_idx; cur_d = d; break end
            end

            local ps_str  = cur_ps and tostring(cur_ps) or "-"
            local el_str  = cur_d and format_elapsed(cur_d.elapsed_sec) or "-"
            local hop_str = cur_d and tostring(cur_d.hops) or "0"
            local name    = acc.name or pkg_short(c.pkg)

            p((cur_d and C.green or C.dim)
                .." "..pad(pkg_short(c.pkg), COL_PKG).." "
                ..pad(trunc(name, COL_NAME+2), COL_NAME+2).." "
                ..pad(ps_str, 4).." "
                ..pad(el_str, 9).." "
                ..hop_str..crash_mark
                ..C.reset)
        end

        p(cc(C.dim, string.rep("-", W)))
        print("")

        -- Detail hop history semua PS
        p(cc(C.dim, " "
            ..pad("C", 3)..pad("PS", 4)
            ..pad("Joined", 9)..pad("Elapsed", 9).."Hops"))
        p(cc(C.dim, string.rep("·", W)))
        for i, c in ipairs(clients_data) do
            local ps_data    = build_ps_summary(visits[i], now_sec)
            local crash_mark = crashes[i] and cc(C.red," !") or ""
            for _, ps_idx in ipairs(c.ps_idx_list) do
                local d = ps_data[ps_idx]
                if d then
                    local col = d.is_current and C.green or C.cyan
                    p(col..string.format(" %-3d %-4d %-9s %-9s %d%s",
                        i, ps_idx, d.joined,
                        format_elapsed(d.elapsed_sec), d.hops, crash_mark)..C.reset)
                    crash_mark = ""
                else
                    p(C.gray..string.format(" %-3d %-4d %-9s %-9s %d",
                        i, ps_idx, "-", "-", 0)..C.reset)
                end
            end
            if i < #clients_data then p(cc(C.gray, string.rep("·", W))) end
        end

        print("")
        sep()
        p(string.format("  %sWaktu%s %s   %sPID%s %s",
            C.dim, C.reset, now_str,
            C.dim, C.reset, hopper_pid or "-"))
        sep()
        p(cc(C.yellow,"  [q] Stop & Keluar"))
        print("")

        local key = read_key(1)
        if key and key:lower() == "q" then return end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- GENERATE LOOP SCRIPT
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function generate_loop(pkgs)
    local out = {}

    table.insert(out, "-- AUTO-GENERATED by hopper.lua v6\n")
    table.insert(out, "local STATE_FILE      = "..string.format("%q", STATE_FILE).."\n")
    table.insert(out, "local STOP_FILE       = "..string.format("%q", STOP_FILE).."\n")
    table.insert(out, "local LOG_FILE        = "..string.format("%q", LOG_FILE).."\n")
    table.insert(out, "local AE_BAK_FILE     = "..string.format("%q", AE_BAK_FILE).."\n")
    table.insert(out, "local AUTOEXEC_SCRIPT = "..string.format("%q", CFG.autoexec_script).."\n")
    table.insert(out, "local AUTOEXEC_PATH   = "..string.format("%q", CFG.autoexec_path).."\n")
    table.insert(out, "local AUTOEXEC_RESTORE= "..string.format("%q", CFG.autoexec_restore).."\n")
    table.insert(out, "local HB_MAX_FAIL     = "..CFG.hb_max_fail.."\n")
    table.insert(out, "local DELAY_MIN       = "..CFG.delay_min.."\n")
    table.insert(out, "local DELAY_MAX       = "..CFG.delay_max.."\n")
    table.insert(out, "local LAUNCH_DELAY    = "..CFG.launch_delay.."\n\n")

    -- PS links
    table.insert(out, "local ps_links = {\n")
    for _, link in ipairs(CFG.ps_links) do
        table.insert(out, '  "'..escape_lua_str(link)..'",\n')
    end
    table.insert(out, "}\n\n")

    -- Clients (cookie per-client, tanpa L/T/R/B)
    table.insert(out, "local clients = {\n")
    for i, pkg in ipairs(pkgs) do
        local acc     = CFG.accounts[pkg] or {}
        local cookie  = acc.cookie or ""
        local ps_map  = CFG.client_ps_map[pkg] or {}
        local indices = {}
        if #ps_map == 0 then
            for j = 1, #CFG.ps_links do table.insert(indices, j) end
        else indices = ps_map end
        table.insert(out, "  { -- client "..i.."\n")
        table.insert(out, "    pkg    = "..string.format("%q",pkg)..",\n")
        table.insert(out, "    cookie = "..string.format("%q",cookie)..",\n")
        table.insert(out, "    ps_idx_list = {"..table.concat(indices,",").."},\n")
        table.insert(out, "    curr_ptr = 1,\n  },\n")
    end
    table.insert(out, "}\n\n")
    table.insert(out, LOOP_CODE)

    return table.concat(out)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- HELPERS: find lua, kill hopper
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function find_lua_bin()
    local h = io.popen("command -v lua54 2>/dev/null || command -v lua5.4 2>/dev/null || command -v lua 2>/dev/null")
    local bin
    if h then bin = clean(h:read("*a")); h:close() end
    if not bin or bin == "" then bin = "/data/data/com.termux/files/usr/bin/lua" end
    return bin
end

local function kill_hopper(pid)
    if pid and pid ~= "" then os.execute("kill -9 "..pid.." 2>/dev/null") end
    local old = read_file(PID_FILE)
    if old then os.execute("kill -9 "..clean(old).." 2>/dev/null") end
    os.remove(PID_FILE)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- RESET ALL
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function reset_all(pkgs)
    print("")
    p(cc(C.yellow,"  Resetting..."))

    if CFG.autoexec_restore ~= "" then
        local dir = CFG.autoexec_path:match("^(.+)/[^/]+$")
        if dir then su_exec("mkdir -p '"..dir.."'") end
        local ok = write_file(CFG.autoexec_path, CFG.autoexec_restore)
        if not ok then
            su_exec("echo '"..CFG.autoexec_restore:gsub("'","'\\''")
                .."' > '"..CFG.autoexec_path.."'")
        end
        su_exec("chmod 644 '"..CFG.autoexec_path.."'")
        su_exec("rm -f '"..AE_BAK_FILE.."' 2>/dev/null")
        p("  "..cc(C.green,"[+]").." Autoexec restored")
    end

    if pkgs and #pkgs > 0 then
        for _, pkg in ipairs(pkgs) do
            su_exec("am force-stop "..pkg)
            p("  "..cc(C.green,"[+]").." Closed: "..pkg_short(pkg))
        end
    end

    os.remove(STATE_FILE); os.remove(STOP_FILE)
    os.remove(LOOP_FILE);  os.remove(PID_FILE)
    p("\n  "..cc(C.green,"Reset selesai!")); sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- START HOPPER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function start_hopper()
    if not su_cmd("id"):match("uid=0") then
        draw_header("stopped")
        p(cc(C.red,"  [!] Root tidak terdeteksi!")); sleep(2); return
    end

    local pkgs = detect_packages()
    if #pkgs == 0 then
        draw_header("stopped")
        p(cc(C.red,"  [!] Tidak ada package dengan prefix: "..CFG.pkg_prefix))
        sleep(2); return
    end

    os.remove(STOP_FILE); os.remove(STATE_FILE); os.remove(LOG_FILE)

    local script = generate_loop(pkgs)
    if not write_file(LOOP_FILE, script) then
        p(cc(C.red,"  [!] Gagal tulis loop script!")); sleep(2); return
    end
    os.execute("chmod 755 '"..LOOP_FILE.."'")

    kill_hopper(nil)

    local lua_bin = find_lua_bin()
    local ph = io.popen("nohup "..lua_bin.." '"..LOOP_FILE.."'"
        .." >> '"..LOG_FILE.."' 2>&1 & echo $!")
    if not ph then p(cc(C.red,"  [!] Gagal launch!")); sleep(2); return end
    local pid = clean(ph:read("*a")); ph:close()
    write_file(PID_FILE, pid)
    log_main("Hopper started PID="..pid)

    -- Tunggu state tersedia
    local waited = 0
    while not file_exists(STATE_FILE) and waited < 20 do
        draw_header("starting", pkgs)
        p(cc(C.dim,"  Memulai ("..waited.."s)..."))
        sleep(1); waited = waited + 1
    end

    -- Siapkan clients_data untuk monitor
    local clients_data = {}
    for i, pkg in ipairs(pkgs) do
        local ps_map = CFG.client_ps_map[pkg] or {}
        local indices = {}
        if #ps_map == 0 then
            for j = 1, #CFG.ps_links do table.insert(indices, j) end
        else indices = ps_map end
        table.insert(clients_data, {pkg=pkg, ps_idx_list=indices})
    end

    p(cc(C.dim,"  Masuk monitor...")); sleep(2)
    monitor_live(clients_data, pid)

    -- Setelah q
    draw_header("stopping", pkgs)
    p(cc(C.yellow,"  Menghentikan hopper..."))
    write_file(STOP_FILE, "stop")
    for _ = 1, 12 do
        local ch = io.popen("kill -0 "..pid.." 2>/dev/null; echo $?")
        if ch then
            local e = clean(ch:read("*a")); ch:close()
            if e ~= "0" then break end
        end
        sleep(1)
    end
    kill_hopper(pid)

    print(""); sep()
    local rst = ask("Reset semua (restore autoexec + close Roblox)? (y/n)")
    if rst == "y" then reset_all(pkgs) end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ROUTER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
math.randomseed(os.time())
os.remove(STOP_FILE); os.remove(STATE_FILE)
load_config()
log_main("=== SESSION: "..os.date().." ===")

local routes = {
    main           = main_menu,
    menu_prefix    = function() menu_prefix();    return "main" end,
    menu_ps        = function() menu_ps();        return "main" end,
    menu_ps_map    = function() menu_ps_map();    return "main" end,
    menu_delay     = function() menu_delay();     return "main" end,
    menu_accounts  = function() menu_accounts();  return "main" end,
    menu_autoexec  = function() menu_autoexec();  return "main" end,
    menu_heartbeat = function() menu_heartbeat(); return "main" end,
    menu_config    = function() menu_config();    return "main" end,
    start          = function() start_hopper();   return "main" end,
}

local state = "main"
while state ~= "exit" do
    local fn = routes[state]
    state = fn and (fn() or "main") or "main"
end

clear_screen()
log_main("=== SESSION END ===")
