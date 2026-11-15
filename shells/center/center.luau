-- The control center's logic: it watches what the system says and carries its
-- orders. Nothing here draws.

local pending = nil               -- the network being joined, if any

-- ── the network ──────────────────────────────────────────────────
sys.watch("network", function(n)
    local list = {}
    for i, x in ipairs(n.networks or {}) do
        local note
        if x.active then note = "подключено"
        elseif x.known then note = "сохранено"
        elseif x.secure then note = "защищена"
        else note = "открыта" end
        --  The signal bars read 0..1; the service says 0..1, a report in
        --  0..100 is brought down to it.
        local s = tonumber(x.strength) or 0
        if s > 1 then s = s / 100 end
        list[i] = {
            ssid = x.ssid or "", note = note,
            active = x.active and 1 or 0,
            secure = x.secure and true or false,
            known  = x.known and true or false,
            strength = s,
        }
    end
    model.wifi_nets = list
    if pending and n.online and n.name == pending then pending = nil end
end)

on("wifi_toggle", function()
    pcall(sys.call, "network.wifi", not (fact["net.wifi"] == true))
end)

on("connect_net", function(i)
    local n = model.wifi_nets[i + 1]
    if not n then return end
    if n.secure and not n.known then
        text.pwd_name = n.ssid
        text.pwd_value = ""
        fact.pwd_error = false
        fact.pwd_open = true
        return
    end
    local ok, err = pcall(sys.call, "network.connect", n.ssid)
    if not ok then log("could not join:", err) end
end)

on("pwd_submit", function()
    local pw = text.pwd_value or ""
    if #pw < 8 then fact.pwd_error = true; return end
    local ssid = text.pwd_name
    fact.pwd_open = false
    fact.pwd_error = false
    pending = ssid
    local mine = ssid
    local ok, err = pcall(sys.call, "network.connect", ssid, pw)
    if not ok then
        log("could not join:", err)
        pending = nil
        return
    end
    --  NetworkManager does not say why a join failed (only iwd does), so a
    --  join that is not up after twenty-five seconds is taken as a wrong
    --  password, and the field is asked again.
    after(25000, function()
        if pending ~= mine then return end
        pending = nil
        text.pwd_name = mine
        fact.pwd_error = true
        fact.pwd_open = true
    end)
end)

-- ── the bluetooth ────────────────────────────────────────────────
sys.watch("bluetooth", function(b)
    local list = {}
    for i, d in ipairs(b.devices or {}) do
        local sub
        if d.connected then sub = "подключено"
        elseif d.paired then sub = "сопряжено"
        else sub = "нажмите для сопряжения" end
        if d.battery and d.battery >= 0 then
            sub = string.format("%d%%", math.floor(d.battery * 100 + 0.5))
        end
        list[i] = {
            name = d.name or d.address or "", sub = sub,
            address = d.address or "",
            connected = d.connected and 1 or 0,
            icon = d.icon or "",
        }
    end
    model.bt_devs = list
end)

on("bt_toggle", function()
    pcall(sys.call, "bluetooth.power", not (fact["bt.powered"] == true))
end)

on("bt_scan", function()
    pcall(sys.call, "bluetooth.scan", true)
end)

on("bt_tap", function(i)
    local d = model.bt_devs[i + 1]
    if not d then return end
    if d.connected == 1 then
        pcall(sys.call, "bluetooth.disconnect", d.address)
    else
        pcall(sys.call, "bluetooth.connect", d.address)
    end
end)

--  Pairing: BlueZ asks, and only this scene may answer it.
on("pair_accept", function()
    local kind = fact["bt.pairing"]
    local id = fact["bt.pairing_id"]
    if kind == "pin" or kind == "passkey" then
        local ok, err = pcall(sys.call, "bluetooth.answer", id, text.pair_code)
        if not ok then log("the code was not taken:", err) end
    elseif kind == "confirm" or kind == "authorize" then
        pcall(sys.call, "bluetooth.confirm", id)
    end
end)

on("pair_reject", function()
    pcall(sys.call, "bluetooth.cancel", fact["bt.pairing_id"])
end)

-- ── the sound ────────────────────────────────────────────────────
sys.watch("audio", function(a)
    fact.volume = a.volume or 0
    fact.muted  = a.muted and true or false
end)

on("volume_set", function(v) pcall(sys.call, "audio.volume", v) end)
on("mute", function() pcall(sys.call, "audio.mute") end)

-- ── the notices ──────────────────────────────────────────────────
--  The centre is the one that keeps them; it says how many there are.
on("note_count", function(n) fact.note_count = n end)

on("open_notes", function()
    fact.open = false
    pcall(sys.call, "say", "notes", "emit toggle")
end)

-- ── the power ────────────────────────────────────────────────────
on("ask_power", function(which) fact.ask = which end)

on("do_power", function()
    local which = fact.ask
    fact.ask = 0
    fact.open = false
    if which == 1 then pcall(sys.call, "session.poweroff")
    elseif which == 2 then pcall(sys.call, "session.reboot") end
end)

on("cancel_power", function() fact.ask = 0 end)

on("suspend", function()
    fact.open = false
    pcall(sys.call, "session.suspend")
end)

-- ── the bar's door and the launcher's release ────────────────────
on("fact:open", function(v)
    --  Closed by the bar's diamond or by Super: no dialog is left waiting
    --  for the next opening.
    if not v then
        fact.pwd_open = false
        fact.pwd_error = false
        fact.ask = 0
    end
    pcall(sys.call, "say", "bar", "emit center_state " .. (v and "1" or "0"))
end)

on("suppress", function()
    fact.suppress = true
    after(500, function() fact.suppress = false end)
end)
