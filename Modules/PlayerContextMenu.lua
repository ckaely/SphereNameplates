-------------------------------------------------------------------------------
--  SphereNameplates · PlayerContextMenu
--
--  Menu radial contextuel sur clic droit des spheres de joueurs.
--  Inspiration OPie: layout radial, pool de boutons, animation scale/alpha.
--  Implementation propre SphereNameplates: pas de code/asset OPie copie.
-------------------------------------------------------------------------------

local addonName, _ = ...
local SP = _G["SphereNameplates"]
if not SP then return end

SP.PlayerContextMenu = SP.PlayerContextMenu or {}
local PCM = SP.PlayerContextMenu

local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW_TEX      = "Interface\\Cooldown\\ping4"
local MASK_TEX      = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE         = "Interface\\Buttons\\WHITE8x8"
local ICON_SHEET    = (SP.MEDIA or "Interface\\AddOns\\SphereNameplates\\media\\") .. "icones_no_bg.png"
local LABEL_CAPSULE = SP.PLAYER_MENU_LABEL_CAPSULE_PATH or ((SP.MEDIA or "Interface\\AddOns\\SphereNameplates\\media\\") .. "player_menu_label_capsule.png")

-- Single spritesheet, 1536x1024. TexCoord order: left, right, top, bottom.
-- Crops are tight around each gold-ring icon to avoid the colored cell backgrounds.
local ACTION_ICON_UVS = {
    invite      = { texture = ICON_SHEET, texCoord = { 0.141276, 0.304688, 0.142578, 0.387695 } },
    duel        = { texture = ICON_SHEET, texCoord = { 0.413411, 0.578776, 0.146484, 0.394531 } },
    trade       = { texture = ICON_SHEET, texCoord = { 0.665365, 0.838542, 0.145508, 0.405273 } },
    inspect     = { texture = ICON_SHEET, texCoord = { 0.057292, 0.212891, 0.529297, 0.762695 } },
    follow      = { texture = ICON_SHEET, texCoord = { 0.292318, 0.448568, 0.528320, 0.762695 } },
    achievement = { texture = ICON_SHEET, texCoord = { 0.538411, 0.699219, 0.520508, 0.761719 } },
    whisper     = { texture = ICON_SHEET, texCoord = { 0.783203, 0.940104, 0.531250, 0.766602 } },
}

local ACTION_COLORS = {
    invite      = { 0.22, 1.00, 0.28 },
    duel        = { 1.00, 0.16, 0.08 },
    trade       = { 1.00, 0.62, 0.12 },
    inspect     = { 0.22, 0.68, 1.00 },
    follow      = { 0.10, 0.95, 0.72 },
    achievement = { 0.82, 0.48, 1.00 },
    whisper     = { 0.95, 0.30, 1.00 },
}

local ACTIONS = {
    {
        key = "whisper", label = "Chuchoter",
        iconKey = "whisper",
        icon = "Interface\\Icons\\INV_Letter_15",
        enabledKey = "player_menu_action_whisper",
    },
    {
        key = "inspect", label = "Inspecter",
        iconKey = "inspect",
        icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
        enabledKey = "player_menu_action_inspect",
        combatBlocked = true,
    },
    {
        key = "invite", label = "Inviter",
        iconKey = "invite",
        icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        enabledKey = "player_menu_action_invite",
        combatBlocked = true,
    },
    {
        key = "trade", label = "Echanger",
        iconKey = "trade",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        enabledKey = "player_menu_action_trade",
        combatBlocked = true,
    },
    {
        key = "duel", label = "Duel",
        iconKey = "duel",
        icon = "Interface\\Icons\\Ability_DualWield",
        enabledKey = "player_menu_action_duel",
        combatBlocked = true,
    },
    {
        key = "follow", label = "Suivre",
        iconKey = "follow",
        icon = "Interface\\Icons\\Ability_Hunter_Pathfinding",
        enabledKey = "player_menu_action_follow",
        combatBlocked = true,
    },
    {
        key = "achievement", label = "Hauts faits",
        iconKey = "achievement",
        icon = "Interface\\Icons\\Achievement_General",
        enabledKey = "player_menu_action_achievement",
        combatBlocked = true,
    },
}

local function DB()
    return SP.db or {}
end

local function Opt(key, fallback)
    local db = DB()
    if db[key] ~= nil then return db[key] end
    return fallback
end

local function SafeTrue(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    if not ok then return false end
    local ok2, result = pcall(function() return value == true end)
    return ok2 and result == true
end

local function SafeFullName(unit)
    if not unit then return nil end
    if UnitFullName then
        local ok, name, realm = pcall(UnitFullName, unit)
        if ok and name then
            local ok2, full = pcall(function()
                if not name or name == "" then return nil end
                if realm and realm ~= "" then return name .. "-" .. realm end
                return name
            end)
            if ok2 and type(full) == "string" then return full end
        end
    end
    if UnitName then
        local ok, name = pcall(UnitName, unit)
        if ok and name then
            local ok2, clean = pcall(function() return name ~= "" and name or nil end)
            if ok2 and type(clean) == "string" then return clean end
        end
    end
    return nil
end

local function SafeUnitNameRaw(unit)
    if not unit or not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if ok and name then return name end
    return nil
end

local function Log(level, msg)
    if SP.Log and SP.Log[level] then
        SP.Log[level](SP.Log, "PlayerMenu", msg)
    elseif SP.db and SP.db.player_menu_debug and SP.Print then
        SP:Print("[PlayerMenu] " .. tostring(msg))
    end
end

local function SetTextureDesaturated(tex, desaturated)
    if tex and tex.SetDesaturated then
        pcall(tex.SetDesaturated, tex, desaturated == true)
    end
end

local function GetActionColor(action)
    if Opt("player_menu_select_color_auto", true) and action then
        local c = ACTION_COLORS[action.key]
        if c then return c[1], c[2], c[3] end
    end
    return 1.00, 0.72, 0.25
end

local function ApplyActionIcon(btn, action)
    if not btn or not btn.icon then return end

    local iconData = action and action.iconKey and ACTION_ICON_UVS[action.iconKey]
    if iconData and iconData.texCoord then
        btn.icon:SetTexture(iconData.texture)
        btn.icon:SetTexCoord(iconData.texCoord[1], iconData.texCoord[2], iconData.texCoord[3], iconData.texCoord[4])
    else
        btn.icon:SetTexture((action and action.icon) or ICON_FALLBACK)
        btn.icon:SetTexCoord(0, 1, 0, 1)
    end

    SetTextureDesaturated(btn.icon, action and action.disabledReason ~= nil)
end

local function MigrateVisualDefaults()
    local db = DB()
    if db.player_menu_radius == 78 and not db.player_menu_radius_tight_v2 then
        db.player_menu_radius = 58
        db.player_menu_radius_tight_v2 = true
    end
    if db.player_menu_tooltips == true and not db.player_menu_center_label_v2 then
        db.player_menu_tooltips = false
        db.player_menu_center_label_v2 = true
    end
end

local function GetAnchorFrame(data)
    if data and data.orbFrame and data.orbFrame.IsShown and data.orbFrame:IsShown() then return data.orbFrame end
    if data and data.orb and data.orb.IsShown and data.orb:IsShown() then return data.orb end
    if data and data.playerMenuButton and data.playerMenuButton.IsShown and data.playerMenuButton:IsShown() then return data.playerMenuButton end
    return nil
end

local function IsPlayerUnit(unit)
    return SafeTrue(UnitIsPlayer, unit)
end

local function IsKnownPlayerType(unitType)
    return unitType == "ENEMY_PLAYER" or unitType == "FRIENDLY_PLAYER"
end

local function IsCombatBlocked(action)
    return action.combatBlocked and InCombatLockdown and InCombatLockdown()
end

local function IsCooperative(unit)
    return SafeTrue(UnitCanCooperate, "player", unit)
end

local function ActionUnavailableReason(action, unit)
    if IsCombatBlocked(action) then return "Indisponible en combat." end
    if action.key == "whisper" then
        return nil
    elseif action.key == "inspect" then
        if not (InspectUnit or NotifyInspect or (SP.Inspect and SP.Inspect.Queue)) then return "API inspection indisponible." end
        if CanInspect and not SafeTrue(CanInspect, unit, false) then return "Inspection impossible maintenant." end
    elseif action.key == "invite" then
        if not (C_PartyInfo and C_PartyInfo.InviteUnit) and not InviteUnit then return "API invitation indisponible." end
    elseif action.key == "trade" then
        if not InitiateTrade then return "API echange indisponible." end
        if not IsCooperative(unit) then return "Cible non cooperative." end
    elseif action.key == "duel" then
        if not StartDuel then return "API duel indisponible." end
        if not IsCooperative(unit) then return "Duel indisponible avec cette cible." end
    elseif action.key == "follow" then
        if not FollowUnit then return "API suivre indisponible." end
        if not IsCooperative(unit) then return "Cible non cooperative." end
    elseif action.key == "achievement" then
        if not InspectAchievements then return "Comparaison indisponible." end
    end
    return nil
end

function PCM:EnsureFrame()
    if self.frame then return self.frame end

    local catcher = CreateFrame("Frame", "SPPlayerContextMenuCatcher", UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(850)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function()
        PCM:Hide("outside")
    end)
    catcher:Hide()
    self.catcher = catcher

    local f = CreateFrame("Frame", "SPPlayerContextMenu", UIParent)
    f:SetSize(1, 1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(900)
    f:Hide()
    f.buttons = {}
    f:SetScript("OnUpdate", function(_, elapsed)
        PCM:OnUpdate(elapsed)
    end)
    f:SetScript("OnHide", function()
        if GameTooltip and GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end)

    f.centerLabel = f:CreateFontString(nil, "OVERLAY")
    f.centerLabel:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.centerLabel:SetFontObject(GameFontHighlightLarge)
    f.centerLabel:SetTextColor(1, 0.86, 0.28, 1)
    f.centerLabel:SetShadowColor(0, 0, 0, 0.95)
    f.centerLabel:SetShadowOffset(1, -1)
    f.centerLabel:SetJustifyH("CENTER")
    f.centerLabel:SetText("")
    f.centerLabel:Hide()

    f.centerLabelBgMid = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.centerLabelBgMid:SetTexture(LABEL_CAPSULE)
    f.centerLabelBgMid:SetBlendMode("BLEND")
    f.centerLabelBgMid:SetVertexColor(0, 0, 0, 0.42)
    f.centerLabelBgMid:Hide()

    f.centerLabelBgLeft = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.centerLabelBgLeft:SetTexture(GLOW_TEX)
    f.centerLabelBgLeft:SetBlendMode("BLEND")
    f.centerLabelBgLeft:SetVertexColor(0, 0, 0, 0.42)
    f.centerLabelBgLeft:Hide()

    f.centerLabelBgRight = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.centerLabelBgRight:SetTexture(GLOW_TEX)
    f.centerLabelBgRight:SetBlendMode("BLEND")
    f.centerLabelBgRight:SetVertexColor(0, 0, 0, 0.42)
    f.centerLabelBgRight:Hide()

    self.frame = f
    return f
end

function PCM:PositionActionLabel(btn)
    local f = self.frame
    local label = f and f.centerLabel
    if not f or not label or not btn or not label:IsShown() then return end

    local side = btn._labelSide or "right"
    local gap = btn._labelGap or 10
    label:ClearAllPoints()
    if side == "left" then
        label:SetPoint("RIGHT", btn, "LEFT", -gap, 0)
        label:SetJustifyH("RIGHT")
    elseif side == "right" then
        label:SetPoint("LEFT", btn, "RIGHT", gap, 0)
        label:SetJustifyH("LEFT")
    elseif side == "bottom" then
        label:SetPoint("TOP", btn, "BOTTOM", 0, -gap)
        label:SetJustifyH("CENTER")
    else
        label:SetPoint("BOTTOM", btn, "TOP", 0, gap)
        label:SetJustifyH("CENTER")
    end
end

function PCM:UpdateLabelBackground()
    local f = self.frame
    local label = f and f.centerLabel
    if not f or not label then return end

    local mid, left, right = f.centerLabelBgMid, f.centerLabelBgLeft, f.centerLabelBgRight
    if not Opt("player_menu_label_bg", true) or not label:IsShown() then
        if mid then mid:Hide() end
        if left then left:Hide() end
        if right then right:Hide() end
        return
    end

    local pad = tonumber(Opt("player_menu_label_padding", 7)) or 7
    local alpha = math.max(0, math.min(1, tonumber(Opt("player_menu_label_bg_alpha", 0.42)) or 0.42))
    if mid then
        mid:SetTexture(LABEL_CAPSULE)
        mid:SetBlendMode("BLEND")
        mid:SetVertexColor(0, 0, 0, alpha)
        mid:ClearAllPoints()
        mid:SetPoint("TOPLEFT", label, "TOPLEFT", -pad * 1.15, pad * 0.55)
        mid:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", pad * 1.15, -pad * 0.55)
        mid:Show()
    end
    if left then left:Hide() end
    if right then right:Hide() end
end

function PCM:ShowCenterLabel(action, btn)
    local f = self.frame
    if not f or not f.centerLabel or not action then return end
    local label = f.centerLabel
    local size = tonumber(Opt("player_menu_label_text_size", 15)) or 15
    if STANDARD_TEXT_FONT and label.SetFont then
        pcall(label.SetFont, label, STANDARD_TEXT_FONT, size, "OUTLINE")
    end
    local r, g, b = GetActionColor(action)
    label:SetTextColor(r, g, b, 1)
    label:SetText(action.label or action.key or "")
    label:Show()
    self.hoverButton = btn
    self:PositionActionLabel(btn)
    self:UpdateLabelBackground()
end

function PCM:ClearCenterLabel()
    local f = self.frame
    if not f then return end
    self.hoverButton = nil
    if f.centerLabel then
        f.centerLabel:SetText("")
        f.centerLabel:Hide()
    end
    if f.centerLabelBgMid then f.centerLabelBgMid:Hide() end
    if f.centerLabelBgLeft then f.centerLabelBgLeft:Hide() end
    if f.centerLabelBgRight then f.centerLabelBgRight:Hide() end
end

function PCM:ResetButton(btn)
    btn:Hide()
    btn:SetAlpha(1)
    btn:SetScale(1)
    btn._hover = false
    btn._sparkPhase = 0
    btn.action = nil
    btn.disabledReason = nil
    if btn.icon then
        btn.icon:SetTexture(ICON_FALLBACK)
        btn.icon:SetTexCoord(0, 1, 0, 1)
        btn.icon:SetAlpha(1)
        SetTextureDesaturated(btn.icon, false)
    end
    if btn.glow then btn.glow:SetAlpha(0) end
    if btn.sparks then
        for _, spark in ipairs(btn.sparks) do
            spark:SetAlpha(0)
        end
    end
end

function PCM:AcquireButton(index)
    local f = self:EnsureFrame()
    local btn = f.buttons[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, f)
    btn:SetSize(40, 40)
    btn:SetFrameLevel(f:GetFrameLevel() + 10)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetTexture(WHITE)
    btn.bg:SetAllPoints()
    btn.bg:SetVertexColor(0.04, 0.035, 0.03, 0)
    btn.bgMask = btn:CreateMaskTexture()
    btn.bgMask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    btn.bgMask:SetAllPoints(btn.bg)
    btn.bg:AddMaskTexture(btn.bgMask)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(30, 30)
    btn.icon:SetTexture(ICON_FALLBACK)
    btn.icon:SetTexCoord(0, 1, 0, 1)
    btn.mask = btn:CreateMaskTexture()
    btn.mask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    btn.mask:SetAllPoints(btn.icon)
    btn.icon:AddMaskTexture(btn.mask)

    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetTexture(SP.SHADOW_CIRCLE_PATH or (SP.MEDIA .. "shadowcircle"))
    btn.border:SetAllPoints()
    btn.border:SetVertexColor(1, 0.78, 0.34, 0.95)
    btn.border:SetAlpha(0)

    btn.glow = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    btn.glow:SetTexture(GLOW_TEX)
    btn.glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.glow:SetSize(44, 44)
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1, 0.72, 0.25, 1)
    btn.glow:SetAlpha(0)

    btn.sparks = {}
    for i = 1, 3 do
        local spark = btn:CreateTexture(nil, "OVERLAY", nil, 2)
        spark:SetTexture(GLOW_TEX)
        spark:SetBlendMode("ADD")
        spark:SetAlpha(0)
        btn.sparks[i] = spark
    end

    btn:SetScript("OnEnter", function(self)
        local r, g, b = GetActionColor(self.action)
        if self.glow then
            self.glow:SetVertexColor(r, g, b, 1)
            if Opt("player_menu_hover_glow", true) then
                self.glow:SetAlpha(tonumber(Opt("player_menu_select_glow_alpha", 0.62)) or 0.62)
            end
        end
        if self.sparks then
            for _, spark in ipairs(self.sparks) do
                spark:SetVertexColor(r, g, b, 1)
            end
        end
        self._hover = true
        self._sparkPhase = self._sparkPhase or 0
        self:SetScale((PCM.currentScale or 1) * 1.24)
        PCM:ShowCenterLabel(self.action, self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.glow then self.glow:SetAlpha(0) end
        if self.sparks then
            for _, spark in ipairs(self.sparks) do
                spark:SetAlpha(0)
            end
        end
        self._hover = false
        self:SetScale(PCM.currentScale or 1)
        if PCM.hoverButton == self then
            PCM:ClearCenterLabel()
        end
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    btn:SetScript("OnClick", function(self)
        if not self.action or self.disabledReason then return end
        PCM:RunAction(self.action)
    end)

    f.buttons[index] = btn
    return btn
end

function PCM:BuildActions(unit, unitType)
    local out = {}
    if not unit or not IsKnownPlayerType(unitType) or not IsPlayerUnit(unit) then return out end

    for _, action in ipairs(ACTIONS) do
        if Opt(action.enabledKey, true) then
            local copy = {}
            for k, v in pairs(action) do copy[k] = v end
            copy.disabledReason = ActionUnavailableReason(action, unit)
            out[#out + 1] = copy
        end
    end
    return out
end

function PCM:ClampPoint(x, y, pad)
    pad = pad or 70
    local w, h = UIParent:GetSize()
    w, h = w or 0, h or 0
    if x < pad then x = pad elseif x > w - pad then x = w - pad end
    if y < pad then y = pad elseif y > h - pad then y = h - pad end
    return x, y
end

function PCM:LayoutButtons(progress)
    local f = self.frame
    if not f or not self.actions then return end
    local count = #self.actions
    if count == 0 then return end

    local radius = tonumber(Opt("player_menu_radius", 58)) or 58
    local iconSize = tonumber(Opt("player_menu_icon_size", 38)) or 38
    local iconZoom = tonumber(Opt("player_menu_icon_zoom", 1.0)) or 1.0
    local scale = tonumber(Opt("player_menu_scale", 1.0)) or 1.0
    local alpha = tonumber(Opt("player_menu_alpha", 1.0)) or 1.0
    local eased = progress * progress * (3 - 2 * progress)
    local startAngle = -90
    local step = 360 / count
    self.currentScale = scale

    for i, action in ipairs(self.actions) do
        local btn = self:AcquireButton(i)
        local angle = math.rad(startAngle + (i - 1) * step)
        local r = radius * eased
        local x = math.cos(angle) * r
        local y = math.sin(angle) * r
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", f, "CENTER", x, y)
        btn:SetSize(iconSize, iconSize)
        btn._pcmIconSize = iconSize
        btn._labelGap = math.max(8, iconSize * 0.22)
        if math.abs(x) > iconSize * 0.35 then
            btn._labelSide = (x < 0) and "left" or "right"
        else
            btn._labelSide = (y < 0) and "bottom" or "top"
        end
        btn.icon:SetSize(iconSize * 0.74 * iconZoom, iconSize * 0.74 * iconZoom)
        if btn.glow then
            local glowSize = iconSize * (tonumber(Opt("player_menu_select_glow_size", 1.12)) or 1.12)
            btn.glow:SetSize(glowSize, glowSize)
        end
        local hoverScale = btn._hover and 1.24 or 1
        btn:SetScale(scale * (0.78 + 0.22 * eased) * hoverScale)
        btn:SetAlpha(alpha * eased * (action.disabledReason and 0.42 or 1))
        btn:Show()
    end

    for i = count + 1, #(f.buttons or {}) do
        self:ResetButton(f.buttons[i])
    end
end

function PCM:UpdateHoverEffects(elapsed)
    local f = self.frame
    if not f or not f.buttons then return end
    if self.hoverButton and self.hoverButton._hover then
        self:PositionActionLabel(self.hoverButton)
        self:UpdateLabelBackground()
    end
    local particles = Opt("player_menu_select_particles", true)
    local rotate = Opt("player_menu_select_rotation", true)
    local speed = tonumber(Opt("player_menu_select_rotation_speed", 180)) or 180
    local particleAlpha = tonumber(Opt("player_menu_select_particle_alpha", 0.75)) or 0.75
    local glowScale = tonumber(Opt("player_menu_select_glow_size", 1.12)) or 1.12
    local step = math.rad(speed) * (elapsed or 0)

    for _, btn in ipairs(f.buttons) do
        if btn._hover and btn.sparks and particles then
            if rotate then
                btn._sparkPhase = (btn._sparkPhase or 0) + step
            else
                btn._sparkPhase = 0
            end
            local r, g, b = GetActionColor(btn.action)
            local base = btn._pcmIconSize or 40
            local radius = base * glowScale * 0.42
            local size = math.max(3, base * 0.13)
            for i, spark in ipairs(btn.sparks) do
                local ang = (btn._sparkPhase or 0) + (i - 1) * (math.pi * 2 / #btn.sparks)
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", btn, "CENTER", math.cos(ang) * radius, math.sin(ang) * radius)
                spark:SetSize(size, size)
                spark:SetVertexColor(r, g, b, 1)
                spark:SetAlpha(math.max(0, math.min(1, particleAlpha)))
            end
        elseif btn.sparks then
            for _, spark in ipairs(btn.sparks) do
                spark:SetAlpha(0)
            end
        end
    end
end

function PCM:UpdateAnchor()
    if not self.frame or not self.data then return false end
    local anchor = GetAnchorFrame(self.data)
    if not anchor then
        self:Hide("anchor_missing")
        return false
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    return true
end

function PCM:ShowForPlate(data, unit)
    local t0 = (SP.Profiler and SP.Profiler.IsEnabled and SP.Profiler:IsEnabled() and debugprofilestop and debugprofilestop()) or nil
    MigrateVisualDefaults()
    if not Opt("player_menu_enabled", true) then return end
    if not data or not unit then return end
    local unitType = data.unitType or (SP.ActiveUnits and SP.ActiveUnits[unit])
    if not IsKnownPlayerType(unitType) then return end
    if data.orbFrame and not data.orbFrame:IsShown() then return end

    local actions = self:BuildActions(unit, unitType)
    if #actions == 0 then return end

    local f = self:EnsureFrame()
    self.unit = unit
    self.data = data
    self.actions = actions
    self:UpdateAnchor()
    self.anim = "open"
    self.animT = 0
    self.animD = tonumber(Opt("player_menu_open_duration", 0.16)) or 0.16

    f:SetAlpha(1)
    f:Show()
    self:ClearCenterLabel()
    if self.catcher then self.catcher:Show() end

    for i, action in ipairs(actions) do
        local btn = self:AcquireButton(i)
        self:ResetButton(btn)
        btn.action = action
        btn.disabledReason = action.disabledReason
        ApplyActionIcon(btn, action)
        btn:Show()
    end
    self:LayoutButtons(0)
    Log("Debug", "open " .. tostring(unit) .. " actions=" .. tostring(#actions))
    if t0 and SP.Profiler and SP.Profiler.Track then
        pcall(SP.Profiler.Track, SP.Profiler, "PlayerMenu", debugprofilestop() - t0)
    end
end

function PCM:Hide(reason)
    local f = self.frame
    if not f or not f:IsShown() then return end
    if self.anim == "close" then return end
    self.anim = "close"
    self.animT = 0
    self.animD = tonumber(Opt("player_menu_close_duration", 0.10)) or 0.10
    self.hideReason = reason or "hide"
    if GameTooltip then GameTooltip:Hide() end
end

function PCM:FinishHide()
    local f = self.frame
    if not f then return end
    self:ClearCenterLabel()
    for _, btn in ipairs(f.buttons or {}) do self:ResetButton(btn) end
    f:Hide()
    if self.catcher then self.catcher:Hide() end
    self.unit, self.data, self.actions = nil, nil, nil
    self.anim, self.animT, self.hideReason = nil, 0, nil
end

function PCM:OnUpdate(elapsed)
    if not self.frame or not self.frame:IsShown() then return end
    self:UpdateAnchor()
    if not self.anim then
        self:LayoutButtons(1)
        self:UpdateHoverEffects(elapsed)
        return
    end
    self.animT = (self.animT or 0) + (elapsed or 0)
    local d = math.max(0.01, self.animD or 0.12)
    local p = math.min(1, self.animT / d)
    if self.anim == "open" then
        self:LayoutButtons(p)
        self:UpdateHoverEffects(elapsed)
        if p >= 1 then self.anim = nil end
    elseif self.anim == "close" then
        self:LayoutButtons(1 - p)
        self:UpdateHoverEffects(elapsed)
        if p >= 1 then self:FinishHide() end
    end
end

function PCM:RunAction(action)
    local unit = self.unit
    local name = SafeFullName(unit)
    local ok = false

    if action.key == "whisper" then
        if ChatFrame_SendTell then
            local rawName = name or SafeUnitNameRaw(unit)
            if rawName then ok = pcall(ChatFrame_SendTell, rawName) end
        end
        if not ok and ChatFrame_OpenChat and name then ok = pcall(ChatFrame_OpenChat, "/w " .. name .. " ") end
    elseif action.key == "inspect" then
        if SP.Inspect and SP.Inspect.Queue then pcall(SP.Inspect.Queue, SP.Inspect, unit) end
        if InspectUnit then ok = pcall(InspectUnit, unit)
        elseif NotifyInspect then ok = pcall(NotifyInspect, unit) end
    elseif action.key == "invite" then
        if C_PartyInfo and C_PartyInfo.InviteUnit then ok = pcall(C_PartyInfo.InviteUnit, name or unit)
        elseif InviteUnit then ok = pcall(InviteUnit, name or unit) end
    elseif action.key == "trade" then
        if InitiateTrade then ok = pcall(InitiateTrade, unit) end
    elseif action.key == "duel" then
        if StartDuel then ok = pcall(StartDuel, unit) end
    elseif action.key == "follow" then
        if FollowUnit then ok = pcall(FollowUnit, unit) end
    elseif action.key == "achievement" then
        if InspectAchievements then ok = pcall(InspectAchievements, unit) end
    end

    if not ok then Log("Warn", "action failed/unavailable: " .. tostring(action.key)) end
    if Opt("player_menu_close_after_action", true) then self:Hide("action") end
end

function PCM:Attach(data, unit)
    if not data or not data.orbFrame or not unit then return end
    local unitType = data.unitType or (SP.ActiveUnits and SP.ActiveUnits[unit])
    if not IsKnownPlayerType(unitType) then return end
    if data.playerMenuButton then
        data.playerMenuButton._spUnit = unit
        data.playerMenuButton._spData = data
        data.playerMenuButton:Show()
        return
    end

    local b = CreateFrame("Button", nil, data.orbFrame)
    b:SetAllPoints(data.orbFrame)
    b:SetFrameLevel((data.orbFrame:GetFrameLevel() or 10) + 30)
    b:EnableMouse(true)
    b:RegisterForClicks("RightButtonUp")
    -- Retail expose SetPropagateMouseClicks: laisser les clics non geres
    -- (notamment LeftButton) continuer vers la nameplate quand disponible.
    pcall(b.SetPropagateMouseClicks, b, true)
    b._spUnit = unit
    b._spData = data
    b:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        local d = self._spData
        if d and d.orbFrame and d.orbFrame:IsShown() then
            PCM:ShowForPlate(d, self._spUnit)
        end
    end)
    data.playerMenuButton = b
end

function PCM:Detach(data, unit)
    if self.unit == unit then self:Hide("plate_removed") end
    if data and data.playerMenuButton then
        data.playerMenuButton:Hide()
        data.playerMenuButton._spUnit = nil
        data.playerMenuButton._spData = nil
    end
end

function PCM:RefreshAttachments()
    if not SP.Plates then return end
    for unit, data in pairs(SP.Plates) do
        local unitType = data and (data.unitType or SP.ActiveUnits[unit])
        if data and IsKnownPlayerType(unitType) and Opt("player_menu_enabled", true) then
            self:Attach(data, unit)
        elseif data and data.playerMenuButton then
            data.playerMenuButton:Hide()
        end
    end
end

function PCM:Reset()
    self:FinishHide()
    self:RefreshAttachments()
end
