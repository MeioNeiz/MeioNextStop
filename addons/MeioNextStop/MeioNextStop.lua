-- Blizzard's MainMenuBarVehicleLeaveButton never appears on a flight path in this client:
-- it only updates on vehicle events, none of which fire for a taxi. This is a plain
-- (non-secure) stand-in: TaxiRequestEarlyLanding and VehicleExit aren't protected, so it
-- works in combat too.

local ADDON, ns = ...
local PREFIX = "|cffb090ffMeioNextStop:|r "

local db
function ns.Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end
local Say = ns.Say

local btn = CreateFrame("Button", "MeioNextStopFrame", UIParent)
btn:SetSize(40, 40)
btn:SetFrameStrata("HIGH")
btn:SetMotionScriptsWhileDisabled(true)
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForDrag("LeftButton")
btn:Hide()

btn:SetNormalTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Up]])
btn:SetPushedTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Down]])
btn:SetDisabledTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Down]])
for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(),
    btn:GetDisabledTexture() }) do
    t:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
end
btn:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")

local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")

local TAXI_TITLE = TAXI_CANCEL or "Request Stop"
local TAXI_DESC = TAXI_CANCEL_DESCRIPTION or "You will get off at the next flight point."
local VEHICLE_TITLE = LEAVE_VEHICLE or "Leave Vehicle"
local MOVE_HINT = "Shift-drag to move"

local requested, placing = false, false

-- The flight under way, from TakeTaxiNode: the points on the route and where they sit on the
-- taxi map. The game never says which point is next, so it is the first one not yet passed
-- over (closest approach). Saved so a /reload mid-air keeps it.
local PASS_YARDS, AWAY_YARDS, CATCH, RESUME = 200, 40, 15, 3600
local flight, landingAt

local function TaxiMapID()
    local fm = _G.FlightMapFrame
    if fm and fm:IsShown() and fm.GetMapID then return fm:GetMapID() end
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 10 do
        local info = map and C_Map.GetMapInfo(map)
        if not info or info.mapType <= Enum.UIMapType.Continent or not info.parentMapID
            or info.parentMapID == 0 then
            return map
        end
        map = info.parentMapID
    end
    return map
end

local function Yards(map, a, b)
    local w, h
    if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(map) end
    if not (w and w > 0 and h and h > 0) then w, h = 40000, 40000 end
    local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h
    return math.sqrt(dx * dx + dy * dy)
end

local function OnTake(slot)
    if not (db and NumTaxiNodes and GetNumRoutes and TaxiGetNodeSlot) then return end
    local here
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then here = i break end
    end
    local hops = GetNumRoutes(slot) or 0
    if not here or here == slot or hops < 1 then return end
    local map = TaxiMapID()
    local where = {}
    local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, map)
    for _, n in ipairs(ok and list or {}) do
        local p = n.position
        if n.slotIndex and p and p.x then where[n.slotIndex] = { x = p.x, y = p.y } end
    end
    local f = { names = { TaxiNodeName(here) }, pos = { where[here] }, map = map, next = 2,
                at = GetTime(), stamp = time() }
    for i = 1, hops do
        local s = TaxiGetNodeSlot(slot, i, false)
        f.names[i + 1], f.pos[i + 1] = s and TaxiNodeName(s), s and where[s]
        if not f.names[i + 1] then return end
    end
    flight, landingAt = f, nil
    db.flight = f
end

local function Track()
    local f = flight
    if not (f and f.map and f.next < #f.names and C_Map.GetPlayerMapPosition) then return end
    local p = C_Map.GetPlayerMapPosition(f.map, "player")
    local node = f.pos[f.next]
    if not (p and p.x and node) then return end
    local d = Yards(f.map, p, node)
    if not f.best or d < f.best then f.best = d end
    local after = f.pos[f.next + 1]
    if f.best <= PASS_YARDS and d > f.best + AWAY_YARDS
        or after and Yards(f.map, p, after) < PASS_YARDS then
        f.next, f.best = f.next + 1, nil
        f.stamp = time()
    end
end

local function ShortName(name)
    return name and name:match("^([^,]+)") or name
end

-- the point the flight reaches next, and seconds to landing there when MeioFlightTimes knows
local function NextStop()
    local api = _G.MeioFlightTimes_API
    if api and api.NextStop then
        local name, secs = api.NextStop()
        if name then return name, secs end
    end
    return flight and flight.names[flight.next]
end
ns.NextStop = NextStop

local function Clock(s)
    s = math.floor(s + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- FlareUI's Flight Timer bar (Modules/ResourceBars.lua, "FlareUI_Resource_flight"): it exists
-- only when that bar is on, and shows only while flying (and in Edit Mode)
function ns.FlareBar()
    return _G.FlareUI_Resource_flight
end

function ns.FlareBarOff()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("FlareUI")
    return loaded and not ns.FlareBar()
end

local besideBar = false
local function Place()
    local bar = ns.FlareBar()
    if bar and not bar.leaveButtonHooked then
        bar.leaveButtonHooked = true
        bar:HookScript("OnShow", Place)
        bar:HookScript("OnHide", Place)
    end
    besideBar = not placing and bar and bar:IsShown() and db and not db.point
        and db.besideBar and true or false
    btn:ClearAllPoints()
    label:ClearAllPoints()
    if besideBar then
        -- one row: label, button, then FlareUI's bar with the destination and time left
        btn:SetPoint("RIGHT", bar, "LEFT", -6, 0)
        label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    else
        local p = db and db.point --[[@as any]]
        if p then
            btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 178)   -- above the default action bars
        end
        label:SetPoint("BOTTOM", btn, "TOP", 0, 4)
    end
end
ns.Place = Place
Place()

local function BlizzardShowing()
    local b = _G.MainMenuBarVehicleLeaveButton
    return b and b:IsVisible() and b:GetEffectiveAlpha() > 0.5
end

local function Update()
    local taxi = UnitOnTaxi("player")
    local vehicle = not taxi and CanExitVehicle and CanExitVehicle() and not BlizzardShowing()
    if not taxi then
        requested, landingAt = false, nil
        if flight and GetTime() - flight.at > CATCH then flight, db.flight = nil, nil end
    elseif not flight and db and db.flight and time() - (db.flight.stamp or 0) < RESUME then
        flight = db.flight
    end
    -- not mid shift-drag: re-anchoring would drop the frame StartMoving holds
    if not btn.moving then Place() end
    if placing then
        label:SetText(MOVE_HINT)
        btn:SetEnabled(true)
        btn:Show()
    elseif taxi or vehicle then
        local landing = landingAt and "Landing at " .. ShortName(landingAt)
            or "Landing at next stop"
        label:SetText(taxi and (requested and landing or "Get off at next stop")
            or VEHICLE_TITLE)
        btn:SetEnabled(not requested)
        btn:Show()
    else
        btn:Hide()
    end
end

function ns.SetPlacing(on)
    placing = on
    Update()
    if on then
        Say(MOVE_HINT .. ", then click it or type |cffffd100/nextstop move|r again.")
    end
end

function ns.ResetPosition()
    db.point = nil
    Place()
    Say("back at the default position.")
end

btn:SetScript("OnClick", function(self)
    -- releasing a drag over the button can click it: never land by accident
    if self.dragEnd and GetTime() - self.dragEnd < 0.3 then return end
    if placing then
        ns.SetPlacing(false)
    elseif UnitOnTaxi("player") then
        TaxiRequestEarlyLanding()
        requested, landingAt = true, NextStop()
    else
        VehicleExit()
    end
    Update()
end)
btn:SetScript("OnDragStart", function(self)
    if not IsShiftKeyDown() then return end
    self.moving = true
    self:StartMoving()
end)
btn:SetScript("OnDragStop", function(self)
    if not self.moving then return end
    self.moving = false
    self.dragEnd = GetTime()
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    db.point = { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
    Place()
end)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    if besideBar then
        -- right is FlareUI's bar, left the label
        GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 6)
    else
        -- level with the button's top: ANCHOR_RIGHT covers the label above it
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 8, 0)
    end
    if placing then
        GameTooltip_SetTitle(GameTooltip, ADDON)
        GameTooltip:AddLine(MOVE_HINT .. ". Click when done.", 1, 1, 1, true)
    elseif UnitOnTaxi("player") then
        GameTooltip_SetTitle(GameTooltip, TAXI_TITLE)
        local c = NORMAL_FONT_COLOR
        GameTooltip:AddLine(TAXI_DESC, c.r, c.g, c.b, true)
        local name, secs = NextStop()
        if requested and landingAt then name, secs = landingAt, nil end
        if name then
            local last = flight and name == flight.names[#flight.names]
            GameTooltip:AddLine(("Next stop: |cffffffff%s|r%s%s"):format(ShortName(name),
                secs and (", ~%s"):format(Clock(secs)) or "",
                last and " |cff999999(the end)|r" or ""), c.r, c.g, c.b, true)
        end
    else
        GameTooltip_SetTitle(GameTooltip, VEHICLE_TITLE)
    end
    if not placing then GameTooltip:AddLine(MOVE_HINT, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

-- fresh: nothing saved under our name; the old folder (NextStop) loads after us
-- and may have it
local fresh
local function LoadDB()
    if not MeioNextStopDB and type(NextStopDB) == "table" then
        MeioNextStopDB = NextStopDB
    end
    NextStopDB = nil
    fresh = not MeioNextStopDB
    MeioNextStopDB = MeioNextStopDB or {}
    db = MeioNextStopDB
    if db.besideBar == nil then db.besideBar = true end
    ns.db = db
    Place()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "VEHICLE_UPDATE",
    "UPDATE_BONUS_ACTIONBAR" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            LoadDB()
        elseif arg1 == "NextStop" and fresh then
            MeioNextStopDB = nil
            LoadDB()
        end
        return
    end
    -- UnitOnTaxi can turn true a moment after PLAYER_CONTROL_LOST, hence the rechecks
    Update()
    C_Timer.After(0.5, Update)
    C_Timer.After(2, Update)
end)
-- safety net for a taxi start or landing no event reported
C_Timer.NewTicker(2, Update)
C_Timer.NewTicker(0.25, function()
    if flight and UnitOnTaxi("player") then Track() end
end)
if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTake) end

local function Cmd(text)
    return "|cffffd100" .. text .. "|r"
end

function ns.Help()
    Say("a \"get off at next stop\" button on flight paths (and in vehicles when "
        .. "Blizzard's doesn't show)")
    local beside = Cmd("/nextstop beside on||off") .. " - while flying, sit left of"
        .. " FlareUI's Flight Timer bar (now " .. (db.besideBar and "on" or "off") .. ")"
    if ns.FlareBarOff() then
        beside = beside .. " |cff999999(that bar is off: FlareUI > Resource Bars)|r"
    end
    local lines = {
        Cmd("/nextstop move") .. " - show it now to place it (" .. MOVE_HINT:lower() .. ")",
        Cmd("/nextstop reset") .. " - back to the default position",
        beside,
        Cmd("/nextstop settings") .. " - open the Settings panel",
        "Settings: Esc > Options > AddOns > MeioNextStop",
    }
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
end

function ns.SetBeside(on)
    db.besideBar = on
    Place()
    Say("beside FlareUI's Flight Timer " .. (on and "|cff80ff80on|r" or "|cffff8080off|r"))
end

SLASH_MEIONEXTSTOP1 = "/nextstop"
SLASH_MEIONEXTSTOP2 = "/leavebutton"
SlashCmdList.MEIONEXTSTOP = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "" or cmd == "help" or cmd == "?" then
        ns.Help()
    elseif cmd == "move" then
        ns.SetPlacing(not placing)
    elseif cmd == "reset" then
        ns.ResetPosition()
    elseif cmd == "beside" and (arg == "on" or arg == "off") then
        ns.SetBeside(arg == "on")
    elseif cmd == "settings" or cmd == "options" then
        if not ns.OpenSettings() then ns.Help() end
    else
        Say(("unknown command \"%s\""):format(cmd))
        ns.Help()
    end
end

function ns.IsPlacing()
    return placing
end

-- The old folder (NextStop, before the Meio rename) may still be installed: both would run.
-- Its slash command is pointed here and the player told to disable it.
local oldFolder = CreateFrame("Frame")
oldFolder:RegisterEvent("PLAYER_LOGIN")
oldFolder:SetScript("OnEvent", function()
    if not C_AddOns.IsAddOnLoaded("NextStop") then return end
    SlashCmdList.NEXTSTOP = SlashCmdList.MEIONEXTSTOP
    if hash_SlashCmdList then
        hash_SlashCmdList["/NEXTSTOP"] = nil
        hash_SlashCmdList["/LEAVEBUTTON"] = nil
    end
    Say("the old NextStop addon is still enabled: disable it in the AddOns list"
        .. " (MeioNextStop replaces it)")
end)
