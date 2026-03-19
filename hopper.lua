-- PS Hopper Tool v3.3
-- Base: v3.2 | + Dynamic terminal width
-- Target: Termux + Root Android
-- ============================================

-- ============================================
-- TERMINAL WIDTH (auto-detect, fallback 50)
-- ============================================
local function get_term_width()
    local h = io.popen("tput cols 2>/dev/null")
    if h then
        local w = tonumber(h:read("*l")); h:close()
        if w and w >= 30 then return math.min(w, 120) end
    end
    return 50
end
local W = get_term_width()
local function col(frac) return math.max(4, math.floor(W * frac)) end

-- ============================================
-- PATHS & CONSTANTS
-- ============================================
local ACTIVITY      = "com.roblox.client.startup.ActivitySplash"
local PS_FILE_PATH  = "/sdcard/private_servers.txt"
local AUTOEXEC_DIR  = "/storage/emulated/0/RonixExploit/autoexec"
local AUTOEXEC_FILE = AUTOEXEC_DIR .. "/auto_1.lua"
local HOPPER_LOG    = "/sdcard/hopper_log.txt"
local JOIN_SCRIPT   = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/FnDXueyi/list/refs/heads/main/game2"))()'
local DEFAULT_DELAY = 20
local WATCHDOG_SEC  = 10

local HOME        = os.getenv("HOME") or "/data/data/com.termux/files/home"
local CONFIG_FILE = HOME .. "/.hopper_config.lua"

-- ============================================
-- CONFIG
-- ============================================
local CFG = {
    pkg_prefix   = "com.roblox.",
    accounts     = {},
    cookies      = {},
    idle_timeout = 300,
    delay_min    = 3,
    delay_max    = 7,
    autoexec_path    = "/storage/emulated/0/RonixExploit/autoexec/auto_1.lua",
    autoexec_script  = "",
    autoexec_restore = "",
    ps_links         = {},
    client_ps_map    = {},
}

local function cfg_save()
    local lines = { "return {" }
    lines[#lines+1] = "  pkg_prefix   = " .. string.format("%q", CFG.pkg_prefix) .. ","
    lines[#lines+1] = "  idle_timeout = " .. tostring(CFG.idle_timeout) .. ","
    lines[#lines+1] = "  delay_min    = " .. tostring(CFG.delay_min) .. ","
    lines[#lines+1] = "  delay_max    = " .. tostring(CFG.delay_max) .. ","
    lines[#lines+1] = "  autoexec_path    = " .. string.format("%q", CFG.autoexec_path) .. ","
    lines[#lines+1] = "  autoexec_script  = " .. string.format("%q", CFG.autoexec_script) .. ","
    lines[#lines+1] = "  autoexec_restore = " .. string.format("%q", CFG.autoexec_restore) .. ","
    lines[#lines+1] = "  ps_links = {"
    for _, l in ipairs(CFG.ps_links) do
        lines[#lines+1] = "    " .. string.format("%q", l) .. ","
    end
    lines[#lines+1] = "  },"
    lines[#lines+1] = "  client_ps_map = {"
    for pkg, plist in pairs(CFG.client_ps_map) do
        lines[#lines+1] = "    [" .. string.format("%q", pkg) .. "] = {"
            .. table.concat(plist, ",") .. "},"
    end
    lines[#lines+1] = "  },"
    lines[#lines+1] = "  cookies = {"
    for _, ck in ipairs(CFG.cookies) do
        lines[#lines+1] = "    { cookie=" .. string.format("%q", ck.cookie or "")
            .. ", name=" .. string.format("%q", ck.name or "")
            .. ", id=" .. string.format("%q", ck.id or "") .. " },"
    end
    lines[#lines+1] = "  },"
    lines[#lines+1] = "  accounts = {"
    for pkg, acc in pairs(CFG.accounts) do
        lines[#lines+1] = "    [" .. string.format("%q", pkg) .. "] = {"
            .. " cookie=" .. string.format("%q", acc.cookie or "")
            .. ", name=" .. string.format("%q", acc.name or "")
            .. ", id=" .. string.format("%q", acc.id or "") .. " },"
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
    if not ok or type(loaded) ~= "table" then return end
    local keys = {"pkg_prefix","idle_timeout","delay_min","delay_max",
        "autoexec_path","autoexec_script","autoexec_restore",
        "ps_links","client_ps_map","cookies","accounts"}
    for _, k in ipairs(keys) do
        if loaded[k] ~= nil then CFG[k] = loaded[k] end
    end
end

-- ============================================
-- LOG
-- ============================================
local function hlog(level, msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then f:write(string.format("[%s] %s %s\n", level, os.date("%H:%M:%S"), msg)); f:close() end
end
local function linfo(m) hlog("INFO", m) end
local function lwarn(m) hlog("WARN", m) end
local function lerror(m) hlog("ERROR", m) end

-- ============================================
-- CORE HELPERS
-- ============================================
local function sleep(s) if s and s > 0 then os.execute("sleep " .. math.floor(s)) end end

local function clean(str)
    if not str then return "" end
    str = str:gsub("\27%[[%d;]*[A-Za-z]",""):gsub("[\r\n\t]",""):gsub("%c","")
    return str:gsub("^%s+",""):gsub("%s+$","")
end

local function sanitize_pkg(p)
    if not p then return nil end
    local s = p:gsub("[^%w%._]","")
    return s ~= "" and s or nil
end

local function is_valid_ps_link(l)
    if not l or l == "" then return false end
    if not l:match("^https?://") and not l:match("^intent://") then return false end
    local lower = l:lower()
    if not lower:match("code=") and not lower:match("share%?code=") then return false end
    if l:match("[;|`$%(%){}%z]") then return false end
    return true
end

local function is_share_url(l)
    return l and l:match("roblox%.com/share%?code=") ~= nil
end

local function trunc(s, max)
    if not s then return "" end
    s = tostring(s)
    if max <= 3 then return s:sub(1, max) end
    if #s <= max then return s end
    return s:sub(1, max-1) .. "…"
end

local function rpad(s, len)
    s = tostring(s or "")
    if #s >= len then return trunc(s, len) end
    return s .. string.rep(" ", len - #s)
end

local function parse_selection(input, max)
    local sel, seen = {}, {}
    local a, b = input:match("^(%d+)%-(%d+)$")
    if a and b then
        for i = tonumber(a), math.min(tonumber(b), max) do
            if not seen[i] then table.insert(sel, i); seen[i]=true end
        end
        return sel
    end
    for n in input:gmatch("(%d+)") do
        local v = tonumber(n)
        if v and v>=1 and v<=max and not seen[v] then
            table.insert(sel, v); seen[v]=true
        end
    end
    return sel
end

-- ============================================
-- UI PRIMITIVES
-- ============================================
local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end

local function hr()
    print("\27[33m" .. string.rep("─", W) .. "\27[0m")
end
local function sep()
    print("\27[2m" .. string.rep("╌", W) .. "\27[0m")
end

local function center(text)
    local plain = text:gsub("\27%[[%d;]*[A-Za-z]","")
    local pad = math.max(0, math.floor((W - #plain) / 2))
    return string.rep(" ", pad) .. text
end

local function ask(prompt)
    if prompt and prompt ~= "" then
        io.write("\27[36m  ❯ \27[0m" .. prompt .. ": ")
    else
        io.write("\27[36m  ❯ \27[0m")
    end
    io.flush()
    local tty = io.open("/dev/tty","r")
    local r
    if tty then r = tty:read("*l"); tty:close()
    else r = io.read("*l") end
    if r == nil then sleep(1); return nil end
    return r:gsub("^%s+",""):gsub("%s+$","")
end

local function read_key(t)
    local h = io.popen("bash -c 'read -t "..(t or 1)
        .." -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
end

-- ============================================
-- SYSTEM / ROOT
-- ============================================
local function su_cmd(cmd)
    local h = io.popen("su -c '"..cmd:gsub("'","'\\''").."' 2>&1")
    if not h then return "" end
    local r = h:read("*a"); h:close(); return clean(r)
end

local function su_exec(cmd)
    os.execute("su -c '"..cmd:gsub("'","'\\''").."' >/dev/null 2>&1")
end

-- ============================================
-- DETECTION
-- ============================================
local function detect_offset()
    local st = su_cmd("dumpsys window | grep mStable | head -1")
    local v = st:match("mStable=%[%d+,(%d+)%]")
    if v then return tonumber(v) or 0 end
    local d = su_cmd("wm density"):match("(%d+)")
    return d and math.ceil(24 * tonumber(d) / 160) or 48
end

local function detect_screen()
    local off = detect_offset()
    local r = su_cmd("wm size")
    local sw, sh = r:match("(%d+)x(%d+)")
    if not sw then return nil, nil, off end
    sw, sh = tonumber(sw), tonumber(sh)
    return math.min(sw,sh), math.max(sw,sh), off
end

local function detect_packages()
    local h = io.popen("pm list packages 2>/dev/null")
    if not h then return {} end
    local out = h:read("*a") or ""; h:close()
    local pkgs = {}
    local prefix = CFG.pkg_prefix
    for line in out:gmatch("[^\r\n]+") do
        local p = sanitize_pkg(clean(line:match("package:(.+)")))
        if p and p:sub(1,#prefix) == prefix then table.insert(pkgs, p) end
    end
    table.sort(pkgs); return pkgs
end

local function pkg_short(pkg)
    local s = pkg:sub(#CFG.pkg_prefix + 1)
    return s ~= "" and s or pkg
end

-- ============================================
-- COOKIE HELPERS
-- ============================================
local function parse_cookie_input(input)
    if not input or input == "" then return nil end
    return input:match("(_|WARNING.+)$") or input
end

local function extract_cookie_from_app(pkg)
    local pref = "/data/data/"..pkg.."/shared_prefs/RobloxSharedPreferences.xml"
    local out = su_cmd("cat '"..pref.."' 2>/dev/null")
    if not out or out == "" or out == "-" then return nil end
    local cookie = out:match('name="%.ROBLOSECURITY">([^<]+)<')
    return (cookie and #cookie > 20) and cookie or nil
end

local function fetch_account(cookie)
    if not cookie or cookie == "" then return nil, nil, "empty" end
    local h = io.popen('curl -s --insecure --max-time 10 '
        ..'-H "Cookie: .ROBLOSECURITY='..cookie..'" '
        ..'"https://users.roblox.com/v1/users/authenticated" 2>&1')
    if not h then return nil, nil, "curl" end
    local res = h:read("*a"); h:close()
    if res:match("CANNOT LINK") or res:match("cannot locate symbol") or res:match("^curl:") then
        return nil, nil, "curl"
    end
    local name = res:match('"name":"([^"]+)"')
    local id   = res:match('"id":(%d+)')
    if name and id then return name, id, nil end
    return nil, nil, "invalid"
end

-- ============================================
-- LAYOUT
-- ============================================
local function apply_layout(pkg, L, T, R, B)
    local pref = "/data/data/"..pkg.."/shared_prefs/"..pkg.."_preferences.xml"
    su_exec("chmod 666 "..pref)
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
    su_exec("sed -i "..table.concat(args," ").." "..pref)
    su_exec("chmod 444 "..pref)
end

local function grid_h(n, sh, off) return math.floor((sh-off)/n) end
local function grid_bounds(i, n, sw, sh, off)
    if n == 1 then return 0, 0, sw, sh end
    local gh = grid_h(n, sh, off)
    return 0, ((i-1)*gh)+off, sw, (i*gh)+off
end

-- ============================================
-- INLINE HOPPER HELPERS
-- ============================================
local function is_running(pkg)
    local h = io.popen("su -c 'pidof "..pkg.."' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

local function inject_cookie(pkg)
    local acc = CFG.accounts[pkg]
    if not acc or not acc.cookie or acc.cookie == "" then return end
    local dir  = "/data/data/"..pkg.."/shared_prefs"
    local file = dir.."/RobloxSharedPreferences.xml"
    local tmp  = "/tmp/hcookie.xml"
    local f = io.open(tmp,"w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">'..acc.cookie.."</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '"..dir.."'")
    su_exec("cp '"..tmp.."' '"..file.."'")
    su_exec("chmod 660 '"..file.."'")
    os.remove(tmp)
end

local function launch_client(c, ps_list, ps_idx, cnum, ps_total)
    if not ps_list[ps_idx] then lerror("Client "..cnum..": PS OOB"); return end
    su_exec("am force-stop "..c.pkg); sleep(1)
    inject_cookie(c.pkg)
    local raw = ps_list[ps_idx]
    local dp = raw:match("^intent://(.-)#Intent") or raw:gsub("^https?://","")
    su_exec('am start --user 0 "intent://'..dp
        ..'#Intent;scheme=https;package='..c.pkg
        ..';action=android.intent.action.VIEW;end"')
    linfo(string.format("Client %d -> PS %d/%d", cnum, ps_idx, ps_total or ps_idx))
end

-- ============================================
-- SHARE URL RESOLVE
-- ============================================
local function get_csrf(cookie)
    local h = io.popen('curl -s --insecure --max-time 10 -X POST '
        ..'-H "Cookie: .ROBLOSECURITY='..cookie..'" -D - '
        ..'"https://auth.roblox.com/v1/logout" 2>/dev/null')
    if not h then return nil end
    local res = h:read("*a"); h:close()
    local token = res:match("[Xx]%-[Cc][Ss][Rr][Ff]%-[Tt]oken: ([^\r\n]+)")
    return token and clean(token) or nil
end

local function resolve_share_url(url, cookie)
    if not cookie or cookie == "" then return nil, nil, "no_cookie" end
    linfo("Resolving: "..trunc(url, 40))
    local csrf = get_csrf(cookie)
    local csrf_h = csrf and ('-H "X-CSRF-Token: '..csrf..'" ') or ""
    local body = '{"shareLink":"'..url..'"}'
    local h = io.popen('curl -s --insecure --max-time 15 -X POST '
        ..csrf_h
        ..'-H "Content-Type: application/json" '
        ..'-H "Cookie: .ROBLOSECURITY='..cookie..'" '
        .."-d '"..body.."' "
        ..'"https://apis.roblox.com/sharelinks/v1/resolve" 2>/dev/null')
    if not h then return nil, nil, "curl" end
    local res = h:read("*a"); h:close()
    local place_id  = res:match('"placeId":(%d+)')
    local link_code = res:match('"linkCode":"([^"]+)"')
    if place_id and link_code then return place_id, link_code, nil end
    return nil, nil, "failed"
end

local function resolve_all(ps_list, cookie)
    local resolved = {}
    local share_count = 0
    for _, l in ipairs(ps_list) do if is_share_url(l) then share_count = share_count + 1 end end
    if share_count == 0 then return ps_list end
    if not cookie or cookie == "" then
        print("[WARN] Share URL ada tapi tidak ada cookie — skip resolve")
        return ps_list
    end
    print("[INFO] Resolving "..share_count.." share URL(s)...")
    for i, l in ipairs(ps_list) do
        if is_share_url(l) then
            local pid, lcode, err = resolve_share_url(l, cookie)
            if pid and lcode then
                resolved[i] = "https://www.roblox.com/games/"..pid
                    .."?privateServerLinkCode="..lcode
                print("[OK] PS "..i.." resolved")
            else
                resolved[i] = l
                print("[ERR] PS "..i.." gagal ("..(err or "?")..")")
            end
            sleep(1)
        else
            resolved[i] = l
        end
    end
    return resolved
end

-- ============================================
-- MONITOR / RENDER
-- ============================================
local function fmt_elapsed(s)
    if s < 0 then s = 0 end
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); s = s%60
    if h > 0 then return string.format("%dh%dm", h, m)
    elseif m > 0 then return string.format("%dm%ds", m, s)
    else return string.format("%ds", s) end
end

local function ts2sec(ts)
    local h, m, s = ts:match("(%d+):(%d+):(%d+)")
    return h and (tonumber(h)*3600+tonumber(m)*60+tonumber(s)) or 0
end

local function parse_log()
    local vis, cr = {}, {}
    local f = io.open(HOPPER_LOG,"r")
    if not f then return vis, cr end
    for line in f:lines() do
        local t, cn, ps = line:match("%[INFO%] (%d+:%d+:%d+) Client (%d+) %-> PS (%d+)")
        if t then
            local c = tonumber(cn)
            if not vis[c] then vis[c] = {} end
            table.insert(vis[c], {ps=tonumber(ps), sec=ts2sec(t), ts=t})
        end
        local ct, cc = line:match("%[WARN%] (%d+:%d+:%d+) Crash client (%d+)")
        if ct then cr[tonumber(cc)] = ct end
    end
    f:close(); return vis, cr
end

local function ps_summary(cv, now)
    local pd = {}
    if not cv or #cv == 0 then return pd end
    local n = #cv
    for i, v in ipairs(cv) do
        local dur
        if i < n then dur = cv[i+1].sec - v.sec; if dur<0 then dur=dur+86400 end
        else dur = now - v.sec; if dur<0 then dur=dur+86400 end end
        local cur = (i == n)
        if not pd[v.ps] then
            pd[v.ps] = {joined=v.ts, elapsed=dur, hops=1, current=cur}
        else
            local d = pd[v.ps]; d.joined=v.ts; d.elapsed=d.elapsed+dur; d.hops=d.hops+1
            if cur then d.current = true end
        end
    end
    return pd
end

local function render(cdata, hi, status, ps_total, idle_timers)
    W = get_term_width()
    cls(); hr()
    print(center("\27[1mHOPPER MONITOR\27[0m"))
    hr(); print("")

    local now_s = os.date("%H:%M:%S")
    local now   = ts2sec(now_s)
    local vis, cr = parse_log()

    -- Kolom proporsional
    local c_pkg  = col(0.26)
    local c_user = col(0.18)
    local c_ps   = math.max(5, col(0.07))
    local c_el   = math.max(7, col(0.12))
    local c_hops = math.max(4, col(0.07))
    local c_st   = math.max(6, W - c_pkg - c_user - c_ps - c_el - c_hops - 12)

    -- Header
    print(string.format("\27[2m %-*s  %-*s  %-*s  %-*s  %-*s  %s\27[0m",
        c_pkg,"Package", c_user,"Username", c_ps,"PS",
        c_el,"Elapsed", c_hops,"Hops", "State"))
    print("\27[2m"..string.rep("─",W).."\27[0m")

    for i, c in ipairs(cdata) do
        local acc  = CFG.accounts[c.pkg] or {}
        local name = trunc(acc.name or "-", c_user)
        local pd   = ps_summary(vis[i], now)
        local crash = cr[i] and "\27[31m!\27[0m" or ""
        local idle_t = idle_timers and idle_timers[i] or 0

        -- cari PS aktif
        local cur_ps, cur_d
        for _, pi in ipairs(c.ps_idx_list) do
            local d = pd[pi]; if d and d.current then cur_ps=pi; cur_d=d; break end
        end

        local ps_str  = cur_ps and tostring(cur_ps) or "-"
        local el_str  = cur_d  and fmt_elapsed(cur_d.elapsed) or "-"
        local hop_str = cur_d  and tostring(cur_d.hops) or "0"

        -- idle warning
        local idle_w = ""
        if idle_t > 0 and idle_t >= CFG.idle_timeout - 30 and is_running(c.pkg) then
            idle_w = " \27[33m⚑"..(CFG.idle_timeout - idle_t).."s\27[0m"
        end

        local run = is_running(c.pkg)
        local st_col, st_str
        if status == "STOPPED" then st_str="closed"; st_col="90"
        elseif run then st_str="● run"..idle_w; st_col="32"
        else st_str="○ off"; st_col="33" end

        print(string.format(
            " \27[36m%-*s\27[0m  \27[2m%-*s\27[0m  %-*s  %-*s  %-*s  \27[%sm%s\27[0m%s",
            c_pkg, rpad(pkg_short(c.pkg), c_pkg),
            c_user, rpad(name, c_user),
            rpad(ps_str, c_ps),
            rpad(el_str, c_el),
            rpad(hop_str, c_hops),
            st_col, trunc(st_str, c_st),
            crash))
    end

    print("\27[2m"..string.rep("─",W).."\27[0m"); print("")

    -- Detail hop history (semua PS per client)
    local c_h_ps = math.max(5, col(0.07))
    local c_h_jn = math.max(8, col(0.12))
    local c_h_el = math.max(8, col(0.12))
    print(string.format("\27[2m %-3s  %-*s  %-*s  %-*s  %s\27[0m",
        "C", c_h_ps,"PS", c_h_jn,"Joined", c_h_el,"Elapsed", "Hops"))
    print("\27[2m"..string.rep("·",W).."\27[0m")

    for i, c in ipairs(cdata) do
        local pd = ps_summary(vis[i], now)
        local cm = cr[i] and "\27[31m !\27[0m" or ""
        for _, pi in ipairs(c.ps_idx_list) do
            local d = pd[pi]
            if d then
                local cc = d.current and "32" or "36"
                print(string.format("\27[%sm %-3d  %-*s  %-*s  %-*s  %d\27[0m%s",
                    cc, i,
                    c_h_ps, rpad(tostring(pi), c_h_ps),
                    c_h_jn, rpad(trunc(d.joined,c_h_jn), c_h_jn),
                    c_h_el, rpad(fmt_elapsed(d.elapsed), c_h_el),
                    d.hops, cm))
                cm = ""
            else
                print(string.format("\27[90m %-3d  %-*s  %-*s  %-*s  0\27[0m",
                    i, c_h_ps, rpad(tostring(pi),c_h_ps),
                    c_h_jn, "-", c_h_el, "-"))
            end
        end
        if i < #cdata then print("\27[90m"..string.rep("·",W).."\27[0m") end
    end

    print(""); sep()
    print(string.format("  \27[2mMode\27[0m %s  \27[2mIdle\27[0m %ds  \27[2mWaktu\27[0m %s",
        hi > 0 and (hi.."m/hop") or "watchdog",
        CFG.idle_timeout, now_s))
    sep(); print("")
    print("  \27[33m[q] Stop & Reset\27[0m"); print("")
end

-- ============================================
-- DASHBOARD HEADER (menu pages)
-- ============================================
local function draw_header(pkgs)
    W = get_term_width()
    cls(); hr()
    print(center("\27[1m🎮 ROBLOX SERVER HOPPER v3.3\27[0m"))
    hr(); print("")

    pkgs = pkgs or detect_packages()

    -- Info bar
    print(string.format("  \27[2mPrefix\27[0m \27[36m%s\27[0m  \27[2mPkg\27[0m %d  \27[2mPS\27[0m %d  \27[2mCK\27[0m %d  \27[2mIdle\27[0m %ds",
        trunc(CFG.pkg_prefix, col(0.25)),
        #pkgs, #CFG.ps_links, #CFG.cookies, CFG.idle_timeout))
    print("")

    if #pkgs > 0 then
        local c_pkg  = col(0.30)
        local c_user = col(0.22)
        local c_ck   = W - c_pkg - c_user - 8
        print(string.format("\27[2m %-*s  %-*s  %s\27[0m",
            c_pkg,"Package", c_user,"Username", "Cookie"))
        print("\27[2m"..string.rep("─",W).."\27[0m")
        for _, p in ipairs(pkgs) do
            local acc = CFG.accounts[p] or {}
            local has = acc.cookie and acc.cookie ~= ""
            print(string.format(" \27[36m%-*s\27[0m  \27[2m%-*s\27[0m  %s",
                c_pkg, rpad(pkg_short(p), c_pkg),
                c_user, rpad(has and trunc(acc.name or "?", c_user) or "-", c_user),
                has and "\27[32m✓\27[0m" or "\27[90m✗\27[0m"))
        end
        print("\27[2m"..string.rep("─",W).."\27[0m")
    end
    print("")
end

-- ============================================
-- MAIN MENU
-- ============================================
local function main_menu()
    local pkgs = detect_packages()
    draw_header(pkgs)
    local can_start = #pkgs > 0 and #CFG.ps_links > 0

    local function item(n, label, info)
        local s = info and ("\27[2m("..info..")\27[0m") or ""
        print(string.format("  \27[1m%-3s\27[0m %-22s %s", n..".", label, s))
    end

    item("1",  "Set package prefix",   trunc(CFG.pkg_prefix, col(0.20)))
    item("2",  "Cookie Manager",       #CFG.cookies.." cookie")
    item("3",  "Kelola PS links",      #CFG.ps_links.." link")
    item("4",  "Per-client PS map",    next(CFG.client_ps_map) and "✓ set" or "– kosong")
    item("5",  "Set delay",            CFG.delay_min.."-"..CFG.delay_max.."m")
    item("6",  "Set autoexec",         CFG.autoexec_script ~= "" and "✓ set" or "–")
    item("7",  "Idle timeout",         CFG.idle_timeout.."s")
    item("8",  "Layout manager",       #pkgs.." pkg")
    item("9",  "Lihat config")
    print("")
    if can_start then
        print("  \27[32m\27[1m10. ▶  START HOPPER\27[0m")
    else
        print("  \27[2m10.   START HOPPER\27[0m")
        if #pkgs == 0 then print("  \27[31m     ⚠  Tidak ada package ("..CFG.pkg_prefix..")\27[0m") end
        if #CFG.ps_links == 0 then print("  \27[31m     ⚠  Tambahkan PS link dulu\27[0m") end
    end
    item("0",  "Keluar")
    print("")

    local ch = ask("")
    if     ch=="1"  then return "menu_prefix"
    elseif ch=="2"  then return "menu_cookie_mgr"
    elseif ch=="3"  then return "menu_ps"
    elseif ch=="4"  then return "menu_ps_map"
    elseif ch=="5"  then return "menu_delay"
    elseif ch=="6"  then return "menu_autoexec"
    elseif ch=="7"  then return "menu_idle"
    elseif ch=="8"  then return "menu_layout"
    elseif ch=="9"  then return "menu_config"
    elseif ch=="10" then return can_start and "start" or "main"
    elseif ch=="0"  then return "exit"
    end
    return "main"
end

-- ============================================
-- MENU: PREFIX
-- ============================================
local function menu_prefix()
    draw_header()
    print("  \27[1mSET PACKAGE PREFIX\27[0m"); print("")
    print("  Saat ini : \27[36m"..CFG.pkg_prefix.."\27[0m")
    print("  Contoh   : com.roblox.  /  com.winter.")
    print("")
    local pkgs = detect_packages()
    if #pkgs > 0 then
        print("  Package terdeteksi ("..#pkgs.."):")
        for i, p in ipairs(pkgs) do
            print(string.format("    \27[2m[%d]\27[0m %s", i, trunc(p, W-8)))
        end
    end
    print("")
    local inp = ask("Prefix baru (Enter=batal)")
    if not inp or inp == "" then return end
    if inp:sub(-1) ~= "." then inp = inp.."." end
    CFG.pkg_prefix = inp; CFG.accounts = {}; CFG.client_ps_map = {}
    cfg_save()
    local np = detect_packages()
    print("\27[32m[OK]\27[0m Prefix: "..inp.."  →  "..#np.." package")
    sleep(2)
end

-- ============================================
-- MENU: COOKIE MANAGER
-- ============================================
local function draw_cookie_table()
    local c_no   = 4
    local c_name = col(0.22)
    local c_uid  = col(0.18)
    local c_st   = W - c_no - c_name - c_uid - 8
    print(string.format("\27[2m %-*s  %-*s  %-*s  %s\27[0m",
        c_no,"No", c_name,"Username", c_uid,"UserID", "Status"))
    print("\27[2m"..string.rep("─",W).."\27[0m")
    if #CFG.cookies == 0 then print("  \27[90m(belum ada cookie)\27[0m"); return end
    for i, ck in ipairs(CFG.cookies) do
        local has = ck.name and ck.name ~= ""
        print(string.format(" \27[%sm%-*d  %-*s  %-*s  %s\27[0m",
            has and "32" or "33",
            c_no, i,
            c_name, rpad(trunc(ck.name or "-", c_name), c_name),
            c_uid,  rpad(trunc(ck.id   or "-", c_uid),  c_uid),
            has and "✓ valid" or "? unverified"))
    end
    print("\27[2m"..string.rep("─",W).."\27[0m")
end

local function menu_cookie_mgr()
    while true do
        draw_header()
        print("  \27[1mCOOKIE MANAGER\27[0m"); print("")
        draw_cookie_table(); print("")

        -- Inject mapping
        local pkgs = detect_packages()
        if #pkgs > 0 then
            local c_pkg = col(0.33)
            print(string.format("\27[2m %-*s  %s\27[0m", c_pkg,"Package","Injected"))
            print("\27[2m"..string.rep("─",W).."\27[0m")
            for i, p in ipairs(pkgs) do
                local acc = CFG.accounts[p] or {}
                local has = acc.cookie and acc.cookie ~= ""
                print(string.format(" \27[36m%-*s\27[0m  %s",
                    c_pkg, rpad(pkg_short(p), c_pkg),
                    has and ("\27[32m✓ "..trunc(acc.name or "?", W-c_pkg-6).."\27[0m")
                         or "\27[90m✗ belum\27[0m"))
            end
            print("\27[2m"..string.rep("─",W).."\27[0m"); print("")
        end

        sep()
        print("  \27[1m1.\27[0m Add cookie       \27[1m2.\27[0m Delete  (1 / 1,2,3 / 1-5 / all)")
        print("  \27[1m3.\27[0m Validate         \27[1m4.\27[0m Inject all  (ck[1]→pkg[1], dst)")
        print("  \27[1m5.\27[0m Inject spesifik  \27[1m0.\27[0m Kembali")
        sep(); print("")

        local ch = ask("")
        if ch == "0" or ch == nil then break

        elseif ch == "1" then
            draw_header()
            print("  \27[1mADD COOKIE\27[0m"); print("")
            print("  Format: cookie langsung  atau  nick:pass:cookie")
            print("  Baris kosong = selesai"); print("")
            local added = 0
            while true do
                local raw = ask("")
                if not raw or raw == "" then break end
                local ck = parse_cookie_input(raw)
                if ck then
                    local dup = false
                    for _, e in ipairs(CFG.cookies) do if e.cookie == ck then dup=true; break end end
                    if dup then print("  \27[33m[WARN]\27[0m Duplikat — skip")
                    else
                        local entry = {cookie=ck, name="", id=""}
                        io.write("  \27[36m[INFO]\27[0m Fetching... "); io.flush()
                        local name, id, err = fetch_account(ck)
                        if name then
                            entry.name=name; entry.id=id
                            print("\27[32m[OK]\27[0m "..name.." (ID: "..id..")")
                        elseif err == "curl" then print("\27[33m[WARN]\27[0m curl error — disimpan")
                        else print("\27[31m[ERR]\27[0m Invalid/expired — disimpan") end
                        table.insert(CFG.cookies, entry); added=added+1; cfg_save()
                    end
                else print("  \27[31m[ERR]\27[0m Format tidak valid") end
            end
            print("\n  \27[32m[OK]\27[0m "..added.." cookie ditambahkan"); sleep(1)

        elseif ch == "2" then
            if #CFG.cookies == 0 then print("  Tidak ada cookie"); sleep(1)
            else
                local inp = ask("Hapus (1 / 1,2,3 / 1-5 / all)")
                if inp then
                    local to_del
                    if inp == "all" then
                        to_del = {}; for i=1,#CFG.cookies do to_del[#to_del+1]=i end
                    else to_del = parse_selection(inp, #CFG.cookies) end
                    table.sort(to_del, function(a,b) return a>b end)
                    for _, idx in ipairs(to_del) do
                        print("  \27[32m[OK]\27[0m Hapus: "..(CFG.cookies[idx].name or "?"))
                        table.remove(CFG.cookies, idx)
                    end
                    cfg_save()
                end
                sleep(1)
            end

        elseif ch == "3" then
            if #CFG.cookies == 0 then print("  Tidak ada cookie"); sleep(1)
            else
                local inp = ask("Validate (1 / 1,2,3 / 1-5 / all)")
                local to_val
                if inp == "all" or inp == "" then
                    to_val = {}; for i=1,#CFG.cookies do to_val[#to_val+1]=i end
                else to_val = parse_selection(inp, #CFG.cookies) end
                print("")
                for _, idx in ipairs(to_val) do
                    local ck = CFG.cookies[idx]
                    io.write(string.format("  \27[36m[%d]\27[0m Validating... ", idx)); io.flush()
                    local name, id, err = fetch_account(ck.cookie)
                    if name then
                        ck.name=name; ck.id=id
                        print("\27[32m[OK]\27[0m "..name.." (ID: "..id..")")
                    elseif err == "curl" then print("\27[33m[WARN]\27[0m curl error")
                    else print("\27[31m[ERR]\27[0m Invalid/expired") end
                end
                cfg_save(); sleep(2)
            end

        elseif ch == "4" then
            if #CFG.cookies == 0 or #pkgs == 0 then
                print("  \27[31m[ERR]\27[0m Cookie atau package kosong"); sleep(1)
            else
                print("")
                local count = math.min(#CFG.cookies, #pkgs)
                for i = 1, count do
                    local ck = CFG.cookies[i]; local p = pkgs[i]
                    CFG.accounts[p] = {cookie=ck.cookie, name=ck.name, id=ck.id}
                    print(string.format("  \27[32m[OK]\27[0m Cookie[%d] (%s) → %s",
                        i, trunc(ck.name or "?", 12), pkg_short(p)))
                end
                if #CFG.cookies < #pkgs then
                    print(string.format("  \27[33m[WARN]\27[0m %d package tidak dapat cookie",
                        #pkgs - #CFG.cookies))
                end
                cfg_save(); sleep(2)
            end

        elseif ch == "5" then
            if #CFG.cookies == 0 or #pkgs == 0 then
                print("  \27[31m[ERR]\27[0m Cookie atau package kosong"); sleep(1)
            else
                print(""); draw_cookie_table(); print("")
                for i, p in ipairs(pkgs) do
                    print(string.format("  \27[36m[%d]\27[0m %s", i, pkg_short(p)))
                end
                print("")
                local ci = ask("Nomor cookie (1-3, 1,2, dll)")
                local pi = ask("Nomor package (1-3, 1,2, dll)")
                if ci and pi and ci ~= "" and pi ~= "" then
                    local csel = parse_selection(ci, #CFG.cookies)
                    local psel = parse_selection(pi, #pkgs)
                    local count = math.min(#csel, #psel)
                    print("")
                    for k = 1, count do
                        local ck = CFG.cookies[csel[k]]; local p = pkgs[psel[k]]
                        CFG.accounts[p] = {cookie=ck.cookie, name=ck.name, id=ck.id}
                        print(string.format("  \27[32m[OK]\27[0m Cookie[%d] → pkg[%d] (%s)",
                            csel[k], psel[k], pkg_short(p)))
                    end
                    if #csel ~= #psel then
                        print("  \27[33m[WARN]\27[0m "..count.." pasang diproses")
                    end
                    cfg_save()
                end
                sleep(2)
            end
        end
    end
end

-- ============================================
-- MENU: PS LINKS
-- ============================================
local function menu_ps()
    while true do
        draw_header()
        print("  \27[1mPS LINKS\27[0m"); print("")
        if #CFG.ps_links == 0 then print("  \27[90m(kosong)\27[0m")
        else
            local c_url = W - 10
            for i, l in ipairs(CFG.ps_links) do
                local tag = is_share_url(l) and " \27[2m[share]\27[0m" or ""
                print(string.format("  \27[36m[%2d]\27[0m%s %s", i, tag, trunc(l, c_url)))
            end
        end
        print(""); sep()
        print("  \27[1ma\27[0m Tambah  \27[1md\27[0m Hapus  \27[1mc\27[0m Hapus semua  \27[1mb\27[0m Kembali")
        sep(); print("")
        local opt = ask("")
        if opt == "b" or opt == nil then break

        elseif opt == "a" then
            draw_header(); print("  \27[1mTAMBAH PS LINKS\27[0m"); print("")
            print("  Format: https://roblox.com/games/...?privateServerLinkCode=...")
            print("          https://www.roblox.com/share?code=...")
            print("  Baris kosong = selesai"); print("")
            local added, skipped = 0, 0
            while true do
                local line = ask("")
                if not line or line == "" then break end
                if is_valid_ps_link(line) then
                    table.insert(CFG.ps_links, line); added=added+1
                    local tag = is_share_url(line) and " \27[2m[share]\27[0m" or ""
                    print("  \27[32m✓\27[0m ["..#CFG.ps_links.."]"..tag.." Ditambahkan")
                else
                    skipped=skipped+1
                    print("  \27[31m✗\27[0m Tidak valid")
                end
            end
            if added > 0 then cfg_save() end
            print("\n  "..added.." ditambahkan"..(skipped>0 and (", "..skipped.." dilewati") or ""))
            sleep(1)

        elseif opt == "d" then
            if #CFG.ps_links == 0 then print("  Tidak ada link"); sleep(1)
            else
                local ni = ask("Hapus nomor (0=batal)")
                local di = tonumber(ni)
                if di and di>=1 and di<=#CFG.ps_links then
                    table.remove(CFG.ps_links, di)
                    for pkg, plist in pairs(CFG.client_ps_map) do
                        local new = {}
                        for _, pidx in ipairs(plist) do
                            if pidx <= #CFG.ps_links then table.insert(new, pidx) end
                        end
                        CFG.client_ps_map[pkg] = new
                    end
                    cfg_save(); print("  \27[32m[OK]\27[0m Dihapus #"..di)
                else print("  Batal") end
                sleep(1)
            end

        elseif opt == "c" then
            local cf = ask("Ketik 'hapus' untuk konfirmasi")
            if cf == "hapus" then
                CFG.ps_links = {}; CFG.client_ps_map = {}; cfg_save()
                print("  \27[32m[OK]\27[0m Semua link dihapus"); sleep(1)
            end
        end
    end
end

-- ============================================
-- MENU: PER-CLIENT PS MAP
-- ============================================
local function menu_ps_map()
    draw_header()
    print("  \27[1mPER-CLIENT PS MAP\27[0m"); print("")
    if #CFG.ps_links == 0 then print("  \27[31m⚠ Tambahkan PS link dulu!\27[0m"); sleep(2); return end
    local pkgs = detect_packages()
    if #pkgs == 0 then print("  \27[31m⚠ Tidak ada package!\27[0m"); sleep(2); return end

    local c_url = W - 8
    print("  Total PS: \27[36m"..#CFG.ps_links.."\27[0m"); print("")
    for i, l in ipairs(CFG.ps_links) do
        print(string.format("  \27[2m[%2d]\27[0m %s", i, trunc(l, c_url)))
    end
    print("")
    for i, pkg in ipairs(pkgs) do
        local cur = CFG.client_ps_map[pkg] or {}
        print(string.format("  \27[36m[%d]\27[0m %s  \27[2m→ saat ini: %s\27[0m",
            i, trunc(pkg_short(pkg), W-24),
            #cur > 0 and table.concat(cur,",") or "semua"))
        local inp = ask("PS untuk client "..i.." (1-3, 1,2 / Enter=semua)")
        if inp and inp ~= "" then
            local sel = parse_selection(inp, #CFG.ps_links)
            if #sel > 0 then
                CFG.client_ps_map[pkg] = sel
                print("  \27[32m✓\27[0m "..table.concat(sel,","))
            else print("  \27[2mTidak valid, skip\27[0m") end
        else CFG.client_ps_map[pkg] = {}; print("  \27[2m→ Semua PS\27[0m") end
        print("")
    end
    cfg_save(); print("  \27[32m[OK]\27[0m PS map disimpan"); sleep(1)
end

-- ============================================
-- MENU: DELAY
-- ============================================
local function menu_delay()
    draw_header()
    print("  \27[1mSET DELAY\27[0m"); print("")
    print("  Hop delay   : \27[36m"..CFG.delay_min.."-"..CFG.delay_max.." menit (random)\27[0m")
    print("  Launch delay: \27[36m"..DEFAULT_DELAY.." detik antar client\27[0m"); print("")
    local mn = ask("Hop min menit (Enter=batal)")
    if not mn or mn == "" then return end
    local mx = ask("Hop max menit")
    mn=tonumber(mn); mx=tonumber(mx)
    if mn and mx and mn>=1 and mx>=mn then
        CFG.delay_min=mn; CFG.delay_max=mx; cfg_save()
        print("\n  \27[32m[OK]\27[0m Delay: "..mn.."-"..mx.."m")
    else print("\n  \27[31m[ERR]\27[0m Tidak valid") end
    sleep(1)
end

-- ============================================
-- MENU: AUTOEXEC
-- ============================================
local function menu_autoexec()
    draw_header()
    print("  \27[1mSET AUTOEXEC\27[0m"); print("")
    print("  Path   : \27[36m"..trunc(CFG.autoexec_path, W-12).."\27[0m")
    print("  Script : "..(CFG.autoexec_script ~= "" and "\27[32m✓ Set\27[0m" or "\27[31m✗ Kosong\27[0m"))
    print("  Restore: "..(CFG.autoexec_restore ~= "" and "\27[32m✓ Set\27[0m" or "\27[2m– Kosong\27[0m"))
    print("")
    print("  \27[1m1.\27[0m Path  \27[1m2.\27[0m Script  \27[1m3.\27[0m Restore  \27[1m4.\27[0m Test inject  \27[1m0.\27[0m Kembali")
    print("")
    local opt = ask("")
    if opt == "1" then
        local p = ask("Path baru (Enter=batal)")
        if p and p ~= "" then CFG.autoexec_path=p; cfg_save(); print("  \27[32m[OK]\27[0m Path diupdate"); sleep(1) end
    elseif opt == "2" then
        print("  Paste script (1 baris):"); local s = ask("")
        if s and s ~= "" then CFG.autoexec_script=s; cfg_save(); print("  \27[32m[OK]\27[0m Disimpan"); sleep(1) end
    elseif opt == "3" then
        print("  Paste restore script:"); local s = ask("")
        if s and s ~= "" then CFG.autoexec_restore=s; cfg_save(); print("  \27[32m[OK]\27[0m Disimpan"); sleep(1) end
    elseif opt == "4" then
        if CFG.autoexec_script == "" then print("  \27[31m[ERR]\27[0m Script belum diset!")
        else
            local dir = CFG.autoexec_path:match("^(.+)/[^/]+$")
            if dir then su_exec("mkdir -p '"..dir.."'") end
            su_exec("cp '"..CFG.autoexec_path.."' '/sdcard/.auto_1.lua.bak' 2>/dev/null")
            local f = io.open(CFG.autoexec_path,"w")
            if f then f:write(CFG.autoexec_script); f:close()
                su_exec("chmod 644 '"..CFG.autoexec_path.."'")
                print("  \27[32m[OK]\27[0m Berhasil inject!")
            else print("  \27[31m[ERR]\27[0m Gagal inject") end
        end
        sleep(2)
    end
end

-- ============================================
-- MENU: IDLE TIMEOUT
-- ============================================
local function menu_idle()
    draw_header()
    print("  \27[1mSET IDLE TIMEOUT\27[0m"); print("")
    print("  Roblox force hop setelah N detik idle")
    print("  Default: 300s  |  Minimal: 30s"); print("")
    print("  Saat ini: \27[36m"..CFG.idle_timeout.."s\27[0m"); print("")
    local inp = ask("Timeout baru detik (Enter=batal)")
    if not inp or inp == "" then return end
    local v = tonumber(inp)
    if v and v >= 30 then
        CFG.idle_timeout=v; cfg_save()
        print("\n  \27[32m[OK]\27[0m Idle timeout: "..v.."s")
    else print("\n  \27[31m[ERR]\27[0m Minimal 30 detik") end
    sleep(1)
end

-- ============================================
-- MENU: LAYOUT MANAGER
-- ============================================
local function menu_layout()
    draw_header()
    print("  \27[1mLAYOUT MANAGER\27[0m"); print("")
    local pkgs = detect_packages()
    if #pkgs == 0 then print("  \27[31m⚠ Tidak ada package!\27[0m"); sleep(2); return end
    local sw, sh, off = detect_screen()
    if not sw then print("  \27[31m⚠ Gagal baca resolusi!\27[0m"); sleep(2); return end

    local n = #pkgs; local gh = math.floor((sh-off)/n)
    print("  Screen : \27[36m"..sw.." × "..sh.."\27[0m")
    print("  Offset : "..off.."px")
    print("  Grid   : 1 × "..n.." ("..sw.." × "..gh.." per slot)")
    print(""); sep()
    local c_pkg = col(0.35)
    for i, pkg in ipairs(pkgs) do
        local L, T, R, B = grid_bounds(i, n, sw, sh, off)
        print(string.format("  \27[36m[%d]\27[0m %-*s  \27[2mL=%d T=%d R=%d B=%d\27[0m",
            i, c_pkg, trunc(pkg_short(pkg), c_pkg), L, T, R, B))
    end
    sep(); print("")
    print("  \27[1m1.\27[0m Apply+launch  \27[1m2.\27[0m Apply saja  \27[1m3.\27[0m Reset fullscreen  \27[1m0.\27[0m Kembali")
    print("")
    local opt = ask("")
    if opt == "1" or opt == "2" then
        print("")
        for i, pkg in ipairs(pkgs) do
            local L, T, R, B = grid_bounds(i, n, sw, sh, off)
            su_exec("am force-stop "..pkg); apply_layout(pkg, L, T, R, B)
            print("  \27[32m[OK]\27[0m "..trunc(pkg_short(pkg), W-10))
            if opt == "1" then
                sleep(3); su_exec("am start --user 0 -n "..pkg.."/"..ACTIVITY)
                if i < n then sleep(5) end
            end
        end
        print("\n  \27[32mSelesai!\27[0m"); sleep(2)
    elseif opt == "3" then
        for _, pkg in ipairs(pkgs) do apply_layout(pkg,0,0,sw,sh); su_exec("am force-stop "..pkg) end
        print("  \27[32m[OK]\27[0m Reset fullscreen"); sleep(1)
    end
end

-- ============================================
-- MENU: VIEW CONFIG
-- ============================================
local function menu_config()
    draw_header()
    print("  \27[1mCONFIG LENGKAP\27[0m"); print("")
    local function row(l, v)
        print(string.format("  \27[2m%-16s\27[0m %s", l, tostring(v or "-")))
    end
    row("Prefix",       CFG.pkg_prefix)
    row("Delay",        CFG.delay_min.."-"..CFG.delay_max.."m | launch "..DEFAULT_DELAY.."s")
    row("Idle timeout", CFG.idle_timeout.."s")
    row("Cookies",      #CFG.cookies.." tersimpan")
    row("Autoexec",     CFG.autoexec_script ~= "" and "✓ Set" or "– Kosong")
    row("AE Restore",   CFG.autoexec_restore ~= "" and "✓ Set" or "– Kosong")
    row("AE Path",      trunc(CFG.autoexec_path, W-20))
    row("PS Links",     #CFG.ps_links.." link")
    print("")
    for i, l in ipairs(CFG.ps_links) do
        print(string.format("  \27[36m[%2d]\27[0m %s", i, trunc(l, W-9)))
    end
    if next(CFG.client_ps_map) then
        print(""); print("  \27[1mPer-client PS map:\27[0m")
        local c_pkg = col(0.32)
        for pkg, plist in pairs(CFG.client_ps_map) do
            if #plist > 0 then
                print(string.format("  \27[36m%-*s\27[0m → {%s}",
                    c_pkg, trunc(pkg_short(pkg), c_pkg), table.concat(plist,",")))
            end
        end
    end
    print(""); ask("Enter untuk kembali")
end

-- ============================================
-- LOAD PS LINKS
-- ============================================
local function load_ps_links()
    local f = io.open(PS_FILE_PATH,"r")
    if not f then
        local d = io.open(PS_FILE_PATH,"w")
        if d then d:write("-- Taruh PS links di sini\n"); d:close() end
        return nil, 0
    end
    local list, skip = {}, 0
    for line in f:lines() do
        local l = line:gsub("%c",""):gsub("%s+","")
        if l ~= "" and not l:match("^%-%-") and not l:match("^#") then
            if is_valid_ps_link(l) then table.insert(list, l)
            elseif l:match("^https?://") then skip=skip+1 end
        end
    end
    f:close(); return list, skip
end

-- ============================================
-- START HOPPER
-- ============================================
local function start_hopper()
    draw_header()
    print("  \27[1mSTARTING HOPPER...\27[0m"); print("")

    local pkgs = detect_packages()
    if #pkgs == 0 then
        print("  \27[31m[ERR]\27[0m Tidak ada package ("..CFG.pkg_prefix..")"); sleep(2); return
    end

    local ps_list, skip = load_ps_links()
    if not ps_list then
        print("  \27[31m[ERR]\27[0m File PS tidak ada!"); sleep(2); return
    end
    if skip > 0 then print("  \27[33m[WARN]\27[0m "..skip.." link invalid dilewati") end
    if #ps_list == 0 then print("  \27[31m[ERR]\27[0m Tidak ada link valid!"); sleep(2); return end
    print("  \27[32m[OK]\27[0m "..#ps_list.." link PS")

    print("")
    local hi = tonumber(ask("Hop tiap brp menit? (0=tidak)")) or 0
    if hi < 0 then hi = 0 end

    -- Select clients
    print(""); print("  Pilih client (Enter=semua):")
    for i, p in ipairs(pkgs) do
        print(string.format("    \27[36m[%d]\27[0m %s", i, trunc(pkg_short(p), W-8)))
    end
    print("")
    local si = ask("Client (Enter=semua)")
    local sel
    if not si or si == "" then sel={}; for i=1,#pkgs do table.insert(sel,i) end
    else sel = parse_selection(si, #pkgs) end
    if #sel == 0 then print("  \27[31mInvalid!\27[0m"); sleep(1); return end

    -- Per-client PS map
    local cpm = {}
    print(""); print("\27[36m[INFO]\27[0m PS per client (Enter=semua):")
    for _, idx in ipairs(sel) do
        local p = pkgs[idx]
        local pi = ask("PS utk Client "..idx)
        local ps = pi and pi ~= "" and parse_selection(pi, #ps_list) or {}
        if #ps == 0 then ps={}; for j=1,#ps_list do table.insert(ps,j) end end
        cpm[p] = ps
    end

    -- Screen detect
    local sw, sh, off = detect_screen()
    if not sw then print("  \27[31m[ERR]\27[0m Gagal baca resolusi!"); sleep(2); return end
    local ns = #sel

    -- Resolve share URLs
    local resolve_cookie = ""
    for _, idx in ipairs(sel) do
        local acc = CFG.accounts[pkgs[idx]] or {}
        if acc.cookie and acc.cookie ~= "" then resolve_cookie=acc.cookie; break end
    end
    local ps_list_r = resolve_all(ps_list, resolve_cookie)

    -- Autoexec replace
    su_exec("mkdir -p "..AUTOEXEC_DIR)
    su_exec("cp "..AUTOEXEC_FILE.." /sdcard/.auto_1.lua.bak 2>/dev/null")
    local ae_content = CFG.autoexec_script ~= "" and CFG.autoexec_script or JOIN_SCRIPT
    local af = io.open(AUTOEXEC_FILE,"w")
    if af then af:write(ae_content); af:close(); su_exec("chmod 644 "..AUTOEXEC_FILE) end
    print("  \27[32m[OK]\27[0m Autoexec replaced")

    -- Build cdata + apply layout
    local cdata = {}
    for i, idx in ipairs(sel) do
        local p = pkgs[idx]
        local L, T, R, B = grid_bounds(i, ns, sw, sh, off)
        su_exec("am force-stop "..p); apply_layout(p, L, T, R, B)
        table.insert(cdata, {pkg=p, ps_idx_list=cpm[p], curr_ptr=1})
    end

    -- Launch semua
    su_exec("rm -f "..HOPPER_LOG.." 2>/dev/null")
    linfo("--- Hopper Started ---")
    print("  \27[33m[INFO]\27[0m Launching clients..."); print("")
    for i, c in ipairs(cdata) do
        launch_client(c, ps_list_r, c.ps_idx_list[c.curr_ptr], i, #ps_list_r)
        c.curr_ptr = c.curr_ptr + 1
        if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
        if i < #cdata then sleep(DEFAULT_DELAY) end
    end

    -- MAIN LOOP
    local hop_sec = hi * 60
    local elapsed = 0
    local idle_timers = {}
    for i=1,#cdata do idle_timers[i]=0 end

    while true do
        render(cdata, hi, "RUNNING", #ps_list_r, idle_timers)
        local key = read_key(1)
        if key and key:lower() == "q" then break end
        elapsed = elapsed + 1

        for i=1,#cdata do
            if is_running(cdata[i].pkg) then idle_timers[i]=idle_timers[i]+1
            else idle_timers[i]=0 end
        end

        -- Watchdog
        if elapsed % WATCHDOG_SEC == 0 then
            for i, c in ipairs(cdata) do
                if not is_running(c.pkg) then
                    lwarn("Crash client "..i..", reopening")
                    local ptr = c.curr_ptr - 1; if ptr < 1 then ptr = #c.ps_idx_list end
                    launch_client(c, ps_list_r, c.ps_idx_list[ptr], i, #ps_list_r)
                    idle_timers[i] = 0
                end
            end
        end

        -- Idle detection
        for i, c in ipairs(cdata) do
            if idle_timers[i] >= CFG.idle_timeout then
                lwarn("Idle client "..i.." ("..idle_timers[i].."s) → force hop")
                launch_client(c, ps_list_r, c.ps_idx_list[c.curr_ptr], i, #ps_list_r)
                c.curr_ptr = c.curr_ptr + 1
                if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
                idle_timers[i] = 0
            end
        end

        -- Hop timer
        if hi > 0 and hop_sec > 0 and elapsed >= hop_sec then
            elapsed = 0; linfo("--- Hop cycle ---")
            for i, c in ipairs(cdata) do
                launch_client(c, ps_list_r, c.ps_idx_list[c.curr_ptr], i, #ps_list_r)
                c.curr_ptr = c.curr_ptr + 1
                if c.curr_ptr > #c.ps_idx_list then c.curr_ptr = 1 end
                if i < #cdata then sleep(DEFAULT_DELAY) end
                idle_timers[i] = 0
            end
        end
    end

    -- RESET
    render(cdata, hi, "STOPPED", #ps_list_r, idle_timers)
    print(""); sep()
    local rst = ask("Reset semua (restore autoexec + close Roblox)? (y/n)")
    if rst == "y" then
        print(""); print("  \27[33m[INFO]\27[0m Resetting...")
        if CFG.autoexec_restore ~= "" then
            local rf = io.open(AUTOEXEC_FILE,"w")
            if rf then rf:write(CFG.autoexec_restore); rf:close()
                su_exec("chmod 644 "..AUTOEXEC_FILE) end
            su_exec("rm -f /sdcard/.auto_1.lua.bak 2>/dev/null")
            print("  \27[32m[OK]\27[0m Autoexec restored")
        end
        for i, p in ipairs(pkgs) do
            local L, T, R, B = grid_bounds(i, #pkgs, sw, sh, off)
            apply_layout(p, L, T, R, B); su_exec("am force-stop "..p)
        end
        print("  \27[32m[OK]\27[0m "..#pkgs.." Roblox closed")
        su_exec("rm -f "..HOPPER_LOG.." 2>/dev/null")
        print(""); print("  \27[32mReset selesai!\27[0m")
    end
    print(""); ask("Enter")
end

-- ============================================
-- ROUTER
-- ============================================
math.randomseed(os.time())
cfg_load()
linfo("=== SESSION: "..os.date().." ===")

local routes = {
    main            = main_menu,
    menu_prefix     = function() menu_prefix();    return "main" end,
    menu_cookie_mgr = function() menu_cookie_mgr();return "main" end,
    menu_ps         = function() menu_ps();        return "main" end,
    menu_ps_map     = function() menu_ps_map();    return "main" end,
    menu_delay      = function() menu_delay();     return "main" end,
    menu_autoexec   = function() menu_autoexec();  return "main" end,
    menu_idle       = function() menu_idle();      return "main" end,
    menu_layout     = function() menu_layout();    return "main" end,
    menu_config     = function() menu_config();    return "main" end,
    start           = function() start_hopper();   return "main" end,
}

local state = "main"
while state ~= "exit" do
    local fn = routes[state]
    state = fn and (fn() or "main") or "main"
end

cls()
linfo("=== SESSION END ===")
