-------------------------------------------------------------------------------
--  SphereNameplates / Sphere UI — TargetFrame (Lot G)
--
--  UnitFrames fixes "Cible" et "Cible de la cible", construites sur le même
--  pipeline que Moi : SP.Orb:Create + CastBar + Auras, anchor déplaçable,
--  bouton secure (clic gauche = cibler, clic droit = menu Blizzard).
--
--  Règles reprises de Moi/DEC-020 :
--  - L'anchor est ANCÊTRE du bouton secure → protégé : aucune mutation
--    (SetPoint/SetShown/...) en combat; flags pending + PLAYER_REGEN_ENABLED.
--  - Le root de l'orbe (enfant non-ancêtre) reste librement manipulable.
--  - RegisterUnitWatch gère l'affichage du bouton secure même en combat;
--    le rendu insecure suit via PLAYER_TARGET_CHANGED / UNIT_TARGET.
--  - Toute valeur Unit* passe par pcall; jamais d'arithmétique sur du brut.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.TargetUF = SP.TargetUF or {}
local T = SP.TargetUF

local function DB()
    return SP.db or {}
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function IsEditMode()
    return DB().snp_edit_mode == true
end

local function SafeUnitExists(unit)
    local ok, res = pcall(function() return UnitExists(unit) and true or false end)
    return ok and res == true
end

-- ── Définition des deux frames ──────────────────────────────────────────────

local FRAMES = {
    {
        key = "target", unit = "target", utype = "TARGET",
        anchorName = "SPTargetAnchor", secureName = "SPTargetSecureButton",
        label = "Cible",
        dbEnabled = "tuf_target_enabled", dbX = "tuf_target_x", dbY = "tuf_target_y",
        dbScale = "tuf_target_scale", dbLocked = "tuf_target_locked",
        defX = 280, defY = -170,
    },
    {
        key = "tot", unit = "targettarget", utype = "TARGET_TARGET",
        anchorName = "SPToTAnchor", secureName = "SPToTSecureButton",
        label = "Cible de cible",
        dbEnabled = "tuf_tot_enabled", dbX = "tuf_tot_x", dbY = "tuf_tot_y",
        dbScale = "tuf_tot_scale", dbLocked = "tuf_tot_locked",
        defX = 470, defY = -120,
    },
}

function T:IsEnabled(fdef)
    local db = DB()
    if db.addonEnabled == false or db.modules_moi_enabled == false then return false end
    return db[fdef.dbEnabled] ~= false
end

function T:GetCfg(fdef)
    return SP.GetCfg and SP:GetCfg(fdef.utype) or {}
end

-- ── Anchor + bouton secure ──────────────────────────────────────────────────

function T:SaveAnchorPosition(fdef, f)
    local ok, cx, cy, ux, uy = pcall(function()
        local a, b = f:GetCenter()
        local c, d = UIParent:GetCenter()
        return a, b, c, d
    end)
    if ok and cx and cy and ux and uy and SP.db then
        local x, y = cx - ux, cy - uy
        if SP.ActionBars and SP.ActionBars.SnapPoint and IsEditMode() then
            x, y = SP.ActionBars:SnapPoint(x, y)
        end
        SP.db[fdef.dbX] = math.floor(x + 0.5)
        SP.db[fdef.dbY] = math.floor(y + 0.5)
    end
end

function T:EnsureAnchor(fdef)
    local st = self.frames[fdef.key]
    if st.anchor then return st.anchor end

    local anchor = CreateFrame("Button", fdef.anchorName, UIParent)
    anchor:SetFrameStrata("HIGH")
    anchor:SetFrameLevel(20)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor._isSPFrame = true

    anchor:SetScript("OnDragStart", function(f)
        if (DB()[fdef.dbLocked] == true and not IsEditMode()) or IsCombatLocked() then return end
        f:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        T:SaveAnchorPosition(fdef, f)
    end)

    -- Surcouche mode édition (drag + étiquette), même langage que Moi/barres
    local edit = CreateFrame("Frame", nil, anchor)
    edit:SetAllPoints()
    edit:SetFrameLevel(anchor:GetFrameLevel() + 50)
    edit:EnableMouse(false)
    edit.bg = edit:CreateTexture(nil, "BACKGROUND")
    edit.bg:SetAllPoints()
    edit.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    edit.bg:SetVertexColor(0.05, 0.25, 0.22, 0.18)
    edit.label = edit:CreateFontString(nil, "OVERLAY")
    edit.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    edit.label:SetTextColor(0.45, 1.0, 0.78, 1)
    edit.label:SetPoint("TOP", anchor, "TOP", 0, -4)
    edit.label:SetText(fdef.label)
    edit:Hide()
    anchor.editFrame = edit

    st.anchor = anchor
    return anchor
end

function T:EnsureSecureButton(fdef)
    local st = self.frames[fdef.key]
    if st.secureBtn then return st.secureBtn end
    local anchor = self:EnsureAnchor(fdef)
    local btn = CreateFrame("Button", fdef.secureName, anchor, "SecureUnitButtonTemplate")
    btn:SetAllPoints(anchor)
    btn:SetFrameLevel((anchor:GetFrameLevel() or 20) + 30)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("unit", fdef.unit)
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")
    btn._isSPFrame = true
    -- Drag forwardé (déverrouillé/édition) — scripts insecure, clic secure intact
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        local a = st.anchor
        if not a then return end
        if (DB()[fdef.dbLocked] == true and not IsEditMode()) or IsCombatLocked() then return end
        pcall(a.StartMoving, a)
    end)
    btn:SetScript("OnDragStop", function()
        local a = st.anchor
        if not a then return end
        pcall(a.StopMovingOrSizing, a)
        T:SaveAnchorPosition(fdef, a)
    end)
    st.secureBtn = btn
    return btn
end

function T:ApplyAnchor(fdef)
    if IsCombatLocked() then
        self._pendingAnchor = true
        return
    end
    local st = self.frames[fdef.key]
    local anchor = self:EnsureAnchor(fdef)
    local db = DB()
    local cfg = self:GetCfg(fdef)
    local size = tonumber(cfg.size) or 74
    local enabled = self:IsEnabled(fdef)

    anchor:ClearAllPoints()
    anchor:SetSize(size, size)
    anchor:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(db[fdef.dbX]) or fdef.defX, tonumber(db[fdef.dbY]) or fdef.defY)
    anchor:SetScale(Clamp(db[fdef.dbScale], 0.5, 2.0))
    anchor:EnableMouse(IsEditMode() and enabled)
    anchor:SetShown(enabled)
    if anchor.editFrame then
        anchor.editFrame:SetShown(IsEditMode() and enabled)
    end

    -- Bouton secure : RegisterUnitWatch le montre quand l'unité existe.
    local btn = self:EnsureSecureButton(fdef)
    if enabled and not IsEditMode() then
        btn:EnableMouse(true)
        if RegisterUnitWatch and not st._watching then
            pcall(RegisterUnitWatch, btn)
            st._watching = true
        end
    else
        if UnregisterUnitWatch and st._watching then
            pcall(UnregisterUnitWatch, btn)
            st._watching = false
        end
        btn:EnableMouse(false)
        btn:Hide()
    end
end

-- ── Masquage des frames Blizzard cible / cible de cible ─────────────────────

local function BlizzardTargetFrames()
    local out = {}
    if TargetFrame then out[#out + 1] = TargetFrame end
    if TargetFrameToT then out[#out + 1] = TargetFrameToT end
    return out
end

function T:ApplyBlizzardTargetFrame()
    local hide = DB().tuf_hide_blizzard_target ~= false
        and (self:IsEnabled(FRAMES[1]) or self:IsEnabled(FRAMES[2]))
    if IsCombatLocked() then
        self._pendingBlizzard = true
        return
    end
    for _, frame in ipairs(BlizzardTargetFrames()) do
        if hide then
            frame._snpTufHidden = true
            -- Kill DÉFINITIF : Blizzard re-Show la frame sur PLAYER_TARGET_CHANGED
            -- (y compris en combat où notre Hide serait bloqué → "parfois visible").
            -- Sans ses events, elle ne réapparaît plus jamais (pattern ElvUI/SUF).
            -- Réactivation = /reload après désactivation de l'option.
            if not frame._snpTufKilled then
                frame._snpTufKilled = true
                pcall(frame.UnregisterAllEvents, frame)
                pcall(frame.HookScript, frame, "OnShow", function(f)
                    if f._snpTufHidden and not IsCombatLocked() then
                        pcall(f.Hide, f)
                    end
                end)
            end
            pcall(frame.Hide, frame)
        else
            frame._snpTufHidden = nil
        end
    end
end

-- ── Données orbe ─────────────────────────────────────────────────────────────

function T:Destroy(fdef)
    local st = self.frames[fdef.key]
    local data = st.data
    if data then
        if SP.CastBar and data.castbar then pcall(SP.CastBar.Reset, SP.CastBar, data) end
        if SP.Auras then pcall(SP.Auras.RemoveAll, SP.Auras, data) end
        if data.root then data.root:Hide() end
    end
    SP.UnitFrames[fdef.unit] = nil
    SP.ActiveOrbData["unitframe:" .. fdef.unit] = nil
    st.data = nil
end

function T:EnsureData(fdef)
    local st = self.frames[fdef.key]
    if not self:IsEnabled(fdef) then
        self:Destroy(fdef)
        return nil
    end
    self:ApplyAnchor(fdef)
    local cfg = self:GetCfg(fdef)
    if st.data and st.data.orbSize ~= (cfg.size or 74) then
        self:Destroy(fdef)
    end
    if st.data then return st.data end

    local anchor = self:EnsureAnchor(fdef)
    local ok, data = pcall(SP.Orb.Create, SP.Orb, fdef.unit, anchor, fdef.utype)
    if not ok or not data then
        if SP.Log then SP.Log:Error("TargetUF", "Orb.Create failed (" .. fdef.key .. "): " .. tostring(data)) end
        return nil
    end

    data.unit = fdef.unit
    data.unitType = fdef.utype
    data.plate = anchor
    data._isUnitFrame = true
    data._packRank = 3
    data._fadeAlpha = 1
    data._nameDistanceAlpha = 1
    data.root._isSPFrame = true
    pcall(data.root.SetIgnoreParentAlpha, data.root, true)

    SP.UnitFrames[fdef.unit] = data
    SP.ActiveOrbData["unitframe:" .. fdef.unit] = data
    st.data = data

    if cfg.auras_enabled ~= false and SP.Auras then
        pcall(SP.Auras.Init, SP.Auras, data)
    end
    if cfg.castbar_enabled ~= false and SP.CastBar then
        local okCB, cb = pcall(SP.CastBar.Create, SP.CastBar, data)
        if okCB and cb then data.castbar = cb end
    end
    return data
end

-- Rafraîchit tout le rendu d'une frame pour l'unité courante.
-- forceNewUnit=true au changement de cible : purge classe/cast/auras.
function T:RefreshUnit(fdef, forceNewUnit)
    local st = self.frames[fdef.key]
    local data = self:EnsureData(fdef)
    if not data then return end

    local exists = SafeUnitExists(fdef.unit)
    data.root:SetShown(exists)
    if not exists then
        if forceNewUnit and data.castbar and SP.CastBar then
            pcall(SP.CastBar.Reset, SP.CastBar, data)
        end
        return
    end

    if forceNewUnit then
        -- Nouvelle unité derrière le même token : purger ce qui colle à l'ancienne
        data._cachedClass = nil
        data.targetHP = nil
        data.displayHP = nil
        data._lastFillR, data._lastFillG, data._lastFillB = nil, nil, nil
        if data.castbar and SP.CastBar then
            pcall(SP.CastBar.Reset, SP.CastBar, data)
            -- Le poll 0.20s interne du CastBar raccroche un cast déjà en cours
        end
    end

    data._inCombat = (SP.InCombat == true)
    pcall(SP.Orb.SoftUpdate, SP.Orb, data, fdef.unit)
    pcall(SP.UpdateHealth, SP, fdef.unit, data)
    pcall(SP.Orb.UpdateName, SP.Orb, data, fdef.unit)
    pcall(SP.Orb.UpdateLevelText, SP.Orb, data, fdef.unit)
    pcall(SP.Orb.RefreshUnitColors, SP.Orb, data, fdef.unit, nil)
    if SP.Orb.UpdateRaidMark then pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, fdef.unit) end
    local cfg = self:GetCfg(fdef)
    if cfg.auras_enabled ~= false and SP.Auras and data.auraIcons then
        pcall(SP.Auras.UpdateUnit, SP.Auras, data, fdef.unit, nil)
    end
    pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, cfg)
end

function T:RefreshAllFrames(forceNewUnit)
    for _, fdef in ipairs(FRAMES) do
        self:RefreshUnit(fdef, forceNewUnit)
    end
    self:ApplyBlizzardTargetFrame()
end

-- ── Ticks (branchés dans l'OnUpdate Core, comme Moi) ────────────────────────

function T:TickCast(now)
    for _, fdef in ipairs(FRAMES) do
        local data = self.frames[fdef.key].data
        if data and data.castbar and data.root and data.root:IsShown() and SP.CastBar then
            pcall(SP.CastBar.Tick, SP.CastBar, data, now)
        end
    end
end

function T:TickHealth()
    for _, fdef in ipairs(FRAMES) do
        local data = self.frames[fdef.key].data
        if data and data.targetHP ~= nil and data.root and data.root:IsShown() and SP.Orb then
            local cfg = self:GetCfg(fdef)
            local k = math.min(0.90, (cfg.hp_lerp_speed or 10.0) * 0.018)
            local target = data.targetHP
            local display = data.displayHP or target
            local diff = target - display
            if math.abs(diff) > 0.0005 then
                data.displayHP = display + diff * k
            else
                data.displayHP = target
            end
            pcall(SP.Orb.UpdateFill, SP.Orb, data, data.displayHP)
        end
    end
end

function T:Poll()
    for _, fdef in ipairs(FRAMES) do
        local st = self.frames[fdef.key]
        if self:IsEnabled(fdef) then
            local data = st.data or self:EnsureData(fdef)
            if data and SafeUnitExists(fdef.unit) then
                data.root:Show()
                pcall(SP.UpdateHealth, SP, fdef.unit, data)
                pcall(SP.Orb.UpdateLevelText, SP.Orb, data, fdef.unit)
                local cfg = self:GetCfg(fdef)
                if cfg.auras_enabled ~= false and SP.Auras and data.auraIcons then
                    pcall(SP.Auras.UpdateUnit, SP.Auras, data, fdef.unit, nil)
                end
            elseif data then
                data.root:Hide()
            end
        else
            self:Destroy(fdef)
        end
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

function T:EnsureEventFrame()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f

    -- Events unitaires sur les tokens target/targettarget
    for _, fdef in ipairs(FRAMES) do
        for _, ev in ipairs({"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_AURA", "UNIT_LEVEL", "UNIT_FACTION"}) do
            local ok = pcall(f.RegisterUnitEvent, f, ev, fdef.unit)
            if not ok then pcall(f.RegisterEvent, f, ev) end
        end
    end
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "UNIT_TARGET",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "RAID_TARGET_UPDATE",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end

    f:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            T:RefreshUnit(FRAMES[1], true)
            T:RefreshUnit(FRAMES[2], true)
            return
        end
        if event == "UNIT_TARGET" then
            -- La cible de la cible change quand la cible change la sienne
            if unit == "target" then T:RefreshUnit(FRAMES[2], true) end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            SP.InCombat = true
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            SP.InCombat = false
            if T._pendingAnchor or T._pendingBlizzard then
                T._pendingAnchor = nil
                T._pendingBlizzard = nil
                T:RefreshAllFrames(false)
                for _, fdef in ipairs(FRAMES) do T:ApplyAnchor(fdef) end
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            if C_Timer then C_Timer.After(0.40, function() T:RefreshAllFrames(true) end) end
            return
        end
        if event and event:match("^UNIT_") then
            for _, fdef in ipairs(FRAMES) do
                if unit == fdef.unit then
                    T:RefreshUnit(fdef, false)
                end
            end
            return
        end
        -- RAID_TARGET_UPDATE et divers : refresh léger
        T:RefreshAllFrames(false)
    end)
end

function T:Init()
    self.frames = self.frames or { target = {}, tot = {} }
    self:EnsureEventFrame()
    self:RefreshAllFrames(true)
end

function T:Refresh()
    if not self.frames then self.frames = { target = {}, tot = {} } end
    for _, fdef in ipairs(FRAMES) do
        -- Changement de taille → EnsureData détruit/recrée proprement
        self:EnsureData(fdef)
    end
    self:RefreshAllFrames(true)
end
