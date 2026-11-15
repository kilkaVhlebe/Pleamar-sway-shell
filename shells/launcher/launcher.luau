-- The launcher's logic: it knows which applications there are, ranks them
-- against what is typed, and launches the chosen one. Nothing here draws.

local apps = {}                          -- what the `apps` service reports
local shown = {}                         -- the records the list shows, in order

local function filter()
    local q = (text.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local hits = {}
    for _, a in ipairs(apps) do
        local rank
        if q == "" then
            rank = 0
        else
            local n  = (a.name or ""):lower()
            local kw = (a.keywords or ""):lower()
            local gc = ((a.generic_name or "") .. " " .. (a.comment or "")):lower()
            if n:sub(1, #q) == q then rank = 0
            elseif n:find(q, 1, true) then rank = 1
            elseif kw:find(q, 1, true) then rank = 2
            elseif gc:find(q, 1, true) then rank = 3
            end
        end
        if rank then hits[#hits + 1] = { app = a, rank = rank } end
    end
    table.sort(hits, function(x, y)
        if x.rank ~= y.rank then return x.rank < y.rank end
        return (x.app.name or ""):lower() < (y.app.name or ""):lower()
    end)
    local out, keep = {}, {}
    for i = 1, math.min(#hits, 7) do
        local a = hits[i].app
        local sub = a.generic_name or ""
        out[i] = { name = a.name or "", sub = sub, has_sub = sub ~= "", icon = a.icon or "" }
        keep[i] = a
    end
    model.hits = out
    shown = keep
    fact.sel = 0
end

--  A platform service: on Linux, the .desktop files.
if not sys.watch("apps", function(list) apps = list; filter() end) then
    model.hits = {}
end

on("text:query", filter)

--  One that runs in a terminal goes through kitty: this system has no
--  `xdg-terminal-exec`, which is what `apps.launch` asks for.
local function words(s)
    local out = {}
    for w in string.gmatch(s or "", "%S+") do out[#out + 1] = w end
    return out
end

on("launch", function(i)
    local a = shown[i + 1]
    if a then
        if a.terminal then
            local argv = { "-e" }
            for _, w in ipairs(words(a.exec)) do argv[#argv + 1] = w end
            local ok, err = pcall(function() spawn("kitty", argv, function() end) end)
            if not ok then log("could not open a terminal:", err) end
        else
            local ok, err = pcall(sys.call, "apps.launch", a.exec)
            if not ok then log("could not launch:", err) end
        end
    end
    fact.open = false
end)

--  Opening: the field is empty again, and the control center is told that the
--  release of Super (after Super+D) must not open it.
on("fact:open", function(v)
    if not v then return end
    if (text.query or "") ~= "" then
        text.query = ""
    else
        filter()
    end
    pcall(sys.call, "say", "center", "emit suppress")
end)
