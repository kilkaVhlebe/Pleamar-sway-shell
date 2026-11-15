-- The notification centre's logic: it hands over the notices, shows the last
-- one that came as a toast, and tells the bar how many there are.

local notes = {}
local primed = false            -- the first look at the list is not news
local toast_id = nil            -- which one the toast belongs to

local watching = sys.watch("notifications", function(list)
    notes = list or {}
    local rows = {}
    for i, n in ipairs(notes) do
        local body = n.body or ""
        rows[i] = {
            id = n.id,
            app = n.app or "Уведомление",
            title = n.title or "",
            body = body,
            has_body = body ~= "",
            urgent = (n.urgency == "critical" or n.urgency == 2),
        }
    end
    model.notes = rows
    fact.note_count = #rows
    pcall(sys.call, "say", "bar", "emit note_count " .. #rows)
    pcall(sys.call, "say", "center", "emit note_count " .. #rows)

    if #notes == 0 then
        primed = true
        return
    end
    local top = notes[1]
    if not primed then
        primed = true
        toast_id = top.id
        return
    end
    if top.id ~= toast_id then
        toast_id = top.id
        text.toast_app = top.app or "Уведомление"
        text.toast_title = top.title or ""
        text.toast_body = top.body or ""
        fact.toast_has_body = (top.body or "") ~= ""
        fact.toast_urgent = (top.urgency == "critical" or top.urgency == 2)
        fact.toast_show = text.toast_title ~= ""
        if fact.toast_show then
            after(5000, function() fact.toast_show = false end)
        end
    end
end)

--  The notices stay until somebody decides: this is a centre, not a bar of
--  bubbles that fade. (The service is up once it is watched.)
if watching then pcall(sys.call, "notifications.keep", true) end

on("dismiss", function(i)
    local n = notes[i + 1]
    if n then pcall(sys.call, "notifications.dismiss", n.id) end
end)

on("clear", function()
    pcall(sys.call, "notifications.clear")
end)

on("fact:open", function(v)
    pcall(sys.call, "say", "bar", "emit note_open " .. (v and "1" or "0"))
end)
