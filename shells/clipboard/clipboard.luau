-- The clipboard's logic: it reads `cliphist`, keeps the list the scene shows,
-- and copies back what is picked. Pictures get a preview, made once.

local entries = {}                -- everything, as cliphist gives it
local view = {}                   -- the rows the scene shows, in order
local thumbs = {}                 -- id -> preview path, made once and kept
local asked = {}                  -- id -> true while its preview is being made
local previews                    -- (below) previews for the rows on show

-- ── the Russian count of the things ─────────────────────────────
local function count_text(n)
    if n == 0 then return "История пуста" end
    local last_two, last = n % 100, n % 10
    local word = "элементов"
    if last_two < 11 or last_two > 14 then
        if last == 1 then word = "элемент"
        elseif last >= 2 and last <= 4 then word = "элемента" end
    end
    return n .. " " .. word
end

local function filter()
    local q = (text.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    for _, e in ipairs(entries) do
        if q == "" or e.preview:lower():find(q, 1, true) then
            local is_image = e.image and true or false
            local thumb = thumbs[e.id]
            rows[#rows + 1] = {
                id = e.id,
                title = is_image and "Изображение"
                        or (e.binary and "Бинарные данные"
                        or (e.preview ~= "" and e.preview or "Пустой фрагмент")),
                note = e.preview,
                has_note = e.binary and true or false,
                is_image = is_image,
                is_binary = e.binary and true or false,
                glyph = is_image and "▧" or (e.binary and "◆" or "T"),
                --  a picture shows its glyph only until its preview is there
                glyph_show = not (is_image and thumb ~= nil),
                thumb = thumb or "",
            }
            if #rows >= 50 then break end
        end
    end
    model.clips = rows
    view = rows
    fact.sel = 0
    text.count_text = count_text(#entries)
    previews()
end

-- ── reading the history ──────────────────────────────────────────
local function refresh()
    run("cliphist", { "list" }, function(out, code)
        if code ~= 0 then return end
        entries = {}
        for line in (out or ""):gmatch("[^\n]+") do
            local id, preview = line:match("^(%d+)\t(.*)$")
            if id then
                local p = preview:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                local binary = p:find("[[ binary data", 1, true) ~= nil or p:find("image/", 1, true) ~= nil
                local low = p:lower()
                local image = binary and (low:find("png", 1, true) ~= nil or low:find("jpg", 1, true) ~= nil
                              or low:find("jpeg", 1, true) ~= nil or low:find("bmp", 1, true) ~= nil
                              or low:find("gif", 1, true) ~= nil or low:find("webp", 1, true) ~= nil
                              or low:find("tif", 1, true) ~= nil) or false
                entries[#entries + 1] = { id = tonumber(id), preview = p, binary = binary, image = image }
            end
        end
        filter()
    end)
end

--  A preview for every picture on show. Each is made once (the helper caches
--  the file too) and kept by id, so typing in the search does not lose them,
--  and they no longer depend on `cliphist list` finishing within a timer.
previews = function()
    for _, row in ipairs(view) do
        local id = row.id
        if row.is_image and not thumbs[id] and not asked[id] then
            asked[id] = true
            run("sway-clipboard-preview", { tostring(id) }, function(out, code)
                asked[id] = nil
                if code ~= nil and code ~= 0 then return end
                local path = (out or ""):gsub("%s+$", ""):gsub("^file://", "")
                if path == "" then return end
                thumbs[id] = path
                --  Only the rows still on show are touched.
                local changed = false
                for _, r in ipairs(view) do
                    if r.id == id then
                        r.thumb = path
                        r.glyph_show = false
                        changed = true
                    end
                end
                if changed then model.clips = view end
            end)
        end
    end
end

-- ── what the scene asks for ──────────────────────────────────────
on("text:query", filter)

on("pick", function(i)
    local row = view[i + 1]
    if row then
        run("sway-clipboard-select", { tostring(row.id) }, function() end)
    end
    fact.open = false
end)

local armed = 0                   -- which arming the 3 s timer belongs to

on("clear_req", function()
    if not fact.confirm then
        fact.confirm = true
        armed = armed + 1
        local mine = armed
        after(3000, function() if armed == mine then fact.confirm = false end end)
        return
    end
    fact.confirm = false
    run("sway-clipboard-clear", {}, function()
        entries, thumbs = {}, {}
        filter()
    end)
end)

--  Opening: the history is read again; the pictures get their previews as
--  soon as the list is in.
on("fact:open", function(v)
    if not v then return end
    fact.confirm = false
    if (text.query or "") ~= "" then text.query = "" end
    refresh()
    --  The release of Super (after Super+V) must not open the control center.
    pcall(sys.call, "say", "center", "emit suppress")
end)

--  One that does not end: what is copied is kept as it comes.
spawn("wl-paste", { "--watch", "cliphist", "store" }, function() end)

refresh()
