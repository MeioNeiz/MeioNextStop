-- Blizzard's MainMenuBarVehicleLeaveButton never appears on a flight path in this client:
-- it only updates on vehicle events, none of which fire for a taxi. This is a plain
-- (non-secure) stand-in: TaxiRequestEarlyLanding and VehicleExit aren't protected, so it
-- works in combat too.

local ADDON, ns = ...
local PREFIX = "|cffb090ffLeaveButton:|r "

local db
function ns.Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end
local Say = ns.Say

local btn = CreateFrame("Button", "LeaveButtonFrame", UIParent)
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
    if not taxi then requested = false end
    -- not mid shift-drag: re-anchoring would drop the frame StartMoving holds
    if not btn.moving then Place() end
    if placing then
        label:SetText(MOVE_HINT)
        btn:SetEnabled(true)
        btn:Show()
    elseif taxi or vehicle then
        label:SetText(taxi and (requested and "Landing at next stop" or "Get off at next stop")
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
        Say(MOVE_HINT .. ", then click it or type |cffffd100/leavebutton move|r again.")
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
        requested = true
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
    else
        GameTooltip_SetTitle(GameTooltip, VEHICLE_TITLE)
    end
    if not placing then GameTooltip:AddLine(MOVE_HINT, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "VEHICLE_UPDATE",
    "UPDATE_BONUS_ACTIONBAR" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        LeaveButtonDB = LeaveButtonDB or {}
        db = LeaveButtonDB
        if db.besideBar == nil then db.besideBar = true end
        ns.db = db
        Place()
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    -- UnitOnTaxi can turn true a moment after PLAYER_CONTROL_LOST, hence the rechecks
    Update()
    C_Timer.After(0.5, Update)
    C_Timer.After(2, Update)
end)
-- safety net for a taxi start or landing no event reported
C_Timer.NewTicker(2, Update)

local function Cmd(text)
    return "|cffffd100" .. text .. "|r"
end

function ns.Help()
    Say("a \"get off at next stop\" button on flight paths (and in vehicles when "
        .. "Blizzard's doesn't show)")
    local beside = Cmd("/leavebutton beside on||off") .. " - while flying, sit left of"
        .. " FlareUI's Flight Timer bar (now " .. (db.besideBar and "on" or "off") .. ")"
    if ns.FlareBarOff() then
        beside = beside .. " |cff999999(that bar is off: FlareUI > Resource Bars)|r"
    end
    local lines = {
        Cmd("/leavebutton move") .. " - show it now to place it (" .. MOVE_HINT:lower() .. ")",
        Cmd("/leavebutton reset") .. " - back to the default position",
        beside,
        Cmd("/leavebutton settings") .. " - open the Settings panel",
        "Settings: Esc > Options > AddOns > LeaveButton",
    }
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
end

function ns.SetBeside(on)
    db.besideBar = on
    Place()
    Say("beside FlareUI's Flight Timer " .. (on and "|cff80ff80on|r" or "|cffff8080off|r"))
end

SLASH_LEAVEBUTTON1 = "/leavebutton"
SlashCmdList.LEAVEBUTTON = function(msg)
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
