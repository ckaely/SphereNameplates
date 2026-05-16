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

local MARK_COLORS = {
    [1] = {1.00, 0.88, 0.18}, -- star
    [2] = {1.00, 0.55, 0.05}, -- circle
    [3] = {0.86, 0.25, 1.00}, -- diamond
    [4] = {0.30, 1.00, 0.25}, -- triangle
    [5] = {0.35, 0.65, 1.00}, -- moon
    [6] = {0.10, 0.95, 1.00}, -- square
    [7] = {1.00, 0.18, 0.10}, -- cross
    [8] = {0.92, 0.92, 0.86}, -- skull
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

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetMarkColor(mark)
    if Opt("raidmark_menu_select_color_auto", true) == false then
        return 1.0, 0.80, 0.16
    end
    local c = MARK_COLORS[tonumber(mark) or 0] or MARK_COLORS[1]
    return c[1], c[2], c[3]
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
    local path, uv, isAtlas
    if SP.GetRaidMarkerIcon then
        path, uv, isAtlas = SP:GetRaidMarkerIcon(mark, DB().raidmark_pack)
    end
    path = path or "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
    tex:SetTexture(path)
    if isAtlas and SetRaidTargetIconTexture then
        tex:SetTexCoord(0, 1, 0, 1)
        pcall(SetRaidTargetIconTexture, tex, mark)
    else
        SafeSetTexCoord(tex, uv)
    end
end

local function SafeRaidMark(token)
    if not token or not GetRaidTargetIndex then return nil end
    local ok, value = pcall(GetRaidTargetIndex, token)
    if not ok or value == nil then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    value = tonumber(value)
    if value and value > 0 then return value end
    return nil
end

local function SafeSameUnit(a, b)
    if not a or not b or not UnitIsUnit then return false end
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and same == true
end

local function AddSetCandidate(candidates, seen, token)
    if token and not seen[token] then
        seen[token] = true
        candidates[#candidates + 1] = token
    end
end

local function BuildSetCandidates(data, unit)
    local candidates, seen = {}, {}
    if SafeSameUnit(unit, "target") then AddSetCandidate(candidates, seen, "target") end
    if SafeSameUnit(unit, "mouseover") then AddSetCandidate(candidates, seen, "mouseover") end
    if SafeSameUnit(unit, "focus") then AddSetCandidate(candidates, seen, "focus") end
    AddSetCandidate(candidates, seen, unit)
    AddSetCandidate(candidates, seen, data and data.displayedUnit)
    AddSetCandidate(candidates, seen, data and data.unit)
    return candidates
end

local function TrySetRaidTargetVerified(data, unit, mark)
    if not SetRaidTargetIcon and not SetRaidTarget then return false, "SetRaidTargetIcon unavailable" end

    local candidates = BuildSetCandidates(data, unit)
    local details = {}
    for i = 1, #candidates do
        local token = candidates[i]
        local ok, err
        if SetRaidTargetIcon then
            ok, err = pcall(SetRaidTargetIcon, token, mark)
        else
            ok, err = pcall(SetRaidTarget, token, mark)
        end
        local verified = SafeRaidMark(token)
        details[#details + 1] = tostring(token) .. ":call=" .. tostring(ok) .. ":mark=" .. tostring(verified or "nil")
        if ok and verified == mark then
            return true, token, table.concat(details, " | ")
        end
        if ok and verified == nil then
            return true, token, table.concat(details, " | ") .. " | verification=secret_or_delayed"
        end
        if not ok and err then
            details[#details] = details[#details] .. ":err=" .. tostring(err)
        end
    end

    return false, table.concat(details, " | ")
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
    btn._hover = false
    btn._sparkPhase = 0
    if btn.glow then btn.glow:SetAlpha(0) end
    if btn.sparks then
        for _, spark in ipairs(btn.sparks) do
            spark:SetAlpha(0)
            spark:Hide()
        end
    end
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

    btn.sparks = {}
    for i = 1, 3 do
        local spark = btn:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(GLOW_TEX)
        spark:SetBlendMode("ADD")
        spark:SetSize(8, 8)
        spark:SetAlpha(0)
        spark:Hide()
        btn.sparks[i] = spark
    end

    btn:SetScript("OnEnter", function(selfBtn)
        RMM.hoverButton = selfBtn
        selfBtn._hover = true
        selfBtn._sparkPhase = 0
        local r, g, b = GetMarkColor(selfBtn._mark)
        if selfBtn.glow then
            selfBtn.glow:SetVertexColor(r, g, b, 1)
        end
        if selfBtn.sparks then
            for _, spark in ipairs(selfBtn.sparks) do
                spark:SetVertexColor(r, g, b, 1)
                spark:Show()
            end
        end
        RMM:ShowLabel(MARK_LABELS[selfBtn._mark] or "", selfBtn._mark)
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        RMM.hoverButton = nil
        selfBtn._hover = false
        if selfBtn.sparks then
            for _, spark in ipairs(selfBtn.sparks) do
                spark:SetAlpha(0)
                spark:Hide()
            end
        end
        RMM:ShowLabel("")
    end)
    btn:SetScript("OnClick", function(selfBtn)
        RMM:ApplyMark(selfBtn._mark)
    end)

    f.buttons[index] = btn
    return btn
end

function RMM:ShowLabel(text, mark)
    local f = self.frame
    if not f then return end
    if not text or text == "" then
        f.label:Hide()
        f.labelBg:Hide()
        return
    end
    f.label:SetText(text)
    local r, g, b = GetMarkColor(mark)
    f.label:SetTextColor(r, g, b, 1)
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
    local glowScale = ClampNumber(Opt("raidmark_menu_select_glow_size", 1.12), 0.80, 1.80, 1.12)
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
        btn._baseScale = scale
        btn._baseAlpha = alpha * p
        btn._iconSize = size
        btn._radius = r
        btn._angle = angle
        if btn.glow then
            local glowSize = size * glowScale
            btn.glow:ClearAllPoints()
            btn.glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.glow:SetSize(glowSize, glowSize)
        end
        ApplyMarkerTexture(btn.icon, i)
        btn._mark = i
        btn:Show()
    end
end

function RMM:UpdateHoverEffects(elapsed)
    local f = self.frame
    if not f then return end
    local baseScale = tonumber(Opt("raidmark_menu_scale", 1)) or 1
    local glowAlpha = ClampNumber(Opt("raidmark_menu_select_glow_alpha", 0.62), 0, 1, 0.62)
    local rotate = Opt("raidmark_menu_select_rotation", true) ~= false
    local rotationSpeed = ClampNumber(Opt("raidmark_menu_select_rotation_speed", 180), 20, 720, 180)
    local particles = Opt("raidmark_menu_select_particles", true) ~= false
    local particleAlpha = ClampNumber(Opt("raidmark_menu_select_particle_alpha", 0.75), 0, 1, 0.75)
    for _, btn in ipairs(f.buttons or {}) do
        local hovered = btn == self.hoverButton
        btn:SetScale(hovered and (baseScale * 1.16) or baseScale)
        if btn.glow then
            if hovered and Opt("raidmark_menu_hover_glow", true) ~= false then
                local r, g, b = GetMarkColor(btn._mark)
                btn.glow:SetVertexColor(r, g, b, 1)
                btn.glow:SetAlpha(glowAlpha)
                if rotate and btn.glow.SetRotation then
                    local phase = ((btn._sparkPhase or 0) + (elapsed or 0) * rotationSpeed / 57.2957795) % 6.2831853
                    btn._sparkPhase = phase
                    btn.glow:SetRotation(phase)
                end
            else
                btn.glow:SetAlpha(0)
            end
        end
        if btn.sparks then
            if hovered and particles then
                local phase = (btn._sparkPhase or 0)
                local radius = (btn._iconSize or 38) * 0.56
                local r, g, b = GetMarkColor(btn._mark)
                for i, spark in ipairs(btn.sparks) do
                    local a = phase + (i - 1) * 2.0943951
                    spark:ClearAllPoints()
                    spark:SetPoint("CENTER", btn, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
                    spark:SetVertexColor(r, g, b, 1)
                    spark:SetAlpha(particleAlpha * (0.55 + 0.25 * i))
                    spark:Show()
                end
            else
                for _, spark in ipairs(btn.sparks) do
                    spark:SetAlpha(0)
                    spark:Hide()
                end
            end
        end
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
        self:UpdateHoverEffects(elapsed)
        return
    end

    self.animT = (self.animT or 0) + (elapsed or 0)
    local d = self.animD or 0.12
    local p = math.min(1, self.animT / d)
    if self.anim == "close" then p = 1 - p end
    self:LayoutButtons(p)
    self:UpdateHoverEffects(elapsed)

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
    local ok, tokenOrErr, details = TrySetRaidTargetVerified(self.data, self.unit, mark)
    if not ok then
        Log("Warn", "SetRaidTarget not verified mark=" .. tostring(mark) .. " unit=" .. tostring(self.unit) .. " details=" .. tostring(tokenOrErr))
    else
        Log("Info", "SetRaidTarget verified mark=" .. tostring(mark) .. " token=" .. tostring(tokenOrErr) .. " details=" .. tostring(details))
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
        if SP.Orb and SP.Orb.RefreshAllRaidMarks then
            SP.Orb:RefreshAllRaidMarks(0.10)
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
