-- Blizzard's MainMenuBarVehicleLeaveButton never appears on a flight path in this client:
-- it only updates on vehicle events, none of which fire for a taxi. This is a plain
-- (non-secure) stand-in: TaxiRequestEarlyLanding and VehicleExit aren't protected, so it
-- works in combat too.

local ADDON = ...
local DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 178 }   -- above the default action bars

local db
local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7" .. ADDON .. "|r: " .. msg)
end

local btn = CreateFrame("Button", "LeaveButtonFrame", UIParent)
btn:SetSize(40, 40)
btn:SetFrameStrata("HIGH")
btn:SetMotionScriptsWhileDisabled(true)
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForDrag("LeftButton")
btn:Hide()

local function Place()
    local p = db and db.point or DEFAULT_POINT
    btn:ClearAllPoints()
    btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end
Place()

btn:SetNormalTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Up]])
btn:SetPushedTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Down]])
btn:SetDisabledTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Down]])
for _, t in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(),
    btn:GetDisabledTexture() }) do
    t:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
end
btn:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")

local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("BOTTOM", btn, "TOP", 0, 4)

local TAXI_TITLE = TAXI_CANCEL or "Request Stop"
local TAXI_DESC = TAXI_CANCEL_DESCRIPTION or "You will get off at the next flight point."
local VEHICLE_TITLE = LEAVE_VEHICLE or "Leave Vehicle"
local MOVE_HINT = "Shift-drag to move"

local function BlizzardShowing()
    local b = _G.MainMenuBarVehicleLeaveButton
    return b and b:IsVisible() and b:GetEffectiveAlpha() > 0.5
end

local requested, placing = false, false
local function Update()
    local taxi = UnitOnTaxi("player")
    local vehicle = not taxi and CanExitVehicle and CanExitVehicle() and not BlizzardShowing()
    if not taxi then requested = false end
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

local function SetPlacing(on)
    placing = on
    Update()
    if on then Say(MOVE_HINT .. ", then click it or type /leavebutton move again.") end
end

btn:SetScript("OnClick", function(self)
    -- releasing a drag over the button can click it: never land by accident
    if self.dragEnd and GetTime() - self.dragEnd < 0.3 then return end
    if placing then
        SetPlacing(false)
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
    -- level with the button's top: ANCHOR_RIGHT covers the label above it
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 8, 0)
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
    if not placing then GameTooltip:AddLine(MOVE_HINT, 0.5, 0.5, 0.5) end
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

SLASH_LEAVEBUTTON1 = "/leavebutton"
SlashCmdList.LEAVEBUTTON = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "move" then
        SetPlacing(not placing)
    elseif cmd == "reset" then
        db.point = nil
        Place()
        Say("back at the default position.")
    else
        Say("shows on flight paths (and in vehicles when Blizzard's button doesn't).")
        Say("/leavebutton move: show it now to place it (" .. MOVE_HINT:lower() .. ")")
        Say("/leavebutton reset: default position")
    end
end
