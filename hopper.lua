#!/data/data/com.termux/files/usr/bin/lua
-- ============================================================
--  ROBLOX SERVER HOPPER v5
--  Standalone | lua hopper.lua
-- ============================================================

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CONSTANTS & PATHS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local HOME         = os.getenv("HOME") or "/data/data/com.termux/files/home"
local CONFIG_FILE  = HOME .. "/.hopper_config.lua"
local LOG_FILE     = "/sdcard/hopper_log.txt"
local STATE_FILE   = "/sdcard/.hopper_state"
local STOP_FILE    = "/sdcard/.hopper_stop"
local LOOP_FILE    = "/sdcard/.hopper_loop.lua"
local PID_FILE     = "/sdcard/.hopper_pid"
local AE_BAK_FILE  = "/sdcard/.auto_1.lua.bak"

local ACTIVITY     = "com.roblox.client.startup.ActivitySplash"
local W            = 48

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LOOP CODE (injected raw ke generated script)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local LOOP_CODE = [=[
-- ─── HELPERS ─────────────────────────────────────────────────
local function sleep(sec)
    if sec and sec > 0 then
        os.execute("sleep " .. math.floor(sec))
    end
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
    if f then
        f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
end
local function is_running(pkg)
    local h = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- ─── COOKIE INJECT ────────────────────────────────────────────
local function inject_cookie(pkg)
    if not COOKIE or COOKIE == "" then return end
    local dir  = "/data/data/" .. pkg .. "/shared_prefs"
    local file = dir .. "/RobloxSharedPreferences.xml"
    local src  = "/tmp/hcookie.xml"
    local f = io.open(src, "w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">' .. COOKIE .. "</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. src .. "' '" .. file .. "'")
    su_exec("chmod 660 '" .. file .. "'")
    os.remove(src)
    log("Cookie injected: " .. pkg)
end

-- ─── AUTOEXEC INJECT ─────────────────────────────────────────
local function inject_autoexec()
    if not AUTOEXEC_SCRIPT or AUTOEXEC_SCRIPT == "" then return end
    local dir = AUTOEXEC_PATH:match("^(.+)/[^/]+$")
    if dir then su_exec("mkdir -p '" .. dir .. "'") end
    -- Backup dulu ke /sdcard/ (bukan di folder autoexec agar tidak ikut run)
    su_exec("cp '" .. AUTOEXEC_PATH .. "' '" .. AE_BAK_FILE .. "' 2>/dev/null")
    su_exec("rm -f '" .. AUTOEXEC_PATH .. ".bak' 2>/dev/null")
    local f = io.open(AUTOEXEC_PATH, "w")
    if f then f:write(AUTOEXEC_SCRIPT); f:close()
    else
        local esc = AUTOEXEC_SCRIPT:gsub("'", "'\\''")
        su_exec("echo '" .. esc .. "' > '" .. AUTOEXEC_PATH .. "'")
    end
    su_exec("chmod 644 '" .. AUTOEXEC_PATH .. "'")
    log("Autoexec injected")
end

local function restore_autoexec()
    if not AUTOEXEC_RESTORE or AUTOEXEC_RESTORE == "" then return end
    local f = io.open(AUTOEXEC_PATH, "w")
    if f then f:write(AUTOEXEC_RESTORE); f:close()
    else
        local esc = AUTOEXEC_RESTORE:gsub("'", "'\\''")
        su_exec("echo '" .. esc .. "' > '" .. AUTOEXEC_PATH .. "'")
    end
    su_exec("chmod 644 '" .. AUTOEXEC_PATH .. "'")
    su_exec("rm -f '" .. AE_BAK_FILE .. "' 2>/dev/null")
    log("Autoexec restored")
end

-- ─── LAYOUT APPLY ─────────────────────────────────────────────
local function apply_layout(pkg, L, T, R, B)
    local pref = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
    su_exec("chmod 666 '" .. pref .. "' 2>/dev/null")
    -- Combined sed: satu call untuk 4 fields (lebih efisien)
    su_exec("sed -i"
        .. " -e 's/name=\\\"app_cloner_current_window_left\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_left\\\" value=\\\"" .. L .. "\\\"/g'"
        .. " -e 's/name=\\\"app_cloner_current_window_top\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_top\\\" value=\\\"" .. T .. "\\\"/g'"
        .. " -e 's/name=\\\"app_cloner_current_window_right\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_right\\\" value=\\\"" .. R .. "\\\"/g'"
        .. " -e 's/name=\\\"app_cloner_current_window_bottom\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_bottom\\\" value=\\\"" .. B .. "\\\"/g'"
        .. " '" .. pref .. "'")
    su_exec("chmod 444 '" .. pref .. "' 2>/dev/null")
end

-- ─── LAUNCH ──────────────────────────────────────────────────
local function launch_client(c, ps_index, cnum)
    if not ps_links[ps_index] then
        log("ERROR: PS index " .. tostring(ps_index) .. " out of range")
        return
    end
    su_exec("am force-stop " .. c.pkg)
    os.execute("sleep 1")
    inject_cookie(c.pkg)
    local raw = ps_links[ps_index]
    local dp  = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://", "")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. c.pkg
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    -- Log format yang bisa di-parse oleh monitor: "HH:MM:SS Client N -> PS N"
    log("Client " .. cnum .. " -> PS " .. ps_index)
end

-- ─── MAIN LOOP ───────────────────────────────────────────────
math.randomseed(os.time())
log("--- Hopper Started ---")

-- Initial: apply layout + kill semua client
for _, c in ipairs(clients) do
    su_exec("am force-stop " .. c.pkg)
    apply_layout(c.pkg, c.L, c.T, c.R, c.B)
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

    -- Watchdog: nested local function (sesuai v2.1)
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
            write_state("hop|0|" .. #clients
                .. "|0|" .. os.time() .. "|watchdog")
        end
    end

    if DELAY_MIN == 0 then
        watchdog(0)
        break
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
    if sec and sec > 0 then
        os.execute("sleep " .. math.floor(sec))
    end
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

local function sanitize_pkg(pkg)
    if not pkg then return nil end
    local s = pkg:gsub("[^%w%._]", "")
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
    if f then
        f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CONFIG
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local CFG = {}

local function config_defaults()
    return {
        delay_min        = 3,
        delay_max        = 7,
        launch_delay     = 20,
        cookie           = "",
        account_name     = "",
        account_id       = "",
        hb_max_fail      = 3,
        autoexec_path    = "/storage/emulated/0/RonixExploit/autoexec/auto_1.lua",
        autoexec_script  = "",
        autoexec_restore = "",
        ps_links         = {},
        client_ps_map    = {},
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

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TERMINAL / UI
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local C = {
    reset="\27[0m", bold="\27[1m", dim="\27[2m",
    red="\27[31m", green="\27[32m", yellow="\27[33m",
    cyan="\27[36m", gray="\27[90m",
}
local function cc(code, text) return code..text..C.reset end
local function p(text) io.write(text.."\n"); io.flush() end
local function hr()  p(cc(C.yellow, string.rep("━", W))) end
local function sep() p(cc(C.dim,    string.rep("─", W))) end
local function clear_screen() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end
local function center(text)
    local pad = math.max(0, math.floor((W - #text) / 2))
    return string.rep(" ", pad) .. text
end
local function row(lbl, val)
    p(string.format("%s  %-13s%s %s", C.dim, lbl, C.reset, tostring(val or "-")))
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

-- Single keypress (non-blocking, timeout detik)
local function read_key(timeout)
    local h = io.popen("bash -c 'read -t "..(timeout or 1)
        .." -n 1 key < /dev/tty 2>/dev/null && echo $key' 2>/dev/null")
    if not h then sleep(timeout or 1); return nil end
    local key = h:read("*l"); h:close()
    return (key and key ~= "") and key or nil
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DETECTION HELPERS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function detect_offset()
    local stable = su_cmd("dumpsys window | grep mStable | head -1")
    local st = stable:match("mStable=%[%d+,(%d+)%]")
    if st then return tonumber(st) or 0 end
    local dpi = su_cmd("wm density"):match("(%d+)")
    return dpi and math.ceil(24 * tonumber(dpi) / 160) or 48
end

local function detect_screen()
    local offset = detect_offset()
    local res = su_cmd("wm size")
    local sw, sh = res:match("(%d+)x(%d+)")
    if not sw then return nil, nil, offset end
    sw, sh = tonumber(sw), tonumber(sh)
    return math.min(sw,sh), math.max(sw,sh), offset
end

local function detect_packages()
    local h = io.popen("pm list packages | grep com.roblox.")
    if not h then return {} end
    local out = h:read("*a") or ""; h:close()
    local pkgs = {}
    for line in out:gmatch("[^\r\n]+") do
        local pkg = sanitize_pkg(clean(line:match("package:(.+)")))
        if pkg then table.insert(pkgs, pkg) end
    end
    return pkgs
end

local function fetch_account(cookie)
    if not cookie or cookie == "" then return false end
    local h = io.popen('curl -s --max-time 10 '
        ..'-H "Cookie: .ROBLOSECURITY='..cookie..'" '
        ..'"https://users.roblox.com/v1/users/authenticated"')
    if not h then return false end
    local res = h:read("*a"); h:close()
    local name = res:match('"name":"([^"]+)"')
    local id   = res:match('"id":(%d+)')
    if name and id then
        CFG.account_name = name; CFG.account_id = id; return true
    end
    return false
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LAYOUT HELPERS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function calc_grid_height(n, SCR_H, offset)
    return math.floor((SCR_H - offset) / n)
end

local function grid_bounds(index, n, SCR_W, SCR_H, offset)
    if n == 1 then return 0, 0, SCR_W, SCR_H end
    local gh  = calc_grid_height(n, SCR_H, offset)
    local row = index - 1
    return 0, (row*gh)+offset, SCR_W, ((row+1)*gh)+offset
end

local function apply_layout_host(pkg, L, T, R, B)
    local pref = "/data/data/"..pkg.."/shared_prefs/"..pkg.."_preferences.xml"
    su_exec("chmod 666 '"..pref.."' 2>/dev/null")
    su_exec("sed -i"
        .." -e 's/name=\\\"app_cloner_current_window_left\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_left\\\" value=\\\""..L.."\\\"/g'"
        .." -e 's/name=\\\"app_cloner_current_window_top\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_top\\\" value=\\\""..T.."\\\"/g'"
        .." -e 's/name=\\\"app_cloner_current_window_right\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_right\\\" value=\\\""..R.."\\\"/g'"
        .." -e 's/name=\\\"app_cloner_current_window_bottom\\\" value=\\\"[^\\\"]*\\\"/name=\\\"app_cloner_current_window_bottom\\\" value=\\\""..B.."\\\"/g'"
        .." '"..pref.."'")
    su_exec("chmod 444 '"..pref.."' 2>/dev/null")
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- PARSE SELECTION
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
    if h > 0 then return string.format("%dh%dm%ds", h, m, s)
    elseif m > 0 then return string.format("%dm%ds", m, s)
    else return string.format("%ds", s) end
end

-- Parse log → visits[client] = array of {ps, time_sec, time_str}
local function parse_log()
    local visits, crashes = {}, {}
    local f = io.open(LOG_FILE, "r")
    if not f then return visits, crashes end
    for line in f:lines() do
        -- Format: "HH:MM:SS Client N -> PS N"
        local ts, cn, ps = line:match("^(%d+:%d+:%d+) Client (%d+) %-> PS (%d+)")
        if ts and cn and ps then
            local c = tonumber(cn)
            if not visits[c] then visits[c] = {} end
            table.insert(visits[c], {
                ps       = tonumber(ps),
                time_sec = time_str_to_sec(ts),
                time_str = ts,
            })
        end
        -- Format: "HH:MM:SS Crash client N"
        local cts, ccn = line:match("^(%d+:%d+:%d+) Crash client (%d+)")
        if cts and ccn then crashes[tonumber(ccn)] = cts end
    end
    f:close()
    return visits, crashes
end

-- Build per-PS summary dari visits satu client
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
            ps_data[v.ps] = {
                joined = v.time_str, elapsed_sec = dur,
                hops = 1, is_current = is_cur,
            }
        else
            local d = ps_data[v.ps]
            d.joined = v.time_str
            d.elapsed_sec = d.elapsed_sec + dur
            d.hops = d.hops + 1
            if is_cur then d.is_current = true end
        end
    end
    return ps_data
end

local function monitor_live(clients_data, hop_interval, hopper_pid)
    while true do
        clear_screen()
        hr()
        p(cc(C.bold, center("HOPPER MONITOR")))
        hr()
        print("")

        local visits, crashes = parse_log()
        local now_str = os.date("%H:%M:%S")
        local now_sec = time_str_to_sec(now_str)

        -- Tabel header
        p(cc(C.cyan, string.format(" %-3s  %-3s  %-8s  %-9s  %s",
            "C", "PS", "Joined", "Elapsed", "Hops")))
        p(cc(C.dim, string.rep("-", W)))

        for i, c in ipairs(clients_data) do
            local ps_data    = build_ps_summary(visits[i], now_sec)
            local crash_mark = crashes[i] and " !" or ""

            for _, ps_idx in ipairs(c.ps_idx_list) do
                local d = ps_data[ps_idx]
                if d then
                    local color_code = d.is_current and C.green or C.cyan
                    p(color_code .. string.format(" %-3d  %-3d  %-8s  %-9s  %d%s",
                        i, ps_idx, d.joined,
                        format_elapsed(d.elapsed_sec), d.hops, crash_mark)
                        .. C.reset)
                    crash_mark = ""
                else
                    p(C.gray .. string.format(" %-3d  %-3d  %-8s  %-9s  %d",
                        i, ps_idx, "-", "-", 0) .. C.reset)
                end
            end

            -- Separator antar client
            if i < #clients_data then
                p(cc(C.gray, string.rep("·", W)))
            end
        end

        print("")
        sep()
        local mode_str = hop_interval > 0
            and (hop_interval.."m per hop")
            or  "Sekali join + Watchdog"
        p(string.format("  %sMode%s  %s   %sWaktu%s %s   %sPID%s %s",
            C.dim, C.reset, mode_str,
            C.dim, C.reset, now_str,
            C.dim, C.reset, hopper_pid or "-"))
        sep()
        print("")

        p(cc(C.dim, "  Packages:"))
        for i, c in ipairs(clients_data) do
            p(string.format("  %s[%d]%s %s", C.cyan, i, C.reset, trunc(c.pkg, W-6)))
        end
        print("")
        p(cc(C.yellow, "  [q] Reset & Keluar"))
        print("")

        local key = read_key(1)
        if key and key:lower() == "q" then return end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD HEADER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function status_badge(s)
    if s == "running"  then return cc(C.green,  cc(C.bold,"● RUNNING"))
    elseif s == "stopped"  then return cc(C.red,    "● STOPPED")
    elseif s == "starting" then return cc(C.yellow, "● STARTING...")
    elseif s == "stopping" then return cc(C.yellow, "● STOPPING...")
    elseif s == "crashed"  then return cc(C.red,    cc(C.bold,"● CRASHED"))
    end
    return s
end

local function draw_header(status, extra1, extra2)
    local pkgs = detect_packages()
    clear_screen()
    hr()
    p(cc(C.bold, center("🎮 ROBLOX SERVER HOPPER v5")))
    hr()
    print("")

    row("Akun", CFG.account_name ~= ""
        and (cc(C.bold, CFG.account_name)..cc(C.dim," (ID: "..(CFG.account_id or "?")..")"))
        or  cc(C.red, "✗ Belum diset"))
    row("Packages", #pkgs > 0
        and cc(C.cyan, #pkgs.." terdeteksi")
        or  cc(C.red, "✗ Tidak ada"))
    row("Cookie", CFG.cookie ~= ""
        and (cc(C.green,"✓ Set")..cc(C.dim," ("..CFG.cookie:sub(1,14).."...)"))
        or  cc(C.red,"✗ Belum diset"))
    row("PS Links", #CFG.ps_links.." terdaftar")
    row("Delay", CFG.delay_min.."-"..CFG.delay_max.."m | launch "..CFG.launch_delay.."s")
    row("Autoexec", CFG.autoexec_script ~= ""
        and cc(C.green,"✓ Set") or cc(C.dim,"– Tidak diset"))

    print("")
    sep()
    row("Status", status_badge(status or "stopped"))
    if extra1 then row("Info",   extra1) end
    if extra2 then row("Detail", extra2) end
    sep()
    print("")
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MAIN MENU
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function main_menu()
    draw_header("stopped")
    local pkgs      = detect_packages()
    local can_start = #pkgs > 0 and #CFG.ps_links > 0

    p(cc(C.bold,"  1.").." Kelola PS links     "..cc(C.dim,"("..#CFG.ps_links.." terdaftar)"))
    p(cc(C.bold,"  2.").." Per-client PS map   "..cc(C.dim, next(CFG.client_ps_map) and "(✓ set)" or "(– kosong)"))
    p(cc(C.bold,"  3.").." Set delay           "..cc(C.dim,"("..CFG.delay_min.."-"..CFG.delay_max.."m | launch "..CFG.launch_delay.."s)"))
    p(cc(C.bold,"  4.").." Set cookie & akun")
    p(cc(C.bold,"  5.").." Set autoexec")
    p(cc(C.bold,"  6.").." Layout manager      "..cc(C.dim,"("..#pkgs.." pkg)"))
    p(cc(C.bold,"  7.").." Heartbeat           "..cc(C.dim,"(max fail: "..CFG.hb_max_fail.."x)"))
    p(cc(C.bold,"  8.").." Lihat config")
    print("")

    if can_start then
        p(cc(C.green, cc(C.bold,"  9. START HOPPER")))
    else
        p(cc(C.dim,"  9. START HOPPER"))
        if #pkgs == 0 then p(cc(C.red,"     ⚠ Tidak ada package Roblox")) end
        if #CFG.ps_links == 0 then p(cc(C.red,"     ⚠ Tambahkan PS link dulu")) end
    end
    if CFG.cookie == "" then
        p(cc(C.yellow,"     ⚠ Cookie belum diset (opsional)")) end

    p(cc(C.bold,"  0.").." Keluar")
    print("")

    local ch = ask("")
    if     ch == "1" then return "menu_ps"
    elseif ch == "2" then return "menu_ps_map"
    elseif ch == "3" then return "menu_delay"
    elseif ch == "4" then return "menu_cookie"
    elseif ch == "5" then return "menu_autoexec"
    elseif ch == "6" then return "menu_layout"
    elseif ch == "7" then return "menu_heartbeat"
    elseif ch == "8" then return "menu_config"
    elseif ch == "9" then return can_start and "start" or "main"
    elseif ch == "0" then return "exit"
    end
    return "main"
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: PS LINKS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_ps()
    while true do
        draw_header("stopped")
        p(cc(C.bold,"  PRIVATE SERVER LINKS"))
        print("")
        if #CFG.ps_links == 0 then
            p(cc(C.dim,"  Belum ada link"))
        else
            for i, link in ipairs(CFG.ps_links) do
                p(string.format("  %s[%2d]%s %s", C.cyan, i, C.reset, trunc(link, W-7)))
            end
        end
        print("")
        sep()
        p(cc(C.bold,"  a").." Tambah  "..cc(C.bold,"d").." Hapus  "..cc(C.bold,"c").." Hapus semua  "..cc(C.bold,"b").." Kembali")
        sep(); print("")
        local opt = ask("")

        if opt == "a" then
            draw_header("stopped")
            p(cc(C.bold,"  TAMBAH PS LINKS"))
            print("")
            p("  Paste links — "..cc(C.bold,"1 link per baris"))
            p(cc(C.dim,"  'code=' harus ada di link | baris kosong/done = selesai"))
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
                    p("    "..cc(C.red,"✗").." Tidak valid (harus ada 'code=' dan https://), skip")
                end
            end
            if added > 0 then save_config() end
            p("\n  "..cc(C.green,"[+]").." "..added.." ditambahkan"
                ..(skipped>0 and ", "..skipped.." dilewati" or ""))
            sleep(1)

        elseif opt == "d" then
            if #CFG.ps_links == 0 then
                p(cc(C.red,"  Tidak ada link")); sleep(1)
            else
                local n = ask("Hapus nomor (0=batal)")
                local idx = tonumber(n)
                if idx and idx > 0 and idx <= #CFG.ps_links then
                    table.remove(CFG.ps_links, idx)
                    -- Bersihkan ps_map references
                    for pkg, plist in pairs(CFG.client_ps_map) do
                        local new = {}
                        for _, pidx in ipairs(plist) do
                            if pidx <= #CFG.ps_links then
                                table.insert(new, pidx)
                            end
                        end
                        CFG.client_ps_map[pkg] = new
                    end
                    save_config()
                    p("  "..cc(C.green,"[+]").." Link #"..idx.." dihapus")
                else
                    p(cc(C.dim,"  Dibatalkan"))
                end
                sleep(1)
            end

        elseif opt == "c" then
            local conf = ask("Ketik 'hapus' untuk konfirmasi")
            if conf == "hapus" then
                CFG.ps_links = {}; CFG.client_ps_map = {}
                save_config()
                p("  "..cc(C.green,"[+]").." Semua link dihapus")
                sleep(1)
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
    p(cc(C.dim,"  Tentukan PS mana untuk tiap client"))
    p(cc(C.dim,"  Kosong = pakai semua PS secara berurutan"))
    print("")

    if #CFG.ps_links == 0 then
        p(cc(C.red,"  ⚠ Tambahkan PS link dulu!")); sleep(2); return
    end
    local pkgs = detect_packages()
    if #pkgs == 0 then
        p(cc(C.red,"  ⚠ Tidak ada package Roblox!")); sleep(2); return
    end

    p("  Total PS: "..cc(C.cyan, tostring(#CFG.ps_links))); print("")
    for i, link in ipairs(CFG.ps_links) do
        p(string.format("  %s[%2d]%s %s", C.dim, i, C.reset, trunc(link, W-7)))
    end
    print("")

    for i, pkg in ipairs(pkgs) do
        local cur = CFG.client_ps_map[pkg] or {}
        local cur_str = #cur > 0 and table.concat(cur,",") or cc(C.dim,"semua")
        p(string.format("  %s[%d]%s %s", C.cyan, i, C.reset, trunc(pkg, W-6)))
        p(cc(C.dim,"       Saat ini: ")..cur_str)
        local inp = ask("PS untuk client "..i.." (e.g 1-3, 1,2 atau Enter=semua)")
        if inp and inp ~= "" then
            local sel = parse_selection(inp, #CFG.ps_links)
            if #sel > 0 then
                CFG.client_ps_map[pkg] = sel
                p(cc(C.green,"    ✓").." Diset: "..table.concat(sel,","))
            else
                p(cc(C.dim,"    Input tidak valid, skip"))
            end
        else
            CFG.client_ps_map[pkg] = {}
            p(cc(C.dim,"    → Pakai semua PS"))
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
    p("  Hop delay saat ini : "..cc(C.cyan, CFG.delay_min.."-"..CFG.delay_max.." menit (random)"))
    p("  Launch delay       : "..cc(C.cyan, CFG.launch_delay.." detik antar client"))
    p(cc(C.dim,"  Hop delay = diam di server sebelum pindah"))
    p(cc(C.dim,"  Launch delay = jeda antar client saat join"))
    print("")
    local mn = ask("Hop min menit (Enter=batal)")
    if not mn or mn == "" then return end
    local mx = ask("Hop max menit")
    local ld = ask("Launch delay detik (Enter=pakai saat ini)")
    mn = tonumber(mn); mx = tonumber(mx)
    if mn and mx and mn >= 1 and mx >= mn then
        CFG.delay_min = mn; CFG.delay_max = mx
        if ld and ld ~= "" and tonumber(ld) then
            CFG.launch_delay = tonumber(ld)
        end
        save_config()
        p("\n  "..cc(C.green,"[+]").." Delay: "..mn.."-"..mx.."m | launch "..CFG.launch_delay.."s")
    else
        p("\n  "..cc(C.red,"[!]").." Tidak valid")
    end
    sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: COOKIE
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function input_cookie()
    print("")
    p("  Paste "..cc(C.bold,".ROBLOSECURITY").." cookie:")
    local new = ask("")
    if not new or new == "" then p(cc(C.dim,"  Dibatalkan")); sleep(1); return end
    if not new:match("_|WARNING") then
        p(cc(C.yellow,"  [!] Cookie tidak diawali '_|WARNING'"))
        local f = ask("Tetap simpan? (y/n)")
        if f ~= "y" then return end
    end
    CFG.cookie = new
    print("")
    p(cc(C.dim,"  Mengambil info akun dari Roblox API..."))
    if fetch_account(CFG.cookie) then
        save_config()
        p("  "..cc(C.green,"[+]").." Cookie valid!")
        p("  "..cc(C.green,"[+]").." Akun: "..cc(C.bold, CFG.account_name))
        p("  "..cc(C.green,"[+]").." ID  : "..CFG.account_id)
    else
        CFG.account_name = "(gagal fetch)"; CFG.account_id = ""
        save_config()
        p("  "..cc(C.yellow,"[!]").." Gagal fetch akun — cookie mungkin expired")
    end
    sleep(2)
end

local function menu_cookie()
    draw_header("stopped")
    p(cc(C.bold,"  SET COOKIE & AKUN")); print("")
    if CFG.cookie ~= "" then
        p("  Cookie : "..cc(C.green,"✓ Set")..cc(C.dim," ("..CFG.cookie:sub(1,20).."...)"))
        p("  Akun   : "..cc(C.bold,CFG.account_name)..cc(C.dim," (ID: "..CFG.account_id..")"))
        print("")
        p(cc(C.bold,"  1.")..cc(C.bold," Ganti  ")..cc(C.bold,"2.")..cc(C.bold," Refresh akun  ")..cc(C.bold,"3.")..cc(C.bold," Hapus  ")..cc(C.bold,"0.")..cc(C.bold," Kembali"))
        print("")
        local opt = ask("")
        if opt == "1" then input_cookie()
        elseif opt == "2" then
            draw_header("stopped")
            p(cc(C.dim,"  Mengambil info akun..."))
            if fetch_account(CFG.cookie) then
                save_config()
                p("  "..cc(C.green,"[+]").." Akun: "..cc(C.bold,CFG.account_name))
            else
                p("  "..cc(C.red,"[!]").." Gagal — cookie mungkin expired")
            end
            sleep(2)
        elseif opt == "3" then
            CFG.cookie=""; CFG.account_name=""; CFG.account_id=""
            save_config()
            p("  "..cc(C.green,"[+]").." Cookie dihapus"); sleep(1)
        end
    else
        input_cookie()
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: AUTOEXEC
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_autoexec()
    draw_header("stopped")
    p(cc(C.bold,"  SET AUTOEXEC")); print("")
    p(cc(C.dim,"  Diinjek sebelum setiap Roblox launch"))
    p(cc(C.dim,"  Backup ke /sdcard/ — restore saat hopper di-stop"))
    print("")
    p("  Path    : "..cc(C.cyan, CFG.autoexec_path))
    p("  Script  : "..(CFG.autoexec_script ~= "" and cc(C.green,"✓ Set") or cc(C.red,"✗ Kosong")))
    p("  Restore : "..(CFG.autoexec_restore ~= "" and cc(C.green,"✓ Set") or cc(C.dim,"– Kosong")))
    print("")
    p(cc(C.bold,"  1.")..cc(C.bold," Path  ")..cc(C.bold,"2.")..cc(C.bold," Script  ")..cc(C.bold,"3.")..cc(C.bold," Restore  ")..cc(C.bold,"4.")..cc(C.bold," Test inject  ")..cc(C.bold,"0.")..cc(C.bold," Kembali"))
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
-- MENU: LAYOUT MANAGER
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_layout()
    draw_header("stopped")
    p(cc(C.bold,"  LAYOUT MANAGER")); print("")
    local pkgs = detect_packages()
    if #pkgs == 0 then
        p(cc(C.red,"  ⚠ Tidak ada package Roblox!")); sleep(2); return
    end
    local sw, sh, offset = detect_screen()
    if not sw then
        p(cc(C.red,"  ⚠ Gagal baca resolusi!")); sleep(2); return
    end

    local n   = #pkgs
    local gh  = calc_grid_height(n, sh, offset)
    p("  Screen  : "..cc(C.cyan, sw.." × "..sh))
    p("  Offset  : "..offset.."px (status bar)")
    p("  Grid    : 1 × "..n.." ("..sw.." × "..gh.." per slot)")
    print("")

    local adj = ask("Override offset? (kosong=skip)")
    if adj and adj ~= "" and tonumber(adj) then
        offset = tonumber(adj)
        gh = calc_grid_height(n, sh, offset)
        p(cc(C.dim,"  Offset diubah: "..offset.."px"))
    end
    print("")

    sep()
    for i, pkg in ipairs(pkgs) do
        local L, T, R, B = grid_bounds(i, n, sw, sh, offset)
        p(string.format("  %s[%d]%s %s", C.cyan, i, C.reset, trunc(pkg, W-6)))
        p(cc(C.dim, string.format("       L=%-4d T=%-4d R=%-4d B=%d", L, T, R, B)))
    end
    sep(); print("")

    p(cc(C.bold,"  1.")..cc(C.bold," Apply layout + launch")
        .."  "..cc(C.bold,"2.")..cc(C.bold," Apply layout saja")
        .."  "..cc(C.bold,"3.")..cc(C.bold," Reset fullscreen")
        .."  "..cc(C.bold,"0.")..cc(C.bold," Kembali"))
    print("")
    local opt = ask("")

    if opt == "1" or opt == "2" then
        print("")
        for i, pkg in ipairs(pkgs) do
            local L, T, R, B = grid_bounds(i, n, sw, sh, offset)
            su_exec("am force-stop "..pkg)
            apply_layout_host(pkg, L, T, R, B)
            p("  "..cc(C.green,"[+]").." Layout applied: "..trunc(pkg, W-20))
            if opt == "1" then
                sleep(3)
                su_exec("am start --user 0 -n "..pkg.."/"..ACTIVITY)
                p("  "..cc(C.green,"→ Launched"))
                if i < n then sleep(5) end
            end
        end
        p("\n  "..cc(C.green,"Selesai!")); sleep(2)
    elseif opt == "3" then
        for _, pkg in ipairs(pkgs) do
            apply_layout_host(pkg, 0, 0, sw, sh)
            su_exec("am force-stop "..pkg)
        end
        p("  "..cc(C.green,"[+]").." Layout di-reset ke fullscreen"); sleep(1)
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: HEARTBEAT
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_heartbeat()
    draw_header("stopped")
    p(cc(C.bold,"  HEARTBEAT / WATCHDOG")); print("")
    p(cc(C.dim,"  Cek apakah Roblox masih running setiap 10 detik"))
    p(cc(C.dim,"  Jika crash → relaunch PS yang sama secara otomatis"))
    print("")
    p("  Max fail saat ini : "..cc(C.cyan, CFG.hb_max_fail.."x"))
    print("")
    local f = ask("Max fail baru (Enter=batal)")
    if not f or f == "" then return end
    f = tonumber(f)
    if f and f >= 1 then
        CFG.hb_max_fail = f; save_config()
        p("\n  "..cc(C.green,"[+]").." Max fail: "..f.."x")
    else
        p("\n  "..cc(C.red,"[!]").." Tidak valid")
    end
    sleep(1)
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MENU: VIEW CONFIG
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function menu_config()
    draw_header("stopped")
    p(cc(C.bold,"  CONFIG LENGKAP")); print("")
    row("Akun",       CFG.account_name ~= "" and CFG.account_name or "-")
    row("UserID",     CFG.account_id   ~= "" and CFG.account_id   or "-")
    row("Delay",      CFG.delay_min.."-"..CFG.delay_max.."m | launch "..CFG.launch_delay.."s")
    row("HB fail",    CFG.hb_max_fail.."x")
    row("Cookie",     CFG.cookie ~= "" and "✓ Set" or "✗ Kosong")
    row("Autoexec",   CFG.autoexec_script ~= "" and "✓ Set" or "– Kosong")
    row("AE Path",    trunc(CFG.autoexec_path, W-18))
    row("PS Links",   #CFG.ps_links.." link")
    print("")
    for i, link in ipairs(CFG.ps_links) do
        p(string.format("  %s  [%2d]%s %s", C.cyan, i, C.reset, trunc(link, W-9)))
    end
    if next(CFG.client_ps_map) then
        print("")
        p(cc(C.bold,"  Per-client PS map:"))
        for pkg, plist in pairs(CFG.client_ps_map) do
            if #plist > 0 then
                p(string.format("  %s%s%s → {%s}",
                    C.cyan, trunc(pkg, W-12), C.reset, table.concat(plist,",")))
            end
        end
    end
    print("")
    ask("Enter untuk kembali")
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- GENERATE LOOP SCRIPT
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function generate_loop(pkgs)
    local sw, sh, offset = detect_screen()
    if not sw then return nil, "Gagal baca resolusi" end
    local n  = #pkgs
    local out = {}

    -- Header vars
    table.insert(out, "-- AUTO-GENERATED by hopper.lua v5\n")
    table.insert(out, "local STATE_FILE     = "..string.format("%q", STATE_FILE).."\n")
    table.insert(out, "local STOP_FILE      = "..string.format("%q", STOP_FILE).."\n")
    table.insert(out, "local LOG_FILE       = "..string.format("%q", LOG_FILE).."\n")
    table.insert(out, "local AE_BAK_FILE    = "..string.format("%q", AE_BAK_FILE).."\n")
    table.insert(out, "local COOKIE         = "..string.format("%q", CFG.cookie).."\n")
    table.insert(out, "local AUTOEXEC_SCRIPT= "..string.format("%q", CFG.autoexec_script).."\n")
    table.insert(out, "local AUTOEXEC_PATH  = "..string.format("%q", CFG.autoexec_path).."\n")
    table.insert(out, "local AUTOEXEC_RESTORE="..string.format("%q", CFG.autoexec_restore).."\n")
    table.insert(out, "local HB_MAX_FAIL    = "..CFG.hb_max_fail.."\n")
    table.insert(out, "local DELAY_MIN      = "..CFG.delay_min.."\n")
    table.insert(out, "local DELAY_MAX      = "..CFG.delay_max.."\n")
    table.insert(out, "local LAUNCH_DELAY   = "..CFG.launch_delay.."\n\n")

    -- PS links dengan escape
    table.insert(out, "local ps_links = {\n")
    for _, link in ipairs(CFG.ps_links) do
        table.insert(out, '  "'..escape_lua_str(link)..'",\n')
    end
    table.insert(out, "}\n\n")

    -- Clients dengan layout calc
    table.insert(out, "local clients = {\n")
    for i, pkg in ipairs(pkgs) do
        local L, T, R, B = grid_bounds(i, n, sw, sh, offset)
        local ps_map  = CFG.client_ps_map[pkg] or {}
        local indices = {}
        if #ps_map == 0 then
            for j = 1, #CFG.ps_links do table.insert(indices, j) end
        else
            indices = ps_map
        end
        table.insert(out, "  { -- client "..i.."\n")
        table.insert(out, "    pkg="..string.format("%q",pkg)..",\n")
        table.insert(out, "    L="..L..", T="..T..", R="..R..", B="..B..",\n")
        table.insert(out, "    ps_idx_list={"..table.concat(indices,",").."},\n")
        table.insert(out, "    curr_ptr=1,\n  },\n")
    end
    table.insert(out, "}\n\n")
    table.insert(out, LOOP_CODE)

    return table.concat(out), nil
end

local function find_lua_bin()
    local h = io.popen("command -v lua 2>/dev/null")
    local bin
    if h then bin = h:read("*l"); h:close() end
    if not bin or bin == "" then
        bin = "/data/data/com.termux/files/usr/bin/lua"
    end
    return bin
end

local function kill_hopper(pid)
    if pid and pid ~= "" then
        os.execute("kill -9 " .. pid .. " 2>/dev/null")
    end
    local old = read_file(PID_FILE)
    if old then
        os.execute("kill -9 " .. clean(old) .. " 2>/dev/null")
    end
    os.remove(PID_FILE)
end


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
local function reset_all(pkgs)
    print("")
    p(cc(C.yellow,"  Resetting..."))

    -- Restore autoexec
    if CFG.autoexec_restore ~= "" then
        local dir = CFG.autoexec_path:match("^(.+)/[^/]+$")
        if dir then su_exec("mkdir -p '"..dir.."'") end
        local ok = write_file(CFG.autoexec_path, CFG.autoexec_restore)
        if not ok then
            local esc = CFG.autoexec_restore:gsub("'","'\\''")
            su_exec("echo '"..esc.."' > '"..CFG.autoexec_path.."'")
        end
        su_exec("chmod 644 '"..CFG.autoexec_path.."'")
        su_exec("rm -f '"..AE_BAK_FILE.."' 2>/dev/null")
        p("  "..cc(C.green,"[+]").." Autoexec restored")
    end

    -- Restore layout fullscreen + close semua
    if pkgs and #pkgs > 0 then
        local sw, sh = detect_screen()
        for _, pkg in ipairs(pkgs) do
            if sw then apply_layout_host(pkg, 0, 0, sw, sh) end
            su_exec("am force-stop "..pkg)
            p("  "..cc(C.green,"[+]").." Closed: "..trunc(pkg, W-12))
        end
    end

    os.remove(STATE_FILE); os.remove(STOP_FILE)
    os.remove(LOOP_FILE);  os.remove(PID_FILE)
    p("\n  "..cc(C.green,"Reset selesai!"))
    sleep(1)
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
        p(cc(C.red,"  [!] Tidak ada package Roblox!")); sleep(2); return
    end

    os.remove(STOP_FILE); os.remove(STATE_FILE)
    -- Reset log baru setiap session
    os.remove(LOG_FILE)

    -- Generate script
    local script, err = generate_loop(pkgs)
    if not script then
        p(cc(C.red,"  [!] "..err)); sleep(2); return
    end
    if not write_file(LOOP_FILE, script) then
        p(cc(C.red,"  [!] Gagal tulis loop script!")); sleep(2); return
    end
    os.execute("chmod 755 '"..LOOP_FILE.."'")

    -- Cari Lua binary
    local lua_bin = find_lua_bin()

    -- Kill hopper lama jika ada
    kill_hopper(nil)

    -- Launch background
    local ph = io.popen("nohup "..lua_bin.." '"..LOOP_FILE.."'"
        .." >> '"..LOG_FILE.."' 2>&1 & echo $!")
    if not ph then p(cc(C.red,"  [!] Gagal launch!")); sleep(2); return end
    local pid = clean(ph:read("*a")); ph:close()
    write_file(PID_FILE, pid)
    log_main("Hopper started PID="..pid)

    -- Tunggu state tersedia max 20s
    local waited = 0
    while not file_exists(STATE_FILE) and waited < 20 do
        draw_header("starting")
        p(cc(C.dim,"  Memulai ("..waited.."s)..."))
        sleep(1); waited = waited + 1
    end

    -- Siapkan clients_data untuk monitor
    local sw, sh, offset = detect_screen()
    local n = #pkgs
    local clients_data = {}
    for i, pkg in ipairs(pkgs) do
        local L, T, R, B = grid_bounds(i, n, sw or 480, sh or 320, offset)
        local ps_map = CFG.client_ps_map[pkg] or {}
        local indices = {}
        if #ps_map == 0 then
            for j = 1, #CFG.ps_links do table.insert(indices, j) end
        else indices = ps_map end
        table.insert(clients_data, {pkg=pkg, L=L, T=T, R=R, B=B, ps_idx_list=indices})
    end

    -- Launch live monitor langsung
    p(cc(C.dim,"  Masuk monitor..."))
    sleep(2)
    monitor_live(clients_data, CFG.delay_min, pid)

    -- Setelah monitor exit (tekan q)
    draw_header("stopping")
    p(cc(C.yellow,"  Menghentikan hopper..."))
    write_file(STOP_FILE, "stop")
    -- Tunggu max 12s
    for _ = 1, 12 do
        local ch = io.popen("kill -0 "..pid.." 2>/dev/null; echo $?")
        if ch then
            local e = clean(ch:read("*a")); ch:close()
            if e ~= "0" then break end
        end
        sleep(1)
    end
    kill_hopper(pid)

    print("")
    sep()
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
    menu_ps        = function() menu_ps();        return "main" end,
    menu_ps_map    = function() menu_ps_map();    return "main" end,
    menu_delay     = function() menu_delay();     return "main" end,
    menu_cookie    = function() menu_cookie();    return "main" end,
    menu_autoexec  = function() menu_autoexec();  return "main" end,
    menu_layout    = function() menu_layout();    return "main" end,
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
