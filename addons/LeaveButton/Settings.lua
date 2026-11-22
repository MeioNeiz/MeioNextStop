-- Options panel (Esc > Options > AddOns > LeaveButton, or /leavebutton). Settings write
-- straight into LeaveButtonDB.
local _, ns = ...

local category

local function Register()
    if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("LeaveButton")

    local beside = Settings.RegisterAddOnSetting(category, "LEAVEBUTTON_BESIDE", "besideBar",
        ns.db, Settings.VarType.Boolean, "Beside flight bar", true)
    local tip = "While flying, the button sits left of FlareUI's Flight Timer bar "
        .. "(destination and time left) and follows it when you move the bar in Edit Mode. "
        .. "A position you shift-drag the button to wins. /leavebutton beside on||off"
    if ns.FlareBarOff() then
        tip = tip .. "\n\n|cffff8080FlareUI's Flight Timer is off|r: turn it on in "
            .. "FlareUI > Resource Bars for the time left on a flight."
    end
    Settings.CreateCheckbox(category, beside, tip)
    if Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback("LEAVEBUTTON_BESIDE", function() ns.Place() end)
    end

    if layout and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("Move button", "Move",
            function() ns.SetPlacing(not ns.IsPlacing()) end,
            "Show the button now to place it: shift-drag it, then click it. "
                .. "/leavebutton move", true))
        layout:AddInitializer(CreateSettingsButtonInitializer("Reset position", "Reset",
            ns.ResetPosition, "Back above the action bars, or beside FlareUI's Flight "
                .. "Timer while flying. /leavebutton reset", true))
    end
    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local ok, err = pcall(Register)
    if not ok then geterrorhandler()(err) end
end)

function ns.OpenSettings()
    if not category then return false end
    Settings.OpenToCategory(category:GetID())
    return true
end

function LeaveButton_OnAddonCompartmentClick()
    if not ns.OpenSettings() then ns.Help() end
end
