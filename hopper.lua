-- Simple PS Hopper v1.2
-- Single package | Menu-based
-- Target: Termux + Root Android
-- ============================================

local HOPPER_LOG  = "/sdcard/hopper_log.txt"
local PS_FILE     = "/sdcard/private_servers.txt"
local PKG_FILE    = "/sdcard/.hopper_pkg"
local COOKIE_FILE = "/sdcard/.hopper_cookie"

-- Ronix paths
local RONIX_KEY_PATH  = "/storage/emulated/0/RonixExploit/internal/_key.txt"
local RONIX_KEY_VAL   = "LzuYkZDBBIkVTMHEBAJGxZwqycRUimlL"
local RONIX_AE_PATH   = "/storage/emulated/0/RonixExploit/autoexec/Accept.lua"
local RONIX_AE_SCRIPT = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/Fluxyyy333/Auto-Rebirth-speed/refs/heads/main/jgndiambilbg"))()\ngetgenv().scriptkey="HsMgJbFoUwmvfzGxLESxMiUFuYpyqfFA"\nloadstring(game:HttpGet("https://zekehub.com/scripts/AdoptMe/Utility.lua"))()'

local WATCHDOG    = 60  -- cek crash tiap 1 menit (sync dengan update interval)

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

local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end

local function ask(prompt)
    io.write(prompt .. " > "); io.flush()
    local tty = io.open("/dev/tty", "r")
    local r
    if tty then r = tty:read("*l"); tty:close() else r = io.read("*l") end
    return r and r:gsub("^%s+",""):gsub("%s+$","") or ""
end

-- ============================================
-- PERSIST
-- ============================================
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
    local f = io.open(tmp, "w")
    if not f then log("inject_cookie: gagal buat tmp"); return end
    f:write('<?xml version=\'1.0\' encoding=\'utf-8\' standalone=\'yes\' ?>\n')
    f:write('<map>\n')
    f:write('    <string name=".ROBLOSECURITY">' .. cookie .. '</string>\n')
    f:write('</map>\n')
    f:close()
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. target .. "'")
    su_exec("chmod 660 '" .. target .. "'")
    os.remove(tmp)
    log("Cookie injected")
end

local function inject_key()
    -- Buat dir jika belum ada
    local dir = RONIX_KEY_PATH:match("^(.+)/[^/]+$")
    if dir then su_exec("mkdir -p '" .. dir .. "'") end
    local f = io.open(RONIX_KEY_PATH, "w")
    if f then f:write(RONIX_KEY_VAL); f:close() end
    log("Key injected")
end

local function inject_autoexec()
    local dir = RONIX_AE_PATH:match("^(.+)/[^/]+$")
    if dir then su_exec("mkdir -p '" .. dir .. "'") end
    local f = io.open(RONIX_AE_PATH, "w")
    if f then f:write(RONIX_AE_SCRIPT); f:close() end
    log("Autoexec injected")
end

local function launch(ps_link, ps_idx, ps_total)
    log(string.format("Launching PS %d/%d", ps_idx, ps_total))
    su_exec("am force-stop " .. PKG)
    sleep(2)
    inject_cookie()
    inject_key()
    inject_autoexec()
    local dp = ps_link:match("^intent://(.-)#Intent") or ps_link:gsub("^https?://","")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    log(string.format("Launched PS %d/%d", ps_idx, ps_total))
end

-- ============================================
-- HOPPER LOOP
-- ============================================
local function run_hopper()
    local ps_list = load_ps()
    if #ps_list == 0 then
        print("[!] Tidak ada PS link! Tambah dulu di menu 3.")
        sleep(2); return
    end
    if PKG == "" then
        print("[!] Package belum diset! Set dulu di menu 1.")
        sleep(2); return
    end

    os.execute("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
    log("=== Hopper Started ===")
    log("Package: " .. PKG)
    log("PS: " .. #ps_list)
    log("Hop: " .. HOP_MIN .. " menit")

    local ptr         = 1          -- PS index yang akan dilaunch berikutnya
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60
    local start_time  = os.time()  -- waktu mulai session
    local hop_time    = os.time()  -- waktu launch terakhir

    -- Launch pertama
    launch(ps_list[ptr], ptr, #ps_list)
    local cur_ps = ptr
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    while true do
        local now       = os.time()
        local runtime_m = math.floor((now - start_time) / 60)
        local hop_elapsed_m = math.floor((now - hop_time) / 60)

        -- Render status (update tiap kali loop = tiap 1 menit)
        cls()
        print("=== HOPPER MONITOR ===")
        print("")
        print("Package  : " .. PKG)
        print(string.format("PS       : %d/%d", cur_ps, #ps_list))
        print("Status   : " .. (is_running() and "RUNNING" or "NOT RUNNING (crash?)"))
        print("Crash    : " .. crash_count)
        print(string.format("RunTime  : %dm", runtime_m))
        if HOP_MIN > 0 then
            print(string.format("Hop in   : %dm/%dm", hop_elapsed_m, HOP_MIN))
        else
            print("Hop      : OFF")
        end
        print("")
        print("Log terakhir:")
        -- Tampilkan 3 baris log terakhir
        local log_lines = {}
        local lf = io.open(HOPPER_LOG, "r")
        if lf then
            for line in lf:lines() do table.insert(log_lines, line) end
            lf:close()
        end
        local start_idx = math.max(1, #log_lines - 2)
        for i = start_idx, #log_lines do
            print("  " .. (log_lines[i] or ""))
        end
        print("")
        print("[Enter] Refresh  |  [q] Stop")

        -- Blocking input — update interval ditentukan user
        local inp = ask("")
        if inp:lower() == "q" then break end

        -- Cek watchdog
        if not is_running() then
            crash_count = crash_count + 1
            log("Crash #" .. crash_count .. " — relaunch PS " .. cur_ps)
            launch(ps_list[cur_ps], cur_ps, #ps_list)
            hop_time = os.time()
        end

        -- Cek hop
        if HOP_MIN > 0 and (os.time() - hop_time) >= hop_sec then
            log("Hop → PS " .. ptr)
            launch(ps_list[ptr], ptr, #ps_list)
            cur_ps = ptr
            ptr = ptr + 1
            if ptr > #ps_list then ptr = 1 end
            hop_time = os.time()
        end
    end

    log("=== Hopper Stopped ===")
end

-- ============================================
-- MENU HANDLERS
-- ============================================
local function menu_set_package()
    cls()
    print("=== SET PACKAGE ===")
    print("")

    local saved = read_file(PKG_FILE)
    if saved ~= "" then
        print("Tersimpan: " .. saved)
        print("")
    end

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
        print("Package tersedia:")
        for i, p in ipairs(pkgs) do
            print(string.format("  %d. %s", i, p))
        end
        print("")
    end

    local inp = ask("Nomor / nama package (kosong=batal)")
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
        print("Tersimpan: " .. saved:sub(1,24) .. "...")
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
                -- Tampilkan awal dan akhir link
                local display = #l > 45
                    and (l:sub(1,28) .. "..." .. l:sub(-12))
                    or l
                print(string.format("  [%d] %s", i, display))
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
                    print("  [+] OK (" .. added .. ")")
                else
                    print("  [!] Format tidak valid")
                end
            end
            if wf then wf:close() end
            print(added .. " link ditambahkan."); sleep(1)

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
                else
                    print("[!] Tidak valid"); sleep(1)
                end
            end

        elseif opt == "c" then
            local cf = ask("Ketik 'hapus' untuk konfirmasi")
            if cf == "hapus" then
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
    print("Saat ini: " .. (HOP_MIN == 0 and "OFF" or (HOP_MIN .. " menit")))
    print("")
    local inp = ask("Hop tiap berapa menit? (0=OFF)")
    local v = tonumber(inp)
    if v and v >= 0 then
        HOP_MIN = v
        print("[+] Hop: " .. (HOP_MIN == 0 and "OFF" or (HOP_MIN .. " menit")))
    else
        print("[!] Tidak valid")
    end
    sleep(1)
end

-- ============================================
-- MAIN MENU
-- ============================================
local function main()
    PKG = read_file(PKG_FILE)

    while true do
        cls()
        print("=== SIMPLE HOPPER v1.2 ===")
        print("")

        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()

        print("Package  : " .. (PKG ~= "" and PKG or "-"))
        print("Cookie   : " .. (cookie ~= "" and (cookie:sub(1,16) .. "...") or "-"))
        print("PS links : " .. #ps)
        print("Hop      : " .. (HOP_MIN == 0 and "OFF" or (HOP_MIN .. " menit")))
        print("")
        print("1. Set package")
        print("2. Set cookie")
        print("3. Kelola PS links")
        print("4. Set hop interval")
        print("5. START")
        print("0. Keluar")
        print("")

        local ch = ask("Pilih")
        if     ch == "1" then menu_set_package()
        elseif ch == "2" then menu_set_cookie()
        elseif ch == "3" then menu_set_ps()
        elseif ch == "4" then menu_set_hop()
        elseif ch == "5" then
            run_hopper()
            cls()
            local rst = ask("Force stop Roblox? (y/n)")
            if rst == "y" and PKG ~= "" then
                su_exec("am force-stop " .. PKG)
                print("[+] Roblox ditutup.")
                sleep(1)
            end
        elseif ch == "0" then
            cls(); print("Keluar."); break
        end
    end
end

-- ============================================
-- ENTRY
-- ============================================
cls()
main()
