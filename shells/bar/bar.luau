-- The bar's logic: what the system is doing, told to the scene. Nothing here
-- draws; the clock and the tray list fill themselves, the scene asked for them.

-- ── the workspaces: a platform service ───────────────────────────
--  One record per monitor: which of its workspaces is the active one.
local monitors, desks = {}, {}

local function distribute()
    local records = {}
    for k = 0, 3 do
        local place = monitors[k]
        if not place then break end
        local own = 1
        for _, d in ipairs(desks) do
            if d.monitor == place and d.active then own = d.id end
        end
        records[k + 1] = { active = own }
    end
    model.mon = records
end

--  The renderer says which copy is which as soon as it places its surface.
for k = 0, 3 do
    on("text:screen." .. k .. ".name", function(name)
        monitors[k] = name
        distribute()
    end)
end

sys.watch("workspaces", function(w)
    local there, busy = {}, {}
    for _, d in ipairs(w.list) do
        there[d.id] = true
        busy[d.id] = d.windows > 0
    end
    for i = 1, 10 do
        fact["ws." .. i .. ".there"] = there[i] or i == w.active
        fact["ws." .. i .. ".busy"] = busy[i] or false
    end
    desks = w.list
    distribute()
end)

on("go", function(i) sys.call("workspaces.focus", i) end)

-- ── the volume ───────────────────────────────────────────────────
sys.watch("audio", function(a)
    fact.volume = a.volume or 0
    fact.muted = a.muted and true or false
end)

on("volume_step", function(notches) sys.call("audio.step", 0.05 * notches) end)
on("mute", function() sys.call("audio.mute") end)

-- ── the clock, in the line the old bar showed ────────────────────
--  "Sat, 15 Nov  21:53" — weekday, the day, the month, the time.
local days   = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function compose_clock()
    local wd = fact["clock.weekday"]
    local d  = fact["clock.day"]
    local mo = fact["clock.month"]
    local h  = fact["clock.hour"]
    local mi = fact["clock.minute"]
    if not wd or not d or not mo or not h or not mi then return end
    text.clockline = string.format("%s, %02d %s  %02d:%02d",
        days[wd + 1] or "--", d, months[mo] or "--", h, mi)
end

on("fact:clock.minute", compose_clock)
after(1500, compose_clock)

-- ── the keyboard's language, from sway ───────────────────────────
local function set_language(name)
    local s = (name or ""):lower()
    if s:find("russian", 1, true) or s:find("рус", 1, true) then
        text.lang = "RU"
    elseif s:find("english", 1, true) or s:find("англ", 1, true) then
        text.lang = "EN"
    elseif #s > 0 then
        text.lang = s:sub(1, 3):upper()
    end
end

run("swaymsg", { "-r", "-t", "get_inputs" }, function(out, code)
    if code ~= 0 or not out or out == "" then return end
    local ok, inputs = pcall(json.decode, out)
    if not ok or type(inputs) ~= "table" then return end
    for _, dev in ipairs(inputs) do
        if dev.type == "keyboard" and dev.xkb_active_layout_name then
            set_language(dev.xkb_active_layout_name)
            break
        end
    end
end)

--  One that does not end: sway reports its inputs while it lives.
spawn("swaymsg", { "-m", "-t", "subscribe", '["input"]' }, function(line)
    local ok, payload = pcall(json.decode, line)
    if not ok or type(payload) ~= "table" then return end
    local dev = payload.input
    if dev and dev.xkb_active_layout_name then
        set_language(dev.xkb_active_layout_name)
    end
end)

-- ── the tray's menu: a tree, walked one level at a time ──────────
local owner = nil                -- which icon the open menu belongs to
local root, path = {}, {}        -- that menu, whole; and which submenus have been entered

local function show(list)
    local rows = #path > 0 and { { back = true, label = "‹  Назад" } } or {}
    for _, it in ipairs(list) do rows[#rows + 1] = it end
    --  The plate's height: 8 above, 8 below, and 30 for a row (9 for a stripe).
    local h = 16
    for _, r in ipairs(rows) do
        if r.separator then h = h + 9 else h = h + 30 end
    end
    fact.menu_h = h
    model.rows = rows
end

on("activate", function(i)
    local it = model.tray_icons[i + 1]
    if it then sys.call("tray.activate", it.key) end
end)

on("menu", function(i)
    local it = model.tray_icons[i + 1]
    if not it then return end
    local ok, menu = pcall(sys.ask, "tray.menu", it.key)
    if not ok then
        -- No menu to read: let it show the menu itself, if it knows how.
        pcall(sys.call, "tray.context", it.key)
        return
    end
    owner, root, path = it, menu, {}
    show(menu)
    fact.menu_open = true
end)

on("choose", function(i)
    local r = model.rows[i + 1]
    if r.back then
        table.remove(path)
        show(#path > 0 and path[#path].children or root)
    elseif r.children and #r.children > 0 then
        path[#path + 1] = r
        show(r.children)
    else
        sys.call("tray.menu_click", owner.key, r.id)
        fact.menu_open = false
    end
end)

-- ── the doors to the other scenes ────────────────────────────────
on("open_center",    function() sys.call("say", "center",    "emit toggle") end)
on("open_launcher",  function() sys.call("say", "launcher",  "emit toggle") end)
on("open_clip",      function() sys.call("say", "clipboard", "emit toggle") end)
on("open_notes",     function() sys.call("say", "notes",     "emit toggle") end)
