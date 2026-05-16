-------------------------------------------------------------------------------
-- SphereNameplates v8.0 — Modules/Preview.lua
-- Fenêtre de prévisualisation des orbes (sans LibOrb)
--
-- USAGE :
--   SP.Preview:Open(unitType)   → ouvre / rafraîchit pour ce type
--   SP.Preview:OpenBeside()     → ouvre à droite de la fenêtre config
--   SP.Preview:Close()          → ferme
--   SP.Preview:SetHP(ratio)     → change HP prévisualisation (0.0 – 1.0)
--   SP.Preview:Refresh()        → reconstruit l'orbe (après config change)
--
-- MODE ÉMULATION (v8.0) :
--   Boutons pour simuler cast interruptible, canal, auras, aggro, HP bas.
--   L'état d'émulation est conservé lors des Refresh (changement de config).
--   Auto-sync vers le type d'unité courant via UI.lua S() setter.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.Preview = {
    ratio  = 0.75,
    utype  = "ENEMY",
    data   = nil,
    win    = nil,
    emul   = { cast=false, channel=false, auras=false, aggro=false },
}

local TYPE_LABELS = {
    ENEMY           = "Ennemi PNJ",
    FRIENDLY        = "Allié PNJ",
    NEUTRAL         = "PNJ neutre",
    ENEMY_PLAYER    = "Joueur ennemi",
    FRIENDLY_PLAYER = "Joueur allié",
}

-------------------------------------------------------------------------------
--  APPLICATION DE L'ÉMULATION (appelée après chaque Rebuild)
-------------------------------------------------------------------------------
function SP.Preview:ApplyEmulation()
    local data = self.data
    if not data then return end
    local em   = self.emul

    -- Cast / canal
    if em.cast then
        if data.castbar then pcall(SP.CastBar.TestCast, SP.CastBar, data, 10.0) end
    elseif em.channel then
        if data.castbar then pcall(SP.CastBar.TestChannel, SP.CastBar, data, 10.0) end
    end

    -- Auras factices : la preview doit montrer le rendu actif sans /reload.
    local cfg = SP:GetCfg(data.unitType)
    if cfg and cfg.auras_enabled and SP.Auras and SP.Auras.SimulateAuras then
        pcall(SP.Auras.SimulateAuras, SP.Auras, data)
    elseif SP.Auras and SP.Auras.RemoveAll then
        pcall(SP.Auras.RemoveAll, SP.Auras, data)
    end

    -- Aggro (singleGlow mis à jour par AnimTick)
    if em.aggro then
        data._aggroLevel = 3
        pcall(SP.Orb.UpdateName, SP.Orb, data, nil)
    end
end

-------------------------------------------------------------------------------
--  CONSTRUCTION DE LA FENÊTRE (une seule fois)
-------------------------------------------------------------------------------
local function BuildWindow()
    local prev = SP.Preview

    local win = CreateFrame("Frame", "SPherePlatesPreviewWin", UIParent,
        "BackdropTemplate")
    win:SetSize(280, 530)
    win:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(200)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop",  win.StopMovingOrSizing)
    win:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=24,
        insets={left=6,right=6,top=6,bottom=6},
    })

    -- Titre
    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetPoint("TOP", win, "TOP", 0, -12)
    title:SetTextColor(1, 0.5, 0, 1)
    title:SetText("|cFF8B0000Sphere|r|cFFFF7A00Plates|r  — Prévisualisation")

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() SP.Preview:Close() end)

    local sep1 = win:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep1:SetSize(240, 8)
    sep1:SetPoint("TOP", win, "TOP", 0, -32)

    -- Zone orbe
    local orbArea = CreateFrame("Frame", nil, win, "BackdropTemplate")
    orbArea:SetSize(220, 185)
    orbArea:SetPoint("TOP", win, "TOP", 0, -45)
    orbArea:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    })
    orbArea:SetBackdropColor(0.04, 0.04, 0.08, 0.97)
    orbArea:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.85)
    win.orbArea = orbArea

    local fakePlate = CreateFrame("Frame", nil, orbArea)
    fakePlate:SetSize(1, 1)
    fakePlate:SetPoint("CENTER", orbArea, "CENTER", 0, 0)
    win.fakePlate = fakePlate

    local typeLabel = win:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    typeLabel:SetPoint("TOP", orbArea, "BOTTOM", 0, -5)
    typeLabel:SetTextColor(0.9, 0.7, 0.1, 1)
    win.typeLabel = typeLabel

    local sep2 = win:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep2:SetSize(240, 8)
    sep2:SetPoint("TOP", orbArea, "BOTTOM", 0, -18)

    -- Boutons de type (2×2)
    local typeDefs = {
        {ut="ENEMY",           lb="Ennemi PNJ",    c=1, r=1},
        {ut="NEUTRAL",         lb="PNJ neutre",    c=2, r=1},
        {ut="FRIENDLY",        lb="Allie PNJ",     c=1, r=2},
        {ut="ENEMY_PLAYER",    lb="Joueur ennemi", c=2, r=2},
        {ut="FRIENDLY_PLAYER", lb="Joueur allie",  c=1, r=3},
    }
    win.typeButtons = {}
    for _, bd in ipairs(typeDefs) do
        local btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        btn:SetSize(118, 24)
        btn:SetText(bd.lb)
        btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        local xOff = (bd.c == 1) and -62 or 62
        btn:SetPoint("TOP", sep2, "BOTTOM", xOff, -6 - (bd.r - 1) * 28)
        local utype = bd.ut
        btn:SetScript("OnClick", function() SP.Preview:Open(utype) end)
        win.typeButtons[utype] = btn
    end

    -- Sep sous les boutons de type
    local sep3 = win:CreateTexture(nil, "ARTWORK")
    sep3:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep3:SetSize(240, 8)
    sep3:SetPoint("TOP", sep2, "BOTTOM", 0, -92)

    -- Slider HP
    local slider = CreateFrame("Slider", "SPherePlatesPreviewSlider", win,
        "OptionsSliderTemplate")
    slider:SetSize(220, 16)
    slider:SetPoint("TOP", sep3, "BOTTOM", 0, -10)
    slider:SetMinMaxValues(0, 100)
    slider:SetValue(75)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName().."Low"]:SetText("0%")
    _G[slider:GetName().."High"]:SetText("100%")
    _G[slider:GetName().."Text"]:SetText("HP : 75%")
    slider:SetScript("OnValueChanged", function(self, val)
        _G[self:GetName().."Text"]:SetText(string.format("HP : %d%%", math.floor(val)))
        SP.Preview:SetHP(val / 100)
    end)
    win.hpSlider = slider

    -- ── SECTION ÉMULATION ───────────────────────────────────────────────────────
    local sep4 = win:CreateTexture(nil, "ARTWORK")
    sep4:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep4:SetSize(240, 8)
    sep4:SetPoint("TOP", slider, "BOTTOM", 0, -10)

    local emulTitle = win:CreateFontString(nil, "OVERLAY")
    emulTitle:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    emulTitle:SetPoint("TOP", sep4, "BOTTOM", 0, -4)
    emulTitle:SetTextColor(0.55, 0.80, 1.0, 1)
    emulTitle:SetText("— Mode Émulation —")

    -- Helper bouton émulation (2 colonnes)
    local function EmulBtn(label, col, row, onClick)
        local btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        btn:SetSize(118, 22)
        btn:SetText(label)
        btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        local xOff = (col == 1) and -62 or 62
        btn:SetPoint("TOP", emulTitle, "BOTTOM", xOff, -6 - (row - 1) * 26)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- Ligne 1 : Cast / Canal
    local btnCast = EmulBtn("Cast (interrupt.)", 1, 1, function()
        local em = SP.Preview.emul
        em.cast    = not em.cast
        em.channel = false
        local d = SP.Preview.data
        if not d then return end
        if em.cast then
            if d.castbar then pcall(SP.CastBar.TestCast, SP.CastBar, d, 10.0) end
        else
            if d.castbar then pcall(SP.CastBar.StopCast, SP.CastBar, d, false) end
        end
    end)

    local btnChan = EmulBtn("Canal (channel)", 2, 1, function()
        local em = SP.Preview.emul
        em.channel = not em.channel
        em.cast    = false
        local d = SP.Preview.data
        if not d then return end
        if em.channel then
            if d.castbar then pcall(SP.CastBar.TestChannel, SP.CastBar, d, 10.0) end
        else
            if d.castbar then pcall(SP.CastBar.StopCast, SP.CastBar, d, false) end
        end
    end)

    -- Ligne 2 : Auras / Aggro
    local btnAuras = EmulBtn("Auras (débuffs)", 1, 2, function()
        local em = SP.Preview.emul
        em.auras = not em.auras
        local d = SP.Preview.data
        if not d then return end
        if em.auras then
            pcall(SP.Auras.SimulateAuras, SP.Auras, d)
        else
            pcall(SP.Auras.RemoveAll, SP.Auras, d)
        end
    end)

    local btnAggro = EmulBtn("Aggro (menace)", 2, 2, function()
        local em = SP.Preview.emul
        em.aggro = not em.aggro
        local d = SP.Preview.data
        if not d then return end
        d._aggroLevel = em.aggro and 3 or 0
        -- singleGlow : AnimTick s'en charge au prochain tick (30 FPS)
        pcall(SP.Orb.UpdateName, SP.Orb, d, nil)
    end)

    -- Ligne 3 : HP bas / Réinitialiser
    local btnHP = EmulBtn("HP Bas (15%)", 1, 3, function()
        local v = (SP.Preview.ratio > 0.20) and 0.15 or 0.75
        SP.Preview:SetHP(v)
    end)

    local btnReset = EmulBtn("↺  Réinitialiser", 2, 3, function()
        local em = SP.Preview.emul
        em.cast = false ; em.channel = false
        em.auras = false ; em.aggro = false
        SP.Preview:SetHP(0.75)
        SP.Preview:Rebuild(SP.Preview.utype)
    end)

    -- Sep + bouton Rafraîchir
    local sep5 = win:CreateTexture(nil, "ARTWORK")
    sep5:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep5:SetSize(240, 8)
    sep5:SetPoint("TOP", emulTitle, "BOTTOM", 0, -86)

    local refreshBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    refreshBtn:SetSize(140, 22)
    refreshBtn:SetPoint("TOP", sep5, "BOTTOM", 0, -6)
    refreshBtn:SetText("↺  Rafraîchir l'orbe")
    refreshBtn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    refreshBtn:SetScript("OnClick", function() SP.Preview:Refresh() end)

    local note = win:CreateFontString(nil, "OVERLAY")
    note:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    note:SetPoint("BOTTOM", win, "BOTTOM", 0, 10)
    note:SetTextColor(0.6, 0.6, 0.6, 0.8)
    note:SetText("Config → mise à jour en temps réel  ·  Cliquer pour activer/désactiver")

    win:Hide()
    prev.win = win
    return win
end

-------------------------------------------------------------------------------
--  RECONSTRUCTION DE L'ORBE DE PRÉVISUALISATION
-------------------------------------------------------------------------------
function SP.Preview:Rebuild(utype)
    local win = self.win
    if not win then return end

    -- Nettoyer l'ancienne data
    if self.data then
        if self.data.castbar then pcall(SP.CastBar.Reset, SP.CastBar, self.data) end
        if self.data.root    then pcall(self.data.root.Hide, self.data.root) end
        self.data = nil
    end

    utype = utype or self.utype
    self.utype = utype

    local fakePlate = win.fakePlate
    fakePlate:ClearAllPoints()
    fakePlate:SetPoint("CENTER", win.orbArea, "CENTER", 0, -5)

    -- Créer l'orbe (unit=nil → mode preview)
    local ok, result = pcall(SP.Orb.Create, SP.Orb, nil, fakePlate, utype)
    if not ok or not result then
        SP:Print("|cFFFF4444Preview erreur orbe : " .. tostring(result) .. "|r")
        return
    end
    local data = result

    data.root:ClearAllPoints()
    data.root:SetPoint("CENTER", win.orbArea, "CENTER", 0, 0)
    data.root:SetFrameStrata("DIALOG")
    data.root:SetFrameLevel(210)
    data.root:Show()

    -- Créer la castbar pour le mode émulation (pas de watcher : unit=nil)
    if SP.CastBar then
        pcall(SP.CastBar.Create, SP.CastBar, data)
    end

    -- Initialiser les auras
    if SP.Auras then
        pcall(SP.Auras.Init, SP.Auras, data)
    end

    -- Textes fictifs
    if data.nameText then
        data.nameText:SetText(TYPE_LABELS[utype] or utype)
        data.nameText:SetTextColor(1, 1, 1, 1)
        data.nameText:Show()
    end
    -- HP initial
    data.targetHP = self.ratio
    data.displayHP = self.ratio
    data._previewAbsHP = "166k"
    SP.Orb:UpdateFill(data, self.ratio)
    if data.hpBar then
        data.hpBar:SetMinMaxValues(0, 100)
        data.hpBar:SetValue(math.floor(self.ratio * 100))
    end
    if data.levelText then
        local cfg = SP:GetCfg(utype)
        SP:ApplyHPTextPair(data.levelText, data.hpSubText, data, nil, (cfg and cfg.hpFormat) or "percent", cfg and cfg.hp_show_percent)
    end

    self.data = data

    -- Label type + surbrillance bouton actif
    if win.typeLabel then
        win.typeLabel:SetText("▸ " .. (TYPE_LABELS[utype] or utype))
    end
    for ut, btn in pairs(win.typeButtons or {}) do
        btn:SetNormalFontObject(ut == utype and GameFontHighlight or GameFontNormal)
    end

    -- Ré-appliquer l'émulation si elle était active
    self:ApplyEmulation()
end

-------------------------------------------------------------------------------
--  API PUBLIQUE
-------------------------------------------------------------------------------
function SP.Preview:Open(utype)
    if not self.win then BuildWindow() end
    self.win:Show()
    self:Rebuild(utype or self.utype)
end

function SP.Preview:OpenBeside()
    if not self.win then BuildWindow() end

    local cfgFrame = _G["AceConfigDialog_SphereNameplatesFrame"]
        or _G["SphereNameplatesFrame"]

    if cfgFrame and cfgFrame:IsShown() then
        local cx, cy = cfgFrame:GetCenter()
        local cw     = cfgFrame:GetWidth()
        self.win:ClearAllPoints()
        self.win:SetPoint("RIGHT", UIParent, "BOTTOMLEFT",
            (cx or 400) - cw / 2 - 10,
            (cy or 300) - self.win:GetHeight() / 2)
    else
        self.win:ClearAllPoints()
        self.win:SetPoint("LEFT", UIParent, "CENTER", -430, 0)
    end

    self.win:Show()
    self:Rebuild(self.utype)
end

function SP.Preview:Close()
    if self.win then self.win:Hide() end
    if self.data then
        if self.data.castbar then pcall(SP.CastBar.Reset, SP.CastBar, self.data) end
        if self.data.root    then pcall(self.data.root.Hide, self.data.root) end
        self.data = nil
    end
end

function SP.Preview:SetHP(ratio)
    self.ratio = math.max(0, math.min(1, ratio))
    if self.data then
        SP.Orb:UpdateFill(self.data, self.ratio)
        if self.data.hpBar then
            self.data.hpBar:SetValue(math.floor(self.ratio * 100))
        end
    end
    if self.win and self.win:IsShown() and self.win.hpSlider then
        self.win.hpSlider:SetValue(self.ratio * 100)
    end
end

function SP.Preview:Refresh()
    if self.win and self.win:IsShown() then
        self:Rebuild(self.utype)
    end
end
