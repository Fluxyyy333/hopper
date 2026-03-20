-- Simple PS Hopper v1.1
-- Single package | Menu-based
-- Target: Termux + Root Android
-- ============================================

local HOPPER_LOG  = "/sdcard/hopper_log.txt"
local PS_FILE     = "/sdcard/private_servers.txt"
local PKG_FILE    = "/sdcard/.hopper_pkg"
local COOKIE_FILE = "/sdcard/.hopper_cookie"
local WATCHDOG    = 10

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

local function read_key(t)
    local h = io.popen("bash -c 'read -t "..(t or 1).." -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
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
    -- Tulis XML ke /sdcard dulu (tidak butuh root)
    local f = io.open(tmp, "w")
    if not f then log("inject_cookie: gagal buat tmp"); return end
    f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n")
    f:write("<map>\n")
    f:write('    <string name=".ROBLOSECURITY">' .. cookie .. "</string>\n")
    f:write("</map>\n")
    f:close()
    -- Copy ke data dir via su
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. target .. "'")
    su_exec("chmod 660 '" .. target .. "'")
    os.remove(tmp)
    log("Cookie injected")
end

local function launch(ps_link)
    su_exec("am force-stop " .. PKG)
    sleep(1)
    inject_cookie()
    local dp = ps_link:match("^intent://(.-)#Intent") or ps_link:gsub("^https?://","")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    log("Launch → " .. ps_link:sub(1, 60))
end

-- ============================================
-- MONITOR
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
    log("Package: " .. PKG .. " | PS: " .. #ps_list .. " | Hop: " .. HOP_MIN .. "m")

    local ptr         = 1
    local elapsed     = 0
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60

    launch(ps_list[ptr])
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    while true do
        -- Render monitor
        cls()
        print("=== HOPPER MONITOR ===")
        print("")
        print("Package : " .. PKG)
        print("PS      : " .. ((ptr == 1 and #ps_list or ptr-1)) .. "/" .. #ps_list)
        print("Status  : " .. (is_running() and "RUNNING" or "NOT RUNNING"))
        print("Crash   : " .. crash_count)
        print("Waktu   : " .. os.date("%H:%M:%S"))
        if HOP_MIN > 0 then
            local remain = math.max(0, hop_sec - elapsed)
            print(string.format("Hop in  : %dm %ds", math.floor(remain/60), remain%60))
        else
            print("Hop     : OFF")
        end
        print("")
        local cur = ptr == 1 and #ps_list or ptr - 1
        local link = ps_list[cur] or "-"
        print("PS link:")
        print("  " .. (link:sub(1,30) .. (link and #link > 30 and "..." .. link:sub(-12) or "")))
        print("")
        print("[q] Kembali ke menu")

        local key = read_key(1)
        if key and key:lower() == "q" then break end
        elapsed = elapsed + 1

        -- Watchdog
        if elapsed % WATCHDOG == 0 and not is_running() then
            crash_count = crash_count + 1
            log("Crash #" .. crash_count)
            local reptr = ptr - 1
            if reptr < 1 then reptr = #ps_list end
            launch(ps_list[reptr])
        end

        -- Hop
        if HOP_MIN > 0 and elapsed >= hop_sec then
            elapsed = 0
            log("Hop → PS " .. ptr)
            launch(ps_list[ptr])
            ptr = ptr + 1
            if ptr > #ps_list then ptr = 1 end
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

    -- Tampilkan package tersimpan
    local saved = read_file(PKG_FILE)
    if saved ~= "" then
        print("Tersimpan: " .. saved)
        print("")
    end

    -- List packages
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
        local del = ask("Ganti? (y/n)")
        if del:lower() ~= "y" then return end
    end

    print("Paste .ROBLOSECURITY (kosong=batal):")
    print("")
    local raw = ask("")
    if raw == "" then print("Batal."); sleep(1); return end

    -- Support format nick:pass:cookie
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
                print(string.format("  [%d] %s...%s", i, l:sub(1,25), l:sub(-12)))
            end
        end
        print("")
        print("a. Tambah  d. Hapus  c. Hapus semua  0. Kembali")
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
                    print("  [+] OK")
                else
                    print("  [!] Format tidak valid")
                end
            end
            if wf then wf:close() end
            print(added .. " link ditambahkan."); sleep(1)

        elseif opt == "d" then
            if #ps == 0 then print("Kosong."); sleep(1)
            else
                local n = tonumber(ask("Hapus nomor"))
                if n and ps[n] then
                    table.remove(ps, n)
                    local wf = io.open(PS_FILE, "w")
                    if wf then
                        for _, l in ipairs(ps) do wf:write(l .. "\n") end
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
    -- Load saved settings
    PKG = read_file(PKG_FILE)

    while true do
        cls()
        print("=== SIMPLE HOPPER v1.1 ===")
        print("")

        -- Status bar
        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()
        print("Package : " .. (PKG ~= "" and PKG or "-"))
        print("Cookie  : " .. (cookie ~= "" and (cookie:sub(1,16) .. "...") or "-"))
        print("PS links: " .. #ps)
        print("Hop     : " .. (HOP_MIN == 0 and "OFF" or (HOP_MIN .. " menit")))
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
            -- Setelah q dari monitor
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
