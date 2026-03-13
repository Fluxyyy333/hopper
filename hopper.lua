-- PS Hopper Tool v3.1
-- Base: v3.0 Single-Process Inline
-- Improvements: pkg prefix, per-pkg cookie, dashboard table, config persist
-- Target: Termux + Root Android
-- ============================================

local W = 50
local ACTIVITY = "com.roblox.client.startup.ActivitySplash"
local PS_FILE_PATH = "/sdcard/private_servers.txt"
local AUTOEXEC_DIR = "/storage/emulated/0/RonixExploit/autoexec"
local AUTOEXEC_FILE = AUTOEXEC_DIR .. "/auto_1.lua"
local HOPPER_LOG = "/sdcard/hopper_log.txt"
local JOIN_SCRIPT = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/FnDXueyi/list/refs/heads/main/game2"))()'
local AUTOEXEC_RESTORE = 'loadstring(game:HttpGet(""))()'
local DEFAULT_DELAY = 20
local LAYOUT_DELAY = 10
local WATCHDOG_SEC = 10

-- Config file (persist antar session)
local HOME = os.getenv("HOME") or "/data/data/com.termux/files/home"
local CONFIG_FILE = HOME .. "/.hopper_config.lua"

-- ============================================
-- CONFIG (prefix + accounts)
-- ============================================
local CFG = {
    pkg_prefix = "com.roblox.",
    -- accounts[pkg] = { cookie="", name="", id="" }
    accounts   = {},
}

local function cfg_save()
    local lines = { "return {" }
    lines[#lines+1] = "  pkg_prefix = " .. string.format("%q", CFG.pkg_prefix) .. ","
    lines[#lines+1] = "  accounts = {"
    for pkg, acc in pairs(CFG.accounts) do
        lines[#lines+1] = "    [" .. string.format("%q", pkg) .. "] = {"
        lines[#lines+1] = "      cookie = " .. string.format("%q", acc.cookie or "") .. ","
        lines[#lines+1] = "      name   = " .. string.format("%q", acc.name   or "") .. ","
        lines[#lines+1] = "      id     = " .. string.format("%q", acc.id     or "") .. ","
        lines[#lines+1] = "    },"
    end
    lines[#lines+1] = "  },"
    lines[#lines+1] = "}"
    local f = io.open(CONFIG_FILE, "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    os.execute("chmod 600 '" .. CONFIG_FILE .. "'")
end

local function cfg_load()
    if not io.open(CONFIG_FILE, "r") then return end
    local ok, loaded = pcall(dofile, CONFIG_FILE)
    if ok and type(loaded) == "table" then
        if type(loaded.pkg_prefix) == "string" then CFG.pkg_prefix = loaded.pkg_prefix end
        if type(loaded.accounts)   == "table"  then CFG.accounts   = loaded.accounts   end
    end
end

-- ============================================
-- CORE HELPERS (sama persis v3.0)
-- ============================================
local function sleep(s) if s and s > 0 then os.execute("sleep " .. tostring(s)) end end

local function clean(str)
    if not str then return "-" end
    str = str:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("[\r\n\t]", ""):gsub("%c", "")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    return str ~= "" and str or "-"
end

local function sanitize_pkg(p)
    if not p then return nil end
    local s = p:gsub("[^%w%._]", "")
    return s ~= "" and s or nil
end

local function is_valid_ps_link(l)
    if not l or l == "" then return false end
    if not l:match("^https?://") and not l:match("^intent://") then return false end
    if not l:lower():match("code=") then return false end
    if l:match("[;|`$%(%){}%z]") then return false end
    return true
end

local function trunc(s, m)
    if not s then return "-" end
    if #s <= m then return s end
    return m > 2 and (s:sub(1, m-2) .. "..") or s:sub(1, m)
end

local function parse_selection(input, max)
    local sel, seen = {}, {}
    local a, b = input:match("^(%d+)%-(%d+)$")
    if a and b then
        for i = tonumber(a), tonumber(b) do
            if i >= 1 and i <= max and not seen[i] then table.insert(sel, i); seen[i] = true end
        end
        return sel
    end
    for n in input:gmatch("(%d+)") do
        local v = tonumber(n)
        if v and v >= 1 and v <= max and not seen[v] then table.insert(sel, v); seen[v] = true end
    end
    return sel
end

-- ============================================
-- UI (sama persis v3.0)
-- ============================================
local function color(c) io.write("\27[" .. c .. "m"); io.flush() end
local function noreset() io.write("\27[0m"); io.flush() end
local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end
local function border() print(string.rep("-", W)) end

local function box_title(t)
    local inner = math.max(W-2, #t+2)
    local pl = math.floor((inner-#t)/2)
    local pr = inner - #t - pl
    print("+" .. string.rep("-", inner) .. "+")
    print("|" .. string.rep(" ", pl) .. t .. string.rep(" ", pr) .. "|")
    print("+" .. string.rep("-", inner) .. "+")
end

local function info(l, v)
    local p = l .. ": "
    print(p .. trunc(v, math.max(W-#p, 4)))
end

local function print_logo()
    color("36")
    print([[ ░▒▓███████▓▒░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░    ░▒▓██▓▒░ 
 ░▒▓██████▓▒░░▒▓██████▓▒░ ░▒▓█▓▒░  ░▒▓██▓▒░   
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓██▓▒░     
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░       
░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░]])
    noreset(); print("")
end

-- ============================================
-- INPUT (sama persis v3.0)
-- ============================================
local function ask(prompt)
    io.write(prompt .. " > "); io.flush()
    local tty = io.open("/dev/tty", "r")
    local r
    if tty then r = tty:read("*l"); tty:close() else r = io.read("*l") end
    if r == nil then sleep(2) end
    return r
end

local function read_key(t)
    local h = io.popen("bash -c 'read -t " .. (t or 1) .. " -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
end

-- ============================================
-- SYSTEM / ROOT (sama persis v3.0)
-- ============================================
local function su_cmd(cmd)
    local h = io.popen("su -c '" .. cmd:gsub("'", "'\\''") .. "' 2>&1")
    if not h then return "ERROR" end
    local r = h:read("*a"); h:close()
    return clean(r)
end

local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'", "'\\''") .. "' >/dev/null 2>&1")
end

-- ============================================
-- DETECTION
-- ============================================
local function detect_offset()
    local off = 0
    local st = su_cmd("dumpsys window | grep mStable | head -1")
    local v = st:match("mStable=%[%d+,(%d+)%]")
    if v then off = tonumber(v) or 0 end
    if off == 0 then
        local d = su_cmd("wm density"):match("(%d+)")
        off = d and math.ceil(24 * tonumber(d) / 160) or 48
    end
    return off
end

local function detect_screen()
    local off = detect_offset()
    local r = su_cmd("wm size")
    local sw, sh = r:match("(%d+)x(%d+)")
    if not sw then return nil, nil, off, r end
    sw, sh = tonumber(sw), tonumber(sh)
    return math.min(sw, sh), math.max(sw, sh), off, nil
end

-- [IMPROVED] detect_packages pakai CFG.pkg_prefix, bukan hardcode
local function detect_packages()
    local h = io.popen("pm list packages 2>/dev/null")
    if not h then return {} end
    local r = h:read("*a") or ""; h:close()
    local pkgs = {}
    local prefix = CFG.pkg_prefix
    for line in r:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p then
            p = sanitize_pkg(clean(p))
            if p and p:sub(1, #prefix) == prefix then
                table.insert(pkgs, p)
            end
        end
    end
    table.sort(pkgs)
    return pkgs
end

-- [IMPROVED] parse input cookie — support 2 format:
--   1. cookie only        → langsung nilai cookie
--   2. nick:pass:cookie   → ambil dari _|WARNING ke akhir
local function parse_cookie_input(input)
    if not input or input == "" then return nil end
    -- Cari dari _|WARNING ke akhir — selalu ada di cookie Roblox valid
    local cookie = input:match("(_|WARNING.+)$")
    if cookie then return cookie end
    -- Tidak ada _|WARNING — anggap input adalah cookie langsung
    return input
end

-- [IMPROVED] fetch nama + id akun dari Roblox API
-- Returns: name, id, err
-- err = "curl"   → curl gagal/SSL error (cookie mungkin valid)
-- err = "invalid" → curl OK tapi cookie tidak dikenali Roblox
local function fetch_account(cookie)
    if not cookie or cookie == "" then return nil, nil, "empty" end
    local h = io.popen('curl -s --insecure --max-time 10 '
        .. '-H "Cookie: .ROBLOSECURITY=' .. cookie .. '" '
        .. '"https://users.roblox.com/v1/users/authenticated" 2>&1')
    if not h then return nil, nil, "curl" end
    local res = h:read("*a"); h:close()
    -- Cek error curl / SSL
    if res:match("CANNOT LINK") or res:match("cannot locate symbol") or res:match("^curl:") then
        return nil, nil, "curl"
    end
    local name = res:match('"name":"([^"]+)"')
    local id   = res:match('"id":(%d+)')
    if name and id then return name, id, nil end
    return nil, nil, "invalid"
end

-- ============================================
-- LAYOUT (sama persis v3.0)
-- ============================================
local function apply_layout(pkg, L, T, R, B)
    local pref = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
    su_exec("chmod 666 " .. pref)
    local args = {}
    for _, f in ipairs({
        {"app_cloner_current_window_left",   L},
        {"app_cloner_current_window_top",    T},
        {"app_cloner_current_window_right",  R},
        {"app_cloner_current_window_bottom", B},
    }) do
        table.insert(args,
            "-e 's/name=\\\"" .. f[1] .. "\\\" value=\\\"[^\\\"]*\\\"/name=\\\"" .. f[1] .. "\\\" value=\\\"" .. f[2] .. "\\\"/g'")
    end
    su_exec("sed -i " .. table.concat(args, " ") .. " " .. pref)
    su_exec("chmod 444 " .. pref)
end

local function grid_h(n, sh, off) return math.floor((sh-off)/n) end

local function grid_bounds(i, n, sw, sh, off)
    if n == 1 then return 0, 0, sw, sh end
    local gh = grid_h(n, sh, off); local row = i-1
    return 0, (row*gh)+off, sw, ((row+1)*gh)+off
end

-- ============================================
-- INLINE HOPPER HELPERS (sama persis v3.0)
-- ============================================
local function hlog(msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function is_running(pkg)
    local h = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- [IMPROVED] launch_client inject cookie per-client sebelum am start
local function inject_cookie(pkg)
    local acc = CFG.accounts[pkg]
    if not acc or not acc.cookie or acc.cookie == "" then return end
    local dir  = "/data/data/" .. pkg .. "/shared_prefs"
    local file = dir .. "/RobloxSharedPreferences.xml"
    local tmp  = "/tmp/hcookie.xml"
    local f = io.open(tmp, "w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">' .. acc.cookie .. "</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. file .. "'")
    su_exec("chmod 660 '" .. file .. "'")
    os.remove(tmp)
end

local function launch_client(c, ps_list, ps_idx, cnum)
    if not ps_list[ps_idx] then hlog("ERROR: PS " .. tostring(ps_idx) .. " OOB"); return end
    su_exec("am force-stop " .. c.pkg); sleep(1)
    inject_cookie(c.pkg)
    local raw = ps_list[ps_idx]
    local dp = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://", "")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. c.pkg
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    hlog("Client " .. cnum .. " -> PS " .. ps_idx)
end

-- ============================================
-- MONITOR (v3.0 + dashboard table di atas)
-- ============================================
local function fmt_elapsed(s)
    if s < 0 then s = 0 end
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); s = s%60
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

local function ts2sec(ts)
    local h, m, s = ts:match("(%d+):(%d+):(%d+)")
    return h and (tonumber(h)*3600 + tonumber(m)*60 + tonumber(s)) or 0
end

local function parse_log()
    local vis, cr = {}, {}
    local f = io.open(HOPPER_LOG, "r")
    if not f then return vis, cr end
    for line in f:lines() do
        local t, cn, ps = line:match("^(%d+:%d+:%d+) Client (%d+) %-> PS (%d+)")
        if t then
            local c = tonumber(cn)
            if not vis[c] then vis[c] = {} end
            table.insert(vis[c], {ps=tonumber(ps), sec=ts2sec(t), ts=t})
        end
        local ct, cc = line:match("^(%d+:%d+:%d+) Crash client (%d+)")
        if ct then cr[tonumber(cc)] = ct end
    end
    f:close()
    return vis, cr
end

local function ps_summary(cv, now)
    local pd = {}
    if not cv or #cv == 0 then return pd end
    for i, v in ipairs(cv) do
        local dur
        if i < #cv then
            dur = cv[i+1].sec - v.sec; if dur < 0 then dur = dur + 86400 end
        else
            dur = now - v.sec; if dur < 0 then dur = dur + 86400 end
        end
        local cur = (i == #cv)
        if not pd[v.ps] then
            pd[v.ps] = {joined=v.ts, elapsed=dur, hops=1, current=cur}
        else
            local d = pd[v.ps]; d.joined=v.ts; d.elapsed=d.elapsed+dur; d.hops=d.hops+1
            if cur then d.current = true end
        end
    end
    return pd
end

-- [IMPROVED] render: tambah dashboard table di atas (Package | UserId | Username | State)
local function pkg_short(pkg)
    local short = pkg:sub(#CFG.pkg_prefix + 1)
    return trunc(short ~= "" and short or pkg, 14)
end

local function render(cdata, hop_int, status)
    cls()
    color("33"); box_title("HOPPER MONITOR (Live)"); noreset(); print("")

    -- [NEW] Dashboard table: Package | UserId | Username | State
    color("36")
    print(string.format(" %-14s  %-10s  %-10s  %s",
        "Package", "UserId", "Username", "State"))
    print(string.rep("-", W))
    noreset()
    for i, c in ipairs(cdata) do
        local acc = CFG.accounts[c.pkg] or {}
        local uid  = acc.id   and trunc(acc.id,   10) or "-"
        local name = acc.name and trunc(acc.name,  10) or "-"
        local running = is_running(c.pkg)
        local state_str, state_col
        if status == "STOPPED" then
            state_str = "closed"; state_col = "90"
        elseif running then
            state_str = "● run";  state_col = "32"
        else
            state_str = "○ wait";  state_col = "33"
        end
        color("36"); io.write(string.format(" %-14s  ", pkg_short(c.pkg))); noreset()
        io.write(string.format("%-10s  %-10s  ", uid, name))
        color(state_col); print(state_str); noreset()
    end
    print(string.rep("-", W)); print("")

    -- Hop log table (sama persis v3.0)
    local vis, cr = parse_log()
    local now_s = os.date("%H:%M:%S"); local now = ts2sec(now_s)
    color("36")
    print(string.format(" %-2s  %-3s  %-9s  %-10s %s", "C", "PS", "Joined", "Elapsed", "Hops"))
    print(string.rep("-", W)); noreset()
    for i, c in ipairs(cdata) do
        local pd = ps_summary(vis[i], now)
        local cm = cr[i] and " !" or ""
        for _, pi in ipairs(c.ps_idx_list) do
            local d = pd[pi]
            if d then
                color(d.current and "32" or "36")
                print(string.format(" %-2d  %-3d  %-9s  %-10s %d%s",
                    i, pi, d.joined, fmt_elapsed(d.elapsed), d.hops, cm))
                noreset(); cm = ""
            else
                color("90")
                print(string.format(" %-2d  %-3d  %-9s  %-10s %d", i, pi, "-", "-", 0))
                noreset()
            end
        end
        if i < #cdata then color("90"); print(string.rep(".", W)); noreset() end
    end
    print(""); border(); color("36")
    print(hop_int > 0 and ("  Hop: " .. hop_int .. " menit") or "  Mode: Sekali join + Watchdog")
    print("  Waktu: " .. now_s); print("  Status: " .. (status or "RUNNING"))
    noreset(); border(); print("")
    color("90")
    for i, c in ipairs(cdata) do print("  " .. i .. ": " .. trunc(c.pkg, W-6)) end
    noreset(); print(""); color("33"); print("  Tekan [q] untuk Stop & Reset"); noreset()
end

-- ============================================
-- MENU 1: SET LAYOUT (sama persis v3.0)
-- ============================================
local function set_layout_roblox()
    cls(); color("33"); box_title("SET LAYOUT ROBLOX"); noreset(); print("")
    color("36"); print("Detecting..."); noreset()
    local sw, sh, off, err = detect_screen()
    if not sw then
        color("31"); print("Gagal baca resolusi!")
        if err then print("Output: " .. trunc(err, W-8)) end
        noreset(); print(""); ask("Enter"); return
    end
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then
        color("31"); print("Tidak ada Roblox! (prefix: " .. CFG.pkg_prefix .. ")")
        noreset(); print(""); ask("Enter"); return
    end
    border(); color("36")
    info("Packages  ", tostring(tot)); info("Resolusi  ", sw .. " x " .. sh)
    info("Offset    ", off .. " px"); info("Grid      ", "1 x " .. tot)
    info("Delay/akun", LAYOUT_DELAY .. " dtk"); noreset(); border()
    print(""); print("Offset " .. off .. "px auto.")
    local adj = ask("Ubah offset? (kosong=skip)")
    if adj and adj ~= "" then
        local no = tonumber(adj)
        if no and no >= 0 then off = no; print("Offset: " .. off .. "px") else print("Invalid") end
    end
    print(""); color("32"); print("Package:"); noreset()
    for i, p in ipairs(pkgs) do print(" " .. i .. ". " .. trunc(p, W-5)) end
    print("")
    local c = ask("Lanjut? (y/n)")
    if not c or c:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); border(); color("33"); print("Setup layout..."); noreset(); print("")
    for i = 1, tot do
        local p = pkgs[i]; local L, T, R, B = grid_bounds(i, tot, sw, sh, off)
        color("36"); print("[" .. i .. "/" .. tot .. "] " .. trunc(p, W-8)); noreset()
        su_exec("am force-stop " .. p); apply_layout(p, L, T, R, B)
        su_exec("am start --user 0 -n " .. p .. "/" .. ACTIVITY)
        print("  L=" .. L .. " T=" .. T .. " R=" .. R .. " B=" .. B)
        if i < tot then print("  Tunggu " .. LAYOUT_DELAY .. "s..."); sleep(LAYOUT_DELAY) end
    end
    print(""); border(); color("32"); print("SELESAI!"); noreset(); border(); print("")
    local cl = ask("Close semua? (y/n)")
    if cl and cl:lower() == "y" then
        for _, p in ipairs(pkgs) do su_exec("am force-stop " .. p) end
        color("32"); print(tot .. " ditutup."); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================
-- MENU 2: JOIN PS (sama persis v3.0 + cookie inject)
-- ============================================
local function load_ps_links()
    local f = io.open(PS_FILE_PATH, "r")
    if not f then
        local d = io.open(PS_FILE_PATH, "w")
        if d then
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH\n")
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH2\n")
            d:close()
        end
        return nil, 0
    end
    local list, skip = {}, 0
    for line in f:lines() do
        local l = line:gsub("%c", ""):gsub("%s+", "")
        if l:lower():match("code=") then
            if is_valid_ps_link(l) then table.insert(list, l) else skip = skip + 1 end
        end
    end
    f:close()
    return list, skip
end

local function menu_join_server()
    cls(); color("33"); box_title("JOIN PRIVATE SERVER"); noreset(); print("")
    -- 1. Packages
    color("36"); print("Mencari Roblox... (prefix: " .. CFG.pkg_prefix .. ")"); noreset()
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then
        color("31"); print("Tidak ada Roblox! Cek prefix di Menu 3.")
        noreset(); print(""); ask("Enter"); return
    end
    print("Ditemukan " .. tot .. " client:")
    for i, p in ipairs(pkgs) do print("  " .. i .. ". " .. trunc(p, W-6)) end
    border(); print("")
    -- 2. PS links
    local ps_list, skip = load_ps_links()
    if not ps_list then
        color("31"); print("File PS tidak ada! Dibuat: " .. PS_FILE_PATH)
        noreset(); print(""); ask("Enter"); return
    end
    if skip > 0 then color("33"); print(skip .. " link invalid dilewati"); noreset() end
    if #ps_list == 0 then
        color("31"); print("Tidak ada link valid!")
        noreset(); print(""); ask("Enter"); return
    end
    color("32"); print(#ps_list .. " link PS valid."); noreset(); print("")
    -- 3. Hop interval
    local hi = tonumber(ask("Hop tiap brp menit? (0=tidak)")) or 0
    if hi < 0 then hi = 0 end
    -- 4. Select clients
    print(""); print("Pilih client (cth: 1,2,3 / 1-3 / 2):"); print("")
    local si = ask("Client")
    if not si or si == "" then print("Batal."); sleep(1); return end
    local sel = parse_selection(si, tot)
    if #sel == 0 then color("31"); print("Invalid!"); noreset(); print(""); ask("Enter"); return end
    -- 5. Map PS
    local cpm = {}; print(""); color("36"); print("Pilih PS per client (max: " .. #ps_list .. ")"); noreset()
    for _, idx in ipairs(sel) do
        local p = pkgs[idx]
        local pi = ask("PS utk Client " .. idx .. " (cth: 1-5)")
        local ps = pi and pi ~= "" and parse_selection(pi, #ps_list) or {}
        if #ps == 0 then ps = {}; for j = 1, #ps_list do table.insert(ps, j) end end
        cpm[p] = ps
    end
    -- 6. Preview
    print(""); border(); color("36")
    info("Total PS", tostring(#ps_list))
    info("Client  ", table.concat(sel, ",") .. " (" .. #sel .. " akun)")
    info("Hopper  ", hi == 0 and "OFF (sekali join)" or (hi .. " menit"))
    info("Delay   ", DEFAULT_DELAY .. " dtk"); info("Script  ", "game2 loader")
    noreset(); border(); print("")
    local cf = ask("Launch? (y/n)")
    if not cf or cf:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); color("33"); print("Preparing..."); noreset(); print("")
    -- 7. Screen
    local sw, sh, off, se = detect_screen()
    if not sw then color("31"); print("Gagal resolusi!"); noreset(); ask("Enter"); return end
    local ns = #sel
    color("36"); info("Screen", sw .. "x" .. sh); info("Offset", off .. "px")
    if ns == 1 then
        info("Layout", "fullscreen")
    else
        info("Layout", "split " .. ns .. " (" .. sw .. "x" .. grid_h(ns, sh, off) .. ")")
    end
    noreset(); print("")
    -- 8. Autoexec replace (sama persis v3.0)
    su_exec("mkdir -p " .. AUTOEXEC_DIR)
    su_exec("cp " .. AUTOEXEC_FILE .. " /sdcard/.auto_1.lua.bak 2>/dev/null")
    su_exec("rm -f " .. AUTOEXEC_FILE .. ".bak 2>/dev/null")
    local af = io.open(AUTOEXEC_FILE, "w")
    if af then
        af:write(JOIN_SCRIPT); af:close()
        su_exec("chmod 644 " .. AUTOEXEC_FILE)
    else
        local e = JOIN_SCRIPT:gsub("'", "'\\''")
        su_exec("echo '" .. e .. "' > " .. AUTOEXEC_FILE)
        su_exec("chmod 644 " .. AUTOEXEC_FILE)
    end
    color("32"); print("  Autoexec : replaced"); noreset(); print("")
    -- 9. Build client data + apply layout
    local cdata = {}
    for i, idx in ipairs(sel) do
        local p = pkgs[idx]; local L, T, R, B = grid_bounds(i, ns, sw, sh, off)
        su_exec("am force-stop " .. p); apply_layout(p, L, T, R, B)
        table.insert(cdata, {pkg=p, L=L, T=T, R=R, B=B, ps_idx_list=cpm[p], curr_ptr=1})
    end
    -- 10. Clear log, initial launch ALL clients
    su_exec("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
    hlog("--- Hopper Started ---")
    color("33"); print("Launching clients..."); noreset()
    for i, c in ipairs(cdata) do
        launch_client(c, ps_list, c.ps_idx_list[c.curr_ptr], i)
        c.curr_ptr = c.curr_ptr + 1
        if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
        if i < #cdata then sleep(DEFAULT_DELAY) end
    end
    -- 11. INLINE MAIN LOOP (sama persis v3.0)
    local hop_sec = hi * 60
    local elapsed = 0
    local quit = false
    while not quit do
        render(cdata, hi, "RUNNING")
        local key = read_key(1)
        if key and key:lower() == "q" then quit = true; break end
        elapsed = elapsed + 1
        -- Watchdog
        if elapsed % WATCHDOG_SEC == 0 then
            for i, c in ipairs(cdata) do
                if not is_running(c.pkg) then
                    hlog("Crash client " .. i .. ", reopening")
                    local ptr = c.curr_ptr - 1; if ptr < 1 then ptr = #c.ps_idx_list end
                    launch_client(c, ps_list, c.ps_idx_list[ptr], i)
                end
            end
        end
        -- Hop
        if hi > 0 and hop_sec > 0 and elapsed >= hop_sec then
            elapsed = 0
            hlog("--- Hop cycle ---")
            for i, c in ipairs(cdata) do
                launch_client(c, ps_list, c.ps_idx_list[c.curr_ptr], i)
                c.curr_ptr = c.curr_ptr + 1
                if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
                if i < #cdata then sleep(DEFAULT_DELAY) end
            end
        end
    end
    -- 12. Reset prompt (sama persis v3.0)
    render(cdata, hi, "STOPPED")
    print(""); border()
    local rst = ask("Reset & close semua Roblox? (y/n)")
    if rst and rst:lower() == "y" then
        print(""); color("33"); print("Resetting..."); noreset()
        local rf = io.open(AUTOEXEC_FILE, "w")
        if rf then
            rf:write(AUTOEXEC_RESTORE); rf:close()
            su_exec("chmod 644 " .. AUTOEXEC_FILE)
        else
            local e = AUTOEXEC_RESTORE:gsub("'", "'\\''")
            su_exec("echo '" .. e .. "' > " .. AUTOEXEC_FILE)
            su_exec("chmod 644 " .. AUTOEXEC_FILE)
        end
        su_exec("rm -f /sdcard/.auto_1.lua.bak 2>/dev/null")
        su_exec("rm -f " .. AUTOEXEC_FILE .. ".bak 2>/dev/null")
        print("  auto_1.lua : restored")
        for i, p in ipairs(pkgs) do
            local L, T, R, B = grid_bounds(i, tot, sw, sh, off)
            apply_layout(p, L, T, R, B)
        end
        print("  Layout     : restored (" .. tot .. " akun)")
        for _, p in ipairs(pkgs) do su_exec("am force-stop " .. p) end
        print("  Roblox     : " .. tot .. " closed")
        su_exec("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
        print(""); color("32"); print("Reset selesai!"); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================
-- [NEW] MENU 3: SETTINGS (prefix + cookie per-pkg)
-- ============================================
local function menu_settings()
    while true do
        cls(); color("33"); box_title("SETTINGS"); noreset(); print("")
        color("36")
        info("Prefix saat ini", CFG.pkg_prefix)
        noreset(); print("")

        -- Tampilkan akun per package
        local pkgs = detect_packages()
        if #pkgs > 0 then
            color("36")
            print(string.format(" %-16s  %-10s  %s", "Package", "Username", "Cookie"))
            print(string.rep("-", W)); noreset()
            for _, p in ipairs(pkgs) do
                local acc = CFG.accounts[p] or {}
                local has = acc.cookie and acc.cookie ~= ""
                local name = has and trunc(acc.name or "?", 10) or "-"
                local ck   = has and "✓ Set" or "✗ Kosong"
                color(has and "32" or "90")
                print(string.format(" %-16s  %-10s  %s", pkg_short(p), name, ck))
                noreset()
            end
            print(string.rep("-", W))
        end
        print("")
        border()
        print("1. Set package prefix")
        print("2. Set cookie per-package")
        print("3. Refresh semua akun (fetch ulang nama/id)")
        print("4. Kelola PS links")
        print("0. Kembali")
        border(); print("")
        local ch = ask("Pilih")
        if ch == nil or ch == "0" then break

        elseif ch == "1" then
            cls(); color("33"); box_title("SET PACKAGE PREFIX"); noreset(); print("")
            print("Prefix saat ini: " .. CFG.pkg_prefix)
            print("Contoh: com.roblox.  /  com.winter.  /  com.byfron.")
            print("")
            local inp = ask("Prefix baru (kosong=batal)")
            if inp and inp ~= "" then
                if inp:sub(-1) ~= "." then inp = inp .. "." end
                CFG.pkg_prefix = inp
                CFG.accounts = {} -- reset accounts saat prefix berubah
                cfg_save()
                color("32"); print("Prefix diset: " .. inp); noreset()
                local np = detect_packages()
                print(#np .. " package ditemukan dengan prefix baru.")
                sleep(2)
            end

        elseif ch == "2" then
            if #pkgs == 0 then
                color("31"); print("Tidak ada package! Cek prefix dulu."); noreset()
                sleep(2)
            else
                cls(); color("33"); box_title("SET COOKIE PER-PACKAGE"); noreset(); print("")
                print("Prefix: " .. CFG.pkg_prefix); print("")
                for i, p in ipairs(pkgs) do
                    local acc = CFG.accounts[p] or {}
                    local has = acc.cookie and acc.cookie ~= ""
                    color("36"); print("[" .. i .. "] " .. p)
                    color(has and "32" or "90")
                    print("    " .. (has and ("✓ " .. (acc.name or "?") .. " (ID: " .. (acc.id or "?") .. ")") or "✗ Belum diset"))
                    noreset()
                end
                print("")
                local ni = ask("Nomor package (0=batal)")
                local idx = tonumber(ni)
                if idx and idx >= 1 and idx <= #pkgs then
                    local p = pkgs[idx]
                    print(""); print("Paste cookie untuk: " .. p)
                    print("Format: cookie / nick:pass:cookie")
                    local raw = ask("Input")
                    local ck  = parse_cookie_input(raw)
                    if ck and ck ~= "" then
                        local acc = CFG.accounts[p] or {}
                        acc.cookie = ck
                        print("Mengambil info akun...")
                        local name, id, err = fetch_account(ck)
                        if name then
                            acc.name = name; acc.id = id
                            color("32"); print("✓ Akun: " .. name .. " (ID: " .. id .. ")")
                        elseif err == "curl" then
                            acc.name = nil; acc.id = nil
                            color("33"); print("! curl/SSL error — cookie TETAP disimpan")
                            print("  Jalankan: pkg install -y --reinstall curl")
                        else
                            acc.name = nil; acc.id = nil
                            color("31"); print("✗ Cookie tidak valid / expired")
                        end
                        noreset()
                        CFG.accounts[p] = acc
                        cfg_save()
                        sleep(2)
                    end
                end
            end

        elseif ch == "3" then
            if #pkgs == 0 then
                color("31"); print("Tidak ada package!"); noreset(); sleep(2)
            else
                print("")
                for _, p in ipairs(pkgs) do
                    local acc = CFG.accounts[p] or {}
                    if acc.cookie and acc.cookie ~= "" then
                        color("36"); io.write("Fetching: " .. pkg_short(p) .. "... "); noreset(); io.flush()
                        local name, id, err = fetch_account(acc.cookie)
                        if name then
                            acc.name = name; acc.id = id
                            color("32"); print("✓ " .. name)
                        elseif err == "curl" then
                            color("33"); print("! curl/SSL error — skip")
                        else
                            color("31"); print("✗ Invalid/expired")
                        end
                        noreset()
                        CFG.accounts[p] = acc
                    end
                end
                cfg_save()
                sleep(2)
            end
        elseif ch == "4" then
            -- Kelola PS links (baca/tulis PS_FILE_PATH)
            while true do
                cls(); color("33"); box_title("KELOLA PS LINKS"); noreset(); print("")
                -- Baca links saat ini
                local cur_links = {}
                local rf = io.open(PS_FILE_PATH, "r")
                if rf then
                    for line in rf:lines() do
                        local l = line:gsub("%c",""):gsub("%s+","")
                        if is_valid_ps_link(l) then table.insert(cur_links, l) end
                    end
                    rf:close()
                end
                if #cur_links == 0 then
                    color("90"); print("  (kosong)"); noreset()
                else
                    for i, l in ipairs(cur_links) do
                        print(string.format("  [%2d] %s", i, trunc(l, W-8)))
                    end
                end
                print(""); border()
                print("a. Tambah link")
                print("d. Hapus link")
                print("c. Hapus semua")
                print("0. Kembali")
                border(); print("")
                local po = ask("Pilih")
                if po == "0" or po == nil then break

                elseif po == "a" then
                    print(""); print("Paste PS links (1 per baris, kosong=selesai):")
                    local added, skipped = 0, 0
                    while true do
                        local line = ask("")
                        if not line or line == "" then break end
                        if is_valid_ps_link(line) then
                            table.insert(cur_links, line)
                            added = added + 1
                            color("32"); print("  ✓ [" .. #cur_links .. "] Ditambahkan"); noreset()
                        else
                            skipped = skipped + 1
                            color("31"); print("  ✗ Tidak valid (butuh https:// + code=)"); noreset()
                        end
                    end
                    -- Tulis ulang file
                    local wf = io.open(PS_FILE_PATH, "w")
                    if wf then
                        for _, l in ipairs(cur_links) do wf:write(l .. "\n") end
                        wf:close()
                    end
                    print(added .. " ditambahkan" .. (skipped > 0 and (", " .. skipped .. " dilewati") or ""))
                    sleep(1)

                elseif po == "d" then
                    if #cur_links == 0 then
                        print("Tidak ada link."); sleep(1)
                    else
                        local ni = ask("Hapus nomor (0=batal)")
                        local di = tonumber(ni)
                        if di and di >= 1 and di <= #cur_links then
                            table.remove(cur_links, di)
                            local wf = io.open(PS_FILE_PATH, "w")
                            if wf then
                                for _, l in ipairs(cur_links) do wf:write(l .. "\n") end
                                wf:close()
                            end
                            color("32"); print("Link #" .. di .. " dihapus."); noreset()
                        else
                            print("Batal.")
                        end
                        sleep(1)
                    end

                elseif po == "c" then
                    local cf2 = ask("Ketik 'hapus' untuk konfirmasi")
                    if cf2 == "hapus" then
                        local wf = io.open(PS_FILE_PATH, "w")
                        if wf then wf:write(""); wf:close() end
                        color("32"); print("Semua link dihapus."); noreset()
                        sleep(1)
                    end
                end
            end
        end

-- ============================================
-- MAIN MENU
-- ============================================
local function show_menu()
    cls(); print_logo()
    color("33"); box_title("LAYOUT & HOPPER TOOL"); noreset(); print("")
    color("36"); print("Prefix: " .. CFG.pkg_prefix); noreset(); print("")
    color("32"); print("MENU UTAMA"); noreset()
    print("1. Set Layout Roblox")
    print("2. Join Private Server (Auto Hop)")
    print("3. Settings (prefix, cookie)")
    print("0. Keluar"); print("")
end

local function main_menu()
    while true do
        show_menu()
        local c = ask("Pilih")
        if c == nil then break end
        if c == "1" then set_layout_roblox()
        elseif c == "2" then menu_join_server()
        elseif c == "3" then menu_settings()
        elseif c == "0" then cls(); print("Keluar!"); break end
    end
end

-- ============================================
-- ENTRY POINT
-- ============================================
cls(); print(""); print("Siap!"); sleep(1)
cfg_load()
main_menu()        lines[#lines+1] = "    [" .. string.format("%q", pkg) .. "] = {"
        lines[#lines+1] = "      cookie = " .. string.format("%q", acc.cookie or "") .. ","
        lines[#lines+1] = "      name   = " .. string.format("%q", acc.name   or "") .. ","
        lines[#lines+1] = "      id     = " .. string.format("%q", acc.id     or "") .. ","
        lines[#lines+1] = "    },"
    end
    lines[#lines+1] = "  },"
    lines[#lines+1] = "}"
    local f = io.open(CONFIG_FILE, "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    os.execute("chmod 600 '" .. CONFIG_FILE .. "'")
end

local function cfg_load()
    if not io.open(CONFIG_FILE, "r") then return end
    local ok, loaded = pcall(dofile, CONFIG_FILE)
    if ok and type(loaded) == "table" then
        if type(loaded.pkg_prefix) == "string" then CFG.pkg_prefix = loaded.pkg_prefix end
        if type(loaded.accounts)   == "table"  then CFG.accounts   = loaded.accounts   end
    end
end

-- ============================================
-- CORE HELPERS (sama persis v3.0)
-- ============================================
local function sleep(s) if s and s > 0 then os.execute("sleep " .. tostring(s)) end end

local function clean(str)
    if not str then return "-" end
    str = str:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("[\r\n\t]", ""):gsub("%c", "")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    return str ~= "" and str or "-"
end

local function sanitize_pkg(p)
    if not p then return nil end
    local s = p:gsub("[^%w%._]", "")
    return s ~= "" and s or nil
end

local function is_valid_ps_link(l)
    if not l or l == "" then return false end
    if not l:match("^https?://") and not l:match("^intent://") then return false end
    if not l:lower():match("code=") then return false end
    if l:match("[;|`$%(%){}%z]") then return false end
    return true
end

local function trunc(s, m)
    if not s then return "-" end
    if #s <= m then return s end
    return m > 2 and (s:sub(1, m-2) .. "..") or s:sub(1, m)
end

local function parse_selection(input, max)
    local sel, seen = {}, {}
    local a, b = input:match("^(%d+)%-(%d+)$")
    if a and b then
        for i = tonumber(a), tonumber(b) do
            if i >= 1 and i <= max and not seen[i] then table.insert(sel, i); seen[i] = true end
        end
        return sel
    end
    for n in input:gmatch("(%d+)") do
        local v = tonumber(n)
        if v and v >= 1 and v <= max and not seen[v] then table.insert(sel, v); seen[v] = true end
    end
    return sel
end

-- ============================================
-- UI (sama persis v3.0)
-- ============================================
local function color(c) io.write("\27[" .. c .. "m"); io.flush() end
local function noreset() io.write("\27[0m"); io.flush() end
local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end
local function border() print(string.rep("-", W)) end

local function box_title(t)
    local inner = math.max(W-2, #t+2)
    local pl = math.floor((inner-#t)/2)
    local pr = inner - #t - pl
    print("+" .. string.rep("-", inner) .. "+")
    print("|" .. string.rep(" ", pl) .. t .. string.rep(" ", pr) .. "|")
    print("+" .. string.rep("-", inner) .. "+")
end

local function info(l, v)
    local p = l .. ": "
    print(p .. trunc(v, math.max(W-#p, 4)))
end

local function print_logo()
    color("36")
    print([[ ░▒▓███████▓▒░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░
░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░    ░▒▓██▓▒░ 
 ░▒▓██████▓▒░░▒▓██████▓▒░ ░▒▓█▓▒░  ░▒▓██▓▒░   
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓██▓▒░     
       ░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░       
░▒▓███████▓▒░░▒▓████████▓▒░▒▓█▓▒░▒▓████████▓▒░]])
    noreset(); print("")
end

-- ============================================
-- INPUT (sama persis v3.0)
-- ============================================
local function ask(prompt)
    io.write(prompt .. " > "); io.flush()
    local tty = io.open("/dev/tty", "r")
    local r
    if tty then r = tty:read("*l"); tty:close() else r = io.read("*l") end
    if r == nil then sleep(2) end
    return r
end

local function read_key(t)
    local h = io.popen("bash -c 'read -t " .. (t or 1) .. " -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
end

-- ============================================
-- SYSTEM / ROOT (sama persis v3.0)
-- ============================================
local function su_cmd(cmd)
    local h = io.popen("su -c '" .. cmd:gsub("'", "'\\''") .. "' 2>&1")
    if not h then return "ERROR" end
    local r = h:read("*a"); h:close()
    return clean(r)
end

local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'", "'\\''") .. "' >/dev/null 2>&1")
end

-- ============================================
-- DETECTION
-- ============================================
local function detect_offset()
    local off = 0
    local st = su_cmd("dumpsys window | grep mStable | head -1")
    local v = st:match("mStable=%[%d+,(%d+)%]")
    if v then off = tonumber(v) or 0 end
    if off == 0 then
        local d = su_cmd("wm density"):match("(%d+)")
        off = d and math.ceil(24 * tonumber(d) / 160) or 48
    end
    return off
end

local function detect_screen()
    local off = detect_offset()
    local r = su_cmd("wm size")
    local sw, sh = r:match("(%d+)x(%d+)")
    if not sw then return nil, nil, off, r end
    sw, sh = tonumber(sw), tonumber(sh)
    return math.min(sw, sh), math.max(sw, sh), off, nil
end

-- [IMPROVED] detect_packages pakai CFG.pkg_prefix, bukan hardcode
local function detect_packages()
    local h = io.popen("pm list packages 2>/dev/null")
    if not h then return {} end
    local r = h:read("*a") or ""; h:close()
    local pkgs = {}
    local prefix = CFG.pkg_prefix
    for line in r:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p then
            p = sanitize_pkg(clean(p))
            if p and p:sub(1, #prefix) == prefix then
                table.insert(pkgs, p)
            end
        end
    end
    table.sort(pkgs)
    return pkgs
end

-- [IMPROVED] parse input cookie — support 2 format:
--   1. cookie only        → langsung nilai cookie
--   2. nick:pass:cookie   → ambil dari _|WARNING ke akhir
local function parse_cookie_input(input)
    if not input or input == "" then return nil end
    -- Cari dari _|WARNING ke akhir — selalu ada di cookie Roblox valid
    local cookie = input:match("(_|WARNING.+)$")
    if cookie then return cookie end
    -- Tidak ada _|WARNING — anggap input adalah cookie langsung
    return input
end

-- [IMPROVED] fetch nama + id akun dari Roblox API
local function fetch_account(cookie)
    if not cookie or cookie == "" then return nil, nil end
    local h = io.popen('curl -s --max-time 10 '
        .. '-H "Cookie: .ROBLOSECURITY=' .. cookie .. '" '
        .. '"https://users.roblox.com/v1/users/authenticated"')
    if not h then return nil, nil end
    local res = h:read("*a"); h:close()
    local name = res:match('"name":"([^"]+)"')
    local id   = res:match('"id":(%d+)')
    return name, id
end

-- ============================================
-- LAYOUT (sama persis v3.0)
-- ============================================
local function apply_layout(pkg, L, T, R, B)
    local pref = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
    su_exec("chmod 666 " .. pref)
    local args = {}
    for _, f in ipairs({
        {"app_cloner_current_window_left",   L},
        {"app_cloner_current_window_top",    T},
        {"app_cloner_current_window_right",  R},
        {"app_cloner_current_window_bottom", B},
    }) do
        table.insert(args,
            "-e 's/name=\\\"" .. f[1] .. "\\\" value=\\\"[^\\\"]*\\\"/name=\\\"" .. f[1] .. "\\\" value=\\\"" .. f[2] .. "\\\"/g'")
    end
    su_exec("sed -i " .. table.concat(args, " ") .. " " .. pref)
    su_exec("chmod 444 " .. pref)
end

local function grid_h(n, sh, off) return math.floor((sh-off)/n) end

local function grid_bounds(i, n, sw, sh, off)
    if n == 1 then return 0, 0, sw, sh end
    local gh = grid_h(n, sh, off); local row = i-1
    return 0, (row*gh)+off, sw, ((row+1)*gh)+off
end

-- ============================================
-- INLINE HOPPER HELPERS (sama persis v3.0)
-- ============================================
local function hlog(msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function is_running(pkg)
    local h = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- [IMPROVED] launch_client inject cookie per-client sebelum am start
local function inject_cookie(pkg)
    local acc = CFG.accounts[pkg]
    if not acc or not acc.cookie or acc.cookie == "" then return end
    local dir  = "/data/data/" .. pkg .. "/shared_prefs"
    local file = dir .. "/RobloxSharedPreferences.xml"
    local tmp  = "/tmp/hcookie.xml"
    local f = io.open(tmp, "w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">' .. acc.cookie .. "</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. file .. "'")
    su_exec("chmod 660 '" .. file .. "'")
    os.remove(tmp)
end

local function launch_client(c, ps_list, ps_idx, cnum)
    if not ps_list[ps_idx] then hlog("ERROR: PS " .. tostring(ps_idx) .. " OOB"); return end
    su_exec("am force-stop " .. c.pkg); sleep(1)
    inject_cookie(c.pkg)
    local raw = ps_list[ps_idx]
    local dp = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://", "")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. c.pkg
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    hlog("Client " .. cnum .. " -> PS " .. ps_idx)
end

-- ============================================
-- MONITOR (v3.0 + dashboard table di atas)
-- ============================================
local function fmt_elapsed(s)
    if s < 0 then s = 0 end
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); s = s%60
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

local function ts2sec(ts)
    local h, m, s = ts:match("(%d+):(%d+):(%d+)")
    return h and (tonumber(h)*3600 + tonumber(m)*60 + tonumber(s)) or 0
end

local function parse_log()
    local vis, cr = {}, {}
    local f = io.open(HOPPER_LOG, "r")
    if not f then return vis, cr end
    for line in f:lines() do
        local t, cn, ps = line:match("^(%d+:%d+:%d+) Client (%d+) %-> PS (%d+)")
        if t then
            local c = tonumber(cn)
            if not vis[c] then vis[c] = {} end
            table.insert(vis[c], {ps=tonumber(ps), sec=ts2sec(t), ts=t})
        end
        local ct, cc = line:match("^(%d+:%d+:%d+) Crash client (%d+)")
        if ct then cr[tonumber(cc)] = ct end
    end
    f:close()
    return vis, cr
end

local function ps_summary(cv, now)
    local pd = {}
    if not cv or #cv == 0 then return pd end
    for i, v in ipairs(cv) do
        local dur
        if i < #cv then
            dur = cv[i+1].sec - v.sec; if dur < 0 then dur = dur + 86400 end
        else
            dur = now - v.sec; if dur < 0 then dur = dur + 86400 end
        end
        local cur = (i == #cv)
        if not pd[v.ps] then
            pd[v.ps] = {joined=v.ts, elapsed=dur, hops=1, current=cur}
        else
            local d = pd[v.ps]; d.joined=v.ts; d.elapsed=d.elapsed+dur; d.hops=d.hops+1
            if cur then d.current = true end
        end
    end
    return pd
end

-- [IMPROVED] render: tambah dashboard table di atas (Package | UserId | Username | State)
local function pkg_short(pkg)
    local short = pkg:sub(#CFG.pkg_prefix + 1)
    return trunc(short ~= "" and short or pkg, 14)
end

local function render(cdata, hop_int, status)
    cls()
    color("33"); box_title("HOPPER MONITOR (Live)"); noreset(); print("")

    -- [NEW] Dashboard table: Package | UserId | Username | State
    color("36")
    print(string.format(" %-14s  %-10s  %-10s  %s",
        "Package", "UserId", "Username", "State"))
    print(string.rep("-", W))
    noreset()
    for i, c in ipairs(cdata) do
        local acc = CFG.accounts[c.pkg] or {}
        local uid  = acc.id   and trunc(acc.id,   10) or "-"
        local name = acc.name and trunc(acc.name,  10) or "-"
        local running = is_running(c.pkg)
        local state_str, state_col
        if status == "STOPPED" then
            state_str = "closed"; state_col = "90"
        elseif running then
            state_str = "● run";  state_col = "32"
        else
            state_str = "○ wait";  state_col = "33"
        end
        color("36"); io.write(string.format(" %-14s  ", pkg_short(c.pkg))); noreset()
        io.write(string.format("%-10s  %-10s  ", uid, name))
        color(state_col); print(state_str); noreset()
    end
    print(string.rep("-", W)); print("")

    -- Hop log table (sama persis v3.0)
    local vis, cr = parse_log()
    local now_s = os.date("%H:%M:%S"); local now = ts2sec(now_s)
    color("36")
    print(string.format(" %-2s  %-3s  %-9s  %-10s %s", "C", "PS", "Joined", "Elapsed", "Hops"))
    print(string.rep("-", W)); noreset()
    for i, c in ipairs(cdata) do
        local pd = ps_summary(vis[i], now)
        local cm = cr[i] and " !" or ""
        for _, pi in ipairs(c.ps_idx_list) do
            local d = pd[pi]
            if d then
                color(d.current and "32" or "36")
                print(string.format(" %-2d  %-3d  %-9s  %-10s %d%s",
                    i, pi, d.joined, fmt_elapsed(d.elapsed), d.hops, cm))
                noreset(); cm = ""
            else
                color("90")
                print(string.format(" %-2d  %-3d  %-9s  %-10s %d", i, pi, "-", "-", 0))
                noreset()
            end
        end
        if i < #cdata then color("90"); print(string.rep(".", W)); noreset() end
    end
    print(""); border(); color("36")
    print(hop_int > 0 and ("  Hop: " .. hop_int .. " menit") or "  Mode: Sekali join + Watchdog")
    print("  Waktu: " .. now_s); print("  Status: " .. (status or "RUNNING"))
    noreset(); border(); print("")
    color("90")
    for i, c in ipairs(cdata) do print("  " .. i .. ": " .. trunc(c.pkg, W-6)) end
    noreset(); print(""); color("33"); print("  Tekan [q] untuk Stop & Reset"); noreset()
end

-- ============================================
-- MENU 1: SET LAYOUT (sama persis v3.0)
-- ============================================
local function set_layout_roblox()
    cls(); color("33"); box_title("SET LAYOUT ROBLOX"); noreset(); print("")
    color("36"); print("Detecting..."); noreset()
    local sw, sh, off, err = detect_screen()
    if not sw then
        color("31"); print("Gagal baca resolusi!")
        if err then print("Output: " .. trunc(err, W-8)) end
        noreset(); print(""); ask("Enter"); return
    end
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then
        color("31"); print("Tidak ada Roblox! (prefix: " .. CFG.pkg_prefix .. ")")
        noreset(); print(""); ask("Enter"); return
    end
    border(); color("36")
    info("Packages  ", tostring(tot)); info("Resolusi  ", sw .. " x " .. sh)
    info("Offset    ", off .. " px"); info("Grid      ", "1 x " .. tot)
    info("Delay/akun", LAYOUT_DELAY .. " dtk"); noreset(); border()
    print(""); print("Offset " .. off .. "px auto.")
    local adj = ask("Ubah offset? (kosong=skip)")
    if adj and adj ~= "" then
        local no = tonumber(adj)
        if no and no >= 0 then off = no; print("Offset: " .. off .. "px") else print("Invalid") end
    end
    print(""); color("32"); print("Package:"); noreset()
    for i, p in ipairs(pkgs) do print(" " .. i .. ". " .. trunc(p, W-5)) end
    print("")
    local c = ask("Lanjut? (y/n)")
    if not c or c:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); border(); color("33"); print("Setup layout..."); noreset(); print("")
    for i = 1, tot do
        local p = pkgs[i]; local L, T, R, B = grid_bounds(i, tot, sw, sh, off)
        color("36"); print("[" .. i .. "/" .. tot .. "] " .. trunc(p, W-8)); noreset()
        su_exec("am force-stop " .. p); apply_layout(p, L, T, R, B)
        su_exec("am start --user 0 -n " .. p .. "/" .. ACTIVITY)
        print("  L=" .. L .. " T=" .. T .. " R=" .. R .. " B=" .. B)
        if i < tot then print("  Tunggu " .. LAYOUT_DELAY .. "s..."); sleep(LAYOUT_DELAY) end
    end
    print(""); border(); color("32"); print("SELESAI!"); noreset(); border(); print("")
    local cl = ask("Close semua? (y/n)")
    if cl and cl:lower() == "y" then
        for _, p in ipairs(pkgs) do su_exec("am force-stop " .. p) end
        color("32"); print(tot .. " ditutup."); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================
-- MENU 2: JOIN PS (sama persis v3.0 + cookie inject)
-- ============================================
local function load_ps_links()
    local f = io.open(PS_FILE_PATH, "r")
    if not f then
        local d = io.open(PS_FILE_PATH, "w")
        if d then
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH\n")
            d:write("https://www.roblox.com/games/123456?privateServerLinkCode=CONTOH2\n")
            d:close()
        end
        return nil, 0
    end
    local list, skip = {}, 0
    for line in f:lines() do
        local l = line:gsub("%c", ""):gsub("%s+", "")
        if l:lower():match("code=") then
            if is_valid_ps_link(l) then table.insert(list, l) else skip = skip + 1 end
        end
    end
    f:close()
    return list, skip
end

local function menu_join_server()
    cls(); color("33"); box_title("JOIN PRIVATE SERVER"); noreset(); print("")
    -- 1. Packages
    color("36"); print("Mencari Roblox... (prefix: " .. CFG.pkg_prefix .. ")"); noreset()
    local pkgs = detect_packages(); local tot = #pkgs
    if tot == 0 then
        color("31"); print("Tidak ada Roblox! Cek prefix di Menu 3.")
        noreset(); print(""); ask("Enter"); return
    end
    print("Ditemukan " .. tot .. " client:")
    for i, p in ipairs(pkgs) do print("  " .. i .. ". " .. trunc(p, W-6)) end
    border(); print("")
    -- 2. PS links
    local ps_list, skip = load_ps_links()
    if not ps_list then
        color("31"); print("File PS tidak ada! Dibuat: " .. PS_FILE_PATH)
        noreset(); print(""); ask("Enter"); return
    end
    if skip > 0 then color("33"); print(skip .. " link invalid dilewati"); noreset() end
    if #ps_list == 0 then
        color("31"); print("Tidak ada link valid!")
        noreset(); print(""); ask("Enter"); return
    end
    color("32"); print(#ps_list .. " link PS valid."); noreset(); print("")
    -- 3. Hop interval
    local hi = tonumber(ask("Hop tiap brp menit? (0=tidak)")) or 0
    if hi < 0 then hi = 0 end
    -- 4. Select clients
    print(""); print("Pilih client (cth: 1,2,3 / 1-3 / 2):"); print("")
    local si = ask("Client")
    if not si or si == "" then print("Batal."); sleep(1); return end
    local sel = parse_selection(si, tot)
    if #sel == 0 then color("31"); print("Invalid!"); noreset(); print(""); ask("Enter"); return end
    -- 5. Map PS
    local cpm = {}; print(""); color("36"); print("Pilih PS per client (max: " .. #ps_list .. ")"); noreset()
    for _, idx in ipairs(sel) do
        local p = pkgs[idx]
        local pi = ask("PS utk Client " .. idx .. " (cth: 1-5)")
        local ps = pi and pi ~= "" and parse_selection(pi, #ps_list) or {}
        if #ps == 0 then ps = {}; for j = 1, #ps_list do table.insert(ps, j) end end
        cpm[p] = ps
    end
    -- 6. Preview
    print(""); border(); color("36")
    info("Total PS", tostring(#ps_list))
    info("Client  ", table.concat(sel, ",") .. " (" .. #sel .. " akun)")
    info("Hopper  ", hi == 0 and "OFF (sekali join)" or (hi .. " menit"))
    info("Delay   ", DEFAULT_DELAY .. " dtk"); info("Script  ", "game2 loader")
    noreset(); border(); print("")
    local cf = ask("Launch? (y/n)")
    if not cf or cf:lower() ~= "y" then print("Batal."); sleep(1); return end
    print(""); color("33"); print("Preparing..."); noreset(); print("")
    -- 7. Screen
    local sw, sh, off, se = detect_screen()
    if not sw then color("31"); print("Gagal resolusi!"); noreset(); ask("Enter"); return end
    local ns = #sel
    color("36"); info("Screen", sw .. "x" .. sh); info("Offset", off .. "px")
    if ns == 1 then
        info("Layout", "fullscreen")
    else
        info("Layout", "split " .. ns .. " (" .. sw .. "x" .. grid_h(ns, sh, off) .. ")")
    end
    noreset(); print("")
    -- 8. Autoexec replace (sama persis v3.0)
    su_exec("mkdir -p " .. AUTOEXEC_DIR)
    su_exec("cp " .. AUTOEXEC_FILE .. " /sdcard/.auto_1.lua.bak 2>/dev/null")
    su_exec("rm -f " .. AUTOEXEC_FILE .. ".bak 2>/dev/null")
    local af = io.open(AUTOEXEC_FILE, "w")
    if af then
        af:write(JOIN_SCRIPT); af:close()
        su_exec("chmod 644 " .. AUTOEXEC_FILE)
    else
        local e = JOIN_SCRIPT:gsub("'", "'\\''")
        su_exec("echo '" .. e .. "' > " .. AUTOEXEC_FILE)
        su_exec("chmod 644 " .. AUTOEXEC_FILE)
    end
    color("32"); print("  Autoexec : replaced"); noreset(); print("")
    -- 9. Build client data + apply layout
    local cdata = {}
    for i, idx in ipairs(sel) do
        local p = pkgs[idx]; local L, T, R, B = grid_bounds(i, ns, sw, sh, off)
        su_exec("am force-stop " .. p); apply_layout(p, L, T, R, B)
        table.insert(cdata, {pkg=p, L=L, T=T, R=R, B=B, ps_idx_list=cpm[p], curr_ptr=1})
    end
    -- 10. Clear log, initial launch ALL clients
    su_exec("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
    hlog("--- Hopper Started ---")
    color("33"); print("Launching clients..."); noreset()
    for i, c in ipairs(cdata) do
        launch_client(c, ps_list, c.ps_idx_list[c.curr_ptr], i)
        c.curr_ptr = c.curr_ptr + 1
        if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
        if i < #cdata then sleep(DEFAULT_DELAY) end
    end
    -- 11. INLINE MAIN LOOP (sama persis v3.0)
    local hop_sec = hi * 60
    local elapsed = 0
    local quit = false
    while not quit do
        render(cdata, hi, "RUNNING")
        local key = read_key(1)
        if key and key:lower() == "q" then quit = true; break end
        elapsed = elapsed + 1
        -- Watchdog
        if elapsed % WATCHDOG_SEC == 0 then
            for i, c in ipairs(cdata) do
                if not is_running(c.pkg) then
                    hlog("Crash client " .. i .. ", reopening")
                    local ptr = c.curr_ptr - 1; if ptr < 1 then ptr = #c.ps_idx_list end
                    launch_client(c, ps_list, c.ps_idx_list[ptr], i)
                end
            end
        end
        -- Hop
        if hi > 0 and hop_sec > 0 and elapsed >= hop_sec then
            elapsed = 0
            hlog("--- Hop cycle ---")
            for i, c in ipairs(cdata) do
                launch_client(c, ps_list, c.ps_idx_list[c.curr_ptr], i)
                c.curr_ptr = c.curr_ptr + 1
                if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
                if i < #cdata then sleep(DEFAULT_DELAY) end
            end
        end
    end
    -- 12. Reset prompt (sama persis v3.0)
    render(cdata, hi, "STOPPED")
    print(""); border()
    local rst = ask("Reset & close semua Roblox? (y/n)")
    if rst and rst:lower() == "y" then
        print(""); color("33"); print("Resetting..."); noreset()
        local rf = io.open(AUTOEXEC_FILE, "w")
        if rf then
            rf:write(AUTOEXEC_RESTORE); rf:close()
            su_exec("chmod 644 " .. AUTOEXEC_FILE)
        else
            local e = AUTOEXEC_RESTORE:gsub("'", "'\\''")
            su_exec("echo '" .. e .. "' > " .. AUTOEXEC_FILE)
            su_exec("chmod 644 " .. AUTOEXEC_FILE)
        end
        su_exec("rm -f /sdcard/.auto_1.lua.bak 2>/dev/null")
        su_exec("rm -f " .. AUTOEXEC_FILE .. ".bak 2>/dev/null")
        print("  auto_1.lua : restored")
        for i, p in ipairs(pkgs) do
            local L, T, R, B = grid_bounds(i, tot, sw, sh, off)
            apply_layout(p, L, T, R, B)
        end
        print("  Layout     : restored (" .. tot .. " akun)")
        for _, p in ipairs(pkgs) do su_exec("am force-stop " .. p) end
        print("  Roblox     : " .. tot .. " closed")
        su_exec("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
        print(""); color("32"); print("Reset selesai!"); noreset()
    end
    print(""); ask("Enter")
end

-- ============================================
-- [NEW] MENU 3: SETTINGS (prefix + cookie per-pkg)
-- ============================================
local function menu_settings()
    while true do
        cls(); color("33"); box_title("SETTINGS"); noreset(); print("")
        color("36")
        info("Prefix saat ini", CFG.pkg_prefix)
        noreset(); print("")

        -- Tampilkan akun per package
        local pkgs = detect_packages()
        if #pkgs > 0 then
            color("36")
            print(string.format(" %-16s  %-10s  %s", "Package", "Username", "Cookie"))
            print(string.rep("-", W)); noreset()
            for _, p in ipairs(pkgs) do
                local acc = CFG.accounts[p] or {}
                local has = acc.cookie and acc.cookie ~= ""
                local name = has and trunc(acc.name or "?", 10) or "-"
                local ck   = has and "✓ Set" or "✗ Kosong"
                color(has and "32" or "90")
                print(string.format(" %-16s  %-10s  %s", pkg_short(p), name, ck))
                noreset()
            end
            print(string.rep("-", W))
        end
        print("")
        border()
        print("1. Set package prefix")
        print("2. Set cookie per-package")
        print("3. Refresh semua akun (fetch ulang nama/id)")
        print("0. Kembali")
        border(); print("")
        local ch = ask("Pilih")
        if ch == nil or ch == "0" then break

        elseif ch == "1" then
            cls(); color("33"); box_title("SET PACKAGE PREFIX"); noreset(); print("")
            print("Prefix saat ini: " .. CFG.pkg_prefix)
            print("Contoh: com.roblox.  /  com.winter.  /  com.byfron.")
            print("")
            local inp = ask("Prefix baru (kosong=batal)")
            if inp and inp ~= "" then
                if inp:sub(-1) ~= "." then inp = inp .. "." end
                CFG.pkg_prefix = inp
                CFG.accounts = {} -- reset accounts saat prefix berubah
                cfg_save()
                color("32"); print("Prefix diset: " .. inp); noreset()
                local np = detect_packages()
                print(#np .. " package ditemukan dengan prefix baru.")
                sleep(2)
            end

        elseif ch == "2" then
            if #pkgs == 0 then
                color("31"); print("Tidak ada package! Cek prefix dulu."); noreset()
                sleep(2)
            else
                cls(); color("33"); box_title("SET COOKIE PER-PACKAGE"); noreset(); print("")
                print("Prefix: " .. CFG.pkg_prefix); print("")
                for i, p in ipairs(pkgs) do
                    local acc = CFG.accounts[p] or {}
                    local has = acc.cookie and acc.cookie ~= ""
                    color("36"); print("[" .. i .. "] " .. p)
                    color(has and "32" or "90")
                    print("    " .. (has and ("✓ " .. (acc.name or "?") .. " (ID: " .. (acc.id or "?") .. ")") or "✗ Belum diset"))
                    noreset()
                end
                print("")
                local ni = ask("Nomor package (0=batal)")
                local idx = tonumber(ni)
                if idx and idx >= 1 and idx <= #pkgs then
                    local p = pkgs[idx]
                    print(""); print("Paste cookie untuk: " .. p)
                    print("Format: cookie / nick:pass:cookie")
                    local raw = ask("Input")
                    local ck  = parse_cookie_input(raw)
                    if ck and ck ~= "" then
                        local acc = CFG.accounts[p] or {}
                        acc.cookie = ck
                        print("Mengambil info akun...")
                        local name, id = fetch_account(ck)
                        if name then
                            acc.name = name; acc.id = id
                            color("32"); print("✓ Akun: " .. name .. " (ID: " .. id .. ")")
                        else
                            acc.name = nil; acc.id = nil
                            color("33"); print("! Gagal fetch — cookie mungkin expired")
                        end
                        noreset()
                        CFG.accounts[p] = acc
                        cfg_save()
                        sleep(2)
                    end
                end
            end

        elseif ch == "3" then
            if #pkgs == 0 then
                color("31"); print("Tidak ada package!"); noreset(); sleep(2)
            else
                print("")
                for _, p in ipairs(pkgs) do
                    local acc = CFG.accounts[p] or {}
                    if acc.cookie and acc.cookie ~= "" then
                        color("36"); io.write("Fetching: " .. pkg_short(p) .. "... "); noreset(); io.flush()
                        local name, id = fetch_account(acc.cookie)
                        if name then
                            acc.name = name; acc.id = id
                            color("32"); print("✓ " .. name)
                        else
                            color("33"); print("! Gagal")
                        end
                        noreset()
                        CFG.accounts[p] = acc
                    end
                end
                cfg_save()
                sleep(2)
            end
        end
    end
end

-- ============================================
-- MAIN MENU
-- ============================================
local function show_menu()
    cls(); print_logo()
    color("33"); box_title("LAYOUT & HOPPER TOOL"); noreset(); print("")
    color("36"); print("Prefix: " .. CFG.pkg_prefix); noreset(); print("")
    color("32"); print("MENU UTAMA"); noreset()
    print("1. Set Layout Roblox")
    print("2. Join Private Server (Auto Hop)")
    print("3. Settings (prefix, cookie)")
    print("0. Keluar"); print("")
end

local function main_menu()
    while true do
        show_menu()
        local c = ask("Pilih")
        if c == nil then break end
        if c == "1" then set_layout_roblox()
        elseif c == "2" then menu_join_server()
        elseif c == "3" then menu_settings()
        elseif c == "0" then cls(); print("Keluar!"); break end
    end
end

-- ============================================
-- ENTRY POINT
-- ============================================
cls(); print(""); print("Siap!"); sleep(1)
cfg_load()
main_menu()
