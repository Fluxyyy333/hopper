-- Simple PS Hopper v1.7
-- v1.7 Changes:
--   [FIX] safe_num() — prevents 'tonumber base out of range' crash from
--         garbled curl|sed pipelines or corrupt file reads
--   [FIX] All numeric file reads use safe_num() instead of raw tonumber()
--   [1] Static UI saat running — tidak ada cls/redraw, tidak ada ghost input
--   [2] Endpoint PS link — 1 PS khusus untuk age-up/fusion centralized
--   [3] Switch Mode — toggle regular <-> age-up mode dari main menu
--       Age-up mode: langsung launch endpoint PS, stay di sana (watchdog relaunch)
--   [4] Executor: Ronix → Delta (key path, autoexec path, license.txt)
-- ============================================

local HOPPER_LOG      = "/sdcard/hopper_log.txt"
local PS_FILE         = "/sdcard/private_servers.txt"
local PKG_FILE        = "/sdcard/.hopper_pkg"
local COOKIE_FILE     = "/sdcard/.hopper_cookie"
local STOP_FILE       = "/sdcard/.hopper_stop"
local ACCOUNT_FILE    = "/sdcard/.hopper_account"
local HOP_FILE        = "/sdcard/.hopper_hop"
local PTR_FILE        = "/sdcard/.hopper_ptr"
local ENDPOINT_FILE   = "/sdcard/.hopper_endpoint"   -- [NEW] endpoint PS link
local MODE_FILE       = "/sdcard/.hopper_mode"        -- [NEW] "normal" | "ageup"

local DELTA_KEY_DIR  = "/storage/emulated/0/Delta/Internals/Cache/"
local DELTA_KEY_PATH = DELTA_KEY_DIR .. "license.txt"
local DELTA_KEY_VAL  = "KEY_d1da50257e7edf4c344e746a942662c8"
local DELTA_AE_DIR   = "/storage/emulated/0/Delta/Autoexecute/"
local DELTA_AE_PATH  = DELTA_AE_DIR .. "Accept.lua"
local DELTA_AE_SCRIPT = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/Fluxyyy333/Auto-Rebirth-speed/refs/heads/main/jgndiambilbg"))()
getgenv().scriptkey="HsMgJbFoUwmvfzGxLESxMiUFuYpyqfFA"
loadstring(game:HttpGet("https://zekehub.com/scripts/AdoptMe/Utility.lua"))()]]

local DELTA_TRACK_PATH   = DELTA_AE_DIR .. "Trackstat.lua"
local DELTA_TRACK_SCRIPT = '_G.Config={UserID="37825915-c3be-41bc-987f-661da09d9b3c",discord_id="757533465213141053",Note="Pc"}local s;for i=1,5 do s=pcall(function()loadstring(game:HttpGet("https://cdn.yummydata.click/scripts/adoptmee"))()end)if s then break end wait(5)end'

local PKG     = ""
local HOP_MIN = 0
local MODE    = "normal"  -- "normal" | "ageup"

-- ============================================
-- HELPERS
-- ============================================
local function sleep(s)
    if s and s > 0 then os.execute("sleep " .. tostring(s)) end
end

local function su_exec(cmd)
    os.execute("su -c '" .. cmd:gsub("'","'\\''") .. "' >/dev/null 2>&1")
end

local function su_read(cmd)
    local h = io.popen("su -c '" .. cmd:gsub("'","'\\''") .. "' 2>/dev/null")
    if not h then return "" end
    local r = h:read("*a") or ""; h:close()
    return r
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

-- [v1.7 FIX] Safe numeric conversion — never crashes on garbage input.
-- Uses tostring() first so corrupt file reads or nil values never reach
-- the tonumber(str, base) code path that caused "base out of range".
local function safe_num(val, default)
    local n = tonumber(tostring(val or ""))
    if n and n == n then  -- NaN guard
        return n
    end
    return default or 0
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

local function load_endpoint()
    local ep = read_file(ENDPOINT_FILE)
    if ep ~= "" and ep:match("^https?://") and ep:lower():match("code=") then
        return ep
    end
    return nil
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

    local xml_tmp = "/sdcard/.hopper_xmlread.tmp"
    os.execute("su -c 'cat \"" .. target .. "\"' > '" .. xml_tmp .. "' 2>/dev/null")
    local xf = io.open(xml_tmp, "r")
    local existing = xf and xf:read("*a") or ""
    if xf then xf:close() end
    os.remove(xml_tmp)

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

    -- WebView cookie store
    local cookie_db = "/data/data/" .. PKG .. "/app_webview/Default/Cookies"
    local sql_tmp   = "/sdcard/.hopper_wv.sql"
    local safe      = cookie:gsub("'", "''")
    local sq3       = "/data/data/com.termux/files/usr/bin/sqlite3"

    local sf = io.open(sql_tmp, "w")
    if sf then
        local unix_now = os.time()
        local chrome_base = unix_now + 11644473600
        local now_us = string.format("%.0f", chrome_base * 1000000)
        local exp_us = string.format("%.0f", (chrome_base + 31536000) * 1000000)

        local schema_tmp = "/sdcard/.hopper_schema.tmp"
        os.execute("su -c '" .. sq3 .. " \"" .. cookie_db
            .. "\" \"PRAGMA table_info(cookies);\"' > '"
            .. schema_tmp .. "' 2>/dev/null")
        local sf2 = io.open(schema_tmp, "r")
        local schema_raw = sf2 and sf2:read("*a") or ""
        if sf2 then sf2:close() end
        os.remove(schema_tmp)

        local has_col = {}
        for line in schema_raw:gmatch("([^\n\r]+)") do
            local col = line:match("^%d+|([^|]+)|")
            if col then has_col[col] = true end
        end

        local col_names = {
            "creation_utc", "host_key", "name", "value",
            "path", "expires_utc",
            has_col["is_secure"]   and "is_secure"   or "secure",
            has_col["is_httponly"] and "is_httponly"  or "httponly",
            has_col["has_expires"] and "has_expires"  or nil,
            has_col["is_persistent"] and "is_persistent" or
                (has_col["persistent"] and "persistent" or nil),
            "priority",
        }
        local col_vals = {
            now_us, "'.roblox.com'", "'.ROBLOSECURITY'", "'" .. safe .. "'",
            "'/'", exp_us,
            "1", "1",
            has_col["has_expires"]   and "1" or nil,
            (has_col["is_persistent"] or has_col["persistent"]) and "1" or nil,
            "1",
        }
        local optional = {
            {"encrypted_value",       "X''"},
            {"samesite",              "-1"},
            {"top_frame_site_key",    "''"},
            {"source_scheme",         "2"},
            {"source_port",           "443"},
            {"is_same_party",         "0"},
            {"source_type",           "0"},
            {"has_cross_site_ancestor","0"},
            {"last_access_utc",       now_us},
            {"last_update_utc",       now_us},
            {"firstpartyonly",        "0"},
        }
        for _, pair in ipairs(optional) do
            if has_col[pair[1]] then
                table.insert(col_names, pair[1])
                table.insert(col_vals,  pair[2])
            end
        end

        local final_cols, final_vals = {}, {}
        for i, c in ipairs(col_names) do
            if c ~= nil and col_vals[i] ~= nil then
                table.insert(final_cols, c)
                table.insert(final_vals, col_vals[i])
            end
        end

        sf:write(string.format(
            "UPDATE cookies SET value='%s' WHERE name='.ROBLOSECURITY';\n", safe))
        sf:write(string.format(
            "INSERT OR IGNORE INTO cookies (%s) VALUES (%s);\n",
            table.concat(final_cols, ", "),
            table.concat(final_vals, ", ")))
        sf:close()

        local sq_err_tmp = "/sdcard/.hopper_sq_err.tmp"
        os.execute("su -c '" .. sq3 .. " \"" .. cookie_db
            .. "\" < \"" .. sql_tmp .. "\"' > '"
            .. sq_err_tmp .. "' 2>&1")
        local sq_err = read_file(sq_err_tmp)
        os.remove(sq_err_tmp)
        if sq_err ~= "" then log("sqlite3 error: " .. sq_err) end
        os.remove(sql_tmp)
        log("WebView cookie: sqlite3 executed")
    else
        log("WARN: gagal tulis sql tmp")
    end

    su_exec("mkdir -p '" .. dir .. "'")
    su_exec("cp '" .. tmp .. "' '" .. target .. "'")

    local uid_tmp = "/sdcard/.hopper_uid.tmp"
    os.execute("su -c 'stat -c %u /data/data/" .. PKG .. "' > '" .. uid_tmp .. "' 2>/dev/null")
    local uid = read_file(uid_tmp)
    os.remove(uid_tmp)
    if uid ~= "" then
        su_exec("chown " .. uid .. ":" .. uid .. " '" .. target .. "'")
    end
    su_exec("chmod 660 '" .. target .. "'")
    su_exec("restorecon '" .. target .. "'")
    os.remove(tmp)
    log("Cookie injected (uid=" .. uid .. ")")
end

local function inject_key()
    su_exec("mkdir -p '" .. DELTA_KEY_DIR .. "'")
    local f = io.open(DELTA_KEY_PATH, "w")
    if f then f:write(DELTA_KEY_VAL); f:close() end
    log("Key injected")
end

local function inject_autoexec()
    su_exec("mkdir -p '" .. DELTA_AE_DIR .. "'")
    local f = io.open(DELTA_AE_PATH, "w")
    if f then f:write(DELTA_AE_SCRIPT); f:close() end
    log("Autoexec injected")
end

local function inject_trackstat()
    su_exec("mkdir -p '" .. DELTA_AE_DIR .. "'")
    local f = io.open(DELTA_TRACK_PATH, "w")
    if f then f:write(DELTA_TRACK_SCRIPT); f:close() end
    log("Trackstat injected")
end

local function inject_all_verbose()
    out("[1/4] Injecting cookie...")
    inject_cookie()
    out("[2/4] Injecting Delta key...")
    inject_key()
    out("[3/4] Injecting autoexec...")
    inject_autoexec()
    out("[4/4] Injecting trackstat...")
    inject_trackstat()
    out("[+] All injected.")
end

local function launch(ps_link, label)
    log("Launching: " .. (label or ps_link:sub(1,40)))
    su_exec("am force-stop " .. PKG)
    sleep(2)
    su_exec("rm -rf /data/data/" .. PKG .. "/cache/*")
    su_exec("rm -rf /data/data/" .. PKG .. "/code_cache/*")
    su_exec("rm -rf /sdcard/Android/data/" .. PKG .. "/cache/*")

    local dp = ps_link:match("^intent://(.-)#Intent")
           or ps_link:gsub("^https?://","")
    local intent = "intent://" .. dp
        .. "#Intent;scheme=https;package=" .. PKG
        .. ";action=android.intent.action.VIEW;end"
    su_exec('am start --user 0 "' .. intent .. '"')
    log("Launched: " .. (label or "PS"))
end

-- ============================================
-- HOPPER LOOP — STATIC UI
-- [CHANGED] Tidak ada cls/redraw di dalam loop.
-- Semua update hanya ke log file.
-- ============================================
local function run_hopper()
    local is_ageup = (MODE == "ageup")

    -- Validasi
    if PKG == "" then
        out("[!] Package belum diset!"); sleep(2); return
    end

    if is_ageup then
        local ep = load_endpoint()
        if not ep then
            out("[!] Endpoint PS belum diset! Set dulu di menu PS Links.")
            sleep(2); return
        end
    else
        local ps_list = load_ps()
        if #ps_list == 0 then
            out("[!] Tidak ada PS link!"); sleep(2); return
        end
    end

    os.remove(STOP_FILE)
    os.execute("rm -f " .. HOPPER_LOG .. " 2>/dev/null")

    -- Cold-start check
    local cookie_db_path = "/data/data/" .. PKG .. "/app_webview/Default/Cookies"
    local db_ready = su_read('test -f "' .. cookie_db_path .. '" && echo Y'):match("Y")
    if not db_ready then
        out("[*] Fresh install — cold-starting app...")
        log("Fresh install: cold-start untuk inisialisasi WebView DB")
        su_exec("monkey -p " .. PKG .. " -c android.intent.category.LAUNCHER 1")
        sleep(8)
        su_exec("am force-stop " .. PKG)
        sleep(2)
        log("Cold-start selesai")
    else
        su_exec("am force-stop " .. PKG)
        sleep(2)
    end

    out("[*] Injecting...")
    inject_all_verbose()
    out("")

    -- ── STATIC BANNER ──────────────────────────────────
    cls()
    if is_ageup then
        out("╔══════════════════════════════╗")
        out("║   HOPPER v1.6 — AGE UP MODE  ║")
        out("╚══════════════════════════════╝")
        out("")
        out("Mode   : AGE UP (endpoint PS)")
        out("Pkg    : " .. PKG)
        out("Status : RUNNING")
        out("")
        out("Tekan Ctrl+C untuk stop.")
        out("Log    : " .. HOPPER_LOG)
        out("══════════════════════════════")
    else
        local ps_list = load_ps()
        out("╔══════════════════════════════╗")
        out("║   HOPPER v1.6 — NORMAL MODE  ║")
        out("╚══════════════════════════════╝")
        out("")
        out("Mode   : NORMAL (" .. #ps_list .. " PS)")
        out("Pkg    : " .. PKG)
        out("Hop    : " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
        out("Status : RUNNING")
        out("")
        out("Tekan Ctrl+C untuk stop.")
        out("Log    : " .. HOPPER_LOG)
        out("══════════════════════════════")
    end
    -- ────────────────────────────────────────────────────

    log("=== Hopper Started === Mode: " .. MODE)

    -- ── AGE UP MODE LOOP ──────────────────────────────
    if is_ageup then
        local ep = load_endpoint()
        log("Age-up endpoint: " .. ep:sub(1,40))
        launch(ep, "ENDPOINT")

        local ok, err = pcall(function()
            while true do
                sleep(10)
                if file_exists(STOP_FILE) then
                    log("Stop file detected")
                    return
                end
                if not is_running() then
                    log("Crash detected — relaunch endpoint")
                    launch(ep, "ENDPOINT (relaunch)")
                end
            end
        end)
        if not ok then log("Stopped: " .. tostring(err)) end

    -- ── NORMAL MODE LOOP ──────────────────────────────
    else
        local ps_list = load_ps()
        local ptr = 1
        local saved_ptr = safe_num(read_file(PTR_FILE))
        if saved_ptr and saved_ptr >= 1 and saved_ptr <= #ps_list then
            ptr = saved_ptr
            log("Resumed from PS " .. ptr)
        end
        os.remove(PTR_FILE)

        local cur_ps   = ptr
        local crash_count = 0
        local hop_sec  = HOP_MIN * 60
        local hop_time = os.time()
        local start_time = os.time()

        launch(ps_list[ptr], "PS " .. ptr .. "/" .. #ps_list)
        cur_ps = ptr; ptr = ptr + 1
        if ptr > #ps_list then ptr = 1 end

        local ok, err = pcall(function()
            while true do
                sleep(5)
                if file_exists(STOP_FILE) then
                    log("Stop file detected")
                    return
                end

                local now = os.time()
                local hop_elapsed = now - hop_time
                local running = is_running()

                -- Hop timer
                if HOP_MIN > 0 and hop_elapsed >= hop_sec then
                    log(string.format("Hop -> PS %d/%d", ptr, #ps_list))
                    launch(ps_list[ptr], "PS " .. ptr .. "/" .. #ps_list)
                    cur_ps = ptr; ptr = ptr + 1
                    if ptr > #ps_list then ptr = 1 end
                    hop_time = os.time()

                -- Crash watchdog
                elseif not running then
                    crash_count = crash_count + 1
                    log(string.format("Crash #%d — relaunch PS %d", crash_count, cur_ps))
                    launch(ps_list[cur_ps], "PS " .. cur_ps .. " (relaunch)")
                end
            end
        end)

        if not ok then log("Stopped: " .. tostring(err)) end

        save_file(PTR_FILE, tostring(cur_ps))
        log("Saved PS pointer: " .. cur_ps)
    end

    os.remove(STOP_FILE)
    log("=== Hopper Stopped ===")

    cls()
    out("========================")
    out("   HOPPER STOPPED")
    out("========================")
    out("")
    out("Cek log: " .. HOPPER_LOG)
    out("")
    sleep(1)
end

-- ============================================
-- MENU: SET PACKAGE
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

-- ============================================
-- MENU: SET COOKIE
-- ============================================
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

    if PKG ~= "" then
        out("[*] Injecting cookie...")
        inject_cookie()
        out("[+] Cookie injected.")
    end

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

-- ============================================
-- MENU: PS LINKS + ENDPOINT
-- [CHANGED] Tambah opsi 4 = Set Endpoint PS
-- ============================================
local function menu_set_ps()
    while true do
        cls()
        out("=== PS LINKS ===")
        out("")

        -- Tampilkan endpoint
        local ep = load_endpoint()
        out("Endpoint PS : " .. (ep and (ep:sub(1,30) .. "...") or "(belum diset)"))
        out("")

        -- Tampilkan normal PS list
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
        out("1=Tambah  2=Hapus  3=Clear  4=Set Endpoint  0=Kembali")
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
                    out("  [!] Tidak valid (harus https + code=)")
                end
            end
            if wf then wf:close() end
            out(added .. " PS ditambahkan."); sleep(1)

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
                out("[+] Semua PS dihapus."); sleep(1)
            end

        -- [NEW] Set Endpoint PS
        elseif opt == "4" then
            cls()
            out("=== SET ENDPOINT PS ===")
            out("")
            out("Endpoint PS = 1 PS khusus untuk age-up/fusion mode.")
            out("Semua hopper akan diarahkan ke sini saat mode Age-Up aktif.")
            out("")
            local cur_ep = load_endpoint()
            if cur_ep then
                out("Saat ini: " .. cur_ep:sub(1,50))
                out("")
                local ch = ask("Ganti? (y/n/hapus)")
                if ch:lower() == "hapus" then
                    save_file(ENDPOINT_FILE, "")
                    out("[+] Endpoint dihapus."); sleep(1)
                elseif ch:lower() ~= "y" then
                    -- batal
                else
                    out("Paste endpoint PS link:")
                    local link = ask("")
                    if link:match("^https?://") and link:lower():match("code=") then
                        save_file(ENDPOINT_FILE, link)
                        out("[+] Endpoint disimpan.")
                    else
                        out("[!] Tidak valid.")
                    end
                    sleep(1)
                end
            else
                out("Paste endpoint PS link (kosong=batal):")
                local link = ask("")
                if link ~= "" then
                    if link:match("^https?://") and link:lower():match("code=") then
                        save_file(ENDPOINT_FILE, link)
                        out("[+] Endpoint disimpan.")
                    else
                        out("[!] Tidak valid (harus https + code=).")
                    end
                    sleep(1)
                end
            end
        end
    end
end

-- ============================================
-- MENU: HOP INTERVAL
-- ============================================
local function menu_set_hop()
    cls()
    out("=== SET HOP INTERVAL ===")
    out("")
    out("Saat ini: " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))
    out("(Hanya berlaku di Normal Mode)")
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
-- MENU: SWITCH MODE
-- [NEW] Toggle antara normal dan ageup mode
-- ============================================
local function menu_switch_mode()
    cls()
    out("=== SWITCH MODE ===")
    out("")
    out("Mode saat ini : " .. MODE:upper())
    out("")
    out("Normal  = Hop rotation ke banyak PS")
    out("Age-Up  = Stay di 1 Endpoint PS (fusion/age-up)")
    out("")

    local ep = load_endpoint()
    if not ep and MODE == "normal" then
        out("[!] Warning: Endpoint PS belum diset.")
        out("    Set endpoint dulu di menu PS Links sebelum pindah ke Age-Up mode.")
        out("")
    end

    if MODE == "normal" then
        out("Pindah ke Age-Up mode? (y/n)")
    else
        out("Pindah ke Normal mode? (y/n)")
    end

    local ch = ask("")
    if ch:lower() == "y" then
        if MODE == "normal" then
            MODE = "ageup"
        else
            MODE = "normal"
        end
        save_file(MODE_FILE, MODE)
        out("[+] Mode sekarang: " .. MODE:upper())
        log("Mode switched to: " .. MODE)
    else
        out("Batal.")
    end
    sleep(1)
end

-- ============================================
-- DIAGNOSTICS
-- ============================================
local function dump_shared_prefs()
    if PKG == "" then
        out("[!] Package belum diset!")
        sleep(1); return
    end
    cls()
    out("=== DUMP SHARED PREFS ===")
    out("")

    local prefs_dir = "/data/data/" .. PKG .. "/shared_prefs/"

    out("--- File list ---")
    local ls_out = su_read('ls -la "' .. prefs_dir .. '"')
    if ls_out ~= "" then
        for line in ls_out:gmatch("[^\r\n]+") do out("  " .. line) end
    else
        out("  (empty or not accessible)")
    end
    out("--- End ---")
    out("")

    local files_raw = su_read('ls "' .. prefs_dir .. '" 2>/dev/null')
    for fname in files_raw:gmatch("[^\r\n]+") do
        fname = fname:gsub("%c",""):gsub("^%s+",""):gsub("%s+$","")
        if fname:match("%.xml$") then
            local fpath = prefs_dir .. fname
            local sz_raw = su_read('stat -c %s "' .. fpath .. '" 2>/dev/null')
            local sz = tonumber(sz_raw:match("%d+")) or 0
            out("=== " .. fname .. " (" .. sz .. " bytes) ===")
            if sz == 0 then
                out("  (kosong atau tidak bisa dibaca)")
            elseif sz > 20480 then
                out("  (file terlalu besar, skip)")
            else
                local content = su_read('cat "' .. fpath .. '"')
                if content == "" then
                    out("  (tidak bisa dibaca)")
                else
                    for line in content:gmatch("[^\r\n]+") do out(line) end
                end
            end
            out("")
        end
    end

    local cookie_db = "/data/data/" .. PKG .. "/app_webview/Default/Cookies"
    local db_flag = su_read('test -f "' .. cookie_db .. '" && echo Y')
    if db_flag:match("Y") then
        out("WebView Cookies DB: EXISTS")
        local rows = su_read("/data/data/com.termux/files/usr/bin/sqlite3 '"
            .. cookie_db .. "' \".tables\" 2>/dev/null")
        out("  Tables: " .. (rows ~= "" and rows or "(none/error)"))
        local rows2 = su_read("/data/data/com.termux/files/usr/bin/sqlite3 '"
            .. cookie_db .. "' \"SELECT name,host_key,substr(value,1,20) FROM cookies LIMIT 10;\" 2>/dev/null")
        if rows2 ~= "" then
            for line in rows2:gmatch("[^\r\n]+") do out("  " .. line) end
        else
            out("  (no rows)")
        end
    else
        out("WebView Cookies DB: NOT FOUND")
    end

    out("")
    ask("Enter untuk kembali")
end

-- ============================================
-- MAIN MENU
-- ============================================
local function main()
    PKG = read_file(PKG_FILE)

    local hop_saved = safe_num(read_file(HOP_FILE))
    if hop_saved and hop_saved >= 0 then HOP_MIN = hop_saved end

    local mode_saved = read_file(MODE_FILE)
    if mode_saved == "ageup" or mode_saved == "normal" then
        MODE = mode_saved
    end

    while true do
        cls()
        out("╔══════════════════════════════╗")
        out("║    SIMPLE HOPPER  v1.6       ║")
        out("╚══════════════════════════════╝")
        out("")

        local cookie = read_file(COOKIE_FILE)
        local ps     = load_ps()
        local ep     = load_endpoint()

        out("Package  : " .. (PKG ~= "" and PKG or "-"))

        local acct = read_file(ACCOUNT_FILE)
        if acct ~= "" then
            local aname, aid = acct:match("^(.+):(%d+)$")
            if aname then
                out("Account  : " .. aname .. " (" .. aid .. ")")
            else
                out("Account  : " .. acct)
            end
        elseif cookie ~= "" then
            out("Cookie   : " .. cookie:sub(1,16) .. "...")
        else
            out("Cookie   : -")
        end

        out("PS       : " .. #ps .. " links")
        out("Endpoint : " .. (ep and (ep:sub(1,28) .. "...") or "(belum diset)"))
        out("Hop      : " .. (HOP_MIN == 0 and "OFF" or HOP_MIN .. "m"))

        -- Mode indicator
        if MODE == "ageup" then
            out("Mode     : [ AGE-UP ] ← aktif")
        else
            out("Mode     : [ NORMAL ] ← aktif")
        end

        local saved_ptr = read_file(PTR_FILE)
        if saved_ptr ~= "" and MODE == "normal" then
            out("Resume   : PS " .. saved_ptr)
        end

        out("")
        out("1. Set package")
        out("2. Set cookie")
        out("3. Kelola PS links + Endpoint")
        out("4. Set hop interval")
        out("5. Switch mode (" .. (MODE == "normal" and "Normal → Age-Up" or "Age-Up → Normal") .. ")")
        out("6. START")
        out("7. Diagnostik")
        out("0. Keluar")
        out("")
        local ch = ask("Pilih")
        if     ch == "1" then menu_set_package()
        elseif ch == "2" then menu_set_cookie()
        elseif ch == "3" then menu_set_ps()
        elseif ch == "4" then menu_set_hop()
        elseif ch == "5" then menu_switch_mode()
        elseif ch == "6" then run_hopper()
        elseif ch == "7" then dump_shared_prefs()
        elseif ch == "0" then cls(); out("Keluar."); break
        end
    end
end

-- ============================================
-- ENTRY
-- ============================================
cls()
main()
