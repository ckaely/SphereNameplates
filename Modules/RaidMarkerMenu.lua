-------------------------------------------------------------------------------
--  SphereNameplates · RaidMarkerMenu
--
--  Menu radial de marquage WoW. Ouverture par double clic droit sur une sphere
--  PNJ (joueurs optionnels), avec les packs custom declares dans Config.lua.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.RaidMarkerMenu = SP.RaidMarkerMenu or {}
local RMM = SP.RaidMarkerMenu

local WHITE    = "Interface\\Buttons\\WHITE8x8"
local GLOW_TEX = "Interface\\Cooldown\\ping4"
local MASK_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local MARK_LABELS = {
    [1] = "Etoile",
    [2] = "Cercle",
    [3] = "Diamant",
    [4] = "Triangle",
    [5] = "Lune",
    [6] = "Carre",
    [7] = "Croix",
    [8] = "Crane",
}

local function DB()
    return SP.db or {}
end

local function Opt(key, fallback)
    local db = DB()
    if db[key] ~= nil then return db[key] end
    return fallback
end

local function Log(level, msg)
    if SP.Log and SP.Log[level] then
        SP.Log[level](SP.Log, "RaidMarkerMenu", msg)
    elseif SP.db and SP.db.raidmark_menu_debug and SP.Print then
        SP:Print("[RaidMarkerMenu] " .. tostring(msg))
    end
end

local function GetAnchorFrame(data)
    if data and data.orbFrame and data.orbFrame.IsShown and data.orbFrame:IsShown() then return data.orbFrame end
    if data and data.orb and data.orb.IsShown and data.orb:IsShown() then return data.orb end
    if data and data.raidMarkerMenuButton and data.raidMarkerMenuButton.IsShown and data.raidMarkerMenuButton:IsShown() then return data.raidMarkerMenuButton end
    return nil
end

local function IsPlayerType(unitType)
    return unitType == "ENEMY_PLAYER" or unitType == "FRIENDLY_PLAYER"
end

local function IsAllowed(data)
    if not data or not data.orbFrame then return false end
    if Opt("raidmark_menu_enabled", true) == false then return false end
    if IsPlayerType(data.unitType) and Opt("raidmark_menu_players", false) ~= true then return false end
    return true
end

local function SafeSetTexCoord(tex, uv)
    if not tex then return end
    if uv then
        tex:SetTexCoord(uv[1] or 0, uv[2] or 1, uv[3] or 0, uv[4] or 1)
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function ApplyMarkerTexture(tex, mark)
    if not tex then return end
    local path, uv
    if SP.GetRaidMarkerIcon then
        path, uv = SP:GetRaidMarkerIcon(mark, DB().raidmark_pack)
    end
    path = path or ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(mark))
    tex:SetTexture(path)
    SafeSetTexCoord(tex, uv)
end

function RMM:Ensure()
    if self.frame then return self.frame end

    local catcher = CreateFrame("Frame", "SPRaidMarkerMenuCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(860)
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", function()
        RMM:Hide()
    end)
    self.catcher = catcher

    local f = CreateFrame("Frame", "SPRaidMarkerMenu", UIParent)
    f:SetSize(2, 2)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(900)
    f:EnableMouse(false)
    f.buttons = {}
    f:SetScript("OnUpdate", function(_, elapsed)
        RMM:OnUpdate(elapsed)
    end)
    f:Hide()

    f.labelBg = f:CreateTexture(nil, "BACKGROUND")
    f.labelBg:SetTexture(WHITE)
    f.labelBg:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.labelBg:SetSize(96, 28)
    f.labelBg:SetVertexColor(0, 0, 0, 0.48)
    f.labelBg:Hide()

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.label:SetPoint("CENTER", f.labelBg, "CENTER", 0, 1)
    f.label:SetTextColor(1, 0.82, 0, 1)
    f.label:Hide()

    self.frame = f
    return f
end

function RMM:ResetButton(btn)
    if not btn then return end
    btn:Hide()
    btn:SetScale(1)
    btn:SetAlpha(0)
    btn._mark = nil
    if btn.glow then btn.glow:SetAlpha(0) end
end

function RMM:GetButton(index)
    local f = self:Ensure()
    if f.buttons[index] then return f.buttons[index] end

    local btn = CreateFrame("Button", nil, f)
    btn:SetFrameLevel(f:GetFrameLevel() + 2)
    btn:RegisterForClicks("LeftButtonUp")
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetTexture(WHITE)
    btn.bg:SetAllPoints(btn)
    btn.bg:SetVertexColor(0, 0, 0, 0.20)

    btn.mask = btn:CreateMaskTexture()
    btn.mask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    btn.mask:SetAllPoints(btn)
    btn.bg:AddMaskTexture(btn.mask)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    btn.icon:AddMaskTexture(btn.mask)

    btn.glow = btn:CreateTexture(nil, "OVERLAY")
    btn.glow:SetTexture(GLOW_TEX)
    btn.glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6)
    btn.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 6, -6)
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1, 0.8, 0.1, 1)
    btn.glow:SetAlpha(0)

    btn:SetScript("OnEnter", function(selfBtn)
        RMM.hoverButton = selfBtn
        RMM:ShowLabel(MARK_LABELS[selfBtn._mark] or "")
    end)
    btn:SetScript("OnLeave", function()
        RMM.hoverButton = nil
        RMM:ShowLabel("")
    end)
    btn:SetScript("OnClick", function(selfBtn)
        RMM:ApplyMark(selfBtn._mark)
    end)

    f.buttons[index] = btn
    return btn
end

function RMM:ShowLabel(text)
    local f = self.frame
    if not f then return end
    if not text or text == "" then
        f.label:Hide()
        f.labelBg:Hide()
        return
    end
    f.label:SetText(text)
    local w = math.max(70, (string.len(text or "") * 8) + 24)
    f.labelBg:SetSize(w, 28)
    f.labelBg:Show()
    f.label:Show()
end

function RMM:LayoutButtons(progress)
    local f = self.frame
    if not f then return end
    local radius = tonumber(Opt("raidmark_menu_radius", 58)) or 58
    local size = tonumber(Opt("raidmark_menu_icon_size", 38)) or 38
    local alpha = tonumber(Opt("raidmark_menu_alpha", 1)) or 1
    local scale = tonumber(Opt("raidmark_menu_scale", 1)) or 1
    local p = progress or 1
    local r = radius * (0.70 + 0.30 * p)
    for i = 1, 8 do
        local btn = self:GetButton(i)
        local angle = -math.pi / 2 + (i - 1) * (math.pi * 2 / 8)
        local x = math.cos(angle) * r
        local y = -math.sin(angle) * r
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", f, "CENTER", x, y)
        btn:SetSize(size, size)
        btn:SetScale(scale)
        btn:SetAlpha(alpha * p)
        ApplyMarkerTexture(btn.icon, i)
        btn._mark = i
        btn:Show()
    end
end

function RMM:ShowForPlate(data, unit)
    if not IsAllowed(data) then return end
    local f = self:Ensure()
    self.data = data
    self.unit = unit
    self.anim = "open"
    self.animT = 0
    self.animD = 0.14
    self.hoverButton = nil

    f:ClearAllPoints()
    f:SetParent(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(900)
    if not self:UpdateAnchor() then return end
    f:Show()
    if self.catcher then self.catcher:Show() end
    self:LayoutButtons(0.01)
    Log("Debug", "open " .. tostring(unit))
end

function RMM:Hide()
    if not self.frame or not self.frame:IsShown() then return end
    if self.anim == "close" then return end
    self.anim = "close"
    self.animT = 0
    self.animD = 0.10
    if self.catcher then self.catcher:Hide() end
end

function RMM:FinishHide()
    local f = self.frame
    if not f then return end
    for _, btn in ipairs(f.buttons or {}) do self:ResetButton(btn) end
    self:ShowLabel("")
    f:Hide()
    if self.catcher then self.catcher:Hide() end
    self.data = nil
    self.unit = nil
    self.hoverButton = nil
    self.anim = nil
    self.animT = 0
end

function RMM:UpdateAnchor()
    if not self.frame or not self.data then return false end
    local anchor = GetAnchorFrame(self.data)
    if not anchor then
        self:Hide()
        return false
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    return true
end

function RMM:OnUpdate(elapsed)
    local f = self.frame
    if not f or not f:IsShown() then return end
    if not self:UpdateAnchor() then return end

    if not self.anim then
        self:LayoutButtons(1)
        for _, btn in ipairs(f.buttons or {}) do
            if btn == self.hoverButton then
                btn:SetScale((tonumber(Opt("raidmark_menu_scale", 1)) or 1) * 1.16)
                if Opt("raidmark_menu_hover_glow", true) ~= false then btn.glow:SetAlpha(0.65) end
            elseif btn.glow then
                btn.glow:SetAlpha(0)
            end
        end
        return
    end

    self.animT = (self.animT or 0) + (elapsed or 0)
    local d = self.animD or 0.12
    local p = math.min(1, self.animT / d)
    if self.anim == "close" then p = 1 - p end
    self:LayoutButtons(p)

    for _, btn in ipairs(f.buttons or {}) do
        if btn == self.hoverButton then
            btn:SetScale((tonumber(Opt("raidmark_menu_scale", 1)) or 1) * 1.16)
            if Opt("raidmark_menu_hover_glow", true) ~= false then btn.glow:SetAlpha(0.65) end
        elseif btn.glow then
            btn.glow:SetAlpha(0)
        end
    end

    if self.animT >= d then
        if self.anim == "close" then
            self:FinishHide()
        else
            self.anim = nil
            self.animT = 0
        end
    end
end

function RMM:ApplyMark(mark)
    if not mark or not self.unit then return end
    local ok, err = false, nil
    if SetRaidTarget then
        ok, err = pcall(SetRaidTarget, self.unit, mark)
        if not ok then
            local sameTarget = false
            if UnitIsUnit then
                local okSame, same = pcall(UnitIsUnit, self.unit, "target")
                sameTarget = okSame and same == true
            end
            if sameTarget then
                ok, err = pcall(SetRaidTarget, "target", mark)
            end
        end
    else
        err = "SetRaidTarget unavailable"
    end
    if not ok then
        Log("Warn", "SetRaidTarget failed mark=" .. tostring(mark) .. " unit=" .. tostring(self.unit) .. " err=" .. tostring(err))
    else
        if self.data and self.unit and SP.Orb and SP.Orb.UpdateRaidMark then
            pcall(SP.Orb.UpdateRaidMark, SP.Orb, self.data, self.unit)
            if C_Timer and C_Timer.After then
                local data, unit = self.data, self.unit
                C_Timer.After(0.05, function()
                    if data and unit and SP.Orb and SP.Orb.UpdateRaidMark then
                        pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, unit)
                    end
                end)
            end
        end
    end
    if Opt("raidmark_menu_close_after_action", true) ~= false then
        self:Hide()
    end
end

function RMM:Attach(data, unit)
    if not data then return end
    if not IsAllowed(data) then
        self:Detach(data, unit)
        return
    end
    if not data.raidMarkerMenuButton then
        local b = CreateFrame("Button", nil, data.orbFrame)
        b:SetAllPoints(data.orbFrame)
        b:SetFrameLevel((data.orbFrame:GetFrameLevel() or 1) + 30)
        b:RegisterForClicks("RightButtonUp")
        b:SetScript("OnClick", function(selfBtn, button)
            if button ~= "RightButton" then return end
            local now = GetTime()
            local win = (tonumber(Opt("raidmark_menu_double_click_ms", 350)) or 350) / 1000
            if selfBtn._lastUnit == selfBtn._unit and selfBtn._lastClick and (now - selfBtn._lastClick) <= win then
                RMM:ShowForPlate(selfBtn._data, selfBtn._unit)
                selfBtn._lastClick = nil
                return
            end
            selfBtn._lastUnit = selfBtn._unit
            selfBtn._lastClick = now
        end)
        data.raidMarkerMenuButton = b
    end
    local b = data.raidMarkerMenuButton
    b:SetParent(data.orbFrame)
    b:SetAllPoints(data.orbFrame)
    b._data = data
    b._unit = unit
    b:Show()
    b:EnableMouse(true)
end

function RMM:Detach(data)
    if not data then return end
    if self.data == data then self:Hide() end
    if data.raidMarkerMenuButton then
        data.raidMarkerMenuButton:Hide()
        data.raidMarkerMenuButton._data = nil
        data.raidMarkerMenuButton._unit = nil
    end
end

function RMM:RefreshAttachments()
    if not SP.Plates then return end
    for unit, data in pairs(SP.Plates) do
        self:Attach(data, unit)
    end
end

function RMM:Reset()
    self:Hide()
end
