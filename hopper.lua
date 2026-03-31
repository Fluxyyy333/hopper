-- Simple PS Hopper v1.7 STANDALONE
-- Base: v1.4.2 (fully working, zero dependencies, no backend)
-- v1.7: Pure standalone — no web backend, no ngrok, no API polling
--       Just local menu + auto hopping. Works offline forever.
-- Config: Package, cookie, PS links, hop interval (all local files)
-- Menu: Setup config, then auto-start hopping. Ctrl+C to stop.
-- ============================================

local HOPPER_LOG   = "/sdcard/hopper_log.txt"
local PS_FILE      = "/sdcard/private_servers.txt"
local PKG_FILE     = "/sdcard/.hopper_pkg"
local COOKIE_FILE  = "/sdcard/.hopper_cookie"
local STOP_FILE    = "/sdcard/.hopper_stop"
local ACCOUNT_FILE = "/sdcard/.hopper_account"
local HOP_FILE     = "/sdcard/.hopper_hop"
local PTR_FILE     = "/sdcard/.hopper_ptr"

local RONIX_KEY_DIR  = "/storage/emulated/0/RonixExploit/internal/"
local RONIX_KEY_PATH = RONIX_KEY_DIR .. "_key.txt"
local RONIX_KEY_VAL  = "LzuYkZDBBIkVTMHEBAJGxZwqycRUimlL"
local RONIX_AE_DIR   = "/storage/emulated/0/RonixExploit/autoexec/"
local RONIX_AE_PATH  = RONIX_AE_DIR .. "Accept.lua"
local RONIX_AE_SCRIPT = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/Fluxyyy333/Auto-Rebirth-speed/refs/heads/main/jgndiambilbg"))()
getgenv().scriptkey="HsMgJbFoUwmvfzGxLESxMiUFuYpyqfFA"
loadstring(game:HttpGet("https://zekehub.com/scripts/AdoptMe/Utility.lua"))()]]

local RONIX_TRACK_PATH   = RONIX_AE_DIR .. "Trackstat.lua"
local RONIX_TRACK_SCRIPT = '_G.Config={UserID="37825915-c3be-41bc-987f-661da09d9b3c",discord_id="757533465213141053",Note="Pc"}local s;for i=1,5 do s=pcall(function()loadstring(game:HttpGet("https://cdn.yummydata.click/scripts/adoptmee"))()end)if s then break end wait(5)end'

local PKG     = ""
local HOP_MIN = 0

-- ============================================
-- HELPERS
-- ============================================
local function sleep(s)
    if s and s > 0 then os.execute("sleep " .. tostring(s)) end
end

local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'","'\\''") .. "' >/dev/null 2>&1")
end

local function log(msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then f:write(os.date("[%H:%M:%S] ") .. msg .. "\n"); f:close() end
end

local function out(text)
    io.write((text or "") .. "\r\n")
    io.flush()
end

local function cls()
    io.write("\27[2J\27[3J\27[H\27[0m"); io.flush()
end

local function ask(prompt)
    io.write(prompt .. " > "); io.flush()
    local tty = io.open("/dev/tty", "r")
    local r
    if tty then r = tty:read("*l"); tty:close()
    else r = io.read("*l") end
    return r and r:gsub("^%s+",""):gsub("%s+$","") or ""
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function save_file(path, content)
    local f = io.open(path, "w")
    if f then f:write(content); f:close() end
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local c = f:read("*a") or ""; f:close()
    return c:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
end

local function load_ps()
    local f = io.open(PS_FILE, "r")
    if not f then return {} end
    local list = {}
    for line in f:lines() do
        local l = line:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
        if l ~= "" and not l:match("^#")
            and l:match("^https?://")
            and l:lower():match("code=") then
            table.insert(list, l)
        end
    end
    f:close()
    return list
end

local function tail_log(n)
    local lines = {}
    local f = io.open(HOPPER_LOG, "r")
    if not f then return {} end
    for line in f:lines() do table.insert(lines, line) end
    f:close()
    local result = {}
    local s = math.max(1, #lines - n + 1)
    for i = s, #lines do table.insert(result, lines[i]) end
    return result
end

local function json_field(json_str, field)
    local pat_str = '"' .. field .. '"%s*:%s*"([^"]*)"'
    local val = json_str:match(pat_str)
    if val then return val end
    local pat_num = '"' .. field .. '"%s*:%s*(%d+)'
    return json_str:match(pat_num)
end

local function fetch_account_info(cookie)
    local h = io.popen('curl -s --connect-timeout 5 '
        .. '-H "Cookie: .ROBLOSECURITY=' .. cookie .. '" '
        .. '"https://users.roblox.com/v1/users/authenticated" 2>/dev/null')
    if not h then return nil, nil end
    local body = h:read("*a") or ""
    h:close()
    local name = json_field(body, "name")
    local id   = json_field(body, "id")
    return name, id
end

-- ============================================
-- CORE
-- ============================================
local function is_running()
    if PKG == "" then return false end
    local h = io.popen("su -c 'pidof " .. PKG .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

local function inject_cookie()
    local cookie = read_file(COOKIE_FILE)
    if cookie == "" or PKG == "" then return end
    local dir    = "/data/data/" .. PKG .. "/shared_prefs"
    local target = dir .. "/RobloxSharedPreferences.xml"
    local tmp    = "/sdcard/.hcookie_tmp.xml"

    local xh = io.popen("su -c 'cat \"" .. target .. "\"' 2>/dev/null")
    local existing = xh and xh:read("*a") or ""
    if xh then xh:close() end

    local xml_content
    if existing ~= "" and existing:find("ROBLOSECURITY") then
        local cookie_safe = cookie:gsub("%%", "%%%%")
        xml_content = existing:gsub(
            '(<string%s+name="%.ROBLOSECURITY">)[^<]*(</string>)',
            '%1' .. cookie_safe .. '%2'
        )
        log("Cookie: replace di XML existing")
    else
        xml_content = "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
                   .. "<map>\n"
                   .. '    <string name=".ROBLOSECURITY">' .. cookie .. "</string>\n"
                   .. "</map>\n"
        log("Cookie: tulis XML minimal (fresh)")
    end

    local f = io.open(tmp, "w")
    if not f then log("ERR: gagal tulis cookie tmp"); return end
    f:write(xml_content)
    f:close()

    -- Update WebView cookie store via sqlite3
    local cookie_db = "/data/data/" .. PKG .. "/app_webview/Default/Cookies"
    local sql_tmp   = "/sdcard/.hopper_wv.sql"
    local safe      = cookie:gsub("'", "''")
    local sf = io.open(sql_tmp, "w")
    if sf then
        sf:write("UPDATE cookies SET value='" .. safe .. "' WHERE name='.ROBLOSECURITY';\n")
        sf:close()
        su_exec("/data/data/com.termux/files/usr/bin/sqlite3 '" .. cookie_db .. "' < '" .. sql_tmp .. "'")
        os.remove(sql_tmp)
        log("WebView cookie updated")
    else
        log("WARN: gagal tulis sql tmp")
    end

    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. target .. "'")

    local uid_h = io.popen("su -c 'stat -c %u /data/data/" .. PKG .. "' 2>/dev/null")
    local uid = uid_h and uid_h:read("*l") or ""
    if uid_h then uid_h:close() end
    uid = uid:gsub("%c",""):gsub("%s","")
    if uid ~= "" then
        su_exec("chown " .. uid .. ":" .. uid .. " '" .. target .. "'")
    end
    su_exec("chmod 660 '" .. target .. "'")
    su_exec("restorecon '" .. target .. "'")
    os.remove(tmp)
    log("Cookie injected (uid=" .. uid .. ")")
end

local function inject_key()
    su_exec("mkdir -p '" .. RONIX_KEY_DIR .. "'")
    local f = io.open(RONIX_KEY_PATH, "w")
    if f then f:write(RONIX_KEY_VAL); f:close() end
    log("Key injected")
end

local function inject_autoexec()
    su_exec("mkdir -p '" .. RONIX_AE_DIR .. "'")
    local f = io.open(RONIX_AE_PATH, "w")
    if f then f:write(RONIX_AE_SCRIPT); f:close() end
    log("Autoexec injected")
end

local function inject_trackstat()
    su_exec("mkdir -p '" .. RONIX_AE_DIR .. "'")
    local f = io.open(RONIX_TRACK_PATH, "w")
    if f then f:write(RONIX_TRACK_SCRIPT); f:close() end
    log("Trackstat injected")
end

local function inject_all_verbose()
    out("[1/4] Injecting cookie...")
    inject_cookie()
    out("[2/4] Injecting Ronix key...")
    inject_key()
    out("[3/4] Injecting autoexec...")
    inject_autoexec()
    out("[4/4] Injecting trackstat...")
    inject_trackstat()
    out("[+] All injected.")
end

local function launch(ps_link, ps_idx, ps_total)
    log(string.format("Launching PS %d/%d", ps_idx, ps_total))
    out(string.format("[*] Stopping %s...", PKG))
    su_exec("am force-stop " .. PKG)
    sleep(2)

    out("[*] Clearing cache...")
    su_exec("rm -rf /data/data/" .. PKG .. "/cache/*")
    su_exec("rm -rf /data/data/" .. PKG .. "/code_cache/*")
    su_exec("rm -rf /sdcard/Android/data/" .. PKG .. "/cache/*")
    log("Cache cleared")

    local dp = ps_link:match("^intent://(.-)#Intent")
           or ps_link:gsub("^https?://","")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"

    out("[*] Launching intent...")
    su_exec('am start --user 0 "' .. intent .. '"')
    out(string.format("[+] Launched PS %d/%d", ps_idx, ps_total))
    log(string.format("Launched PS %d/%d", ps_idx, ps_total))
end

-- ============================================
-- MONITOR DISPLAY
-- ============================================
local function show_status(cur_ps, ps_total, crash_count,
                            runtime_m, hop_elapsed_m, status_str)
    cls()
    out("========================")
    out("  HOPPER MONITOR v1.7 ")
    out("========================")
    out("")
    out("Pkg    : " .. PKG)
    out(string.format("PS     : %d / %d", cur_ps, ps_total))
    out("Status : " .. status_str)
    out("Crash  : " .. crash_count)
    out(string.format("Runtime: %dm", runtime_m))
    if HOP_MIN > 0 then
        out(string.format("Hop    : %dm / %dm", hop_elapsed_m, HOP_MIN))
    else
        out("Hop    : OFF")
    end
    out("")
    out("--- Log ---")
    for _, line in ipairs(tail_log(4)) do
        out(line)
    end
    out("")
    out("========================")
    out("[Ctrl+C] = STOP")
    out("========================")
end

-- ============================================
-- HOPPER LOOP
-- ============================================
local function run_hopper()
    local ps_list = load_ps()
    if #ps_list == 0 then
        out("[!] Tidak ada PS link!"); sleep(2); return
    end
    if PKG == "" then
        out("[!] Package belum diset!"); sleep(2); return
    end

    os.remove(STOP_FILE)
    os.execute("rm -f " .. HOPPER_LOG .. " 2>/dev/null")

    log("=== Hopper Started ===")
    log("Pkg: " .. PKG .. " | PS: " .. #ps_list .. " | Hop: " .. HOP_MIN .. "m")

    -- Resume PS position
    local ptr = 1
    local saved_ptr = tonumber(read_file(PTR_FILE))
    if saved_ptr and saved_ptr >= 1 and saved_ptr <= #ps_list then
        ptr = saved_ptr
        out("[*] Resuming from PS " .. ptr)
        log("Resumed from PS " .. ptr)
    else
        out("[*] Starting from PS 1")
    end
    os.remove(PTR_FILE)

    local cur_ps      = ptr
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60
    local start_time  = os.time()
    local hop_time    = os.time()
    local last_display = 0

    out("")
    inject_all_verbose()
    out("")

    launch(ps_list[ptr], ptr, #ps_list)
    cur_ps = ptr
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    out("")
    out("[*] Hopper running... Ctrl+C to stop")
    sleep(3)

    local ok, err = pcall(function()
        while true do
            sleep(5)

            if file_exists(STOP_FILE) then
                log("Stop file detected")
                return
            end

            local now           = os.time()
            local runtime_m     = math.floor((now - start_time) / 60)
            local hop_elapsed_s = now - hop_time
            local hop_elapsed_m = math.floor(hop_elapsed_s / 60)
            local running       = is_running()
            local status_str    = running and "RUNNING" or "NOT RUNNING"
            local did_action    = false

            -- Hop timer
            if HOP_MIN > 0 and hop_elapsed_s >= hop_sec then
                log("Hop -> PS " .. ptr)
                launch(ps_list[ptr], ptr, #ps_list)
                cur_ps = ptr; ptr = ptr + 1
                if ptr > #ps_list then ptr = 1 end
                hop_time = os.time(); hop_elapsed_m = 0; did_action = true
            end

            -- PATCH 3: Crash watchdog — does NOT reset hop_time
            if not running and not did_action then
                crash_count = crash_count + 1
                log("Crash #" .. crash_count .. " relaunch PS " .. cur_ps)
                launch(ps_list[cur_ps], cur_ps, #ps_list)
            end

            -- Update display every 15 seconds
            if now - last_display >= 15 then
                show_status(cur_ps, #ps_list, crash_count,
                            runtime_m, hop_elapsed_m, status_str)
                last_display = now
            end
        end
    end)

    if not ok then
        log("Stopped: " .. tostring(err))
    end

    -- Save PS pointer for resume
    save_file(PTR_FILE, tostring(cur_ps))
    log("Saved PS pointer: " .. cur_ps)

    os.remove(STOP_FILE)
    log("=== Hopper Stopped ===")

    cls()
    out("========================")
    out("   HOPPER STOPPED")
    out("========================")
    out("")
    out("Last PS : " .. cur_ps .. " / " .. #ps_list)
    out("Crashes : " .. crash_count)
    out("Resume  : will start from PS " .. cur_ps)
    out("")
end

-- ============================================
-- MENU HANDLERS
-- ============================================
local function menu_set_package()
    cls()
    out("=== SET PACKAGE ===")
    out("")
    local saved = read_file(PKG_FILE)
    if saved ~= "" then out("Tersimpan: " .. saved); out("") end

    local h = io.popen("pm list packages 2>/dev/null")
    local pkgs = {}
    if h then
        local r = h:read("*a") or ""; h:close()
        for line in r:gmatch("[^\r\n]+") do
            local p = line:match("package:(.+)")
            if p then
                p = p:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
                if p ~= "" then table.insert(pkgs, p) end
            end
        end
        table.sort(pkgs)
    end

    if #pkgs > 0 then
        out("Package tersedia:")
        for i, p in ipairs(pkgs) do
            out(string.format("  %d. %s", i, p))
        end
        out("")
    end

    local inp = ask("Nomor / nama (kosong=batal)")
    if inp == "" then return end
    local n = tonumber(inp)
    local new_pkg = (n and pkgs[n]) or inp
    if new_pkg and new_pkg ~= "" then
        PKG = new_pkg
        save_file(PKG_FILE, PKG)
        out("[+] Package: " .. PKG)
    else
        out("[!] Tidak valid")
    end
    sleep(1)
end

local function menu_set_cookie()
    cls()
    out("=== SET COOKIE ===")
    out("")
    local saved = read_file(COOKIE_FILE)
    if saved ~= "" then
        out("Tersimpan: " .. saved:sub(1,20) .. "...")
        out("")
        local ch = ask("Ganti? (y/n)")
        if ch:lower() ~= "y" then return end
    end
    out("Paste .ROBLOSECURITY (kosong=batal):")
    out("")
    local raw = ask("")
    if raw == "" then out("Batal."); sleep(1); return end
    local ck = raw:match("(_|WARNING.+)$") or raw
    save_file(COOKIE_FILE, ck)
    os.execute("chmod 600 '" .. COOKIE_FILE .. "'")
    out("[+] Cookie disimpan.")

    -- Inject immediately if package set
    if PKG ~= "" then
        out("[*] Injecting cookie...")
        inject_cookie()
        out("[+] Cookie injected.")
    end

    -- Fetch account info via Roblox API
    out("[*] Fetching account info...")
    local name, id = fetch_account_info(ck)
    if name and id then
        save_file(ACCOUNT_FILE, name .. ":" .. id)
        out("[+] Account: " .. name .. " (" .. id .. ")")
    else
        save_file(ACCOUNT_FILE, "")
        out("[!] Gagal fetch account info (cookie invalid?)")
    end
    sleep(2)
end

local function menu_set_ps()
    while true do
        cls()
        out("=== PS LINKS ===")
        out("")
        local ps = load_ps()
        if #ps == 0 then
            out("  (kosong)")
        else
            for i, l in ipairs(ps) do
                local d = #l > 42
                    and (l:sub(1,25) .. "..." .. l:sub(-12))
                    or l
                out(string.format("  [%d] %s", i, d))
            end
        end
        out("")
        out("1=Tambah  2=Hapus  3=Clear  0=Kembali")
        out("")
        local opt = ask("")
        if opt == "0" or opt == "" then break

        elseif opt == "1" then
            out("Paste link (kosong=selesai):")
            local wf = io.open(PS_FILE, "a")
            local added = 0
            while true do
                local line = ask("")
                if line == "" then break end
                if line:match("^https?://") and line:lower():match("code=") then
                    if wf then wf:write(line .. "\n") end
                    added = added + 1
                    out("  [+] " .. added)
                else
                    out("  [!] Tidak valid")
                end
            end
            if wf then wf:close() end
            out(added .. " ditambahkan."); sleep(1)

        elseif opt == "2" then
            local ps2 = load_ps()
            if #ps2 == 0 then out("Kosong."); sleep(1)
            else
                local n = tonumber(ask("Hapus nomor"))
                if n and ps2[n] then
                    table.remove(ps2, n)
                    local wf = io.open(PS_FILE, "w")
                    if wf then
                        for _, l in ipairs(ps2) do wf:write(l.."\n") end
                        wf:close()
                    end
                    out("[+] Dihapus."); sleep(1)
                else out("[!] Tidak valid"); sleep(1) end
            end

        elseif opt == "3" then
            if ask("Ketik 'hapus'") == "hapus" then
                save_file(PS_FILE, "")
                out("[+] Semua dihapus."); sleep(1)
            end
        end
    end
end

local function menu_set_hop()
    cls()
    out("=== SET HOP INTERVAL ===")
    out("")
    out("Saat ini: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
    out("")
    local inp = ask("Hop tiap berapa menit? (0=OFF)")
    local v = tonumber(inp)
    if v and v >= 0 then
        HOP_MIN = v
        save_file(HOP_FILE, tostring(HOP_MIN))
        out("[+] Hop: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
    else
        out("[!] Tidak valid")
    end
    sleep(1)
end

-- ============================================
-- MAIN MENU
-- ============================================
local function main()
    PKG = read_file(PKG_FILE)

    local hop_saved = read_file(HOP_FILE)
    local hop_val = tonumber(hop_saved)
    if hop_val and hop_val >= 0 then HOP_MIN = hop_val end

    while true do
        cls()
        out("=== SIMPLE HOPPER v1.4.2 ===")
        out("")
        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()
        out("Package : " .. (PKG ~= "" and PKG or "-"))

        -- Show account info if available, fallback to cookie prefix
        local acct = read_file(ACCOUNT_FILE)
        if acct ~= "" then
            local aname, aid = acct:match("^(.+):(%d+)$")
            if aname then
                out("Account : " .. aname .. " (" .. aid .. ")")
            else
                out("Account : " .. acct)
            end
        elseif cookie ~= "" then
            out("Cookie  : " .. cookie:sub(1,16) .. "...")
        else
            out("Cookie  : -")
        end

        out("PS      : " .. #ps)
        out("Hop     : " .. (HOP_MIN == 0 and "OFF" or HOP_MIN.."m"))

        -- Show resume info if available
        local saved_ptr = read_file(PTR_FILE)
        if saved_ptr ~= "" then
            out("Resume  : PS " .. saved_ptr)
        end

        out("")
        out("1. Set package")
        out("2. Set cookie")
        out("3. Kelola PS links")
        out("4. Set hop interval")
        out("5. START")
        out("0. Keluar")
        out("")
        local ch = ask("Pilih")
        if     ch == "1" then menu_set_package()
        elseif ch == "2" then menu_set_cookie()
        elseif ch == "3" then menu_set_ps()
        elseif ch == "4" then menu_set_hop()
        elseif ch == "5" then run_hopper()
        elseif ch == "0" then cls(); out("Keluar."); break
        end
    end
end

-- ============================================
-- ENTRY
-- ============================================
cls()
main()
