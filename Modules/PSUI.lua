-------------------------------------------------------------------------------
-- SphereNameplates - PSUI (fenêtre de configuration principale)
--
-- Visual source studied in Plumber:
--   Modules/ExpansionLandingPage/Basic.lua
--   Modules/ExpansionLandingPage/ExpansionLandingPage.lua
--
-- This module does not replace AceDB/AceConfig data. It only replaces the
-- primary /snp window with a custom frame using the same DB keys and refresh
-- path as the runtime nameplates.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end
SP.UI = SP.UI or {}

-- ── Ticker dédié pour la prévisualisation CastBar ────────────────────────────
-- Tourne en permanence mais ne fait presque rien quand la page n'est pas castbar.
-- Appelle CastBar:Tick(previewData) à chaque frame → anime l'arc en live.
-- Auto-loop cast↔canal avec pause de 0.8s entre chaque cycle.
local _castPreviewTicker = CreateFrame("Frame", "SP_PSUI_CastPreviewTicker", UIParent)
_castPreviewTicker:SetScript("OnUpdate", function(_, elapsed)
    local ui = SP and SP.UIPlumber
    if not ui or ui.page ~= "castbar" then return end
    local data = ui.previewData
    if not (data and data.castbar) then return end
    local cb   = data.castbar
    local now  = GetTime()
    if cb.active then
        -- Animer la castbar preview
        pcall(SP.CastBar.Tick, SP.CastBar, data, now)
        -- Auto-stop quand le cast de prévisualisation expire (pas de UNIT_SPELLCAST_STOP réel)
        -- Sans ce stop, cb.active reste true indéfiniment et le cycle auto-loop ne redémarre jamais.
        if cb.endTime and now >= cb.endTime then
            pcall(SP.CastBar.StopCast, SP.CastBar, data, false)
        end
        -- Réinitialiser le timer de restart (sera recalculé dans la branche else)
        ui._castPreviewRestartAt = nil
    else
        -- Cast terminé → attendre 0.8s puis relancer en alternance
        if not ui._castPreviewRestartAt then
            ui._castPreviewRestartAt = now + 0.8
        elseif now >= ui._castPreviewRestartAt then
            ui._castPreviewRestartAt = nil
            -- Alterner : cast → canal → cast → …
            if not ui._castPreviewLastMode or ui._castPreviewLastMode == "channel" then
                pcall(SP.CastBar.TestCast, SP.CastBar, data, 3.0)
                ui._castPreviewLastMode = "cast"
            else
                pcall(SP.CastBar.TestChannel, SP.CastBar, data, 3.0)
                ui._castPreviewLastMode = "channel"
            end
        end
    end
end)

local TEX = "Interface/AddOns/Plumber/Art/ExpansionLandingPage/ExpansionBorder_TWW"
local BG_ATLAS = "thewarwithin-landingpage-background"
local SCROLL_TEX = "Interface/AddOns/Plumber/Art/ControlCenter/SettingsPanelWidget.png"
local GOLD = {1.0, 0.82, 0.0}
local WHITE = {1.0, 1.0, 1.0}
local MUTED = {0.72, 0.66, 0.56}
local COLUMN_WIDTH = 370
local COLUMN_GAP = 34

local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    return ok, err
end

local function SafeTexture(tex, path)
    if tex and path then
        pcall(tex.SetTexture, tex, path)
    end
end

local function SafeAtlas(tex, atlas)
    if tex and atlas then
        return pcall(tex.SetAtlas, tex, atlas, false)
    end
    return false
end

local CATEGORY = {
    {key="enemy",    label="Ennemis"},
    {key="neutral",  label="Neutres"},
    {key="friendly", label="Allies"},
    {key="behavior", label="Options"},
    {key="modules",  label="Modules"},
    {key="logs",     label="Logs"},
}

local UNIT_BY_CATEGORY = {
    enemy = {
        {kind="npc",    label="PNJ",    utype="ENEMY",        title="PNJ ennemi"},
        {kind="player", label="Joueur", utype="ENEMY_PLAYER", title="Joueur ennemi"},
    },
    neutral = {
        {kind="npc",    label="PNJ",    utype="NEUTRAL",      title="PNJ neutre"},
    },
    friendly = {
        {kind="npc",    label="PNJ",    utype="FRIENDLY",     title="PNJ allie"},
        {kind="player", label="Joueur", utype="FRIENDLY_PLAYER", title="Joueur allie"},
    },
}

local PAGES = {
    {key="sphere",  label="Sphere"},
    {key="text",    label="Nom"},
    {key="castbar", label="CastBar"},
    {key="auras",   label="Auras"},
    {key="target",  label="Cible"},
    {key="effects", label="Effets"},
}

local OPTIONS_NAV = {
    {key="general",    label="General"},
    {key="markers",    label="Marqueurs WoW"},
    {key="playerMenu", label="Menu joueur"},
    {key="pack",       label="Mode Pack"},
}

local COPY_GROUPS = {
    sphere = {
        exact = {
            "enabled", "sphere_display_mode", "size", "offsetX", "offsetY", "hp_lerp_speed",
            "classColorSphere", "fill_color_mode", "fillR", "fillG", "fillB", "fill_alpha", "fill_saturation",
            "fill_prog_highR", "fill_prog_highG", "fill_prog_highB",
            "fill_prog_midR", "fill_prog_midG", "fill_prog_midB",
            "fill_prog_lowR", "fill_prog_lowG", "fill_prog_lowB",
            "fill_prog_critR", "fill_prog_critG", "fill_prog_critB",
            "bgR", "bgG", "bgB", "bgAlpha",
            "borderEnabled", "borderColorMode", "borderClassColor", "borderR", "borderG", "borderB",
            "borderWidth", "borderStyle", "borderOverlayScale", "border_glow_pulse",
            "border_threat_color", "shadeCircleEnabled", "shadeCircleAlpha",
            "orb_shadow_alpha", "orb_shadow2_alpha", "orb_shadow2_enabled",
            "hp_threshold_low", "hp_threshold_crit",
        },
    },
    auras = {
        prefixes = {"auras_"},
    },
    castbar = {
        prefixes = {"castbar_"},
    },
    target = {
        prefixes = {"target_", "non_target_"},
    },
    text = {
        exact = {
            "showName", "nameDisplay", "name_color_mode", "name_saturation", "name_alpha",
            "name_prog_highR", "name_prog_highG", "name_prog_highB",
            "name_prog_midR",  "name_prog_midG",  "name_prog_midB",
            "name_prog_lowR",  "name_prog_lowG",  "name_prog_lowB",
            "name_prog_critR", "name_prog_critG",  "name_prog_critB",
            "classColorName", "nameR", "nameG", "nameB", "nameFont", "nameFontSize",
            "nameOffsetX", "nameOffsetY", "name_maxWidth",
            "showLevelOrHP", "show_ilvl", "show_hp_under_maxlvl", "showHPAlsoInOrb", "hpFormat",
            "hp_show_percent", "levelFont", "levelFontSize", "hp_color_dynamic",
            "hp_percent_color_mode", "hp_absolute_color_mode",
            "hpTextR", "hpTextG", "hpTextB",
            "hpPercentTextA", "hpAbsoluteTextA",
            "hp_col1_r", "hp_col1_g", "hp_col1_b", "hp_col2_r", "hp_col2_g", "hp_col2_b",
            "hp_col3_r", "hp_col3_g", "hp_col3_b", "hp_col4_r", "hp_col4_g", "hp_col4_b",
            "hp_abs_col1_r", "hp_abs_col1_g", "hp_abs_col1_b", "hp_abs_col2_r", "hp_abs_col2_g", "hp_abs_col2_b",
            "hp_abs_col3_r", "hp_abs_col3_g", "hp_abs_col3_b", "hp_abs_col4_r", "hp_abs_col4_g", "hp_abs_col4_b",
            "hpPercentTextR", "hpPercentTextG", "hpPercentTextB",
            "hpAbsoluteTextR", "hpAbsoluteTextG", "hpAbsoluteTextB",
            "showSubTitle", "showGuild", "showHonor",
        },
    },
    effects = {
        exact = {
            "orb_galaxies", "orb_galaxy_alpha", "orb_midnight_star", "orb_midnight_star_alpha",
            "orb_midnight_star_scale", "orb_midnight_star_speed", "orb_midnight_star_dir",
            "orb_shimmer_alpha", "orb_wave", "orb_wave_alpha",
            "orb_wave_speed", "orb_gloss", "orb_gloss_alpha", "orb_spark", "orb_lowhp_glow",
            "anchor_enabled", "anchor_alpha", "showEliteDragon", "quest_enabled", "quest_color_name",
            "quest_sound", "raidmark_enabled", "showCombatIndicator", "npcIconsEnabled",
            "cc_effect_enabled", "showPower", "powerOffsetY", "fade_enabled", "fade_start",
            "fade_end", "fade_min_alpha",
        },
    },
}

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return out
end

local function CopyKeyAllowed(group, key)
    local def = COPY_GROUPS[group]
    if not def or type(key) ~= "string" then return false end
    if def.exact then
        for _, allowed in ipairs(def.exact) do
            if key == allowed then return true end
        end
    end
    if def.prefixes then
        for _, prefix in ipairs(def.prefixes) do
            if key:sub(1, #prefix) == prefix then return true end
        end
    end
    return false
end

local function UnitEntryLabel(entry)
    if not entry then return "" end
    local unitLabel = entry.kind == "player" and "Joueur" or "PNJ"
    local relation = entry.utype == "NEUTRAL" and "Neutres"
        or (entry.utype == "FRIENDLY" or entry.utype == "FRIENDLY_PLAYER") and "Allies"
        or "Ennemis"
    return unitLabel .. " > " .. relation
end

local function SetFont(fs, size, template)
    fs:SetFontObject(template or GameFontNormal)
    local font = "Fonts\\FRIZQT__.TTF"
    pcall(fs.SetFont, fs, font, size or 12, "")
end

local function Text(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFont(fs, size or 13)
    fs:SetText(text or "")
    local c = color or WHITE
    fs:SetTextColor(c[1], c[2], c[3], 1)
    return fs
end

local function CreateNineSlice(parent, padding)
    padding = padding or -28
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", padding, -padding)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -padding, padding)
    pcall(f.SetUsingParentLevel, f, true)

    f.underlay = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.underlay:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    f.underlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    f.underlay:SetColorTexture(0.020, 0.016, 0.012, 0.92)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f.bg:SetColorTexture(0.040, 0.030, 0.022, 0.90)

    f.pieces = {}
    for i = 1, 9 do
        local t = f:CreateTexture(nil, "BORDER")
        SafeTexture(t, TEX)
        -- WoW limite les sublevels de texture a [-8, 7].
        -- Le nine-slice n'a pas besoin de 9 niveaux distincts.
        pcall(t.SetDrawLayer, t, "BORDER", 0)
        f.pieces[i] = t
    end

    local p = f.pieces
    p[1]:SetSize(64, 64);  p[1]:SetPoint("TOPLEFT")
    p[2]:SetHeight(64);   p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("TOPRIGHT", p[3], "TOPLEFT")
    p[3]:SetSize(64, 64); p[3]:SetPoint("TOPRIGHT")
    p[4]:SetWidth(64);    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[4]:SetPoint("BOTTOMLEFT", p[7], "TOPLEFT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    p[6]:SetWidth(64);    p[6]:SetPoint("TOPRIGHT", p[3], "BOTTOMRIGHT"); p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[7]:SetSize(64, 64); p[7]:SetPoint("BOTTOMLEFT")
    p[8]:SetHeight(64);   p[8]:SetPoint("BOTTOMLEFT", p[7], "BOTTOMRIGHT"); p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[9]:SetSize(64, 64); p[9]:SetPoint("BOTTOMRIGHT")

    p[1]:SetTexCoord(0/1024, 128/1024, 0/1024, 128/1024)
    p[2]:SetTexCoord(128/1024, 384/1024, 0/1024, 128/1024)
    p[3]:SetTexCoord(384/1024, 512/1024, 0/1024, 128/1024)
    p[4]:SetTexCoord(0/1024, 128/1024, 128/1024, 384/1024)
    p[5]:SetTexCoord(128/1024, 384/1024, 128/1024, 384/1024)
    p[6]:SetTexCoord(384/1024, 512/1024, 128/1024, 384/1024)
    p[7]:SetTexCoord(0/1024, 128/1024, 384/1024, 512/1024)
    p[8]:SetTexCoord(128/1024, 384/1024, 384/1024, 512/1024)
    p[9]:SetTexCoord(384/1024, 512/1024, 384/1024, 512/1024)

    return f
end

local function CreateDivider(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    f.left = f:CreateTexture(nil, "OVERLAY")
    f.left:SetSize(72, 24)
    f.left:SetPoint("LEFT")
    SafeTexture(f.left, TEX)
    f.left:SetTexCoord(0.5, 634/1024, 0, 48/1024)
    f.center = f:CreateTexture(nil, "OVERLAY")
    f.center:SetHeight(2)
    f.center:SetColorTexture(0.58, 0.43, 0.28, 0.72)
    f.right = f:CreateTexture(nil, "OVERLAY")
    f.right:SetSize(72, 24)
    f.right:SetPoint("RIGHT")
    SafeTexture(f.right, TEX)
    f.right:SetTexCoord(634/1024, 1, 0, 48/1024)
    f.center:SetPoint("LEFT", f.left, "RIGHT", -3, 0)
    f.center:SetPoint("RIGHT", f.right, "LEFT", 3, 0)
    return f
end

local function CreateCloseButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetPoint("CENTER")
    b.tex:SetSize(24, 24)
    SafeTexture(b.tex, TEX)
    b.tex:SetTexCoord(646/1024, 694/1024, 48/1024, 96/1024)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetPoint("CENTER")
    b.hl:SetSize(24, 24)
    SafeTexture(b.hl, TEX)
    b.hl:SetTexCoord(646/1024, 694/1024, 48/1024, 96/1024)
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.55)
    return b
end

local function CreateTextTab(parent, label, onClick, normalColor)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(110, 32)
    b.normalColor = normalColor or GOLD
    b.label = Text(b, label, 18, b.normalColor)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    b:SetScript("OnLeave", function(self)
        if self.selected then self.label:SetTextColor(1, 1, 1, 1)
        else self.label:SetTextColor(self.normalColor[1], self.normalColor[2], self.normalColor[3], 1) end
    end)
    function b:SetSelected(state)
        self.selected = state
        if state then self.label:SetTextColor(1, 1, 1, 1)
        else self.label:SetTextColor(self.normalColor[1], self.normalColor[2], self.normalColor[3], 1) end
    end
    return b
end

local function CreatePanelButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(240, 28)
    b.left = b:CreateTexture(nil, "BACKGROUND")
    b.center = b:CreateTexture(nil, "BACKGROUND")
    b.right = b:CreateTexture(nil, "BACKGROUND")
    SafeTexture(b.left, TEX); SafeTexture(b.center, TEX); SafeTexture(b.right, TEX)
    b.left:SetSize(16, 32); b.left:SetPoint("LEFT", b, "LEFT", -2, 0)
    b.right:SetSize(16, 32); b.right:SetPoint("RIGHT", b, "RIGHT", 2, 0)
    b.center:SetPoint("TOPLEFT", b.left, "TOPRIGHT"); b.center:SetPoint("BOTTOMRIGHT", b.right, "BOTTOMLEFT")
    b.left:SetTexCoord(768/1024, 800/1024, 448/1024, 512/1024)
    b.center:SetTexCoord(800/1024, 972/1024, 448/1024, 512/1024)
    b.right:SetTexCoord(972/1024, 1004/1024, 448/1024, 512/1024)
    b.label = Text(b, label, 12, GOLD)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
    return b
end

local function CreateCheck(parent, label, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(COLUMN_WIDTH - 34, 26)
    b.box = b:CreateTexture(nil, "OVERLAY")
    b.box:SetSize(32, 32)
    b.box:SetPoint("LEFT", b, "LEFT", -4, 0)
    SafeTexture(b.box, TEX)
    b.label = Text(b, label, 12, WHITE)
    b.label:SetPoint("LEFT", b.box, "RIGHT", 4, 0)
    function b:Refresh()
        local checked = getter and getter()
        if checked then
            self.box:SetTexCoord(828/1024, 892/1024, 320/1024, 384/1024)
        else
            self.box:SetTexCoord(764/1024, 828/1024, 320/1024, 384/1024)
        end
    end
    b:SetScript("OnClick", function(self)
        if setter then setter(not getter()) end
        self:Refresh()
        SP.UIPlumber:RefreshAfterChange()
    end)
    b:Refresh()
    return b
end

local function CreateCycle(parent, label, values, getter, setter)
    local b = CreatePanelButton(parent, "", function(self)
        if SP.UIPlumber._openDropdown and SP.UIPlumber._openDropdown ~= self.menu then
            SP.UIPlumber._openDropdown:Hide()
        end
        if self.menu:IsShown() then
            self.menu:Hide()
            SP.UIPlumber._openDropdown = nil
        else
            self.menu:Show()
            SP.UIPlumber._openDropdown = self.menu
        end
    end)
    b:SetSize(COLUMN_WIDTH - 38, 28)
    b.title = label
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", 18, 0)
    b.label:SetJustifyH("LEFT")
    b.menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    b.menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 6, -2)
    b.menu:SetSize(COLUMN_WIDTH - 50, math.max(28, #values * 24 + 8))
    b.menu:SetFrameStrata("DIALOG")
    b.menu:SetFrameLevel(950)
    b.menu:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
    b.menu:SetBackdropColor(0.02, 0.016, 0.012, 0.98)
    b.menu:Hide()
    b:SetScript("OnHide", function(self)
        if self.menu then self.menu:Hide() end
    end)
    b.items = {}
    for i, opt in ipairs(values) do
        local item = CreateFrame("Button", nil, b.menu)
        item:SetSize(COLUMN_WIDTH - 62, 22)
        item:SetPoint("TOPLEFT", b.menu, "TOPLEFT", 6, -4 - (i - 1) * 24)
        item.label = Text(item, opt.label, 12, GOLD)
        item.label:SetPoint("LEFT", item, "LEFT", 8, 0)
        item:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
        item:SetScript("OnLeave", function(self)
            local current = getter()
            if opt.value == current then self.label:SetTextColor(1, 1, 1, 1)
            else self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        end)
        item:SetScript("OnClick", function()
            setter(opt.value)
            b.menu:Hide()
            SP.UIPlumber._openDropdown = nil
            b:Refresh()
            SP.UIPlumber:RefreshAfterChange()
        end)
        b.items[#b.items + 1] = {button=item, option=opt}
    end
    function b:Refresh()
        local current = getter()
        local text = current
        for _, v in ipairs(values) do
            if v.value == current then text = v.label break end
        end
        self.label:SetText(label .. ": |cffffffff" .. tostring(text) .. "|r")
        for _, item in ipairs(self.items or {}) do
            if item.option.value == current then item.button.label:SetTextColor(1, 1, 1, 1)
            else item.button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        end
    end
    b:Refresh()
    return b
end

local function CreateRaidMarkerPackPicker(parent, getter, setter)
    local packs = (SP.GetRaidMarkerPackOptions and SP:GetRaidMarkerPackOptions()) or {}
    local rowH = 34
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(COLUMN_WIDTH - 38, math.max(rowH, #packs * rowH + 4))
    f.rows = {}

    local function refresh()
        local current = getter()
        if not (SP.RAID_MARKER_PACKS and SP.RAID_MARKER_PACKS[current]) then current = "sign_mark" end
        for _, row in ipairs(f.rows) do
            local selected = row.value == current
            row.bg:SetColorTexture(selected and 0.42 or 0.10, selected and 0.24 or 0.07, selected and 0.05 or 0.035, selected and 0.82 or 0.72)
            row.label:SetTextColor(selected and 1 or GOLD[1], selected and 1 or GOLD[2], selected and 1 or GOLD[3], 1)
        end
    end

    for i, opt in ipairs(packs) do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(COLUMN_WIDTH - 38, rowH - 4)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 - (i - 1) * rowH)
        row.value = opt.value
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0.10, 0.07, 0.035, 0.72)
        row.label = Text(row, opt.label, 11, GOLD)
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.icons = {}
        for mark = 1, 8 do
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("RIGHT", row, "RIGHT", -6 - (8 - mark) * 22, 0)
            local tex, uv
            if SP.GetRaidMarkerIcon then tex, uv = SP:GetRaidMarkerIcon(mark, opt.value) end
            if tex then icon:SetTexture(tex) end
            if uv then icon:SetTexCoord(uv[1] or 0, uv[2] or 1, uv[3] or 0, uv[4] or 1) else icon:SetTexCoord(0, 1, 0, 1) end
            row.icons[#row.icons + 1] = icon
        end
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.30, 0.18, 0.05, 0.88)
        end)
        row:SetScript("OnLeave", refresh)
        row:SetScript("OnClick", function(self)
            setter(self.value)
            refresh()
            if SP.UIPlumber then SP.UIPlumber:RefreshAfterChange() end
        end)
        f.rows[#f.rows + 1] = row
    end

    f.Refresh = refresh
    refresh()
    return f
end

local function CreateOptionsNav(parent, currentKey, onSelect)
    local rowH = 30
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(COLUMN_WIDTH - 38, #OPTIONS_NAV * rowH + 4)
    f.rows = {}

    local function refresh()
        local current = currentKey() or "general"
        for _, row in ipairs(f.rows) do
            local selected = row.key == current
            row.bg:SetColorTexture(selected and 0.38 or 0.08, selected and 0.22 or 0.055, selected and 0.045 or 0.030, selected and 0.84 or 0.68)
            row.label:SetTextColor(selected and 1 or GOLD[1], selected and 1 or GOLD[2], selected and 1 or GOLD[3], 1)
        end
    end

    for i, opt in ipairs(OPTIONS_NAV) do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(COLUMN_WIDTH - 38, rowH - 4)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 - (i - 1) * rowH)
        row.key = opt.key
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0.08, 0.055, 0.030, 0.68)
        row.label = Text(row, opt.label, 12, GOLD)
        row.label:SetPoint("LEFT", row, "LEFT", 12, 0)
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.30, 0.17, 0.045, 0.84)
        end)
        row:SetScript("OnLeave", refresh)
        row:SetScript("OnClick", function(self)
            onSelect(self.key)
        end)
        f.rows[#f.rows + 1] = row
    end

    f.Refresh = refresh
    refresh()
    return f
end

local function CreateColorButton(parent, label, getter, setter)
    local b = CreatePanelButton(parent, "", function(self)
        local r, g, bl = getter()
        r = tonumber(r) or 1
        g = tonumber(g) or 1
        bl = tonumber(bl) or 1
        if not ColorPickerFrame then return end

        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            setter(nr, ng, nb)
            self:Refresh()
            SP.UIPlumber:RefreshLive()
        end
        local function cancel(prev)
            if prev then
                setter(prev.r or r, prev.g or g, prev.b or bl)
                self:Refresh()
                SP.UIPlumber:RefreshAfterChange()
            end
        end

        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.previousValues = {r=r, g=g, b=bl}
        pcall(ColorPickerFrame.SetColorRGB, ColorPickerFrame, r, g, bl)
        ColorPickerFrame:Show()
    end)
    b:SetSize(COLUMN_WIDTH - 38, 28)
    b.swatch = b:CreateTexture(nil, "OVERLAY")
    b.swatch:SetSize(18, 18)
    b.swatch:SetPoint("LEFT", b, "LEFT", 14, 0)
    b.swatch:SetColorTexture(1, 1, 1, 1)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.swatch, "RIGHT", 10, 0)
    function b:Refresh()
        local r, g, bl = getter()
        r = tonumber(r) or 1
        g = tonumber(g) or 1
        bl = tonumber(bl) or 1
        self.swatch:SetColorTexture(r, g, bl, 1)
        self.label:SetText(label)
    end
    b:Refresh()
    return b
end

local function CreateSlider(parent, label, minValue, maxValue, step, getter, setter)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(COLUMN_WIDTH - 38, 48)
    f.label = Text(f, label, 12, GOLD)
    f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.value = Text(f, "", 12, WHITE)
    f.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local s = CreateFrame("Slider", nil, f)
    f.slider = s
    s:SetSize(COLUMN_WIDTH - 112, 14)
    s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minValue, maxValue)
    s:SetValueStep(step or 1)
    pcall(s.SetObeyStepOnDrag, s, true)

    f.track = f:CreateTexture(nil, "BACKGROUND")
    f.track:SetPoint("LEFT", s, "LEFT", 0, 0)
    f.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    f.track:SetHeight(3)
    f.track:SetColorTexture(0.50, 0.42, 0.34, 0.72)

    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(20, 20) end

    f.minText = Text(f, tostring(minValue), 9, MUTED)
    f.maxText = Text(f, tostring(maxValue), 9, MUTED)
    f.minText:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, 0)
    f.maxText:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, 0)

    local function normalize(value)
        value = tonumber(value) or minValue
        if step and step > 0 then
            value = math.floor((value / step) + 0.5) * step
        end
        if value < minValue then value = minValue end
        if value > maxValue then value = maxValue end
        return value
    end

    local function formatValue(value)
        if step and step < 1 then
            return string.format("%.2f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    s:SetValue(normalize(getter() or minValue))
    f.value:SetText(formatValue(s:GetValue()))
    s:SetScript("OnValueChanged", function(self, value)
        value = normalize(value)
        f.value:SetText(formatValue(value))
        setter(value)
        SP.UIPlumber:RefreshLive()
    end)
    return f
end

local function CreateScrollArea(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    holder.visibleHeight = height

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    holder.scroll = scroll
    scroll:EnableMouse(true)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -30, 0)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 34, height)
    scroll:SetScrollChild(child)
    holder.child = child

    holder.rail = CreateFrame("Frame", nil, holder)
    holder.rail:SetWidth(20)
    holder.rail:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    holder.rail:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    holder.rail:EnableMouse(true)

    holder.railTop = holder.rail:CreateTexture(nil, "BACKGROUND")
    holder.railMiddle = holder.rail:CreateTexture(nil, "BACKGROUND")
    holder.railBottom = holder.rail:CreateTexture(nil, "BACKGROUND")
    SafeTexture(holder.railTop, SCROLL_TEX)
    SafeTexture(holder.railMiddle, SCROLL_TEX)
    SafeTexture(holder.railBottom, SCROLL_TEX)
    holder.railTop:SetSize(16, 16)
    holder.railTop:SetPoint("CENTER", holder.rail, "TOP", 0, -16)
    holder.railBottom:SetSize(16, 16)
    holder.railBottom:SetPoint("CENTER", holder.rail, "BOTTOM", 0, 16)
    holder.railMiddle:SetPoint("TOPLEFT", holder.railTop, "BOTTOMLEFT")
    holder.railMiddle:SetPoint("BOTTOMRIGHT", holder.railBottom, "TOPRIGHT")
    holder.railTop:SetTexCoord(0/512, 32/512, 0/512, 32/512)
    holder.railMiddle:SetTexCoord(0/512, 32/512, 32/512, 96/512)
    holder.railBottom:SetTexCoord(0/512, 32/512, 96/512, 128/512)

    holder.up = holder.rail:CreateTexture(nil, "OVERLAY")
    holder.up:SetSize(20, 16)
    holder.up:SetPoint("TOP")
    SafeTexture(holder.up, SCROLL_TEX)
    holder.up:SetTexCoord(0/512, 32/512, 396/512, 428/512)
    holder.upHighlight = holder.rail:CreateTexture(nil, "HIGHLIGHT")
    holder.upHighlight:SetAllPoints(holder.up)
    SafeTexture(holder.upHighlight, SCROLL_TEX)
    holder.upHighlight:SetTexCoord(0/512, 32/512, 396/512, 428/512)
    holder.upHighlight:SetBlendMode("ADD")
    holder.upHighlight:SetAlpha(0)

    holder.down = holder.rail:CreateTexture(nil, "OVERLAY")
    holder.down:SetSize(20, 16)
    holder.down:SetPoint("BOTTOM")
    SafeTexture(holder.down, SCROLL_TEX)
    holder.down:SetTexCoord(0/512, 32/512, 428/512, 460/512)
    holder.downHighlight = holder.rail:CreateTexture(nil, "HIGHLIGHT")
    holder.downHighlight:SetAllPoints(holder.down)
    SafeTexture(holder.downHighlight, SCROLL_TEX)
    holder.downHighlight:SetTexCoord(0/512, 32/512, 428/512, 460/512)
    holder.downHighlight:SetBlendMode("ADD")
    holder.downHighlight:SetAlpha(0)

    holder.thumb = CreateFrame("Button", nil, holder.rail)
    holder.thumb:SetSize(20, 48)
    holder.thumb:EnableMouse(true)
    holder.thumb.top = holder.thumb:CreateTexture(nil, "ARTWORK")
    holder.thumb.middle = holder.thumb:CreateTexture(nil, "ARTWORK")
    holder.thumb.bottom = holder.thumb:CreateTexture(nil, "ARTWORK")
    holder.thumb.highlightTop = holder.thumb:CreateTexture(nil, "HIGHLIGHT")
    holder.thumb.highlightMiddle = holder.thumb:CreateTexture(nil, "HIGHLIGHT")
    holder.thumb.highlightBottom = holder.thumb:CreateTexture(nil, "HIGHLIGHT")
    SafeTexture(holder.thumb.top, SCROLL_TEX)
    SafeTexture(holder.thumb.middle, SCROLL_TEX)
    SafeTexture(holder.thumb.bottom, SCROLL_TEX)
    SafeTexture(holder.thumb.highlightTop, SCROLL_TEX)
    SafeTexture(holder.thumb.highlightMiddle, SCROLL_TEX)
    SafeTexture(holder.thumb.highlightBottom, SCROLL_TEX)
    holder.thumb.top:SetSize(16, 16)
    holder.thumb.top:SetPoint("CENTER", holder.thumb, "TOP")
    holder.thumb.bottom:SetSize(16, 16)
    holder.thumb.bottom:SetPoint("CENTER", holder.thumb, "BOTTOM")
    holder.thumb.middle:SetPoint("TOPLEFT", holder.thumb.top, "BOTTOMLEFT")
    holder.thumb.middle:SetPoint("BOTTOMRIGHT", holder.thumb.bottom, "TOPRIGHT")
    holder.thumb.highlightTop:SetAllPoints(holder.thumb.top)
    holder.thumb.highlightMiddle:SetAllPoints(holder.thumb.middle)
    holder.thumb.highlightBottom:SetAllPoints(holder.thumb.bottom)
    holder.thumb.highlightTop:SetBlendMode("ADD")
    holder.thumb.highlightMiddle:SetBlendMode("ADD")
    holder.thumb.highlightBottom:SetBlendMode("ADD")
    holder.thumb.highlightTop:SetAlpha(0.20)
    holder.thumb.highlightMiddle:SetAlpha(0.20)
    holder.thumb.highlightBottom:SetAlpha(0.20)
    holder.thumb.top:SetTexCoord(0/512, 32/512, 132/512, 164/512)
    holder.thumb.middle:SetTexCoord(0/512, 32/512, 164/512, 228/512)
    holder.thumb.bottom:SetTexCoord(0/512, 32/512, 228/512, 260/512)
    holder.thumb.highlightTop:SetTexCoord(0/512, 32/512, 132/512, 164/512)
    holder.thumb.highlightMiddle:SetTexCoord(0/512, 32/512, 164/512, 228/512)
    holder.thumb.highlightBottom:SetTexCoord(0/512, 32/512, 228/512, 260/512)

    function holder:UpdateScroll()
        local range = scroll:GetVerticalScrollRange() or 0
        local scrollValue = scroll:GetVerticalScroll() or 0
        local topPad, bottomPad = 16, 16
        local railHeight = math.max(1, self.rail:GetHeight() - topPad - bottomPad)
        if range <= 1 then
            self.thumb:Hide()
            scroll:SetVerticalScroll(0)
            return
        end
        self.thumb:Show()
        local thumbHeight = math.max(34, math.min(72, railHeight * (height / (height + range))))
        local travel = math.max(1, railHeight - thumbHeight)
        local offset = (scrollValue / range) * travel
        self.thumb:SetHeight(thumbHeight)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.rail, "TOP", 0, -(topPad + offset))
    end

    pcall(scroll.EnableMouseWheel, scroll, true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local current = self:GetVerticalScroll() or 0
        local nextValue = current - (delta * 42)
        if nextValue < 0 then nextValue = 0 end
        if nextValue > range then nextValue = range end
        self:SetVerticalScroll(nextValue)
        holder:UpdateScroll()
    end)
    scroll:SetScript("OnVerticalScroll", function() holder:UpdateScroll() end)
    scroll:SetScript("OnScrollRangeChanged", function() holder:UpdateScroll() end)

    local function setScrollValue(value)
        local range = scroll:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        if value < 0 then value = 0 end
        if value > range then value = range end
        scroll:SetVerticalScroll(value)
        holder:UpdateScroll()
    end

    local function scrollBy(delta)
        setScrollValue((scroll:GetVerticalScroll() or 0) + delta)
    end

    local function scrollToCursor()
        local range = scroll:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local _, y = GetCursorPosition()
        local scale = holder.rail:GetEffectiveScale() or 1
        y = y / scale
        local top = (holder.rail:GetTop() or 0) - 16
        local bottom = (holder.rail:GetBottom() or 0) + 16
        local travel = top - bottom
        if travel <= 0 then return end
        local ratio = (top - y) / travel
        if ratio < 0 then ratio = 0 end
        if ratio > 1 then ratio = 1 end
        setScrollValue(range * ratio)
    end

    holder.rail:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            scrollToCursor()
        end
    end)

    holder.upButton = CreateFrame("Button", nil, holder.rail)
    holder.upButton:SetSize(18, 18)
    holder.upButton:SetPoint("TOP")
    holder.upButton:SetScript("OnClick", function() scrollBy(-42) end)
    holder.upButton:SetScript("OnEnter", function() holder.upHighlight:SetAlpha(0.45) end)
    holder.upButton:SetScript("OnLeave", function() holder.upHighlight:SetAlpha(0) end)

    holder.downButton = CreateFrame("Button", nil, holder.rail)
    holder.downButton:SetSize(18, 18)
    holder.downButton:SetPoint("BOTTOM")
    holder.downButton:SetScript("OnClick", function() scrollBy(42) end)
    holder.downButton:SetScript("OnEnter", function() holder.downHighlight:SetAlpha(0.45) end)
    holder.downButton:SetScript("OnLeave", function() holder.downHighlight:SetAlpha(0) end)

    holder.thumb:SetScript("OnEnter", function(self)
        self.highlightTop:SetAlpha(0.45)
        self.highlightMiddle:SetAlpha(0.45)
        self.highlightBottom:SetAlpha(0.45)
    end)
    holder.thumb:SetScript("OnLeave", function(self)
        self.highlightTop:SetAlpha(0.20)
        self.highlightMiddle:SetAlpha(0.20)
        self.highlightBottom:SetAlpha(0.20)
    end)
    holder.thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, y = GetCursorPosition()
        holder.dragStartY = y / (holder.rail:GetEffectiveScale() or 1)
        holder.dragStartScroll = scroll:GetVerticalScroll() or 0
        self.highlightTop:SetAlpha(0.55)
        self.highlightMiddle:SetAlpha(0.55)
        self.highlightBottom:SetAlpha(0.55)
        pcall(self.LockHighlight, self)
        holder:SetScript("OnUpdate", function(self)
            local range = scroll:GetVerticalScrollRange() or 0
            if range <= 0 or not self.dragStartY then return end
            local _, cy = GetCursorPosition()
            cy = cy / (holder.rail:GetEffectiveScale() or 1)
            local railHeight = math.max(1, holder.rail:GetHeight() - 32)
            local travel = math.max(1, railHeight - holder.thumb:GetHeight())
            local dy = self.dragStartY - cy
            setScrollValue((self.dragStartScroll or 0) + (dy / travel) * range)
        end)
    end)
    holder.thumb:SetScript("OnMouseUp", function(self)
        holder.dragStartY = nil
        holder.dragStartScroll = nil
        holder:SetScript("OnUpdate", nil)
        self.highlightTop:SetAlpha(0.20)
        self.highlightMiddle:SetAlpha(0.20)
        self.highlightBottom:SetAlpha(0.20)
        pcall(self.UnlockHighlight, self)
    end)
    holder.thumb:SetScript("OnHide", function(self)
        holder.dragStartY = nil
        holder.dragStartScroll = nil
        holder:SetScript("OnUpdate", nil)
        pcall(self.UnlockHighlight, self)
    end)

    return holder
end

local function CreateSectionHeader(parent, title, key, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 708, 28)
    b.left = b:CreateTexture(nil, "BACKGROUND")
    b.center = b:CreateTexture(nil, "BACKGROUND")
    b.right = b:CreateTexture(nil, "BACKGROUND")
    SafeTexture(b.left, TEX); SafeTexture(b.center, TEX); SafeTexture(b.right, TEX)
    b.left:SetSize(22, 28); b.left:SetPoint("LEFT")
    b.right:SetSize(22, 28); b.right:SetPoint("RIGHT")
    b.center:SetPoint("TOPLEFT", b.left, "TOPRIGHT")
    b.center:SetPoint("BOTTOMRIGHT", b.right, "BOTTOMLEFT")
    b.left:SetTexCoord(694/1024, 734/1024, 48/1024, 112/1024)
    b.center:SetTexCoord(734/1024, 910/1024, 48/1024, 112/1024)
    b.right:SetTexCoord(910/1024, 950/1024, 48/1024, 112/1024)

    b.label = Text(b, title, 13, MUTED)
    b.label:SetPoint("LEFT", b, "LEFT", 34, 0)

    function b:Refresh()
        local collapsed = SP.UIPlumber.collapsed and SP.UIPlumber.collapsed[key]
        self.label:SetTextColor(collapsed and MUTED[1] or WHITE[1], collapsed and MUTED[2] or WHITE[2], collapsed and MUTED[3] or WHITE[3], 1)
    end
    b:SetScript("OnClick", function(self)
        SP.UIPlumber.collapsed = SP.UIPlumber.collapsed or {}
        SP.UIPlumber.collapsed[key] = not SP.UIPlumber.collapsed[key]
        self:Refresh()
        SP.UIPlumber:BuildSettings()
    end)
    b:Refresh()
    return b
end

SP.UIPlumber = SP.UIPlumber or {
    category = "enemy",
    unitKind = {enemy="npc", neutral="npc", friendly="npc"},
    page = "sphere",
    collapsed = {},
    copySourceByPage = {},
}

local function IsSpecialCategory(key)
    return key == "behavior" or key == "modules" or key == "logs"
end

function SP.UIPlumber:GetUnitEntry()
    if self.category == "behavior" then
        return {kind="global", label="Options", utype="ENEMY", title="Options globales"}
    end
    if self.category == "modules" then
        return {kind="global", label="Modules", utype="ENEMY", title="Modules et performance"}
    end
    if self.category == "logs" then
        return {kind="global", label="Logs", utype="ENEMY", title="Journal interne"}
    end
    local list = UNIT_BY_CATEGORY[self.category] or UNIT_BY_CATEGORY.enemy
    local kind = self.unitKind[self.category] or "npc"
    for _, entry in ipairs(list) do
        if entry.kind == kind then return entry end
    end
    return list[1]
end

function SP.UIPlumber:GetUType()
    return self:GetUnitEntry().utype
end

function SP.UIPlumber:GetCfg()
    return SP:GetCfg(self:GetUType())
end

function SP.UIPlumber:SetCfg(key, value)
    local utype = self:GetUType()
    if SP.db and SP.db[utype] then
        SP.db[utype][key] = value
    end
end

function SP.UIPlumber:GetCfgValue(key, fallback)
    local cfg = self:GetCfg()
    local value = cfg and cfg[key]
    if value == nil then return fallback end
    return value
end

function SP.UIPlumber:GetCopySources()
    local current = self:GetUType()
    local out = {}
    for _, cat in ipairs(CATEGORY) do
        if cat.key ~= "behavior" and cat.key ~= "modules" and cat.key ~= "logs" then
            for _, entry in ipairs(UNIT_BY_CATEGORY[cat.key] or {}) do
                if entry.utype and entry.utype ~= current then
                    out[#out + 1] = {
                        value = entry.utype,
                        label = UnitEntryLabel(entry),
                    }
                end
            end
        end
    end
    return out
end

function SP.UIPlumber:GetCopySource()
    local sources = self:GetCopySources()
    if #sources == 0 then return nil end
    local current = self.copySourceByPage and self.copySourceByPage[self.page]
    for _, source in ipairs(sources) do
        if source.value == current then return current end
    end
    current = sources[1].value
    self.copySourceByPage = self.copySourceByPage or {}
    self.copySourceByPage[self.page] = current
    return current
end

function SP.UIPlumber:SetCopySource(value)
    self.copySourceByPage = self.copySourceByPage or {}
    self.copySourceByPage[self.page] = value
end

function SP.UIPlumber:CopyCurrentPageFrom(sourceUType)
    if self.category == "behavior" or self.category == "modules" or self.category == "logs" or not COPY_GROUPS[self.page] then
        return false, "Cette page ne supporte pas la copie."
    end
    local targetUType = self:GetUType()
    if not sourceUType or sourceUType == targetUType then
        return false, "Source invalide."
    end
    if not (SP.db and SP.db[targetUType]) then
        return false, "Profil cible introuvable."
    end

    local sourceCfg = SP.GetCfg and SP:GetCfg(sourceUType) or (SP.db and SP.db[sourceUType])
    if not sourceCfg then
        return false, "Profil source introuvable."
    end

    local copied = 0
    for key, value in pairs(sourceCfg) do
        if CopyKeyAllowed(self.page, key) then
            SP.db[targetUType][key] = DeepCopy(value)
            copied = copied + 1
        end
    end

    if copied <= 0 then
        return false, "Aucun parametre compatible a copier."
    end
    return true, copied
end

function SP.UIPlumber:RefreshAfterChange()
    if SP.RefreshAll then SP:RefreshAll() end
    if SP.PlayerContextMenu and SP.PlayerContextMenu.RefreshAttachments then
        pcall(SP.PlayerContextMenu.RefreshAttachments, SP.PlayerContextMenu)
    end
    if SP.RaidMarkerMenu and SP.RaidMarkerMenu.RefreshAttachments then
        pcall(SP.RaidMarkerMenu.RefreshAttachments, SP.RaidMarkerMenu)
    end
    if self.win and self.win:IsShown() then
        self:BuildSettings()
        self:RebuildPreview()
    end
end

function SP.UIPlumber:RefreshLive()
    if SP.RefreshAll then SP:RefreshAll() end
    if SP.PlayerContextMenu and SP.PlayerContextMenu.RefreshAttachments then
        pcall(SP.PlayerContextMenu.RefreshAttachments, SP.PlayerContextMenu)
    end
    if SP.RaidMarkerMenu and SP.RaidMarkerMenu.RefreshAttachments then
        pcall(SP.RaidMarkerMenu.RefreshAttachments, SP.RaidMarkerMenu)
    end
    if self.win and self.win:IsShown() then
        self:BuildQuick()
        self:RebuildPreview()
    end
end

function SP.UIPlumber:BuildWindow()
    local win = CreateFrame("Frame", "SphereNameplatesPlumberStyleFrame", UIParent, "BackdropTemplate")
    self.win = win
    win:SetSize(1300, 700)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(400)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    table.insert(UISpecialFrames, win:GetName())

    local left = CreateFrame("Frame", nil, win)
    win.left = left
    left:SetSize(300, 640)
    left:SetPoint("LEFT", win, "LEFT", 30, 8)
    CreateNineSlice(left)

    local right = CreateFrame("Frame", nil, win)
    win.right = right
    right:SetSize(880, 640)
    right:SetPoint("LEFT", left, "RIGHT", 44, 8)
    local ns = CreateNineSlice(right)
    local atlasOK = SafeAtlas(ns.bg, BG_ATLAS)
    if not atlasOK then
        ns.bg:SetColorTexture(0.060, 0.043, 0.030, 0.96)
    end
    ns.bg:SetVertexColor(0.24, 0.20, 0.16, 0.92)

    local close = CreateCloseButton(right)
    close:SetPoint("TOPRIGHT", right, "TOPRIGHT", 20, 22)
    close:SetScript("OnClick", function() win:Hide() end)
    win:SetScript("OnHide", function()
        if self._openDropdown then
            self._openDropdown:Hide()
            self._openDropdown = nil
        end
    end)

    win.title = Text(left, "|cFF8B0000Sphere|r|cFFFF7A00Plates|r", 20, WHITE)
    win.title:SetPoint("TOPLEFT", left, "TOPLEFT", 24, -16)

    win.previewTitle = Text(left, "Previsualisation", 14, GOLD)
    win.previewTitle:SetPoint("TOP", left, "TOP", 0, -58)

    win.previewArea = CreateFrame("Frame", nil, left)
    win.previewArea:SetSize(230, 220)
    win.previewArea:SetPoint("TOP", left, "TOP", 0, -86)
    win.previewArea.bg = win.previewArea:CreateTexture(nil, "BACKGROUND")
    win.previewArea.bg:SetAllPoints()
    win.previewArea.bg:SetColorTexture(0.02, 0.018, 0.014, 0.56)

    win.fakePlate = CreateFrame("Frame", nil, win.previewArea)
    win.fakePlate:SetSize(1, 1)
    win.fakePlate:SetPoint("CENTER")

    win.unitTitle = Text(left, "", 16, WHITE)
    win.unitTitle:SetPoint("TOP", win.previewArea, "BOTTOM", 0, -10)

    win.leftDivider = CreateDivider(left)
    win.leftDivider:SetPoint("TOPLEFT", win.unitTitle, "BOTTOMLEFT", -95, -12)
    win.leftDivider:SetPoint("TOPRIGHT", win.unitTitle, "BOTTOMRIGHT", 95, -12)

    win.profileBar = CreateFrame("Frame", nil, left)
    win.profileBar:SetSize(260, 90)
    win.profileBar:SetPoint("TOP", win.leftDivider, "BOTTOM", 0, -8)

    win.quick = CreateFrame("Frame", nil, left)
    win.quick:SetSize(240, 190)
    win.quick:SetPoint("TOP", win.profileBar, "BOTTOM", 0, -8)

    local header = CreateFrame("Frame", nil, right)
    win.header = header
    header:SetSize(820, 118)
    header:SetPoint("TOP", right, "TOP", 0, -18)

    win.kindButtons = {}
    local playerTab = CreateTextTab(header, "Joueurs", function()
        self.unitKind.enemy = "player"
        self.unitKind.friendly = "player"
        self.unitKind.neutral = "npc"
        if self.category == "neutral" or IsSpecialCategory(self.category) then
            self.category = "enemy"
        end
        self:RefreshAll()
    end)
    playerTab:SetPoint("TOPLEFT", header, "TOPLEFT", 36, -2)
    win.kindButtons.player = playerTab
    win.topButtons = {player = playerTab}

    local npcTab = CreateTextTab(header, "PNJ", function()
        self.unitKind.enemy = "npc"
        self.unitKind.neutral = "npc"
        self.unitKind.friendly = "npc"
        if IsSpecialCategory(self.category) then
            self.category = "enemy"
        end
        self:RefreshAll()
    end)
    npcTab:SetPoint("LEFT", playerTab, "RIGHT", 18, 0)
    win.kindButtons.npc = npcTab
    win.topButtons.npc = npcTab

    local optTab = CreateTextTab(header, "Options", function()
        self.category = "behavior"
        self.optionsPage = self.optionsPage or "general"
        self:RefreshAll()
    end, {0.55, 0.82, 1.00})
    optTab:SetPoint("LEFT", npcTab, "RIGHT", 34, 0)
    win.topButtons.behavior = optTab

    local modTab = CreateTextTab(header, "Modules", function()
        self.category = "modules"
        self:RefreshAll()
    end, {0.78, 0.68, 1.00})
    modTab:SetPoint("LEFT", optTab, "RIGHT", 18, 0)
    win.topButtons.modules = modTab

    local logsTab = CreateTextTab(header, "Logs", function()
        self.category = "logs"
        self:RefreshAll()
    end, {1.00, 0.62, 0.28})
    logsTab:SetPoint("LEFT", modTab, "RIGHT", 18, 0)
    win.topButtons.logs = logsTab

    win.catButtons = {}
    local last
    for _, cat in ipairs(CATEGORY) do
        if not IsSpecialCategory(cat.key) then
        local b = CreateTextTab(header, cat.label, function()
            self.category = cat.key
            local _special = IsSpecialCategory(cat.key)
            if not _special and self.page == "behavior" then self.page = "sphere" end
            if not self.unitKind[cat.key] then self.unitKind[cat.key] = "npc" end
            self:RefreshAll()
        end)
        if last then b:SetPoint("LEFT", last, "RIGHT", 18, 0)
        else b:SetPoint("TOPLEFT", header, "TOPLEFT", 36, -38) end
        win.catButtons[cat.key] = b
        last = b
        end
    end

    win.select = CreateFrame("Button", nil, header)
    win.select:SetSize(190, 32)
    win.select:SetPoint("TOPRIGHT", header, "TOPRIGHT", -34, -4)
    win.select.text = Text(win.select, "", 18, GOLD)
    win.select.text:SetPoint("RIGHT", win.select, "RIGHT", -20, 0)
    win.select.arrow = win.select:CreateTexture(nil, "OVERLAY")
    win.select.arrow:SetSize(18, 18)
    win.select.arrow:SetPoint("RIGHT", win.select.text, "LEFT", 0, 0)
    SafeTexture(win.select.arrow, "Interface/AddOns/Plumber/Art/ExpansionLandingPage/ChecklistButton.tga")
    win.select.arrow:SetTexCoord(0, 48/512, 208/512, 256/512)
    win.select:SetScript("OnClick", function() self:ToggleUnitMenu() end)
    win.select:Hide()

    win.unitMenu = CreateFrame("Frame", nil, win.select, "BackdropTemplate")
    win.unitMenu:SetSize(170, 58)
    win.unitMenu:SetPoint("TOPRIGHT", win.select, "BOTTOMRIGHT", 0, -2)
    win.unitMenu:SetFrameLevel(win:GetFrameLevel() + 30)
    win.unitMenu:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
    win.unitMenu:SetBackdropColor(0.02, 0.016, 0.012, 0.98)
    win.unitMenu:Hide()

    win.divider = CreateDivider(header)
    win.divider:SetPoint("LEFT", header, "BOTTOMLEFT", 22, 14)
    win.divider:SetPoint("RIGHT", header, "BOTTOMRIGHT", -22, 14)

    win.pageButtons = {}
    local pageContainer = CreateFrame("Frame", nil, right)
    win.pageContainer = pageContainer
    pageContainer:SetSize(820, 42)
    pageContainer:SetPoint("TOP", header, "BOTTOM", 0, 0)
    local prev
    for _, page in ipairs(PAGES) do
        local b = CreateTextTab(pageContainer, page.label, function()
            self.page = page.key
            self:BuildQuick()
            self:BuildSettings()
        end)
        b:SetSize(108, 30)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        else b:SetPoint("LEFT", pageContainer, "LEFT", 18, 0) end
        win.pageButtons[page.key] = b
        prev = b
    end

    win.scroll = CreateScrollArea(right, 850, 430)
    win.scroll:SetPoint("TOPRIGHT", pageContainer, "BOTTOMRIGHT", 22, -6)
    win.content = win.scroll.child

    win.status = Text(left, "", 10, MUTED)
    win.status:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 40, 56)

    self:BuildProfileBar()

    return win
end

function SP.UIPlumber:ClearChildren(frame)
    if not frame.children then frame.children = {} end
    for _, child in ipairs(frame.children) do
        child:Hide()
        child:ClearAllPoints()
    end
    frame.children = {}
end

function SP.UIPlumber:AddChild(parent, child)
    parent.children = parent.children or {}
    table.insert(parent.children, child)
    return child
end

local function EnsureRaidMarkerPreview(win)
    if not win or not win.previewArea then return nil end
    if win.raidMarkerPreview then return win.raidMarkerPreview end
    local f = CreateFrame("Frame", nil, win.previewArea)
    f:SetSize(220, 220)
    f:SetPoint("CENTER", win.previewArea, "CENTER", 0, 2)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(470)
    f.buttons = {}
    f.glows = {}
    win.raidMarkerPreview = f
    return f
end

local function HideRaidMarkerPreview(win)
    local f = win and win.raidMarkerPreview
    if f then f:Hide() end
end

function SP.UIPlumber:BuildRaidMarkerPreview()
    local win = self.win
    local f = EnsureRaidMarkerPreview(win)
    if not f then return end
    local db = SP.db or {}
    local radius = tonumber(db.raidmark_menu_radius) or 58
    local size = tonumber(db.raidmark_menu_icon_size) or 38
    local alpha = tonumber(db.raidmark_menu_alpha) or 1
    local scale = tonumber(db.raidmark_menu_scale) or 1
    radius = math.max(34, math.min(128, radius))
    size = math.max(18, math.min(72, size))
    f:Show()
    for i = 1, 8 do
        local btn = f.buttons[i]
        if not btn then
            btn = CreateFrame("Frame", nil, f)
            btn:SetFrameLevel(f:GetFrameLevel() + 2)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints(btn)
            btn.glow = btn:CreateTexture(nil, "OVERLAY")
            btn.glow:SetTexture("Interface\\Cooldown\\ping4")
            btn.glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.glow:SetBlendMode("ADD")
            btn.glow:SetAlpha(0)
            f.buttons[i] = btn
        end
        local angle = -math.pi / 2 + (i - 1) * (math.pi * 2 / 8)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", f, "CENTER", math.cos(angle) * radius, -math.sin(angle) * radius)
        btn:SetSize(size, size)
        btn:SetScale(scale)
        btn:SetAlpha(alpha)
        local tex, uv = nil, nil
        if SP.GetRaidMarkerIcon then tex, uv = SP:GetRaidMarkerIcon(i, db.raidmark_pack) end
        btn.icon:SetTexture(tex or ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(i)))
        if uv then
            btn.icon:SetTexCoord(uv[1] or 0, uv[2] or 1, uv[3] or 0, uv[4] or 1)
        else
            btn.icon:SetTexCoord(0, 1, 0, 1)
        end
        if i == 8 then
            btn.glow:SetSize(size * 1.22, size * 1.22)
            btn.glow:SetVertexColor(0.92, 0.92, 0.86, 1)
            btn.glow:SetAlpha(0.55)
        else
            btn.glow:SetAlpha(0)
        end
        btn:Show()
    end
end

function SP.UIPlumber:ToggleUnitMenu()
    local win = self.win
    if not win then return end
    local menu = win.unitMenu
    if IsSpecialCategory(self.category) then menu:Hide(); return end
    if menu:IsShown() then menu:Hide(); return end
    self:ClearChildren(menu)
    local list = UNIT_BY_CATEGORY[self.category] or UNIT_BY_CATEGORY.enemy
    if #list <= 1 then
        self.unitKind[self.category] = list[1].kind
        menu:Hide()
        self:RefreshHeader()
        return
    end
    local y = -6
    for _, entry in ipairs(list) do
        local b = self:AddChild(menu, CreateFrame("Button", nil, menu))
        b:SetSize(150, 22)
        b:SetPoint("TOP", menu, "TOP", 0, y)
        b.text = Text(b, entry.label, 12, entry.kind == self.unitKind[self.category] and WHITE or GOLD)
        b.text:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            self.unitKind[self.category] = entry.kind
            menu:Hide()
            self:RefreshAll()
        end)
        y = y - 24
    end
    menu:Show()
end

function SP.UIPlumber:RebuildPreview()
    local win = self.win
    if not win then return end
    if self.category == "behavior" or self.category == "modules" or self.category == "logs" then
        if self.previewData then
            if self.previewData.castbar then pcall(SP.CastBar.Reset, SP.CastBar, self.previewData) end
            if self.previewData.root then self.previewData.root:Hide() end
            self.previewData = nil
        end
        HideRaidMarkerPreview(win)
        if self.category == "behavior" and self.optionsPage == "markers" then
            local ok, data = pcall(SP.Orb.Create, SP.Orb, nil, win.fakePlate, "ENEMY")
            if ok and data then
                self.previewData = data
                data.root:ClearAllPoints()
                data.root:SetPoint("CENTER", win.previewArea, "CENTER", 0, 2)
                data.root:SetFrameStrata("DIALOG")
                data.root:SetFrameLevel(450)
                data.root:Show()
                pcall(SP.Orb.UpdateFill, SP.Orb, data, 0.72)
                data.targetHP = 0.72
                data.displayHP = 0.72
                data._isTarget = true
                data._previewName = "Cible marquee"
                if data.nameText then data.nameText:SetText(data._previewName); data.nameText:Show() end
                if data.raidIcon then
                    local tex, uv = nil, nil
                    if SP.GetRaidMarkerIcon then tex, uv = SP:GetRaidMarkerIcon(8, (SP.db or {}).raidmark_pack) end
                    data.raidIcon:ClearAllPoints()
                    data.raidIcon:SetPoint("CENTER", data.orbFrame or data.orb, "CENTER", (SP.db and SP.db.raidmark_offset_x) or 0, (SP.db and SP.db.raidmark_offset_y) or 20)
                    data.raidIcon:SetSize(((SP.db and SP.db.raidmark_size) or 24) * ((SP.db and SP.db.raidmark_scale) or 1), ((SP.db and SP.db.raidmark_size) or 24) * ((SP.db and SP.db.raidmark_scale) or 1))
                    data.raidIcon:SetTexture(tex or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                    if uv then data.raidIcon:SetTexCoord(uv[1] or 0, uv[2] or 1, uv[3] or 0, uv[4] or 1) else data.raidIcon:SetTexCoord(0, 1, 0, 1) end
                    data.raidIcon:SetAlpha((SP.db and SP.db.raidmark_alpha) or 1)
                    if data.raidIconFrame then data.raidIconFrame:Show() end
                end
                pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg("ENEMY"))
                self:BuildRaidMarkerPreview()
            end
            win.unitTitle:SetText("Marqueurs WoW")
            return
        end
        local labels = {behavior="Options globales", modules="Modules et performance", logs="Journal interne"}
        win.unitTitle:SetText(labels[self.category] or "")
        return
    end
    if self.previewData then
        if self.previewData.castbar then pcall(SP.CastBar.Reset, SP.CastBar, self.previewData) end
        if self.previewData.root then self.previewData.root:Hide() end
        self.previewData = nil
    end
    HideRaidMarkerPreview(win)
    local utype = self:GetUType()
    local ok, data = pcall(SP.Orb.Create, SP.Orb, nil, win.fakePlate, utype)
    if ok and data then
        self.previewData = data
        data.root:ClearAllPoints()
        data.root:SetPoint("CENTER", win.previewArea, "CENTER", 0, 2)
        data.root:SetFrameStrata("DIALOG")
        data.root:SetFrameLevel(450)
        data.root:Show()
        pcall(SP.Orb.UpdateFill, SP.Orb, data, 0.72)
        if data.hpBar then data.hpBar:SetMinMaxValues(0, 100); data.hpBar:SetValue(72) end
        data.targetHP = 0.72
        data.displayHP = 0.72
        data._isTarget = true
        data._inCombat = true
        data._previewAbsHP = "166k"
        data._previewName = self:GetUnitEntry().title
        if data.nameText then data.nameText:SetText(data._previewName); data.nameText:Show() end
        if data.levelText then
            local cfg = SP:GetCfg(utype)
            SP:ApplyHPTextPair(data.levelText, data.hpSubText, data, nil, (cfg and cfg.hpFormat) or "percent", cfg and cfg.hp_show_percent)
        end
        if SP.Auras and SP.Auras.SimulateAuras then pcall(SP.Auras.SimulateAuras, SP.Auras, data) end
        if SP.CastBar then
            pcall(SP.CastBar.Create, SP.CastBar, data)
            if self.page == "castbar" then
                -- Démarrer immédiatement un cast de prévisualisation.
                -- Le ticker SP_PSUI_CastPreviewTicker animera l'arc et fera
                -- l'auto-loop cast↔canal de façon transparente.
                self._castPreviewLastMode = "channel"  -- → premier cycle sera "cast"
                self._castPreviewRestartAt = nil
                pcall(SP.CastBar.TestCast, SP.CastBar, data, 3.0)
                self._castPreviewLastMode = "cast"
            end
        end
        pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg(utype))
    end
    win.unitTitle:SetText(self:GetUnitEntry().title)
end

function SP.UIPlumber:BuildQuick()
    local win = self.win
    local q = win.quick
    self:ClearChildren(q)
    if self.category == "behavior" or self.category == "modules" or self.category == "logs" then
        return
    end

    local function pageLabel()
        for _, page in ipairs(PAGES) do
            if page.key == self.page then return page.label end
        end
        return self.page
    end
    local function copySourceLabel(utype)
        for _, source in ipairs(self:GetCopySources()) do
            if source.value == utype then return source.label end
        end
        return tostring(utype or "")
    end
    local sources = self:GetCopySources()
    if #sources == 0 then return end

    local title = self:AddChild(q, Text(q, "Copier a partir de", 13, GOLD))
    title:SetPoint("TOP", q, "TOP", 0, 0)

    local source = self:AddChild(q, CreatePanelButton(q, "", function(button)
        if SP.UIPlumber._openDropdown and SP.UIPlumber._openDropdown ~= button.menu then
            SP.UIPlumber._openDropdown:Hide()
        end
        if button.menu:IsShown() then
            button.menu:Hide()
            SP.UIPlumber._openDropdown = nil
        else
            button.menu:Show()
            SP.UIPlumber._openDropdown = button.menu
        end
    end))
    source:SetSize(238, 28)
    source:SetPoint("TOP", title, "BOTTOM", 0, -14)
    source.label:ClearAllPoints()
    source.label:SetPoint("LEFT", source, "LEFT", 16, 0)
    source.label:SetJustifyH("LEFT")

    source.menu = CreateFrame("Frame", nil, source, "BackdropTemplate")
    source.menu:SetSize(230, math.max(28, #sources * 24 + 8))
    source.menu:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 4, -2)
    source.menu:SetFrameStrata("DIALOG")
    source.menu:SetFrameLevel(960)
    source.menu:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
    source.menu:SetBackdropColor(0.02, 0.016, 0.012, 0.98)
    source.menu:Hide()

    function source:Refresh()
        self.label:SetText("Source: |cffffffff" .. copySourceLabel(SP.UIPlumber:GetCopySource()) .. "|r")
    end

    for i, opt in ipairs(sources) do
        local item = CreateFrame("Button", nil, source.menu)
        item:SetSize(214, 22)
        item:SetPoint("TOPLEFT", source.menu, "TOPLEFT", 8, -4 - (i - 1) * 24)
        item.label = Text(item, opt.label, 12, opt.value == self:GetCopySource() and WHITE or GOLD)
        item.label:SetPoint("LEFT", item, "LEFT", 6, 0)
        item:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
        item:SetScript("OnLeave", function(self)
            if opt.value == SP.UIPlumber:GetCopySource() then self.label:SetTextColor(1, 1, 1, 1)
            else self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        end)
        item:SetScript("OnClick", function()
            self:SetCopySource(opt.value)
            source.menu:Hide()
            SP.UIPlumber._openDropdown = nil
            source:Refresh()
        end)
    end
    source:SetScript("OnHide", function(self)
        if self.menu then self.menu:Hide() end
    end)
    source:Refresh()

    local copy = self:AddChild(q, CreatePanelButton(q, "Copier vers " .. pageLabel(), function()
        local src = self:GetCopySource()
        local ok, result = self:CopyCurrentPageFrom(src)
        if ok then
            if SP.Print then
                SP:Print("Copie " .. pageLabel() .. " : " .. copySourceLabel(src) .. " -> " .. UnitEntryLabel(self:GetUnitEntry()) .. " (" .. tostring(result) .. " reglages)")
            end
            self:RefreshAfterChange()
        elseif SP.Print then
            SP:Print("|cFFFF4444Copie impossible : " .. tostring(result) .. "|r")
        end
    end))
    copy:SetSize(210, 28)
    copy:SetPoint("TOP", source, "BOTTOM", 0, -18)
end

function SP.UIPlumber:BuildSettings()
    local win = self.win
    if not win then return end
    local c = win.content
    self.collapsed = self.collapsed or {}
    if self._openDropdown then
        self._openDropdown:Hide()
        self._openDropdown = nil
    end
    self:ClearChildren(c)
    for k, b in pairs(win.pageButtons or {}) do b:SetSelected(k == self.page) end

    local colX = {8, 8 + COLUMN_WIDTH + COLUMN_GAP}
    local colY = {-4, -4}
    local activeCol = 1
    local function add(widget, x, height, col)
        col = col or activeCol or 1
        widget:SetPoint("TOPLEFT", c, "TOPLEFT", colX[col] + (x or 0), colY[col])
        self:AddChild(c, widget)
        colY[col] = colY[col] - (height or widget:GetHeight() or 32) - 8
        return widget
    end
    local function section(title, key, builder, col)
        activeCol = col or 1
        local fullKey = self.page .. ":" .. key
        add(CreateSectionHeader(c, title, fullKey, COLUMN_WIDTH - 8), 0, 30, activeCol)
        if not self.collapsed[fullKey] then
            colY[activeCol] = colY[activeCol] - 2
            builder()
            colY[activeCol] = colY[activeCol] - 8
        end
    end
    local function get(k, fallback) return function() return self:GetCfgValue(k, fallback) end end
    local function set(k) return function(v) self:SetCfg(k, v) end end
    local function getSphereDisplayMode()
        return function()
            local cfg = self:GetCfg()
            local mode = cfg.sphere_display_mode
            if mode == "never" or cfg.enabled == false then return "never" end
            if mode == "combat" or mode == "target" or mode == "always" then return mode end
            return "always"
        end
    end
    local function setSphereDisplayMode(v)
        self:SetCfg("sphere_display_mode", v)
        self:SetCfg("enabled", v ~= "never")
    end
    local function getGlobal(k, fallback)
        return function()
            if SP.db and SP.db[k] ~= nil then return SP.db[k] end
            return fallback
        end
    end
    local function setGlobal(k)
        return function(v)
            if SP.db then SP.db[k] = v end
            if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
            if SP.HardRefreshAll then SP:HardRefreshAll() end
        end
    end
    local function setBorderMode(v)
        self:SetCfg("borderColorMode", v)
        self:SetCfg("borderClassColor", v == "classe")
    end
    local function setBorderStyle(v)
        self:SetCfg("borderStyle", v)
        if v == "classique" or v == "detail" or v == "shadowcircle" then
            self:SetCfg("borderOverlayScale", 1.6)
        elseif v == "wow_horde" or v == "wow_alliance" or v == "wow_evil"
            or v == "wow_beast" or v == "wow_stone" or v == "wow_gold"
            or v == "ns_horde" or v == "ns_alliance" or v == "ns_void"
            or v == "ns_beast" or v == "ns_obsidian" or v == "ns_gold_ring" then
            self:SetCfg("borderOverlayScale", 1.72)
        end
    end
    local function getColor(rk, gk, bk, dr, dg, db)
        return function()
            local cfg = self:GetCfg()
            return cfg[rk] or dr, cfg[gk] or dg, cfg[bk] or db
        end
    end
    local function setColor(rk, gk, bk)
        return function(r, g, b)
            self:SetCfg(rk, r)
            self:SetCfg(gk, g)
            self:SetCfg(bk, b)
        end
    end
    local function getFontOptions()
        local opts = {}
        for name in pairs(SP.FONT_LIST or {["Friz Quadrata TT"]=true}) do
            opts[#opts + 1] = {value=name, label=name}
        end
        table.sort(opts, function(a, b) return tostring(a.label) < tostring(b.label) end)
        return opts
    end
    -- ─── helpers locaux pour la DB globale (modules/logs/perf) ─────────────────
    local function getDB(k, def)
        return function()
            if SP.db and SP.db[k] ~= nil then return SP.db[k] end
            return def
        end
    end
    local function setDB(k)
        return function(v)
            if SP.db then SP.db[k] = v end
        end
    end
    local function refreshBossEliteFrames()
        if not (SP.Orb and SP.Orb.UpdateElite and SP.Plates) then return end
        for unit, data in pairs(SP.Plates) do
            pcall(SP.Orb.UpdateElite, SP.Orb, data, unit)
        end
    end
    local function setDBBoss(k)
        return function(v)
            if SP.db then SP.db[k] = v end
            refreshBossEliteFrames()
        end
    end
    local function refreshRaidMarkers()
        if not (SP.Orb and SP.Orb.UpdateRaidMark and SP.Plates) then return end
        for unit, data in pairs(SP.Plates) do
            pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, unit)
        end
    end
    local function setDBRaidMark(k)
        return function(v)
            if SP.db then SP.db[k] = v end
            refreshRaidMarkers()
            if SP.RaidMarkerMenu and SP.RaidMarkerMenu.RefreshAttachments then
                pcall(SP.RaidMarkerMenu.RefreshAttachments, SP.RaidMarkerMenu)
            end
            if self and self.RebuildPreview then
                self:RebuildPreview()
            end
        end
    end

    if self.category == "behavior" then
        self.optionsPage = self.optionsPage or "general"
        local optPage = self.optionsPage or "general"
        add(CreateOptionsNav(c, function() return self.optionsPage or "general" end, function(key)
            self.optionsPage = key
            self:RefreshAll()
        end), 34, (#OPTIONS_NAV * 30) + 12)

        if optPage == "general" then
        section("Instance", "instance", function()
            add(CreateCheck(c, "Activer les joueurs allies en instance", getGlobal("behavior_force_friendly_players_instance", true), setGlobal("behavior_force_friendly_players_instance")), 34, 28)
        end, 2)
        section("Boss", "bossEliteFrame", function()
            add(CreateCheck(c, "Cadre boss elite", getDB("boss_elite_frame_enabled", true), setDBBoss("boss_elite_frame_enabled")), 34, 28)
            add(CreateSlider(c, "Taille cadre boss", 0.80, 3.00, 0.05, getDB("boss_elite_frame_scale", 1.85), setDBBoss("boss_elite_frame_scale")), 34, 48)
            add(CreateSlider(c, "Alpha cadre boss", 0.00, 1.00, 0.05, getDB("boss_elite_frame_alpha", 1.0), setDBBoss("boss_elite_frame_alpha")), 34, 48)
        end)
        elseif optPage == "markers" then
        section("Marqueurs WoW", "raidMarkers", function()
            add(CreateCheck(c, "Activer marqueurs WoW", getDB("raidmark_global_enabled", true), setDBRaidMark("raidmark_global_enabled")), 34, 28)
            add(CreateCheck(c, "Afficher sur tous les types", getDB("raidmark_show_all_types", true), setDBRaidMark("raidmark_show_all_types")), 34, 28)
            add(CreateCheck(c, "Utiliser packs SpherePlates", getDB("raidmark_custom_enabled", true), setDBRaidMark("raidmark_custom_enabled")), 34, 28)
            if getDB("raidmark_custom_enabled", true)() ~= false then
                add(CreateRaidMarkerPackPicker(c, getDB("raidmark_pack", "sign_mark"), setDBRaidMark("raidmark_pack")), 34, 350)
            end
            add(CreateCycle(c, "Position", {
                {value="sphere", label="Sur la sphere"},
                {value="name", label="Dans le nom"},
            }, getDB("raidmark_position_mode", "sphere"), setDBRaidMark("raidmark_position_mode")), 34, 32)
            if (SP.db and SP.db.raidmark_position_mode or "sphere") == "name" then
                add(CreateCycle(c, "Placement nom", {
                    {value="above", label="Au-dessus"},
                    {value="left", label="A gauche"},
                    {value="right", label="A droite"},
                    {value="below", label="En dessous"},
                }, getDB("raidmark_name_position", "above"), setDBRaidMark("raidmark_name_position")), 34, 32)
                add(CreateSlider(c, "Espacement", 0, 24, 1, getDB("raidmark_spacing", 4), setDBRaidMark("raidmark_spacing")), 34, 48)
            end
            add(CreateSlider(c, "Taille", 8, 80, 1, getDB("raidmark_size", 24), setDBRaidMark("raidmark_size")), 34, 48)
            add(CreateSlider(c, "Scale", 0.25, 3.00, 0.05, getDB("raidmark_scale", 1.0), setDBRaidMark("raidmark_scale")), 34, 48)
            add(CreateSlider(c, "Alpha", 0.00, 1.00, 0.05, getDB("raidmark_alpha", 1.0), setDBRaidMark("raidmark_alpha")), 34, 48)
            add(CreateSlider(c, "Decalage X", -100, 100, 1, getDB("raidmark_offset_x", 0), setDBRaidMark("raidmark_offset_x")), 34, 48)
            add(CreateSlider(c, "Decalage Y", -100, 100, 1, getDB("raidmark_offset_y", 20), setDBRaidMark("raidmark_offset_y")), 34, 48)
        end, 2)
        section("Menu radial marqueurs", "raidMarkerMenu", function()
            add(CreateCheck(c, "Double clic droit PNJ", getDB("raidmark_menu_enabled", true), setDBRaidMark("raidmark_menu_enabled")), 34, 28)
            add(CreateCheck(c, "Autoriser sur joueurs", getDB("raidmark_menu_players", false), setDBRaidMark("raidmark_menu_players")), 34, 28)
            add(CreateSlider(c, "Delai double clic (ms)", 150, 700, 25, getDB("raidmark_menu_double_click_ms", 350), setDBRaidMark("raidmark_menu_double_click_ms")), 34, 48)
            add(CreateSlider(c, "Rayon", 32, 140, 2, getDB("raidmark_menu_radius", 58), setDBRaidMark("raidmark_menu_radius")), 34, 48)
            add(CreateSlider(c, "Taille icones", 20, 72, 1, getDB("raidmark_menu_icon_size", 38), setDBRaidMark("raidmark_menu_icon_size")), 34, 48)
            add(CreateSlider(c, "Alpha", 0.25, 1.00, 0.05, getDB("raidmark_menu_alpha", 1.0), setDBRaidMark("raidmark_menu_alpha")), 34, 48)
            add(CreateSlider(c, "Scale", 0.70, 1.50, 0.05, getDB("raidmark_menu_scale", 1.0), setDBRaidMark("raidmark_menu_scale")), 34, 48)
            add(CreateCheck(c, "Glow au survol", getDB("raidmark_menu_hover_glow", true), setDBRaidMark("raidmark_menu_hover_glow")), 34, 28)
            add(CreateCheck(c, "Couleur selection auto", getDB("raidmark_menu_select_color_auto", true), setDBRaidMark("raidmark_menu_select_color_auto")), 34, 28)
            add(CreateSlider(c, "Taille cercle selection", 0.80, 1.80, 0.02, getDB("raidmark_menu_select_glow_size", 1.12), setDBRaidMark("raidmark_menu_select_glow_size")), 34, 48)
            add(CreateSlider(c, "Alpha cercle selection", 0.00, 1.00, 0.02, getDB("raidmark_menu_select_glow_alpha", 0.62), setDBRaidMark("raidmark_menu_select_glow_alpha")), 34, 48)
            add(CreateCheck(c, "Rotation selection", getDB("raidmark_menu_select_rotation", true), setDBRaidMark("raidmark_menu_select_rotation")), 34, 28)
            add(CreateSlider(c, "Vitesse rotation", 20, 720, 10, getDB("raidmark_menu_select_rotation_speed", 180), setDBRaidMark("raidmark_menu_select_rotation_speed")), 34, 48)
            add(CreateCheck(c, "Particules selection", getDB("raidmark_menu_select_particles", true), setDBRaidMark("raidmark_menu_select_particles")), 34, 28)
            add(CreateSlider(c, "Intensite particules", 0.00, 1.00, 0.05, getDB("raidmark_menu_select_particle_alpha", 0.75), setDBRaidMark("raidmark_menu_select_particle_alpha")), 34, 48)
            add(CreateCheck(c, "Fermer apres marquage", getDB("raidmark_menu_close_after_action", true), setDBRaidMark("raidmark_menu_close_after_action")), 34, 28)
        end, 2)
        elseif optPage == "playerMenu" then
        section("Menu contextuel joueur", "playerContextMenu", function()
            add(CreateCheck(c, "Activer le clic droit sur sphere joueur", getDB("player_menu_enabled", true), setDB("player_menu_enabled")), 34, 28)
            add(CreateCycle(c, "Position", {
                {value="sphere", label="Autour de la sphere"},
                {value="cursor", label="Autour du curseur"},
            }, getDB("player_menu_position", "sphere"), setDB("player_menu_position")), 34, 32)
            add(CreateCheck(c, "Tooltips", getDB("player_menu_tooltips", false), setDB("player_menu_tooltips")), 34, 28)
            add(CreateCheck(c, "Glow au survol", getDB("player_menu_hover_glow", true), setDB("player_menu_hover_glow")), 34, 28)
            add(CreateCheck(c, "Fermer apres action", getDB("player_menu_close_after_action", true), setDB("player_menu_close_after_action")), 34, 28)
            add(CreateCheck(c, "Debug menu joueur", getDB("player_menu_debug", false), setDB("player_menu_debug")), 34, 28)
        end)
        section("Menu joueur - geometrie", "playerContextGeometry", function()
            add(CreateSlider(c, "Rayon", 34, 150, 2, getDB("player_menu_radius", 58), setDB("player_menu_radius")), 34, 48)
            add(CreateSlider(c, "Taille icones", 24, 64, 1, getDB("player_menu_icon_size", 38), setDB("player_menu_icon_size")), 34, 48)
            add(CreateSlider(c, "Zoom des icones", 0.70, 1.30, 0.05, getDB("player_menu_icon_zoom", 1.0), setDB("player_menu_icon_zoom")), 34, 48)
            add(CreateSlider(c, "Alpha", 0.25, 1.00, 0.05, getDB("player_menu_alpha", 1.0), setDB("player_menu_alpha")), 34, 48)
            add(CreateSlider(c, "Scale", 0.70, 1.50, 0.05, getDB("player_menu_scale", 1.0), setDB("player_menu_scale")), 34, 48)
            add(CreateSlider(c, "Animation ouverture", 0.04, 0.40, 0.02, getDB("player_menu_open_duration", 0.16), setDB("player_menu_open_duration")), 34, 48)
            add(CreateSlider(c, "Animation fermeture", 0.04, 0.30, 0.02, getDB("player_menu_close_duration", 0.10), setDB("player_menu_close_duration")), 34, 48)
        end, 2)
        section("Menu joueur - selection", "playerContextSelection", function()
            add(CreateCheck(c, "Couleur auto selon action", getDB("player_menu_select_color_auto", true), setDB("player_menu_select_color_auto")), 34, 28)
            add(CreateSlider(c, "Taille cercle selection", 0.90, 1.70, 0.05, getDB("player_menu_select_glow_size", 1.12), setDB("player_menu_select_glow_size")), 34, 48)
            add(CreateSlider(c, "Alpha cercle selection", 0.00, 1.00, 0.05, getDB("player_menu_select_glow_alpha", 0.62), setDB("player_menu_select_glow_alpha")), 34, 48)
            add(CreateCheck(c, "Rotation selection", getDB("player_menu_select_rotation", true), setDB("player_menu_select_rotation")), 34, 28)
            add(CreateSlider(c, "Vitesse rotation", 30, 540, 15, getDB("player_menu_select_rotation_speed", 180), setDB("player_menu_select_rotation_speed")), 34, 48)
            add(CreateCheck(c, "Particules selection", getDB("player_menu_select_particles", true), setDB("player_menu_select_particles")), 34, 28)
            add(CreateSlider(c, "Intensite particules", 0.00, 1.00, 0.05, getDB("player_menu_select_particle_alpha", 0.75), setDB("player_menu_select_particle_alpha")), 34, 48)
        end, 2)
        section("Menu joueur - libelles", "playerContextLabels", function()
            add(CreateCheck(c, "Fond sombre du libelle", getDB("player_menu_label_bg", true), setDB("player_menu_label_bg")), 34, 28)
            add(CreateSlider(c, "Alpha fond libelle", 0.00, 1.00, 0.05, getDB("player_menu_label_bg_alpha", 0.42), setDB("player_menu_label_bg_alpha")), 34, 48)
            add(CreateSlider(c, "Padding libelle", 0, 20, 1, getDB("player_menu_label_padding", 7), setDB("player_menu_label_padding")), 34, 48)
            add(CreateSlider(c, "Taille texte libelle", 10, 28, 1, getDB("player_menu_label_text_size", 15), setDB("player_menu_label_text_size")), 34, 48)
        end)
        section("Menu joueur - actions", "playerContextActions", function()
            add(CreateCheck(c, "Chuchoter", getDB("player_menu_action_whisper", true), setDB("player_menu_action_whisper")), 34, 28)
            add(CreateCheck(c, "Inspecter", getDB("player_menu_action_inspect", true), setDB("player_menu_action_inspect")), 34, 28)
            add(CreateCheck(c, "Inviter", getDB("player_menu_action_invite", true), setDB("player_menu_action_invite")), 34, 28)
            add(CreateCheck(c, "Echanger", getDB("player_menu_action_trade", true), setDB("player_menu_action_trade")), 34, 28)
            add(CreateCheck(c, "Duel", getDB("player_menu_action_duel", true), setDB("player_menu_action_duel")), 34, 28)
            add(CreateCheck(c, "Suivre", getDB("player_menu_action_follow", true), setDB("player_menu_action_follow")), 34, 28)
            add(CreateCheck(c, "Comparer hauts faits", getDB("player_menu_action_achievement", true), setDB("player_menu_action_achievement")), 34, 28)
            local hint = Text(c, "Les actions sensibles sont grisées en combat pour éviter le taint.", 10, MUTED)
            hint:SetWidth(COLUMN_WIDTH - 54)
            hint:SetJustifyH("LEFT")
            add(hint, 34, 34)
        end, 2)
        elseif optPage == "pack" then
        -- ── Section Lisibilité Pack ─────────────────────────────────────────────
        -- Solutions A+B+C+PackOrb : mode densité adaptatif pour donjon/raid.
        do
            -- Setter spécialisé : sauvegarde + CVars + reset pack state
            local function setDBPack(k)
                return function(v)
                    if SP.db then SP.db[k] = v end
                    -- Ajuster les CVars Blizzard si le master switch change
                    if k == "pack_mode_enabled" or k == "pack_cvar_adjust"
                       or k == "pack_cvar_overlap_h" or k == "pack_cvar_overlap_v" then
                        if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
                    end
                    -- Reset de l'état pack pour éviter les plaques bloquées
                    SP._packMode = false
                    SP._packPlateCount = 0
                    if SP.PackOrb then pcall(SP.PackOrb.HideAll, SP.PackOrb) end
                end
            end

            section("Lisibilite - Mode Pack", "packMode", function()
                local hint = Text(c,
                    "Active automatiquement quand N spheres sont visibles simultanement (donjon/raid).",
                    10, MUTED)
                hint:SetWidth(COLUMN_WIDTH - 54)
                hint:SetJustifyH("LEFT")
                add(hint, 34, 30)
                add(CreateCheck(c, "Activer le mode pack",
                    getDB("pack_mode_enabled", false),
                    setDBPack("pack_mode_enabled")), 34, 28)
                add(CreateSlider(c, "Seuil d'activation (spheres)", 2, 20, 1,
                    getDB("pack_threshold", 6),
                    setDBPack("pack_threshold")), 34, 48)
            end)
            section("Pack - Non-cibles", "packNonTarget", function()
                add(CreateSlider(c, "Alpha des non-cibles", 0.10, 1.00, 0.05,
                    getDB("pack_non_target_alpha", 0.50),
                    setDB("pack_non_target_alpha")), 34, 48)
                add(CreateSlider(c, "Scale des non-cibles", 0.30, 1.00, 0.05,
                    getDB("pack_non_target_scale", 0.68),
                    setDB("pack_non_target_scale")), 34, 48)
                add(CreateCheck(c, "Masquer les noms (non-cibles)",
                    getDB("pack_name_hide", true),
                    setDB("pack_name_hide")), 34, 28)
                add(CreateCheck(c, "Attenuuer les galaxies (non-cibles)",
                    getDB("pack_galaxy_attenuate", true),
                    setDB("pack_galaxy_attenuate")), 34, 28)
                add(CreateSlider(c, "Alpha galaxies rank-0", 0.00, 0.60, 0.02,
                    getDB("pack_galaxy_alpha", 0.22),
                    setDB("pack_galaxy_alpha")), 34, 48)
            end, 2)
            section("Pack - Cible", "packTarget", function()
                local hint2 = Text(c, "La cible est mise en valeur avec un boost de taille.", 10, MUTED)
                hint2:SetWidth(COLUMN_WIDTH - 54)
                hint2:SetJustifyH("LEFT")
                add(hint2, 34, 28)
                add(CreateSlider(c, "Scale cible (boost)", 0.90, 1.50, 0.05,
                    getDB("pack_target_scale_boost", 1.12),
                    setDB("pack_target_scale_boost")), 34, 48)
                add(CreateSlider(c, "Vitesse de transition", 2.0, 20.0, 0.5,
                    getDB("pack_lerp_speed", 8.0),
                    setDB("pack_lerp_speed")), 34, 48)
            end)
            section("Pack - Espacement Blizzard", "packCVars", function()
                local hint3 = Text(c,
                    "Recalibre l'espacement WoW pour la taille des spheres. Inactif si Plater/Kui est detecte.",
                    10, MUTED)
                hint3:SetWidth(COLUMN_WIDTH - 54)
                hint3:SetJustifyH("LEFT")
                add(hint3, 34, 30)
                add(CreateCheck(c, "Ajuster l'espacement Blizzard",
                    getDB("pack_cvar_adjust", true),
                    setDBPack("pack_cvar_adjust")), 34, 28)
                add(CreateSlider(c, "Overlap horizontal", 0.80, 2.50, 0.05,
                    getDB("pack_cvar_overlap_h", 1.25),
                    setDBPack("pack_cvar_overlap_h")), 34, 48)
                add(CreateSlider(c, "Overlap vertical", 0.80, 2.50, 0.05,
                    getDB("pack_cvar_overlap_v", 1.55),
                    setDBPack("pack_cvar_overlap_v")), 34, 48)
            end, 2)
            -- Getters/setters pour la couleur globale de la Pack Orb
            local function getPackOrbColor()
                local d = SP.db or {}
                return d.pack_orb_color_r or 0.55,
                       d.pack_orb_color_g or 0.18,
                       d.pack_orb_color_b or 0.85
            end
            local function setPackOrbColor(r, g, b)
                if SP.db then
                    SP.db.pack_orb_color_r = r
                    SP.db.pack_orb_color_g = g
                    SP.db.pack_orb_color_b = b
                end
            end

            section("Pack Orb (grande sphere decorative)", "packOrb", function()
                local hint4 = Text(c,
                    "Sphere semi-transparente affichee derriere le cluster. Click-through : les unites restent ciblables.",
                    10, MUTED)
                hint4:SetWidth(COLUMN_WIDTH - 54)
                hint4:SetJustifyH("LEFT")
                add(hint4, 34, 30)
                add(CreateCheck(c, "Activer la Pack Orb",
                    getDB("pack_orb_enabled", true),
                    setDB("pack_orb_enabled")), 34, 28)
                add(CreateSlider(c, "Alpha de la Pack Orb", 0.05, 0.80, 0.02,
                    getDB("pack_orb_alpha", 0.36),
                    setDB("pack_orb_alpha")), 34, 48)
                add(CreateColorButton(c, "Couleur de la Pack Orb",
                    getPackOrbColor, setPackOrbColor), 34, 30)
                add(CreateCheck(c, "Pulse",
                    getDB("pack_orb_pulse", true),
                    setDB("pack_orb_pulse")), 34, 28)
                add(CreateCheck(c, "Afficher le compteur (x8)",
                    getDB("pack_orb_show_count", true),
                    setDB("pack_orb_show_count")), 34, 28)
                add(CreateSlider(c, "Taille du compteur", 9, 22, 1,
                    getDB("pack_orb_count_size", 13),
                    setDB("pack_orb_count_size")), 34, 48)
                add(CreateSlider(c, "Padding de la sphere", 0.10, 0.80, 0.05,
                    getDB("pack_orb_padding", 0.38),
                    setDB("pack_orb_padding")), 34, 48)
            end, 2)
        end

        elseif optPage == "debug" then
        section("Diagnostic", "diagnostic", function()
            local line = Text(c, "SphereNameplates ne peut creer une sphere que si Blizzard fournit une nameplate.", 11, MUTED)
            line:SetWidth(COLUMN_WIDTH - 54)
            line:SetJustifyH("LEFT")
            add(line, 34, 36)
        end, 2)
        end

    elseif self.category == "modules" then
        -- ── Colonne 1 : ON/OFF modules ───────────────────────────────────────────
        section("Modules actifs", "modToggles", function()
            local hint = Text(c, "Desactiver un module pour isoler son impact sur les FPS.", 10, MUTED)
            hint:SetWidth(COLUMN_WIDTH - 54)
            hint:SetJustifyH("LEFT")
            add(hint, 34, 30)
            add(CreateCheck(c, "Animations orbe (AnimTick ~30/s)", getDB("modules_orbanim_enabled", true),  setDB("modules_orbanim_enabled")),  34, 28)
            add(CreateCheck(c, "Barre de cast (60/s)",             getDB("modules_castbar_enabled", true),  setDB("modules_castbar_enabled")),  34, 28)
            add(CreateCheck(c, "Auras / debuffs",                  getDB("modules_auras_enabled", true),    setDB("modules_auras_enabled")),    34, 28)
            add(CreateCheck(c, "Interpolation HP (60/s)",          getDB("modules_hplerp_enabled", true),   setDB("modules_hplerp_enabled")),   34, 28)
            add(CreateCheck(c, "Attenuation distance (4/s)",       getDB("modules_fade_enabled", true),     setDB("modules_fade_enabled")),     34, 28)
            add(CreateCheck(c, "Inspection iLvL",                  getDB("modules_inspectilvl_enabled", true), setDB("modules_inspectilvl_enabled")), 34, 28)
            add(CreateCheck(c, "Indicateurs de quete",             getDB("modules_quest_enabled", true),    setDB("modules_quest_enabled")),    34, 28)
        end)
        -- ── Colonne 2 : Performance Monitor ─────────────────────────────────────
        section("Performance Monitor", "perfPanel", function()
            add(CreateCheck(c, "Activer le suivi de performance", getDB("perf_enabled", false), setDB("perf_enabled")), 34, 28)
            add(CreateSlider(c, "Seuil alerte (ms)", 0.5, 20.0, 0.5, getDB("perf_seuil_ms", 5.0), setDB("perf_seuil_ms")), 34, 48)
            -- Bouton toggle panneau flottant
            local pbtn = CreateFrame("Button", nil, c)
            pbtn:SetSize(COLUMN_WIDTH - 68, 28)
            local pbtex = pbtn:CreateTexture(nil, "BACKGROUND")
            pbtex:SetAllPoints()
            pbtex:SetColorTexture(0.12, 0.08, 0.04, 0.90)
            local pbtxt = pbtn:CreateFontString(nil, "OVERLAY")
            pbtxt:SetFontObject(GameFontNormal)
            pbtxt:SetPoint("CENTER")
            pbtxt:SetText("|cFFFF8800Panneau Perf|r  |cFF888888(/snp perf)|r")
            pbtn:SetScript("OnClick", function()
                if SP.Profiler then SP.Profiler:TogglePanel() end
            end)
            add(pbtn, 34, 32)
            -- Bouton reset stats
            local rbtn = CreateFrame("Button", nil, c)
            rbtn:SetSize(COLUMN_WIDTH - 68, 28)
            local rbtex = rbtn:CreateTexture(nil, "BACKGROUND")
            rbtex:SetAllPoints()
            rbtex:SetColorTexture(0.08, 0.06, 0.04, 0.90)
            local rbtxt = rbtn:CreateFontString(nil, "OVERLAY")
            rbtxt:SetFontObject(GameFontNormalSmall)
            rbtxt:SetPoint("CENTER")
            rbtxt:SetText("|cFF888888Remettre les stats a zero|r")
            rbtn:SetScript("OnClick", function()
                if SP.Profiler then SP.Profiler:ResetStats() end
            end)
            add(rbtn, 34, 28)
        end, 2)
        -- ── Colonne 2 (suite) : Options logs ────────────────────────────────────
        section("Logs internes", "logsOpts", function()
            add(CreateCheck(c, "Activer les logs",   getDB("logs_enabled", false),      setDB("logs_enabled")),      34, 28)
            add(CreateSlider(c, "Capacite buffer", 50, 1000, 50, getDB("logs_max_entries", 200), setDB("logs_max_entries")), 34, 48)
            add(CreateCheck(c, "Niveau INFO",        getDB("logs_level_info", true),    setDB("logs_level_info")),   34, 28)
            add(CreateCheck(c, "Niveau WARN",        getDB("logs_level_warn", true),    setDB("logs_level_warn")),   34, 28)
            add(CreateCheck(c, "Niveau PERF",        getDB("logs_level_perf", true),    setDB("logs_level_perf")),   34, 28)
            add(CreateCheck(c, "Niveau DEBUG",       getDB("logs_level_debug", false),  setDB("logs_level_debug")),  34, 28)
        end, 2)

    elseif self.category == "logs" then
        -- ── Visionneuse de logs ─────────────────────────────────────────────────
        -- Bouton vider + compteur
        local lcount = SP.Log and SP.Log:Count() or 0
        local lcap   = (SP.db and SP.db.logs_max_entries) or 200
        local lenabled = SP.Log and SP.Log:IsEnabled()
        local hdr = Text(c, string.format(
            "|cFF888888%d / %d entrees  |  logs : %s|r",
            lcount, lcap,
            lenabled and "|cFF44FF44actifs|r" or "|cFFFF4444inactifs|r"),
            10, MUTED)
        hdr:SetWidth(COLUMN_WIDTH * 2 + COLUMN_GAP - 20)
        hdr:SetJustifyH("LEFT")
        add(hdr, 8, 16)

        -- Boutons Clear + Refresh
        local clrBtn = CreateFrame("Button", nil, c)
        clrBtn:SetSize(130, 24)
        local clrTex = clrBtn:CreateTexture(nil, "BACKGROUND")
        clrTex:SetAllPoints()
        clrTex:SetColorTexture(0.22, 0.04, 0.04, 0.90)
        local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY")
        clrTxt:SetFontObject(GameFontNormalSmall)
        clrTxt:SetPoint("CENTER")
        clrTxt:SetText("|cFFFF4444Vider les logs|r")
        clrBtn:SetScript("OnClick", function()
            if SP.Log then SP.Log:Clear() end
            self:BuildSettings()
        end)
        self:AddChild(c, clrBtn)
        clrBtn:SetPoint("TOPLEFT", c, "TOPLEFT", 8, colY[1])
        colY[1] = colY[1] - 28

        local entries = SP.Log and SP.Log:GetEntries({max=120}) or {}
        if #entries == 0 then
            local empty = CreateFrame("Frame", nil, c)
            empty:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP - 20, 20)
            local emptyTxt = empty:CreateFontString(nil, "OVERLAY")
            emptyTxt:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            emptyTxt:SetAllPoints(empty)
            emptyTxt:SetJustifyH("LEFT")
            emptyTxt:SetJustifyV("TOP")
            if not lenabled then
                emptyTxt:SetText("|cFFFFAA00Logs desactives — activer dans l'onglet Modules.|r")
            else
                emptyTxt:SetText("|cFF888888Aucun log pour le moment.|r")
            end
            add(empty, 8, 24)
        else
            -- Afficher du plus recent au plus ancien (GetEntries retourne déjà cet ordre)
            local LCOLS = (SP.Log and SP.Log.LEVEL_COLORS) or {
                INFO="|cFF88CCFF", WARN="|cFFFFCC44", ERROR="|cFFFF4444",
                PERF="|cFFFF8800", DEBUG="|cFFAAAAAA",
            }
            local lines = {}
            for _, e in ipairs(entries) do
                local col = LCOLS[e.level] or "|cFFFFFFFF"
                lines[#lines + 1] = string.format(
                    "|cFF888888%s|r %s[%-5s]|r |cFFFFFF88%-12s|r %s",
                    e.date  or "??:??:??",
                    col, e.level or "?",
                    e.module or "?",
                    e.msg   or "")
            end
            local logFrame = CreateFrame("Frame", nil, c)
            local lineH = 13
            logFrame:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP - 20, #lines * lineH + 8)
            local logText = logFrame:CreateFontString(nil, "OVERLAY")
            logText:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            logText:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 0, 0)
            logText:SetWidth(COLUMN_WIDTH * 2 + COLUMN_GAP - 20)
            logText:SetJustifyH("LEFT")
            logText:SetJustifyV("TOP")
            logText:SetSpacing(1)
            logText:SetText(table.concat(lines, "\n"))
            add(logFrame, 8, logFrame:GetHeight())
        end

    elseif self.page == "sphere" then
        section("Orbe", "orb", function()
            add(CreateCycle(c, "Affichage de la sphere", {
                {value="never",  label="Ne pas afficher"},
                {value="combat", label="Uniquement en combat"},
                {value="always", label="Toujours afficher"},
                {value="target", label="Si cible ou combat"},
            }, getSphereDisplayMode(), setSphereDisplayMode), 34, 32)
            add(CreateSlider(c, "Taille", 12, 140, 2, get("size", 64), set("size")), 34, 48)
            add(CreateSlider(c, "Decalage X", -200, 200, 1, get("offsetX", 0), set("offsetX")), 34, 48)
            add(CreateSlider(c, "Decalage Y", -200, 200, 1, get("offsetY", 0), set("offsetY")), 34, 48)
            add(CreateSlider(c, "Fluidite HP", 1, 30, 0.5, get("hp_lerp_speed", 8), set("hp_lerp_speed")), 34, 48)
        end, 1)
        section("Couleur de remplissage", "fill", function()
            local function currentFillMode()
                local mode = self:GetCfgValue("fill_color_mode", "fixed")
                if mode == "custom" then mode = "fixed" end
                if self:GetCfgValue("classColorSphere", false) and mode == "fixed" then mode = "class" end
                if mode ~= "class" and mode ~= "progressive" then mode = "fixed" end
                return mode
            end
            local function setFillMode(v)
                self:SetCfg("fill_color_mode", v)
                self:SetCfg("classColorSphere", v == "class")
            end
            add(CreateCycle(c, "Mode couleur", {
                {value="fixed", label="Fixe"},
                {value="progressive", label="Progressive"},
                {value="class", label="Classe"},
            }, currentFillMode, setFillMode), 34, 32)
            local mode = currentFillMode()
            if mode == "progressive" then
                add(CreateColorButton(c, "100 - 75%", getColor("fill_prog_highR", "fill_prog_highG", "fill_prog_highB", 0.20, 1.0, 0.20), setColor("fill_prog_highR", "fill_prog_highG", "fill_prog_highB")), 34, 30)
                add(CreateColorButton(c, "74 - 50%", getColor("fill_prog_midR", "fill_prog_midG", "fill_prog_midB", 1.0, 0.82, 0.0), setColor("fill_prog_midR", "fill_prog_midG", "fill_prog_midB")), 34, 30)
                add(CreateColorButton(c, "49 - 25%", getColor("fill_prog_lowR", "fill_prog_lowG", "fill_prog_lowB", 1.0, 0.50, 0.0), setColor("fill_prog_lowR", "fill_prog_lowG", "fill_prog_lowB")), 34, 30)
                add(CreateColorButton(c, "24 - 0%", getColor("fill_prog_critR", "fill_prog_critG", "fill_prog_critB", 1.0, 0.15, 0.15), setColor("fill_prog_critR", "fill_prog_critG", "fill_prog_critB")), 34, 30)
            elseif mode == "fixed" then
                add(CreateColorButton(c, "Couleur fixe", getColor("fillR", "fillG", "fillB", 1, 0.1, 0.1), setColor("fillR", "fillG", "fillB")), 34, 30)
            end
            add(CreateSlider(c, "Saturation", 0, 2, 0.05, get("fill_saturation", 1), set("fill_saturation")), 34, 48)
            add(CreateSlider(c, "Transparence", 0.1, 1, 0.01, get("fill_alpha", 0.88), set("fill_alpha")), 34, 48)
        end, 2)
        section("Arriere-plan", "background", function()
            add(CreateColorButton(c, "Couleur de fond", getColor("bgR", "bgG", "bgB", 0, 0, 0), setColor("bgR", "bgG", "bgB")), 34, 30)
            add(CreateSlider(c, "Opacite du fond", 0, 1, 0.05, get("bgAlpha", 0.75), set("bgAlpha")), 34, 48)
        end, 2)
        section("Lisibilite (Codex fix)", "readability", function()
            add(CreateSlider(c, "Ombre interne", 0, 0.9, 0.02, get("orb_shadow_alpha", 0.35), set("orb_shadow_alpha")), 34, 48)
            add(CreateCheck(c, "Ombre directionnelle (asset requis)", get("orb_shadow2_enabled", false), set("orb_shadow2_enabled")), 34, 28)
            add(CreateSlider(c, "Intensite ombre directionnelle", 0, 0.9, 0.02, get("orb_shadow2_alpha", 0), set("orb_shadow2_alpha")), 34, 48)
        end, 2)
        section("Attenuation distance", "fade", function()
            add(CreateCheck(c, "Attenuer selon la distance", get("fade_enabled", false), set("fade_enabled")), 34, 28)
            add(CreateSlider(c, "Debut attenuation (yd)", 5, 60, 1, get("fade_start", 25), set("fade_start")), 34, 48)
            add(CreateSlider(c, "Fin attenuation (yd)", 10, 100, 1, get("fade_end", 40), set("fade_end")), 34, 48)
            add(CreateSlider(c, "Alpha minimum", 0.1, 1.0, 0.05, get("fade_min_alpha", 0.55), set("fade_min_alpha")), 34, 48)
            add(CreateCheck(c, "Ignorer alpha nameplate Blizzard (V3)", get("ignore_parent_alpha", true), set("ignore_parent_alpha")), 34, 28)
        end, 2)
        section("Bordure", "border", function()
            add(CreateCheck(c, "Afficher la bordure", get("borderEnabled", true), set("borderEnabled")), 34, 28)
            if get("borderEnabled", true)() == false then return end
            add(CreateCycle(c, "Style decoratif", {
                {value="solide",       label="Solide"},
                {value="classique",    label="Classique"},
                {value="detail",       label="Detail"},
                {value="shadowcircle", label="Shadow Circle"},
                {value="wow_horde",    label="Horde"},
                {value="wow_alliance", label="Alliance"},
                {value="wow_evil",     label="Evil"},
                {value="wow_beast",    label="Beast"},
                {value="wow_stone",    label="Simple Stone"},
                {value="wow_gold",     label="Simple Gold"},
                {value="ns_horde",     label="Horde Fer"},
                {value="ns_alliance",  label="Alliance Or"},
                {value="ns_void",      label="Vide"},
                {value="ns_beast",     label="Bete"},
                {value="ns_obsidian",  label="Obsidienne"},
                {value="ns_gold_ring", label="Anneau Or"},
            }, get("borderStyle", "solide"), setBorderStyle), 34, 32)
            local bStyle = get("borderStyle", "solide")()
            local bInfo = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(bStyle)
            local hasTexture = bInfo and bInfo.path
            local tintable = not bInfo or bInfo.tint ~= false
            if tintable then
                add(CreateCycle(c, "Couleur bordure", {
                    {value="custom", label="Personnalisee"},
                    {value="classe", label="Classe"},
                }, get("borderColorMode", "custom"), setBorderMode), 34, 32)
                if get("borderColorMode", "custom")() == "custom" then
                    add(CreateColorButton(c, "Couleur personnalisee", getColor("borderR", "borderG", "borderB", 0.9, 0.72, 0.1), setColor("borderR", "borderG", "borderB")), 34, 30)
                end
            end
            if hasTexture then
                add(CreateSlider(c, "Taille du style decoratif", 0.8, 3.0, 0.05, get("borderOverlayScale", 1.5), set("borderOverlayScale")), 34, 48)
                add(CreateCheck(c, "Pulse overlay", get("border_glow_pulse", false), set("border_glow_pulse")), 34, 28)
            else
                add(CreateSlider(c, "Epaisseur bordure", 1, 14, 1, get("borderWidth", 6), set("borderWidth")), 34, 48)
            end
        end, 1)
        section("Ombre et menace", "shadeThreat", function()
            add(CreateCheck(c, "Afficher l'ombre circulaire", get("shadeCircleEnabled", false), set("shadeCircleEnabled")), 34, 28)
            add(CreateSlider(c, "Opacite ombre circulaire", 0, 1, 0.05, get("shadeCircleAlpha", 0.6), set("shadeCircleAlpha")), 34, 48)
            add(CreateCheck(c, "Bordure rouge selon menace", get("border_threat_color", false), set("border_threat_color")), 34, 28)
            add(CreateCheck(c, "Dragon elite", get("showEliteDragon", false), set("showEliteDragon")), 34, 28)
        end, 2)
    elseif self.page == "auras" then
        section("General", "general", function()
            add(CreateCheck(c, "Activer les auras", get("auras_enabled", true), set("auras_enabled")), 34, 28)
            add(CreateCycle(c, "Mode", {
                {value="icons", label="Arc"},
                {value="ring", label="Anneau icones"},
                {value="segments", label="Segments circulaires"},
            }, get("auras_mode", "icons"), set("auras_mode")), 34, 32)
            add(CreateCheck(c, "Priorite debuffs", get("auras_debuff_priority", true), set("auras_debuff_priority")), 34, 28)
            add(CreateCheck(c, "Controles / CC", get("auras_control", true), set("auras_control")), 34, 28)
        end, 1)
        section("Debuffs", "debuffs", function()
            add(CreateCheck(c, "Afficher debuffs", get("auras_debuff", true), set("auras_debuff")), 34, 28)
            add(CreateCheck(c, "Mes sorts uniquement", get("auras_debuff_mine_only", false), set("auras_debuff_mine_only")), 34, 28)
            add(CreateSlider(c, "Max debuffs", 1, 12, 1, get("auras_maxDebuff", 5), set("auras_maxDebuff")), 34, 48)
            add(CreateSlider(c, "Taille debuffs", 10, 56, 1, get("auras_debuff_size", 20), set("auras_debuff_size")), 34, 48)
            add(CreateSlider(c, "Ecart orbe", -20, 90, 1, get("auras_debuff_offsetY", 4), set("auras_debuff_offsetY")), 34, 48)
            add(CreateCycle(c, "Position", {
                {value="below", label="Bas"},
                {value="above", label="Haut"},
                {value="left", label="Gauche"},
                {value="right", label="Droite"},
                {value="full", label="Complet 360 deg"},
            }, get("auras_debuff_side", "below"), set("auras_debuff_side")), 34, 32)
        end, 1)
        section("Buffs", "buffs", function()
            add(CreateCheck(c, "Afficher buffs", get("auras_buff", false), set("auras_buff")), 34, 28)
            add(CreateCheck(c, "Mes sorts uniquement", get("auras_buff_mine_only", false), set("auras_buff_mine_only")), 34, 28)
            add(CreateSlider(c, "Max buffs", 0, 12, 1, get("auras_maxBuff", 3), set("auras_maxBuff")), 34, 48)
            add(CreateSlider(c, "Taille buffs", 10, 56, 1, get("auras_buff_size", 20), set("auras_buff_size")), 34, 48)
            add(CreateSlider(c, "Ecart orbe", -20, 90, 1, get("auras_buff_offsetY", 4), set("auras_buff_offsetY")), 34, 48)
            add(CreateCycle(c, "Position", {
                {value="above", label="Haut"},
                {value="below", label="Bas"},
                {value="left", label="Gauche"},
                {value="right", label="Droite"},
            }, get("auras_buff_side", "above"), set("auras_buff_side")), 34, 32)
        end, 2)
        section("Timer debuffs", "debuffTimers", function()
            add(CreateCheck(c, "Anneau timer", get("auras_debuff_timer", true), set("auras_debuff_timer")), 34, 28)
            add(CreateSlider(c, "Opacite anneau", 0.2, 1.0, 0.02, get("auras_debuff_timer_alpha", 0.92), set("auras_debuff_timer_alpha")), 34, 48)
            add(CreateCheck(c, "Bord lumineux", get("auras_debuff_timer_edge", true), set("auras_debuff_timer_edge")), 34, 28)
            add(CreateColorButton(c, "Couleur anneau", getColor("auras_debuff_timerR", "auras_debuff_timerG", "auras_debuff_timerB", 1, 0.22, 0.08), setColor("auras_debuff_timerR", "auras_debuff_timerG", "auras_debuff_timerB")), 34, 30)
            add(CreateCheck(c, "Texte timer", get("auras_debuff_timer_text", true), set("auras_debuff_timer_text")), 34, 28)
            add(CreateSlider(c, "Taille texte", 6, 18, 1, get("auras_debuff_text_size", 8), set("auras_debuff_text_size")), 34, 48)
            add(CreateColorButton(c, "Couleur texte", getColor("auras_debuff_textR", "auras_debuff_textG", "auras_debuff_textB", 1, 0.92, 0.75), setColor("auras_debuff_textR", "auras_debuff_textG", "auras_debuff_textB")), 34, 30)
        end, 1)
        section("Timer buffs", "buffTimers", function()
            add(CreateCheck(c, "Anneau timer", get("auras_buff_timer", true), set("auras_buff_timer")), 34, 28)
            add(CreateSlider(c, "Opacite anneau", 0.2, 1.0, 0.02, get("auras_buff_timer_alpha", 0.78), set("auras_buff_timer_alpha")), 34, 48)
            add(CreateCheck(c, "Bord lumineux", get("auras_buff_timer_edge", true), set("auras_buff_timer_edge")), 34, 28)
            add(CreateColorButton(c, "Couleur anneau", getColor("auras_buff_timerR", "auras_buff_timerG", "auras_buff_timerB", 0.12, 0.72, 1), setColor("auras_buff_timerR", "auras_buff_timerG", "auras_buff_timerB")), 34, 30)
            add(CreateCheck(c, "Texte timer", get("auras_buff_timer_text", true), set("auras_buff_timer_text")), 34, 28)
            add(CreateSlider(c, "Taille texte", 6, 18, 1, get("auras_buff_text_size", 8), set("auras_buff_text_size")), 34, 48)
            add(CreateColorButton(c, "Couleur texte", getColor("auras_buff_textR", "auras_buff_textG", "auras_buff_textB", 0.78, 0.92, 1), setColor("auras_buff_textR", "auras_buff_textG", "auras_buff_textB")), 34, 30)
        end, 2)
        section("Segments circulaires", "segments", function()
            add(CreateSlider(c, "Opacite segments", 0.2, 1.0, 0.02, get("auras_segment_alpha", 0.92), set("auras_segment_alpha")), 34, 48)
            add(CreateCheck(c, "Glow segments importants", get("auras_segment_glow", true), set("auras_segment_glow")), 34, 28)
        end, 1)
    elseif self.page == "castbar" then
        -- Helpers locaux pour couleurs array {r,g,b[,a]}
        local function getCArr(key, dr, dg, db)
            return function()
                local v = self:GetCfgValue(key, nil)
                if type(v) == "table" then
                    return v[1] or dr or 1, v[2] or dg or 1, v[3] or db or 1
                end
                return dr or 1, dg or 1, db or 1
            end
        end
        local function setCArr(key)
            return function(r, g, b)
                local cur = self:GetCfgValue(key, nil)
                local a = (type(cur) == "table" and cur[4]) or nil
                if a then
                    self:SetCfg(key, { r, g, b, a })
                else
                    self:SetCfg(key, { r, g, b })
                end
            end
        end

        -- Setter CCB avec mise à jour live immédiate (alpha, offsets)
        local function setCCBLive(k)
            return function(v)
                self:SetCfg(k, v)
                local utype = self:GetUType()
                if SP.CCB and SP.CCB.ApplySettings then
                    local cfg = SP:GetCfg(utype) or {}
                    if self.previewData and self.previewData._cb_ccb then
                        pcall(SP.CCB.ApplySettings, SP.CCB, self.previewData, cfg)
                    end
                    if SP.Plates then
                        for _, data in pairs(SP.Plates) do
                            if data._cb_ccb and data.unitType == utype then
                                pcall(SP.CCB.ApplySettings, SP.CCB, data, cfg)
                            end
                        end
                    end
                end
            end
        end
        -- Setter CCB qui nécessite un rebuild complet (border, size_ratio)
        local function setCCBRebuild(k)
            return function(v)
                self:SetCfg(k, v)
                if SP.HardRefreshAll then SP:HardRefreshAll() end
            end
        end

        local modeValue = self:GetCfgValue("castbar_mode", "classic")
        local mode = SP.NormalizeCastbarMode and SP:NormalizeCastbarMode(modeValue) or modeValue
        local isClassic = mode == "classic"
        local isCircular = mode == "circular"
        local isSegments = mode == "segments"
        local isDotted = mode == "dotted"
        local isCCB = mode == "ccb"
        local isCollapse = mode == "collapse"
        local isCollapseGlow = mode == "collapse_glow"
        local isSprite = mode == "sprite"
        local usesBarTexture = isClassic or isCircular or isSegments
        local usesTrack = isDotted
        local usesArcGeometry = isCircular or isSegments or isDotted or isSprite
        local usesOffsets = usesArcGeometry or isCollapse or isCollapseGlow or isSprite or isCCB
        local textMode = self:GetCfgValue("castbar_text_mode", "separate")
        local isSeparateText = textMode == "separate"

        section("General", "general", function()
            add(CreateCheck(c, "Activer la CastBar", get("castbar_enabled", true), set("castbar_enabled")), 34, 28)
            add(CreateCycle(c, "Style", {
                {value="classic", label="Classique"},
                {value="circular", label="Circulaire"},
                {value="segments", label="Segments alignes"},
                {value="dotted", label="Points circulaires"},
                {value="collapse", label="Collapse Ring"},
                {value="collapse_glow", label="Collapse Glow Ring"},
                {value="sprite", label="Anneau Mage (sprite)"},
                {value="ccb", label="CCB (Circular Castbar)"},
            }, get("castbar_mode", "classic"), set("castbar_mode")), 34, 32)
            if usesBarTexture then
                add(CreateCycle(c, "Texture barre", SP.CASTBAR_TEXTURES or {
                    {value="white", label="Blizzard - Plat"},
                }, get("castbar_texture", "white"), set("castbar_texture")), 34, 32)
            end
            if isSegments then
                add(CreateSlider(c, "Nombre segments", 3, 24, 1, get("castbar_v8_count", 12), set("castbar_v8_count")), 34, 48)
            elseif isDotted then
                add(CreateSlider(c, "Nombre de points", 6, 36, 1, get("castbar_dotted_count", 18), set("castbar_dotted_count")), 34, 48)
                add(CreateSlider(c, "Taille des points", 2, 12, 1, get("castbar_dotted_size", 5), set("castbar_dotted_size")), 34, 48)
                add(CreateSlider(c, "Rayon points", -30, 60, 1, get("castbar_dotted_radius", 0), set("castbar_dotted_radius")), 34, 48)
            end
            add(CreateCheck(c, "Nom du sort", get("castbar_showName", true), set("castbar_showName")), 34, 28)
            add(CreateCheck(c, "Temps restant", get("castbar_showTime", true), set("castbar_showTime")), 34, 28)
            -- ── Boutons de prévisualisation castbar ─────────────────────────
            -- Le ticker SP_PSUI_CastPreviewTicker anime automatiquement
            -- l'arc de la sphère preview en auto-loop cast↔canal.
            -- Ces boutons permettent de forcer manuellement un type précis.
            add(CreatePanelButton(c, "▶  Cast 3s", function()
                if self.previewData and SP.CastBar and SP.CastBar.TestCast then
                    pcall(SP.CastBar.TestCast, SP.CastBar, self.previewData, 3.0)
                    self._castPreviewLastMode = "cast"
                    self._castPreviewRestartAt = nil
                end
            end), 34, 30)
            add(CreatePanelButton(c, "▶  Canal 3s", function()
                if self.previewData and SP.CastBar and SP.CastBar.TestChannel then
                    pcall(SP.CastBar.TestChannel, SP.CastBar, self.previewData, 3.0)
                    self._castPreviewLastMode = "channel"
                    self._castPreviewRestartAt = nil
                end
            end), 34, 30)
            add(CreatePanelButton(c, "✕  Interrompre", function()
                -- Si un cast est en cours : interruption visuelle immédiate.
                -- Si aucun cast : démarre un cast court puis l'interrompt.
                local data = self.previewData
                if data and SP.CastBar then
                    local cb = data.castbar
                    if cb and cb.active then
                        pcall(SP.CastBar.StopCast, SP.CastBar, data, true)
                        self._castPreviewRestartAt = GetTime() + 1.2
                    else
                        -- Démarre un cast de 4s et l'interrompt 1.2s plus tard
                        pcall(SP.CastBar.TestCast, SP.CastBar, data, 4.0)
                        self._castPreviewLastMode = "cast"
                        local d = data
                        local restartRef = self
                        C_Timer.After(1.2, function()
                            if restartRef.previewData == d and d.castbar and d.castbar.active then
                                pcall(SP.CastBar.StopCast, SP.CastBar, d, true)
                                restartRef._castPreviewRestartAt = GetTime() + 1.2
                            end
                        end)
                    end
                end
            end), 34, 30)
        end, 1)

        section("Texte CastBar", "text", function()
            add(CreateCycle(c, "Mode texte", {
                {value="separate", label="Texte CastBar separe"},
                {value="replace_name", label="Remplacer le nom"},
            }, get("castbar_text_mode", "separate"), set("castbar_text_mode")), 34, 32)
            if isSeparateText then
                add(CreateCycle(c, "Position", {
                    {value="bottom", label="Bas"},
                    {value="top",    label="Haut"},
                    {value="center", label="Centre"},
                    {value="left",   label="Gauche"},
                    {value="right",  label="Droite"},
                }, get("castbar_text_position", "bottom"), set("castbar_text_position")), 34, 32)
                add(CreateSlider(c, "Decalage X", -60, 60, 1, get("castbar_text_offset_x", 0), set("castbar_text_offset_x")), 34, 48)
                add(CreateSlider(c, "Decalage Y", -40, 40, 1, get("castbar_text_offset_y", 0), set("castbar_text_offset_y")), 34, 48)
                add(CreateCycle(c, "Police", getFontOptions(), get("castbar_text_font", "Friz Quadrata TT"), set("castbar_text_font")), 34, 32)
                add(CreateColorButton(c, "Couleur texte",
                    getColor("castbar_text_colorR", "castbar_text_colorG", "castbar_text_colorB", 1.00, 0.88, 0.45),
                    setColor("castbar_text_colorR", "castbar_text_colorG", "castbar_text_colorB")), 34, 30)
                add(CreateSlider(c, "Taille police", 6, 24, 1, get("castbar_nameFontSize", 10), set("castbar_nameFontSize")), 34, 48)
            end
        end, 1)

        section("Interruption", "interrupt", function()
            add(CreateCheck(c, "Detection CC / fallback", get("castbar_interrupt_fallback", true), set("castbar_interrupt_fallback")), 34, 28)
            add(CreateSlider(c, "Marge fin normale", 0.02, 0.35, 0.01, get("castbar_interrupt_fallback_grace", 0.12), set("castbar_interrupt_fallback_grace")), 34, 48)

            if isCCB then
                -- Choix du visuel d'interruption CCB
                add(CreateCycle(c, "Visuel interruption", {
                    {value="classic_glow", label="Classic Glow"},
                    {value="classic_ccb",  label="Classic CCB"},
                }, get("castbar_interrupt_visual", "classic_glow"), setCCBLive("castbar_interrupt_visual")), 34, 32)

                local intVisual = self:GetCfgValue("castbar_interrupt_visual", "classic_glow")
                if intVisual == "classic_ccb" then
                    add(CreateSlider(c, "Taille overlay (x CCB)", 0.5, 3.0, 0.05, get("ccb_interrupt_size_ratio", 1.0), setCCBLive("ccb_interrupt_size_ratio")), 34, 48)
                    add(CreateColorButton(c, "Couleur overlay", getCArr("ccb_interrupt_color", 1.0, 0.25, 0.25), setCArr("ccb_interrupt_color")), 34, 30)
                else  -- classic_glow
                    add(CreateCheck(c, "Marque centrale interruption", get("castbar_interrupt_mark_enabled", true), set("castbar_interrupt_mark_enabled")), 34, 28)
                    if self:GetCfgValue("castbar_interrupt_mark_enabled", true) then
                        add(CreateCycle(c, "Forme marque", SP.CASTBAR_INTERRUPT_MARK_SHAPES or {
                            {value="none", label="Aucun"},
                            {value="x", label="X"},
                        }, get("castbar_interrupt_mark_shape", "x"), set("castbar_interrupt_mark_shape")), 34, 32)
                        add(CreateSlider(c, "Taille marque", 6, 42, 1, get("castbar_interrupt_mark_size", 18), set("castbar_interrupt_mark_size")), 34, 48)
                        add(CreateSlider(c, "Alpha marque", 0.10, 1.0, 0.02, get("castbar_interrupt_mark_alpha", 0.92), set("castbar_interrupt_mark_alpha")), 34, 48)
                        add(CreateSlider(c, "Duree marque", 0.10, 1.20, 0.02, get("castbar_interrupt_mark_duration", 0.42), set("castbar_interrupt_mark_duration")), 34, 48)
                        add(CreateCheck(c, "Couleur marque personnalisee", get("castbar_interrupt_mark_custom_color", false), set("castbar_interrupt_mark_custom_color")), 34, 28)
                        if self:GetCfgValue("castbar_interrupt_mark_custom_color", false) then
                            add(CreateColorButton(c, "Couleur marque", getColor("castbar_interrupt_markR", "castbar_interrupt_markG", "castbar_interrupt_markB", 0.95, 0.20, 0.20), setColor("castbar_interrupt_markR", "castbar_interrupt_markG", "castbar_interrupt_markB")), 34, 30)
                        end
                    end
                end
            else
                add(CreateCheck(c, "Marque centrale interruption", get("castbar_interrupt_mark_enabled", true), set("castbar_interrupt_mark_enabled")), 34, 28)
                if self:GetCfgValue("castbar_interrupt_mark_enabled", true) then
                    add(CreateCycle(c, "Forme marque", SP.CASTBAR_INTERRUPT_MARK_SHAPES or {
                        {value="none", label="Aucun"},
                        {value="x", label="X"},
                    }, get("castbar_interrupt_mark_shape", "x"), set("castbar_interrupt_mark_shape")), 34, 32)
                    add(CreateSlider(c, "Taille marque", 6, 42, 1, get("castbar_interrupt_mark_size", 18), set("castbar_interrupt_mark_size")), 34, 48)
                    add(CreateSlider(c, "Alpha marque", 0.10, 1.0, 0.02, get("castbar_interrupt_mark_alpha", 0.92), set("castbar_interrupt_mark_alpha")), 34, 48)
                    add(CreateSlider(c, "Duree marque", 0.10, 1.20, 0.02, get("castbar_interrupt_mark_duration", 0.42), set("castbar_interrupt_mark_duration")), 34, 48)
                    add(CreateCheck(c, "Couleur marque personnalisee", get("castbar_interrupt_mark_custom_color", false), set("castbar_interrupt_mark_custom_color")), 34, 28)
                    if self:GetCfgValue("castbar_interrupt_mark_custom_color", false) then
                        add(CreateColorButton(c, "Couleur marque", getColor("castbar_interrupt_markR", "castbar_interrupt_markG", "castbar_interrupt_markB", 0.95, 0.20, 0.20), setColor("castbar_interrupt_markR", "castbar_interrupt_markG", "castbar_interrupt_markB")), 34, 30)
                    end
                end
            end
        end, 1)

        -- ── Sections CCB (col 2, en tête) ────────────────────────────────────
        if isCCB then
            local ccbStyles = SP.CCB_STYLES or {
                {value="Normal",    label="Normal"},
                {value="Channel",   label="Channel"},
                {value="Segmented", label="Segmented"},
                {value="Pulse",     label="Pulse"},
                {value="Runes",     label="Runes"},
                {value="Critical",  label="Critical"},
                {value="Reverse",   label="Reverse"},
                {value="Collapse",  label="Collapse"},
                {value="Expanding", label="Expanding"},
                {value="Charge",    label="Charge"},
                {value="Particles", label="Particles"},
            }

            section("CCB — Styles & Couleurs", "ccb_styles", function()
                add(CreateCycle(c, "Cast interruptible", ccbStyles,
                    get("ccb_cast_style", "Normal"), set("ccb_cast_style")), 34, 32)
                add(CreateColorButton(c, "Teinte cast",
                    getCArr("ccb_color_cast", 1, 1, 1), setCArr("ccb_color_cast")), 34, 30)
                add(CreateCycle(c, "Non-interruptible", ccbStyles,
                    get("ccb_notint_style", "Pulse"), set("ccb_notint_style")), 34, 32)
                add(CreateColorButton(c, "Teinte non-int",
                    getCArr("ccb_color_notint", 1, 1, 1), setCArr("ccb_color_notint")), 34, 30)
                add(CreateCycle(c, "Boss / immune", ccbStyles,
                    get("ccb_boss_style", "Critical"), set("ccb_boss_style")), 34, 32)
                add(CreateColorButton(c, "Teinte boss",
                    getCArr("ccb_color_boss", 1, 1, 1), setCArr("ccb_color_boss")), 34, 30)
                add(CreateCycle(c, "Canalisation", ccbStyles,
                    get("ccb_channel_style", "Channel"), set("ccb_channel_style")), 34, 32)
                add(CreateColorButton(c, "Teinte canal",
                    getCArr("ccb_color_channel", 1, 1, 1), setCArr("ccb_color_channel")), 34, 30)
            end, 2)

            section("CCB — Apparence", "ccb_appearance", function()
                add(CreateCycle(c, "Bordure", {
                    {value="Beveled",  label="Beveled"},
                    {value="Sculpted", label="Sculpted"},
                    {value="Elite",    label="Elite"},
                    {value="Runic",    label="Runic"},
                    {value="Notched",  label="Notched"},
                    {value="Thin",     label="Thin"},
                    {value="Doubled",  label="Doubled"},
                }, get("ccb_border", "Beveled"), setCCBRebuild("ccb_border")), 34, 32)
                add(CreateSlider(c, "Taille (x SIZE)", 1.0, 4.0, 0.1, get("ccb_size_ratio", 2.5), setCCBRebuild("ccb_size_ratio")), 34, 48)
                add(CreateSlider(c, "Opacite", 0.10, 1.0, 0.05, get("ccb_alpha", 0.90), setCCBLive("ccb_alpha")), 34, 48)
                add(CreateSlider(c, "Decalage X", -80, 80, 1, get("ccb_offset_x", 0), setCCBLive("ccb_offset_x")), 34, 48)
                add(CreateSlider(c, "Decalage Y", -80, 80, 1, get("ccb_offset_y", 0), setCCBLive("ccb_offset_y")), 34, 48)
            end, 2)

            section("CCB — Couches", "ccb_layers", function()
                add(CreateCheck(c, "Glow (halo additif)", get("ccb_glow", true), set("ccb_glow")), 34, 28)
                add(CreateCheck(c, "Highlight (reflet)", get("ccb_highlight", true), set("ccb_highlight")), 34, 28)
                add(CreateCheck(c, "Runes (glyphes)", get("ccb_runes", false), set("ccb_runes")), 34, 28)
                add(CreateCheck(c, "Flash completion (0.3 s)", get("ccb_flash_complete", true), set("ccb_flash_complete")), 34, 28)
            end, 2)
        end

        -- ── Couleurs (tous modes sauf CCB) ───────────────────────────────────
        if not isCCB then
            section("Couleurs", "colors", function()
                if isCollapseGlow then
                    add(CreateCycle(c, "Mode couleur glow", {
                        {value="cast", label="Type de cast"},
                        {value="custom", label="Personnalisee"},
                        {value="progressive", label="Progressive"},
                    }, get("castbar_collapse_glow_color_mode", "cast"), set("castbar_collapse_glow_color_mode")), 34, 32)
                    local glowColorMode = self:GetCfgValue("castbar_collapse_glow_color_mode", "cast")
                    if glowColorMode == "custom" then
                        add(CreateColorButton(c, "Couleur glow", getColor("castbar_collapse_glowR", "castbar_collapse_glowG", "castbar_collapse_glowB", 0.30, 1.00, 0.45), setColor("castbar_collapse_glowR", "castbar_collapse_glowG", "castbar_collapse_glowB")), 34, 30)
                    elseif glowColorMode == "progressive" then
                        add(CreateColorButton(c, "Couleur depart", getColor("castbar_collapse_glow_startR", "castbar_collapse_glow_startG", "castbar_collapse_glow_startB", 1.00, 0.22, 0.78), setColor("castbar_collapse_glow_startR", "castbar_collapse_glow_startG", "castbar_collapse_glow_startB")), 34, 30)
                        add(CreateColorButton(c, "Couleur fin", getColor("castbar_collapse_glow_endR", "castbar_collapse_glow_endG", "castbar_collapse_glow_endB", 0.22, 1.00, 0.62), setColor("castbar_collapse_glow_endR", "castbar_collapse_glow_endG", "castbar_collapse_glow_endB")), 34, 30)
                        add(CreateSlider(c, "Saturation", 0.0, 2.0, 0.05, get("castbar_collapse_glow_saturation", 1.0), set("castbar_collapse_glow_saturation")), 34, 48)
                    else
                        add(CreateCheck(c, "Couleur de classe (joueurs)", get("castbar_color_by_class", true), set("castbar_color_by_class")), 34, 28)
                        add(CreateColorButton(c, "Cast interruptible",     getCArr("castbar_color_cast",   1.00, 0.65, 0.00), setCArr("castbar_color_cast")),    34, 30)
                        add(CreateColorButton(c, "Cast non-interruptible", getCArr("castbar_color_nonint", 0.72, 0.18, 1.00), setCArr("castbar_color_nonint")),  34, 30)
                        add(CreateColorButton(c, "Immune / boss",          getCArr("castbar_color_immune", 0.88, 0.10, 0.08), setCArr("castbar_color_immune")),  34, 30)
                        add(CreateColorButton(c, "Channel",                getCArr("castbar_color_channel",0.10, 0.55, 0.95), setCArr("castbar_color_channel")), 34, 30)
                    end
                    add(CreateColorButton(c, "Completion (succes)", getCArr("castbar_color_finish", 0.30, 1.00, 0.30), setCArr("castbar_color_finish")), 34, 30)
                    add(CreateColorButton(c, "Interruption (kick)", getCArr("castbar_color_broken", 0.95, 0.20, 0.20), setCArr("castbar_color_broken")), 34, 30)
                elseif isCollapse then
                    add(CreateCycle(c, "Mode couleur", {
                        {value="dynamic", label="Dynamique rose > vert"},
                        {value="fixed", label="Fixe"},
                    }, get("castbar_collapse_color_mode", "dynamic"), set("castbar_collapse_color_mode")), 34, 32)
                    if self:GetCfgValue("castbar_collapse_color_mode", "dynamic") == "fixed" then
                        add(CreateColorButton(c, "Couleur fixe", getColor("castbar_collapse_fixedR", "castbar_collapse_fixedG", "castbar_collapse_fixedB", 1, 0.25, 0.85), setColor("castbar_collapse_fixedR", "castbar_collapse_fixedG", "castbar_collapse_fixedB")), 34, 30)
                    end
                    add(CreateColorButton(c, "Completion (succes)", getCArr("castbar_color_finish", 0.30, 1.00, 0.30), setCArr("castbar_color_finish")), 34, 30)
                    add(CreateColorButton(c, "Interruption (kick)", getCArr("castbar_color_broken", 0.95, 0.20, 0.20), setCArr("castbar_color_broken")), 34, 30)
                else
                    add(CreateCheck(c, "Couleur de classe (joueurs)", get("castbar_color_by_class", true), set("castbar_color_by_class")), 34, 28)
                    add(CreateColorButton(c, "Cast interruptible",       getCArr("castbar_color_cast",   1.00, 0.65, 0.00), setCArr("castbar_color_cast")),    34, 30)
                    add(CreateColorButton(c, "Cast non-interruptible",   getCArr("castbar_color_nonint", 0.72, 0.18, 1.00), setCArr("castbar_color_nonint")),  34, 30)
                    add(CreateColorButton(c, "Immune / boss",            getCArr("castbar_color_immune", 0.88, 0.10, 0.08), setCArr("castbar_color_immune")),  34, 30)
                    add(CreateColorButton(c, "Channel",                  getCArr("castbar_color_channel",0.10, 0.55, 0.95), setCArr("castbar_color_channel")), 34, 30)
                    add(CreateColorButton(c, "Completion (succes)",      getCArr("castbar_color_finish", 0.30, 1.00, 0.30), setCArr("castbar_color_finish")),  34, 30)
                    add(CreateColorButton(c, "Interruption (kick)",      getCArr("castbar_color_broken", 0.95, 0.20, 0.20), setCArr("castbar_color_broken")),  34, 30)
                    if usesTrack then
                        add(CreateColorButton(c, "Trace de fond", getCArr("castbar_color_track", 0.10, 0.10, 0.12), setCArr("castbar_color_track")), 34, 30)
                    end
                end
            end, 2)
        end

        if isCollapse then
            section("Collapse Ring", "collapse", function()
                add(CreateSlider(c, "Opacite cercle", 0.15, 1.0, 0.02, get("castbar_collapse_alpha", 0.92), set("castbar_collapse_alpha")), 34, 48)
                add(CreateSlider(c, "Taille depart", 1.0, 2.6, 0.05, get("castbar_collapse_start_scale", 1.75), set("castbar_collapse_start_scale")), 34, 48)
                add(CreateSlider(c, "Taille finale", 0.25, 1.2, 0.05, get("castbar_collapse_end_scale", 0.72), set("castbar_collapse_end_scale")), 34, 48)
                add(CreateCheck(c, "Flash de fin", get("castbar_collapse_complete_flash", true), set("castbar_collapse_complete_flash")), 34, 28)
                add(CreateCheck(c, "Blink rouge interruption", get("castbar_collapse_interrupt_flash", true), set("castbar_collapse_interrupt_flash")), 34, 28)
            end, 2)
        end

        if isCollapseGlow then
            section("Collapse Glow Ring", "collapseGlow", function()
                add(CreateCycle(c, "Forme du ring", SP.CASTBAR_RING_SHAPES or {
                    {value="soft", label="Soft Glow"},
                }, get("castbar_collapse_glow_shape", "soft"), set("castbar_collapse_glow_shape")), 34, 32)
                add(CreateSlider(c, "Alpha glow", 0.10, 1.0, 0.02, get("castbar_collapse_glow_alpha", 0.85), set("castbar_collapse_glow_alpha")), 34, 48)
                add(CreateSlider(c, "Intensite glow", 0.0, 2.0, 0.05, get("castbar_collapse_glow_intensity", 1.0), set("castbar_collapse_glow_intensity")), 34, 48)
                add(CreateSlider(c, "Rayon initial", 0.8, 2.5, 0.05, get("castbar_collapse_glow_start_scale", 1.65), set("castbar_collapse_glow_start_scale")), 34, 48)
                add(CreateSlider(c, "Rayon final", 0.20, 1.2, 0.05, get("castbar_collapse_glow_end_scale", 0.45), set("castbar_collapse_glow_end_scale")), 34, 48)
                add(CreateSlider(c, "Epaisseur visuelle", 0.25, 2.5, 0.05, get("castbar_collapse_glow_thickness", 1.0), set("castbar_collapse_glow_thickness")), 34, 48)
                add(CreateCheck(c, "Pulse glow", get("castbar_collapse_glow_pulse", true), set("castbar_collapse_glow_pulse")), 34, 28)
                add(CreateCheck(c, "Flash de fin", get("castbar_collapse_glow_complete_flash", true), set("castbar_collapse_glow_complete_flash")), 34, 28)
                add(CreateCheck(c, "Blink rouge interruption", get("castbar_collapse_glow_interrupt_flash", true), set("castbar_collapse_glow_interrupt_flash")), 34, 28)
            end, 2)
        end

        if not (isCollapse or isCollapseGlow or isCCB) then
            section("Composants visuels", "components", function()
                if usesTrack then
                    add(CreateCheck(c, "Trace de fond", get("castbar_show_track", true), set("castbar_show_track")), 34, 28)
                end
                add(CreateCheck(c, "Flash completion (100%)", get("castbar_complete_flash", true), set("castbar_complete_flash")), 34, 28)
            end, 2)
        end

        if usesArcGeometry then
            section("Geometrie", "arc", function()
                add(CreateSlider(c, "Epaisseur arc", 6, 28, 1, get("castbar_arc_thickness", 14), set("castbar_arc_thickness")), 34, 48)
                add(CreateSlider(c, "Decalage X", -80, 80, 1, get("castbar_offset_x", 0), set("castbar_offset_x")), 34, 48)
                add(CreateSlider(c, "Decalage Y", -80, 80, 1, get("castbar_offset_y", 0), set("castbar_offset_y")), 34, 48)
                add(CreateSlider(c, "Echelle", 0.5, 1.8, 0.05, get("castbar_scale", 1), set("castbar_scale")), 34, 48)
            end, 2)
        elseif usesOffsets and not isCCB then
            section("Positionnement", "position", function()
                add(CreateSlider(c, "Decalage X", -80, 80, 1, get("castbar_offset_x", 0), set("castbar_offset_x")), 34, 48)
                add(CreateSlider(c, "Decalage Y", -80, 80, 1, get("castbar_offset_y", 0), set("castbar_offset_y")), 34, 48)
            end, 2)
        end

        section("Icone du sort", "icon", function()
            add(CreateCheck(c, "Afficher l'icone", get("castbar_show_icon", true), set("castbar_show_icon")), 34, 28)
            add(CreateCheck(c, "Mode focus (masquer HP/ilvl pendant le cast)", get("castbar_focus_mode", false), set("castbar_focus_mode")), 34, 28)
            add(CreateCycle(c, "Position", {
                {value="top",         label="Haut"},
                {value="center",      label="Centre"},
                {value="bottomright", label="Bas-droite"},
                {value="left",        label="Gauche"},
                {value="right",       label="Droite"},
            }, get("castbar_icon_position", "top"), set("castbar_icon_position")), 34, 32)
            add(CreateSlider(c, "Taille (ratio)", 0.20, 0.80, 0.02, get("castbar_icon_size", 0.42), set("castbar_icon_size")), 34, 48)
            add(CreateSlider(c, "Decalage X", -60, 60, 1, get("castbar_icon_offset_x", 0), set("castbar_icon_offset_x")), 34, 48)
            add(CreateSlider(c, "Decalage Y", -60, 60, 1, get("castbar_icon_offset_y", 0), set("castbar_icon_offset_y")), 34, 48)
        end, 2)

    elseif self.page == "text" then
        section("Nom", "name", function()
            local nameUType = self:GetUType()
            local nameIsPlayer = (nameUType == "ENEMY_PLAYER" or nameUType == "FRIENDLY_PLAYER")

            add(CreateCheck(c, "Afficher le nom", get("showName", true), set("showName")), 34, 28)

            -- ── Mode couleur ──────────────────────────────────────────────────
            local function currentNameMode()
                local m = self:GetCfgValue("name_color_mode", nil)
                if m == nil then
                    -- Migration legacy
                    if self:GetCfgValue("classColorName", false) then return "class" end
                    return "fixed"
                end
                if m == "class" and not nameIsPlayer then return "fixed" end
                return m
            end
            local function setNameMode(v)
                self:SetCfg("name_color_mode", v)
                -- Maintenir l'alias legacy pour compat
                self:SetCfg("classColorName", v == "class")
            end

            local nameModeOptions
            if nameIsPlayer then
                nameModeOptions = {
                    {value="fixed",       label="Fixe"},
                    {value="progressive", label="Progressive"},
                    {value="class",       label="Classe"},
                }
            else
                nameModeOptions = {
                    {value="fixed",       label="Fixe"},
                    {value="progressive", label="Progressive"},
                }
            end
            add(CreateCycle(c, "Mode couleur", nameModeOptions, currentNameMode, setNameMode), 34, 32)

            local nameMode = currentNameMode()
            if nameMode == "fixed" then
                add(CreateColorButton(c, "Couleur fixe", getColor("nameR", "nameG", "nameB", 1, 1, 1), setColor("nameR", "nameG", "nameB")), 34, 30)
            elseif nameMode == "progressive" then
                add(CreateColorButton(c, "100 - 75%", getColor("name_prog_highR", "name_prog_highG", "name_prog_highB", 1.0, 1.0, 1.0), setColor("name_prog_highR", "name_prog_highG", "name_prog_highB")), 34, 30)
                add(CreateColorButton(c, "74 - 50%",  getColor("name_prog_midR",  "name_prog_midG",  "name_prog_midB",  1.0, 0.82, 0.0), setColor("name_prog_midR",  "name_prog_midG",  "name_prog_midB")),  34, 30)
                add(CreateColorButton(c, "49 - 25%",  getColor("name_prog_lowR",  "name_prog_lowG",  "name_prog_lowB",  1.0, 0.50, 0.0), setColor("name_prog_lowR",  "name_prog_lowG",  "name_prog_lowB")),  34, 30)
                add(CreateColorButton(c, "24 -  0%",  getColor("name_prog_critR", "name_prog_critG", "name_prog_critB", 1.0, 0.15, 0.15), setColor("name_prog_critR", "name_prog_critG", "name_prog_critB")), 34, 30)
            end
            -- mode "class" : pas d'options couleur (couleurs WoW officielles)

            add(CreateSlider(c, "Saturation", 0, 2, 0.05, get("name_saturation", 1.0), set("name_saturation")), 34, 48)
            add(CreateSlider(c, "Transparence", 0.05, 1.0, 0.05, get("name_alpha", 1.0), set("name_alpha")), 34, 48)

            add(CreateCycle(c, "Police nom", getFontOptions(), get("nameFont", "Friz Quadrata TT"), set("nameFont")), 34, 32)
            add(CreateSlider(c, "Taille nom", 6, 28, 1, get("nameFontSize", 12), set("nameFontSize")), 34, 48)
            add(CreateSlider(c, "Decalage nom X", -80, 80, 1, get("nameOffsetX", 0), set("nameOffsetX")), 34, 48)
            add(CreateSlider(c, "Decalage nom Y", -80, 80, 1, get("nameOffsetY", 6), set("nameOffsetY")), 34, 48)
            add(CreateSlider(c, "Largeur max nom", 0, 260, 5, get("name_maxWidth", 0), set("name_maxWidth")), 34, 48)
        end, 1)
        section("Niveau / HP", "hp", function()
            add(CreateCheck(c, "Afficher niveau / HP", get("showLevelOrHP", true), set("showLevelOrHP")), 34, 28)
            add(CreateCheck(c, "iLvL joueurs max niveau", get("show_ilvl", true), set("show_ilvl")), 34, 28)
            add(CreateCheck(c, "HP sous MAX / iLvL", get("show_hp_under_maxlvl", false), set("show_hp_under_maxlvl")), 34, 28)
            add(CreateCheck(c, "HP aussi dans l'orbe", get("showHPAlsoInOrb", false), set("showHPAlsoInOrb")), 34, 28)
            add(CreateCycle(c, "Format HP", {
                {value="percent", label="Pourcentage"},
                {value="absolute", label="Valeur"},
                {value="both", label="Les deux"},
            }, get("hpFormat", "percent"), set("hpFormat")), 34, 32)
            add(CreateCheck(c, "Afficher symbole %", get("hp_show_percent", false), set("hp_show_percent")), 34, 28)
            add(CreateCycle(c, "Police HP", getFontOptions(), get("levelFont", "Friz Quadrata TT"), set("levelFont")), 34, 32)
            add(CreateSlider(c, "Taille texte HP", 6, 28, 1, get("levelFontSize", 11), set("levelFontSize")), 34, 48)
        end, 2)
        section("Couleurs % HP", "hpPercentColors", function()
            local function setPercentMode(v)
                self:SetCfg("hp_percent_color_mode", v)
                self:SetCfg("hp_color_dynamic", v == "dynamic")
            end
            add(CreateCycle(c, "Mode", {
                {value="fixed", label="Fixe"},
                {value="dynamic", label="Dynamique"},
            }, function()
                local mode = self:GetCfgValue("hp_percent_color_mode", nil)
                if mode == nil and self:GetCfgValue("hp_color_dynamic", false) then
                    return "dynamic"
                end
                if mode == "dynamic" then
                    return "dynamic"
                end
                return "fixed"
            end, setPercentMode), 34, 32)
            local percentMode = self:GetCfgValue("hp_percent_color_mode", nil)
            if percentMode == nil and self:GetCfgValue("hp_color_dynamic", false) then percentMode = "dynamic" end
            if percentMode == "dynamic" then
                add(CreateColorButton(c, "100 - 75%", getColor("hp_col1_r", "hp_col1_g", "hp_col1_b", 0.20, 1.0, 0.20), setColor("hp_col1_r", "hp_col1_g", "hp_col1_b")), 34, 30)
                add(CreateColorButton(c, "74 - 50%", getColor("hp_col2_r", "hp_col2_g", "hp_col2_b", 1.0, 0.82, 0.0), setColor("hp_col2_r", "hp_col2_g", "hp_col2_b")), 34, 30)
                add(CreateColorButton(c, "49 - 25%", getColor("hp_col3_r", "hp_col3_g", "hp_col3_b", 1.0, 0.50, 0.0), setColor("hp_col3_r", "hp_col3_g", "hp_col3_b")), 34, 30)
                add(CreateColorButton(c, "24 - 0%", getColor("hp_col4_r", "hp_col4_g", "hp_col4_b", 1.0, 0.15, 0.15), setColor("hp_col4_r", "hp_col4_g", "hp_col4_b")), 34, 30)
            else
                add(CreateColorButton(c, "Couleur fixe", getColor("hpPercentTextR", "hpPercentTextG", "hpPercentTextB", 1, 1, 1), setColor("hpPercentTextR", "hpPercentTextG", "hpPercentTextB")), 34, 30)
                add(CreateSlider(c, "Transparence", 0.1, 1, 0.05, get("hpPercentTextA", 1), set("hpPercentTextA")), 34, 48)
            end
        end, 2)
        section("Couleurs valeur HP", "hpAbsoluteColors", function()
            add(CreateCycle(c, "Mode", {
                {value="fixed", label="Fixe"},
                {value="dynamic", label="Dynamique"},
            }, get("hp_absolute_color_mode", "fixed"), set("hp_absolute_color_mode")), 34, 32)
            if self:GetCfgValue("hp_absolute_color_mode", "fixed") == "dynamic" then
                add(CreateColorButton(c, "100 - 75%", getColor("hp_abs_col1_r", "hp_abs_col1_g", "hp_abs_col1_b", 0.20, 1.0, 0.20), setColor("hp_abs_col1_r", "hp_abs_col1_g", "hp_abs_col1_b")), 34, 30)
                add(CreateColorButton(c, "74 - 50%", getColor("hp_abs_col2_r", "hp_abs_col2_g", "hp_abs_col2_b", 1.0, 0.82, 0.0), setColor("hp_abs_col2_r", "hp_abs_col2_g", "hp_abs_col2_b")), 34, 30)
                add(CreateColorButton(c, "49 - 25%", getColor("hp_abs_col3_r", "hp_abs_col3_g", "hp_abs_col3_b", 1.0, 0.50, 0.0), setColor("hp_abs_col3_r", "hp_abs_col3_g", "hp_abs_col3_b")), 34, 30)
                add(CreateColorButton(c, "24 - 0%", getColor("hp_abs_col4_r", "hp_abs_col4_g", "hp_abs_col4_b", 1.0, 0.15, 0.15), setColor("hp_abs_col4_r", "hp_abs_col4_g", "hp_abs_col4_b")), 34, 30)
            else
                add(CreateColorButton(c, "Couleur fixe", getColor("hpAbsoluteTextR", "hpAbsoluteTextG", "hpAbsoluteTextB", 1, 1, 1), setColor("hpAbsoluteTextR", "hpAbsoluteTextG", "hpAbsoluteTextB")), 34, 30)
                add(CreateSlider(c, "Transparence", 0.1, 1, 0.05, get("hpAbsoluteTextA", 1), set("hpAbsoluteTextA")), 34, 48)
            end
        end, 2)
        section("Sous-titres", "subtitle", function()
            add(CreateCheck(c, "Afficher sous-titre", get("showSubTitle", false), set("showSubTitle")), 34, 28)
            add(CreateCheck(c, "Afficher guilde", get("showGuild", false), set("showGuild")), 34, 28)
            add(CreateCheck(c, "Afficher honneur", get("showHonor", false), set("showHonor")), 34, 28)
        end, 1)
    elseif self.page == "target" then
        section("Cible", "targetMain", function()
            add(CreateCheck(c, "Personnalisation cible", get("target_custom_enabled", false), set("target_custom_enabled")), 34, 28)
            add(CreateCheck(c, "Glow cible", get("target_glow_enabled", true), set("target_glow_enabled")), 34, 28)
            add(CreateCycle(c, "Effet cible", {
                {value="pulse", label="Pulse"},
                {value="ripple", label="Ondulation glow"},
            }, get("target_glow_style", "pulse"), set("target_glow_style")), 34, 32)
            add(CreateColorButton(c, "Couleur cible", getColor("target_glowR", "target_glowG", "target_glowB", 1.0, 0.88, 0.0), setColor("target_glowR", "target_glowG", "target_glowB")), 34, 30)
            add(CreateSlider(c, "Alpha cible", 0, 1, 0.02, get("target_glow_alpha", 0.85), set("target_glow_alpha")), 34, 48)
            add(CreateCheck(c, "Pulse cible", get("target_glow_pulse", true), set("target_glow_pulse")), 34, 28)
            if get("target_glow_style", "pulse") == "ripple" then
                add(CreateSlider(c, "Vitesse ondulation", 0.20, 3.00, 0.05, get("target_ripple_speed", 1.25), set("target_ripple_speed")), 34, 48)
                add(CreateSlider(c, "Taille ondulation", 1.05, 3.00, 0.05, get("target_ripple_size", 2.20), set("target_ripple_size")), 34, 48)
                add(CreateSlider(c, "Trainee ondulation", 0.05, 1.00, 0.05, get("target_ripple_trail", 0.82), set("target_ripple_trail")), 34, 48)
                add(CreateSlider(c, "Intensite ondulation", 0.20, 3.00, 0.05, get("target_ripple_intensity", 1.35), set("target_ripple_intensity")), 34, 48)
                add(CreateSlider(c, "Saturation ondulation", 0.00, 2.50, 0.05, get("target_ripple_saturation", 1.25), set("target_ripple_saturation")), 34, 48)
                add(CreateSlider(c, "Epaisseur trainee", 0.40, 2.00, 0.05, get("target_ripple_width", 1.20), set("target_ripple_width")), 34, 48)
            end
        end, 1)
        section("Geometrie cible", "targetGeo", function()
            add(CreateCheck(c, "Scale hors-cible", get("non_target_scale_enabled", false), set("non_target_scale_enabled")), 34, 28)
            add(CreateSlider(c, "Echelle hors-cible", 0.20, 1.0, 0.05, get("non_target_scale", 0.75), set("non_target_scale")), 34, 48)
            add(CreateCycle(c, "Priorite visuelle", {
                {value="normal", label="Normale"},
                {value="target_first", label="Cible prioritaire"},
                {value="threat_first", label="Menace prioritaire"},
            }, get("target_priority", "normal"), set("target_priority")), 34, 32)
        end, 2)
    elseif self.page == "effects" then
        section("Effets orbe", "orbfx", function()
            add(CreateCheck(c, "Galaxies", get("orb_galaxies", true), set("orb_galaxies")), 34, 28)
            add(CreateSlider(c, "Alpha galaxies", 0, 1, 0.01, get("orb_galaxy_alpha", 0.15), set("orb_galaxy_alpha")), 34, 48)
            add(CreateCheck(c, "Etoile Midnight", get("orb_midnight_star", false), set("orb_midnight_star")), 34, 28)
            if get("orb_midnight_star", false) then
                add(CreateSlider(c, "Transparence etoile", 0.00, 1.00, 0.02, get("orb_midnight_star_alpha", 0.55), set("orb_midnight_star_alpha")), 34, 48)
                add(CreateSlider(c, "Taille etoile", 0.50, 2.50, 0.05, get("orb_midnight_star_scale", 1.18), set("orb_midnight_star_scale")), 34, 48)
                add(CreateSlider(c, "Vitesse rotation etoile", 0, 360, 5, get("orb_midnight_star_speed", 45), set("orb_midnight_star_speed")), 34, 48)
                add(CreateCycle(c, "Sens rotation etoile", {
                    {value="cw", label="Horaire"},
                    {value="ccw", label="Anti-horaire"},
                }, get("orb_midnight_star_dir", "cw"), set("orb_midnight_star_dir")), 34, 32)
            end
            add(CreateSlider(c, "Alpha shimmer", 0, 1, 0.01, get("orb_shimmer_alpha", 0.22), set("orb_shimmer_alpha")), 34, 48)
            add(CreateCheck(c, "Vague liquide", get("orb_wave", true), set("orb_wave")), 34, 28)
            add(CreateSlider(c, "Alpha vague", 0, 1, 0.01, get("orb_wave_alpha", 0.38), set("orb_wave_alpha")), 34, 48)
            add(CreateSlider(c, "Vitesse vague", 0, 0.8, 0.01, get("orb_wave_speed", 0.18), set("orb_wave_speed")), 34, 48)
            add(CreateCheck(c, "Gloss", get("orb_gloss", true), set("orb_gloss")), 34, 28)
            add(CreateSlider(c, "Alpha gloss", 0, 1, 0.01, get("orb_gloss_alpha", 0.20), set("orb_gloss_alpha")), 34, 48)
            add(CreateCheck(c, "Spark HP", get("orb_spark", true), set("orb_spark")), 34, 28)
            add(CreateCheck(c, "Glow HP critique", get("orb_lowhp_glow", true), set("orb_lowhp_glow")), 34, 28)
        end, 1)
        section("Indicateurs", "indicators", function()
            add(CreateCheck(c, "Pointeur sous l'orbe", get("anchor_enabled", true), set("anchor_enabled")), 34, 28)
            add(CreateSlider(c, "Alpha pointeur", 0, 1, 0.01, get("anchor_alpha", 0.75), set("anchor_alpha")), 34, 48)
            add(CreateCheck(c, "Dragon elite", get("showEliteDragon", false), set("showEliteDragon")), 34, 28)
            add(CreateCheck(c, "Quetes", get("quest_enabled", true), set("quest_enabled")), 34, 28)
            add(CreateCheck(c, "Couleur nom quete", get("quest_color_name", true), set("quest_color_name")), 34, 28)
            add(CreateCheck(c, "Marques raid", get("raidmark_enabled", true), set("raidmark_enabled")), 34, 28)
            add(CreateCheck(c, "Indicateur combat", get("showCombatIndicator", true), set("showCombatIndicator")), 34, 28)
        end, 2)
    end

    c:SetHeight(math.max((win.scroll and win.scroll.visibleHeight) or 340, math.max(-colY[1], -colY[2]) + 16))
    if win.scroll then win.scroll:UpdateScroll() end
end

function SP.UIPlumber:RefreshHeader()
    local win = self.win
    if not win then return end
    local special = IsSpecialCategory(self.category)

    if win.topButtons then
        local entry = self:GetUnitEntry()
        for key, b in pairs(win.topButtons) do
            b:Show()
            if key == "player" then
                b:SetSelected((not special) and entry.kind == "player")
            elseif key == "npc" then
                b:SetSelected((not special) and entry.kind == "npc")
            else
                b:SetSelected(self.category == key)
            end
        end
    end

    if special then
        if win.unitMenu then win.unitMenu:Hide() end
        if win.select then win.select:Hide() end
        for _, b in pairs(win.catButtons or {}) do b:Hide() end
        for _, b in pairs(win.pageButtons or {}) do b:Hide() end
        local entry = self:GetUnitEntry()
        win.status:SetText(entry.title .. "  |  " .. (self.category == "logs" and "journal" or self.category == "modules" and "performance" or "comportement"))
        return
    end

    if win.select then win.select:Hide() end
    for _, b in pairs(win.pageButtons or {}) do b:Show() end
    local list = UNIT_BY_CATEGORY[self.category] or UNIT_BY_CATEGORY.enemy
    if #list <= 1 then
        self.unitKind[self.category] = list[1].kind
        if win.unitMenu then win.unitMenu:Hide() end
    end
    local entry = self:GetUnitEntry()

    local last
    for _, cat in ipairs(CATEGORY) do
        if not IsSpecialCategory(cat.key) then
            local b = win.catButtons and win.catButtons[cat.key]
            if b then
                local visible = not (entry.kind == "player" and cat.key == "neutral")
                b:SetShown(visible)
                b:ClearAllPoints()
                if visible then
                    if last then b:SetPoint("LEFT", last, "RIGHT", 18, 0)
                    else b:SetPoint("TOPLEFT", win.header, "TOPLEFT", 36, -38) end
                    b:SetSelected(cat.key == self.category)
                    last = b
                end
            end
        end
    end

    win.status:SetText("Profil actif : " .. entry.title .. "  |  rendu temps reel")
end

function SP.UIPlumber:RefreshAll()
    self:RefreshHeader()
    self:BuildQuick()
    self:BuildSettings()
    self:RebuildPreview()
    self:RebuildProfileBar()
end

-- ── ProfileBar ──────────────────────────────────────────────────────────────

function SP.UIPlumber:BuildProfileBar()
    local win = self.win
    if not win or not win.profileBar then return end
    local pb = win.profileBar
    self:ClearChildren(pb)

    local function SmallBtn(label, w, onClick)
        local b = CreateFrame("Button", nil, pb)
        b:SetSize(w or 80, 22)
        b.left   = b:CreateTexture(nil, "BACKGROUND")
        b.center = b:CreateTexture(nil, "BACKGROUND")
        b.right  = b:CreateTexture(nil, "BACKGROUND")
        SafeTexture(b.left, TEX); SafeTexture(b.center, TEX); SafeTexture(b.right, TEX)
        b.left:SetSize(10, 26);   b.left:SetPoint("LEFT",  b, "LEFT",  -1, 0)
        b.right:SetSize(10, 26);  b.right:SetPoint("RIGHT", b, "RIGHT",  1, 0)
        b.center:SetPoint("TOPLEFT",     b.left,  "TOPRIGHT")
        b.center:SetPoint("BOTTOMRIGHT", b.right, "BOTTOMLEFT")
        b.left:SetTexCoord(768/1024, 800/1024, 448/1024, 512/1024)
        b.center:SetTexCoord(800/1024, 972/1024, 448/1024, 512/1024)
        b.right:SetTexCoord(972/1024, 1004/1024, 448/1024, 512/1024)
        b.label = Text(b, label, 10, GOLD)
        b.label:SetPoint("CENTER")
        b:SetScript("OnClick",  onClick)
        b:SetScript("OnEnter", function(s) s.label:SetTextColor(1, 1, 1, 1) end)
        b:SetScript("OnLeave", function(s) s.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
        return b
    end

    -- Dropdown profil -------------------------------------------------------
    local dd = self:AddChild(pb, CreateFrame("Button", nil, pb, "BackdropTemplate"))
    win.profileDropdown = dd
    dd:SetSize(256, 26)
    dd:SetPoint("TOPLEFT", pb, "TOPLEFT", 2, 0)
    dd:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left=2, right=2, top=2, bottom=2},
    })
    dd:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
    dd.label = Text(dd, "--", 11, WHITE)
    dd.label:SetPoint("LEFT", dd, "LEFT", 8, 0)
    dd.label:SetJustifyH("LEFT")
    dd.arrow = Text(dd, "v", 9, GOLD)
    dd.arrow:SetPoint("RIGHT", dd, "RIGHT", -6, 0)

    dd.menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dd.menu:SetSize(256, 28)
    dd.menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    dd.menu:SetFrameStrata("DIALOG")
    dd.menu:SetFrameLevel(960)
    dd.menu:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = {left=2, right=2, top=2, bottom=2},
    })
    dd.menu:SetBackdropColor(0.02, 0.016, 0.012, 0.98)
    dd.menu.items = {}
    dd.menu:Hide()

    dd:SetScript("OnClick", function()
        if SP.UIPlumber._openDropdown and SP.UIPlumber._openDropdown ~= dd.menu then
            SP.UIPlumber._openDropdown:Hide()
        end
        if dd.menu:IsShown() then
            dd.menu:Hide()
            SP.UIPlumber._openDropdown = nil
            return
        end
        -- Rebuild items
        for _, it in ipairs(dd.menu.items) do it:Hide() end
        dd.menu.items = {}
        local profiles = SP.Profiles and SP.Profiles:GetList() or {}
        local current  = SP.Profiles and SP.Profiles:GetCurrentName() or ""
        dd.menu:SetSize(256, math.max(28, #profiles * 24 + 8))
        for i, pname in ipairs(profiles) do
            local item = CreateFrame("Button", nil, dd.menu)
            item:SetSize(240, 22)
            item:SetPoint("TOPLEFT", dd.menu, "TOPLEFT", 6, -4 - (i - 1) * 24)
            local c = (pname == current) and WHITE or GOLD
            item.lbl = Text(item, pname, 11, c)
            item.lbl:SetPoint("LEFT", item, "LEFT", 8, 0)
            local pname2 = pname  -- closure capture
            item:SetScript("OnEnter", function(s) s.lbl:SetTextColor(1, 1, 1, 1) end)
            item:SetScript("OnLeave", function(s)
                local cc = (SP.Profiles and SP.Profiles:GetCurrentName() == pname2) and WHITE or GOLD
                s.lbl:SetTextColor(cc[1], cc[2], cc[3], 1)
            end)
            item:SetScript("OnClick", function()
                dd.menu:Hide()
                SP.UIPlumber._openDropdown = nil
                if SP.Profiles then SP.Profiles:Load(pname2) end
            end)
            dd.menu.items[#dd.menu.items + 1] = item
        end
        dd.menu:Show()
        SP.UIPlumber._openDropdown = dd.menu
    end)
    dd:SetScript("OnHide", function() if dd.menu then dd.menu:Hide() end end)

    local BW, GAP = 80, 4

    -- Rangee 2 : Creer / Dupliquer / Supprimer --------------------------------
    local btnCreate = self:AddChild(pb, SmallBtn("Creer", BW, function()
        SP.UIPlumber:ShowInputDialog("Nouveau profil", "", function(name)
            if SP.Profiles then
                local ok, err = SP.Profiles:Create(name)
                if not ok then SP:Print("|cFFFF4444Profil : " .. tostring(err) .. "|r") end
            end
        end)
    end))
    btnCreate:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -6)

    local btnDup = self:AddChild(pb, SmallBtn("Dupliquer", BW, function()
        if SP.Profiles then
            local ok, err = SP.Profiles:Duplicate(SP.Profiles:GetCurrentName(), nil)
            if not ok then SP:Print("|cFFFF4444Profil : " .. tostring(err) .. "|r") end
        end
    end))
    btnDup:SetPoint("LEFT", btnCreate, "RIGHT", GAP, 0)

    local btnDel = self:AddChild(pb, SmallBtn("Supprimer", BW, function()
        if SP.Profiles then
            local cur = SP.Profiles:GetCurrentName()
            SP.UIPlumber:ShowConfirmDialog("Supprimer \"" .. cur .. "\" ?", function()
                local ok, err = SP.Profiles:Delete(cur)
                if not ok then SP:Print("|cFFFF4444Profil : " .. tostring(err) .. "|r") end
            end)
        end
    end))
    btnDel:SetPoint("LEFT", btnDup, "RIGHT", GAP, 0)

    -- Rangee 3 : Renommer / Exporter / Importer -------------------------------
    local btnRen = self:AddChild(pb, SmallBtn("Renommer", BW, function()
        if SP.Profiles then
            local cur = SP.Profiles:GetCurrentName()
            SP.UIPlumber:ShowInputDialog("Renommer", cur, function(newName)
                local ok, err = SP.Profiles:Rename(cur, newName)
                if not ok then SP:Print("|cFFFF4444Profil : " .. tostring(err) .. "|r") end
            end)
        end
    end))
    btnRen:SetPoint("TOPLEFT", btnCreate, "BOTTOMLEFT", 0, -5)

    local btnExp = self:AddChild(pb, SmallBtn("Exporter", BW, function()
        if SP.Profiles then
            local cur = SP.Profiles:GetCurrentName()
            local encoded, err = SP.Profiles:Export(cur)
            if encoded then
                SP.UIPlumber:ShowExportDialog(encoded)
            else
                SP:Print("|cFFFF4444Export : " .. tostring(err) .. "|r")
            end
        end
    end))
    btnExp:SetPoint("LEFT", btnRen, "RIGHT", GAP, 0)

    local btnImp = self:AddChild(pb, SmallBtn("Importer", BW, function()
        SP.UIPlumber:ShowImportDialog(function(str)
            if not SP.Profiles then return end
            local ok, summary, envelope = SP.Profiles:ImportString(str)
            if not ok then
                SP:Print("|cFFFF4444Import : " .. tostring(summary) .. "|r")
                return
            end
            local cur = SP.Profiles:GetCurrentName()
            SP.UIPlumber:ShowConfirmDialog(
                "Importer dans \"" .. cur .. "\" ?\n" .. tostring(summary),
                function()
                    local ok2, err2 = SP.Profiles:ApplyImport(envelope, cur, true)
                    if not ok2 then
                        SP:Print("|cFFFF4444Import : " .. tostring(err2) .. "|r")
                    end
                end
            )
        end)
    end))
    btnImp:SetPoint("LEFT", btnExp, "RIGHT", GAP, 0)
end

function SP.UIPlumber:RebuildProfileBar()
    local win = self.win
    if not win or not win.profileDropdown then return end
    local current = SP.Profiles and SP.Profiles:GetCurrentName() or "--"
    win.profileDropdown.label:SetText(current)
    -- Fermer le menu deroulant si ouvert (profil change de l'exterieur)
    if win.profileDropdown.menu and win.profileDropdown.menu:IsShown() then
        win.profileDropdown.menu:Hide()
        if self._openDropdown == win.profileDropdown.menu then
            self._openDropdown = nil
        end
    end
end

function SP.UIPlumber:OnProfileEvent(event, name)
    if not (self.win and self.win:IsShown()) then return end
    self:RebuildProfileBar()
    -- Rafraichir les settings apres les changements structurels
    if event == "loaded" or event == "deleted" or event == "renamed" or event == "created" or event == "imported" or event == "reset" then
        self:RefreshHeader()
        self:BuildSettings()
        self:RebuildPreview()
    end
end

-- ── Popups ──────────────────────────────────────────────────────────────────

local function _MakePopupBase(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(1200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = {left=4, right=4, top=4, bottom=4},
    })
    f:SetBackdropColor(0.04, 0.03, 0.02, 0.97)
    f:Hide()
    return f
end

local function _MakeEditBox(parent, w)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(w, 24)
    eb:SetFontObject(GameFontNormal)
    pcall(eb.SetFont, eb, "Fonts\\FRIZQT__.TTF", 12, "")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetAutoFocus(false)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.018, 0.014, 0.86)
    local border = CreateFrame("Frame", nil, eb, "BackdropTemplate")
    border:SetPoint("TOPLEFT",     eb, "TOPLEFT",     -3,  3)
    border:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT",  3, -3)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left=2, right=2, top=2, bottom=2},
    })
    border:SetBackdropBorderColor(0.45, 0.35, 0.25, 0.80)
    return eb
end

function SP.UIPlumber:ShowInputDialog(title, defaultText, callback)
    if not self._inputDialog then
        local f = _MakePopupBase("SNPInputDialog", 360, 160)
        f.titleText = Text(f, "", 13, GOLD)
        f.titleText:SetPoint("TOP", f, "TOP", 0, -16)
        f.titleText:SetJustifyH("CENTER")
        f.editBox = _MakeEditBox(f, 320)
        f.editBox:SetPoint("TOP", f.titleText, "BOTTOM", 0, -14)
        f.editBox:SetMaxLetters(40)
        f.btnOK = CreatePanelButton(f, "OK", function() end)
        f.btnOK:SetSize(110, 28)
        f.btnOK:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 30, 16)
        f.btnCancel = CreatePanelButton(f, "Annuler", function() f:Hide() end)
        f.btnCancel:SetSize(110, 28)
        f.btnCancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 16)
        self._inputDialog = f
    end
    local f = self._inputDialog
    f.titleText:SetText(title or "Entrer un nom")
    f.editBox:SetText(defaultText or "")
    f.editBox:SetFocus()
    f.editBox:HighlightText()
    local function submit()
        local text = f.editBox:GetText()
        f:Hide()
        if callback and text ~= "" then callback(text) end
    end
    f.btnOK:SetScript("OnClick", submit)
    f.editBox:SetScript("OnEnterPressed", submit)
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    f:SetPoint("CENTER")
    f:Show()
end

function SP.UIPlumber:ShowConfirmDialog(message, callback)
    if not self._confirmDialog then
        local f = _MakePopupBase("SNPConfirmDialog", 340, 140)
        f.msgText = Text(f, "", 12, WHITE)
        f.msgText:SetPoint("TOP", f, "TOP", 0, -24)
        f.msgText:SetJustifyH("CENTER")
        f.msgText:SetWidth(300)
        f.btnOK = CreatePanelButton(f, "Confirmer", function() end)
        f.btnOK:SetSize(120, 28)
        f.btnOK:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 16)
        f.btnCancel = CreatePanelButton(f, "Annuler", function() f:Hide() end)
        f.btnCancel:SetSize(120, 28)
        f.btnCancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 16)
        self._confirmDialog = f
    end
    local f = self._confirmDialog
    f.msgText:SetText(message or "Confirmer ?")
    f.btnOK:SetScript("OnClick", function()
        f:Hide()
        if callback then callback() end
    end)
    f:SetPoint("CENTER")
    f:Show()
end

function SP.UIPlumber:ShowExportDialog(text)
    if not self._exportDialog then
        local f = _MakePopupBase("SNPExportDialog", 520, 160)
        f.titleText = Text(f, "Exporter le profil -- copiez la chaine ci-dessous", 12, GOLD)
        f.titleText:SetPoint("TOP", f, "TOP", 0, -16)
        f.titleText:SetJustifyH("CENTER")
        f.editBox = _MakeEditBox(f, 480)
        f.editBox:SetPoint("TOP", f.titleText, "BOTTOM", 0, -14)
        f.btnClose = CreatePanelButton(f, "Fermer", function() f:Hide() end)
        f.btnClose:SetSize(120, 28)
        f.btnClose:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
        self._exportDialog = f
    end
    local f = self._exportDialog
    f.editBox:SetText(text or "")
    f.editBox:SetFocus()
    f.editBox:HighlightText()
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    f:SetPoint("CENTER")
    f:Show()
end

function SP.UIPlumber:ShowImportDialog(callback)
    if not self._importDialog then
        local f = _MakePopupBase("SNPImportDialog", 520, 160)
        f.titleText = Text(f, "Coller la chaine d'import (SP1!...)", 12, GOLD)
        f.titleText:SetPoint("TOP", f, "TOP", 0, -16)
        f.titleText:SetJustifyH("CENTER")
        f.editBox = _MakeEditBox(f, 480)
        f.editBox:SetPoint("TOP", f.titleText, "BOTTOM", 0, -14)
        f.btnOK = CreatePanelButton(f, "Importer", function() end)
        f.btnOK:SetSize(120, 28)
        f.btnOK:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 16)
        f.btnCancel = CreatePanelButton(f, "Annuler", function() f:Hide() end)
        f.btnCancel:SetSize(120, 28)
        f.btnCancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 16)
        self._importDialog = f
    end
    local f = self._importDialog
    f.editBox:SetText("")
    f.editBox:SetFocus()
    local function submit()
        local str = f.editBox:GetText()
        f:Hide()
        if callback and str ~= "" then callback(str) end
    end
    f.btnOK:SetScript("OnClick", submit)
    f.editBox:SetScript("OnEnterPressed", submit)
    f.editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    f:SetPoint("CENTER")
    f:Show()
end

-- ── Open / Close ─────────────────────────────────────────────────────────────

function SP.UIPlumber:Open()
    if not self.win then
        local ok, err = SafeCall(self.BuildWindow, self)
        if not ok then
            SP:Print("|cFFFF4444UI custom erreur : " .. tostring(err) .. "|r")
            return
        end
    end
    self.win:Show()
    local ok, err = SafeCall(self.RefreshAll, self)
    if not ok then
        SP:Print("|cFFFF4444UI custom refresh erreur : " .. tostring(err) .. "|r")
    end
end

function SP.UIPlumber:Close()
    if self.win then self.win:Hide() end
end

local oldOpen = SP.UI.Open
function SP.UI:Open()
    if SP.UIPlumber then
        SP.UIPlumber:Open()
    elseif oldOpen then
        oldOpen(SP.UI)
    end
end

function SP.UI:Close()
    if SP.UIPlumber then SP.UIPlumber:Close() end
end

-- Hook ProfileManager → PSUI : rafraichit la barre de profils lors des
-- evenements Create/Load/Delete/Rename/Export/Import.
function SP.UI:OnProfileEvent(event, name)
    if SP.UIPlumber then SP.UIPlumber:OnProfileEvent(event, name) end
end

-- Stub pour Core.lua quand UI.lua est désactivé dans .toc.
-- Plumber gère seul l'ouverture ; rien à enregistrer auprès d'AceConfig.
if not SP.UI.Register then
    SP.UI.Register = function() end
end
