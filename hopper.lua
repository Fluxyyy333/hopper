-- Simple PS Hopper v1.0
-- Single package, no frills
-- Target: Termux + Root Android
-- ============================================

local HOPPER_LOG = "/sdcard/hopper_log.txt"
local PS_FILE    = "/sdcard/private_servers.txt"
local PKG_FILE   = "/sdcard/.hopper_pkg"   -- simpan package terakhir
local WATCHDOG   = 10
local PKG        = ""
local HOP_MIN    = 0

-- ============================================
-- HELPERS
-- ============================================
local function sleep(s)
    if s and s > 0 then os.execute("sleep " .. tostring(s)) end
end

local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'", "'\\''") .. "' >/dev/null 2>&1")
end

local function su_cmd(cmd)
    local h = io.popen("su -c '" .. cmd:gsub("'", "'\\''") .. "' 2>&1")
    if not h then return "" end
    local r = h:read("*a") or ""; h:close()
    r = r:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return r
end

local function log(msg)
    local f = io.open(HOPPER_LOG, "a")
    if f then
        f:write(os.date("[%H:%M:%S] ") .. msg .. "\n")
        f:close()
    end
end

local function cls() io.write("\27[2J\27[3J\27[H\27[0m"); io.flush() end

local function ask(prompt)
    io.write(prompt .. " > "); io.flush()
    local tty = io.open("/dev/tty", "r")
    local r
    if tty then r = tty:read("*l"); tty:close() else r = io.read("*l") end
    return r and r:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local function read_key(t)
    local h = io.popen("bash -c 'read -t " .. (t or 1) ..
        " -n 1 k < /dev/tty 2>/dev/null && echo $k' 2>/dev/null")
    if not h then sleep(t or 1); return nil end
    local k = h:read("*l"); h:close()
    return (k and k ~= "") and k or nil
end

local COOKIE_FILE = "/sdcard/.hopper_cookie"

local function save_cookie(ck)
    local f = io.open(COOKIE_FILE, "w")
    if f then f:write(ck); f:close() end
    os.execute("chmod 600 '" .. COOKIE_FILE .. "'")
end

local function load_cookie()
    local f = io.open(COOKIE_FILE, "r")
    if not f then return "" end
    local c = f:read("*a") or ""; f:close()
    return c:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
end

local function inject_cookie(pkg, cookie)
    if not cookie or cookie == "" then return end
    local dir  = "/data/data/" .. pkg .. "/shared_prefs"
    local file = dir .. "/RobloxSharedPreferences.xml"
    local tmp  = "/tmp/hcookie.xml"
    local f = io.open(tmp, "w")
    if f then
        f:write("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n")
        f:write('    <string name=".ROBLOSECURITY">' .. cookie .. "</string>\n</map>\n")
        f:close()
    end
    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. file .. "'")
    su_exec("chmod 660 '" .. file .. "'")
    os.remove(tmp)
end


    local f = io.open(PKG_FILE, "w")
    if f then f:write(pkg); f:close() end
end

local function load_pkg()
    local f = io.open(PKG_FILE, "r")
    if not f then return "" end
    local p = f:read("*l") or ""; f:close()
    return p:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
end


    local h = io.popen("su -c 'pidof " .. PKG .. "' 2>/dev/null")
    if not h then return false end
    local r = h:read("*a") or ""; h:close()
    return r:match("%d+") ~= nil
end

-- ============================================
-- CORE
-- ============================================
local function launch(ps_link)
    su_exec("wm density 600")
    su_exec("am force-stop " .. PKG)
    sleep(1)
    inject_cookie(PKG, load_cookie())
    local dp     = ps_link:match("^intent://(.-)#Intent") or ps_link:gsub("^https?://", "")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    log("Launch → " .. ps_link:sub(1, 60))
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

-- ============================================
-- SETUP
-- ============================================
local function setup()
    cls()
    print("=== SIMPLE HOPPER v1.0 ===")
    print("")

    -- Detect packages
    local saved_pkg = load_pkg()
    if saved_pkg ~= "" then
        print("Package tersimpan: " .. saved_pkg)
        local reuse = ask("Pakai package ini? (y/n)")
        if reuse and reuse:lower() == "y" then
            PKG = saved_pkg
        end
    end

    if PKG == "" then
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

        if #pkgs == 0 then
            print("[!] Tidak ada package ditemukan!")
            print("    Masukkan nama package manual:")
            PKG = ask("Package")
        else
            print("Package tersedia:")
            for i, p in ipairs(pkgs) do
                print(string.format("  %d. %s", i, p))
            end
            print("")
            local inp = ask("Pilih nomor atau ketik package langsung")
            local n = tonumber(inp)
            if n and pkgs[n] then
                PKG = pkgs[n]
            else
                PKG = inp
            end
        end
    end

    if not PKG or PKG == "" then
        print("[!] Package tidak valid!"); sleep(2); return false
    end

    save_pkg(PKG)

    -- Cookie
    print("")
    local saved_cookie = load_cookie()
    if saved_cookie ~= "" then
        print("Cookie tersimpan: " .. saved_cookie:sub(1,20) .. "...")
        local reuse = ask("Pakai cookie ini? (y/n)")
        if reuse and reuse:lower() ~= "y" then
            saved_cookie = ""
        end
    end
    if saved_cookie == "" then
        print("Paste .ROBLOSECURITY cookie (kosong = skip):")
        local raw = ask("")
        if raw and raw ~= "" then
            local ck = raw:match("(_|WARNING.+)$") or raw
            save_cookie(ck)
            print("[+] Cookie disimpan.")
        else
            print("[-] Tanpa cookie.")
        end
    end

    -- Load PS
    local ps = load_ps()
    if #ps == 0 then
        print("")
        print("[!] Tidak ada PS link di " .. PS_FILE)
        print("    Isi file tersebut dengan format:")
        print("    https://www.roblox.com/games/ID?privateServerLinkCode=XXX")
        print("")
        print("    Atau paste link sekarang (kosong = batal):")
        local added = 0
        local wf = io.open(PS_FILE, "a")
        while true do
            local line = ask("")
            if not line or line == "" then break end
            if line:match("^https?://") and line:lower():match("code=") then
                if wf then wf:write(line .. "\n") end
                added = added + 1
                print("  [+] Ditambahkan")
            else
                print("  [!] Format tidak valid, skip")
            end
        end
        if wf then wf:close() end
        if added == 0 then
            print("Batal."); sleep(1); return false
        end
        ps = load_ps()
    end

    print("")
    print("[+] Package : " .. PKG)
    print("[+] PS links: " .. #ps)
    print("")

    -- Hop interval
    local hi = ask("Hop tiap berapa menit? (0 = tidak hop)")
    HOP_MIN = tonumber(hi) or 0
    if HOP_MIN < 0 then HOP_MIN = 0 end

    print("")
    print("Package : " .. PKG)
    print("PS      : " .. #ps .. " link")
    print("Hop     : " .. (HOP_MIN == 0 and "TIDAK" or (HOP_MIN .. " menit")))
    print("")
    local conf = ask("Mulai? (y/n)")
    if not conf or conf:lower() ~= "y" then
        print("Batal."); sleep(1); return false
    end

    return ps
end

-- ============================================
-- MONITOR
-- ============================================
local function render(ps_list, ptr, elapsed, hop_sec, crash_count)
    cls()
    print("=== HOPPER MONITOR ===")
    print("")
    print("Package : " .. PKG)
    print("PS      : " .. ptr .. "/" .. #ps_list)
    print("Status  : " .. (is_running() and "RUNNING" or "NOT RUNNING"))
    print("Crash   : " .. crash_count)
    print("Waktu   : " .. os.date("%H:%M:%S"))

    if HOP_MIN > 0 and hop_sec > 0 then
        local remain = hop_sec - elapsed
        if remain < 0 then remain = 0 end
        local m = math.floor(remain / 60)
        local s = remain % 60
        print(string.format("Hop in  : %dm %ds", m, s))
    else
        print("Hop     : OFF")
    end

    print("")
    print("PS saat ini:")
    local link = ps_list[ptr]
    if link then
        -- Tampilkan link terpotong tapi tetap informatif
        if #link > 50 then
            print("  " .. link:sub(1, 30) .. "..." .. link:sub(-15))
        else
            print("  " .. link)
        end
    end
    print("")
    print("[q] Stop")
end

-- ============================================
-- MAIN
-- ============================================
local function main()
    local ps_list = setup()
    if not ps_list or #ps_list == 0 then return end

    -- Bersihkan log lama
    os.execute("rm -f " .. HOPPER_LOG .. " 2>/dev/null")
    log("=== Hopper Started ===")
    log("Package: " .. PKG)
    log("PS links: " .. #ps_list)

    local ptr         = 1
    local elapsed     = 0
    local crash_count = 0
    local hop_sec     = HOP_MIN * 60

    -- Launch pertama
    launch(ps_list[ptr])
    ptr = ptr + 1
    if ptr > #ps_list then ptr = 1 end

    -- Main loop
    while true do
        render(ps_list, ptr, elapsed, hop_sec, crash_count)

        local key = read_key(1)
        if key and key:lower() == "q" then break end

        elapsed = elapsed + 1

        -- Watchdog
        if elapsed % WATCHDOG == 0 then
            if not is_running() then
                crash_count = crash_count + 1
                log("Crash #" .. crash_count .. " — relaunch PS " .. ptr)
                -- Relaunch ke PS yang sama (ptr sudah advance, mundur 1)
                local reptr = ptr - 1
                if reptr < 1 then reptr = #ps_list end
                launch(ps_list[reptr])
            end
        end

        -- Hop
        if HOP_MIN > 0 and hop_sec > 0 and elapsed >= hop_sec then
            elapsed = 0
            log("Hop → PS " .. ptr)
            launch(ps_list[ptr])
            ptr = ptr + 1
            if ptr > #ps_list then ptr = 1 end
        end
    end

    -- Stop
    cls()
    print("=== STOPPED ===")
    print("")
    local rst = ask("Force stop Roblox? (y/n)")
    if rst and rst:lower() == "y" then
        su_exec("am force-stop " .. PKG)
        print("[+] Roblox ditutup.")
    end
    log("=== Hopper Stopped ===")
    print(""); print("Selesai.")
end

-- ============================================
-- ENTRY
-- ============================================
cls()
print("")
print("Simple Hopper v1.0")
print("")
sleep(1)
main()
