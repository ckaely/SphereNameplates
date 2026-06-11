-------------------------------------------------------------------------------
--  SphereNameplates / Sphere UI — MoiXP (Lot D)
--
--  Arc de progression XP / réputation autour de la sphère "Moi".
--  Rendu : disque Cooldown (swipe par défaut, PAS de SetSwipeTexture custom —
--  carré noir en 12.x, cf. CastBar) placé SOUS l'orbe : l'orbe couvre le
--  centre, seule la marge extérieure est visible → arc radial propre.
--  Pattern identique au castbar circulaire V5 (prouvé en jeu).
--
--  Modes : auto (XP si pas niveau max, sinon réputation suivie) | xp |
--  reputation | hidden. Rested XP = second arc bleu translucide en avance.
--  Toutes les lectures de valeurs sont en pcall : si une valeur est secrète
--  (Midnight), l'arc se cache proprement au lieu de crasher.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.MoiXP = SP.MoiXP or {}
local X = SP.MoiXP

local UNIT = "player"

local function DB()
    return SP.db or {}
end

local function CFG()
    return SP.GetCfg and SP:GetCfg("PLAYER_SELF") or {}
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Couleurs des modes
local COLOR_XP     = {0.58, 0.22, 0.95}   -- violet XP
local COLOR_RESTED = {0.22, 0.55, 1.00}   -- bleu rested (avance translucide)
local COLOR_REP    = {0.20, 0.78, 0.32}   -- vert réputation

function X:IsEnabled()
    local db = DB()
    local cfg = CFG()
    return db.addonEnabled ~= false
       and db.modules_moi_enabled ~= false
       and db.moi_enabled == true
       and cfg.moi_xp_ring_enabled ~= false
end

function X:GetMoiData()
    return SP.UnitFrames and SP.UnitFrames[UNIT]
end

-- ── Lectures de données (tout en pcall, nil = indisponible/secret) ──────────

function X:ResolveMode()
    local cfg = CFG()
    local mode = cfg.moi_xp_ring_mode or "auto"
    if mode == "hidden" then return nil end
    if mode == "xp" or mode == "reputation" then return mode end
    -- auto : XP tant que pertinente, sinon bascule réputation suivie
    local isMax, xpOff = false, false
    pcall(function()
        local maxL = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 80
        isMax = (UnitLevel(UNIT) or 1) >= maxL
    end)
    pcall(function()
        xpOff = (IsXPUserDisabled and IsXPUserDisabled()) == true
    end)
    if not isMax and not xpOff then return "xp" end
    return "reputation"
end

function X:GetXP()
    local ok, cur, maxv, rested = pcall(function()
        return UnitXP(UNIT) or 0, UnitXPMax(UNIT) or 0, (GetXPExhaustion and GetXPExhaustion()) or 0
    end)
    if not ok or type(maxv) ~= "number" or maxv <= 0 then return nil end
    cur = tonumber(cur) or 0
    rested = tonumber(rested) or 0
    return Clamp(cur / maxv, 0, 1), Clamp((cur + rested) / maxv, 0, 1), cur, maxv, rested
end

function X:GetReputation()
    local fdata
    local ok = pcall(function()
        if C_Reputation and C_Reputation.GetWatchedFactionData then
            fdata = C_Reputation.GetWatchedFactionData()
        end
    end)
    if not ok or type(fdata) ~= "table" or not fdata.name then return nil end
    local okMath, ratio, cur, maxv = pcall(function()
        local lo = tonumber(fdata.currentReactionThreshold) or 0
        local hi = tonumber(fdata.nextReactionThreshold) or 0
        local standing = tonumber(fdata.currentStanding) or 0
        local span = hi - lo
        if span <= 0 then return 1, 0, 0 end   -- rang max (Exalté) → arc plein
        return (standing - lo) / span, standing - lo, span
    end)
    if not okMath then return nil end
    return Clamp(ratio, 0, 1), fdata.name, fdata.reaction, cur, maxv
end

-- ── Construction de l'arc ───────────────────────────────────────────────────

local function ConfigureCooldown(cd)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    pcall(function() cd:SetDrawBling(false) end)
    pcall(function() cd:SetHideCountdownNumbers(true) end)
    pcall(function() cd:SetUseCircularEdge(true) end)
    cd:SetReverse(true)
    cd:EnableMouse(false)
end

-- Progression statique : SetCooldown ancré dans le passé + Pause.
local PROG_DURATION = 1000
local function SetProgress(cd, p)
    p = Clamp(p, 0, 0.9995)
    local now = GetTime and GetTime() or 0
    pcall(cd.SetCooldown, cd, now - p * PROG_DURATION, PROG_DURATION)
    pcall(cd.Pause, cd)
end

function X:EnsureRing()
    local data = self:GetMoiData()
    if not (data and data.root and data.orbFrame) then return nil end
    if self.ring and self.ring._data == data then return self.ring end

    -- La sphère a été reconstruite (changement de taille) : on abandonne
    -- l'ancien holder (parent caché) et on recrée sur le nouveau root.
    local rootFL = data.root:GetFrameLevel() or 10

    local holder = CreateFrame("Frame", nil, data.root)
    holder:SetFrameLevel(math.max(0, rootFL))   -- sous bgFrame (root+1) → l'orbe couvre le centre
    holder:SetPoint("CENTER", data.orbFrame, "CENTER")

    -- Arc rested (sous l'arc principal) : avance translucide
    local cdRested = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    ConfigureCooldown(cdRested)
    cdRested:SetPoint("CENTER", data.orbFrame, "CENTER")
    cdRested:Hide()

    -- Arc principal XP / réputation
    local cdMain = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    ConfigureCooldown(cdMain)
    cdMain:SetPoint("CENTER", data.orbFrame, "CENTER")
    cdMain:SetFrameLevel(cdRested:GetFrameLevel() + 1)

    -- Flash de gain : pulse d'alpha sans OnUpdate
    local flash = holder:CreateAnimationGroup()
    local a1 = flash:CreateAnimation("Alpha")
    a1:SetFromAlpha(1.0); a1:SetToAlpha(0.45); a1:SetDuration(0.10); a1:SetOrder(1)
    local a2 = flash:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.45); a2:SetToAlpha(1.0); a2:SetDuration(0.45); a2:SetOrder(2)
    a2:SetSmoothing("OUT")

    -- Hotspot tooltip : petite zone au sommet de l'arc
    local hotspot = CreateFrame("Frame", nil, holder)
    hotspot:EnableMouse(true)
    hotspot:SetScript("OnEnter", function(f) X:ShowTooltip(f) end)
    hotspot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self.ring = {
        _data = data,
        holder = holder,
        cdMain = cdMain,
        cdRested = cdRested,
        flash = flash,
        hotspot = hotspot,
    }
    holder:Hide()
    return self.ring
end

function X:Layout(ring)
    local data = ring._data
    local cfg = CFG()
    local orbSize = tonumber(data.orbSize) or tonumber(cfg.size) or 74
    local size = orbSize * Clamp(cfg.moi_xp_ring_scale, 1.05, 1.60)
    ring._size = size
    ring.holder:SetSize(size, size)
    ring.cdMain:SetSize(size, size)
    ring.cdRested:SetSize(size + 5, size + 5)
    ring.hotspot:SetSize(math.max(18, size * 0.22), math.max(10, size * 0.10))
    ring.hotspot:ClearAllPoints()
    ring.hotspot:SetPoint("CENTER", data.orbFrame, "CENTER", 0, size * 0.5)
end

-- ── Update principal ────────────────────────────────────────────────────────

function X:Update()
    if not self:IsEnabled() then
        if self.ring and self.ring.holder then self.ring.holder:Hide() end
        return
    end
    local ring = self:EnsureRing()
    if not ring then return end
    local mode = self:ResolveMode()
    if not mode then
        ring.holder:Hide()
        return
    end

    local cfg = CFG()
    local alpha = Clamp(cfg.moi_xp_ring_alpha, 0, 1)
    self:Layout(ring)

    if mode == "xp" then
        local p, pRested = self:GetXP()
        if not p then ring.holder:Hide() return end
        SetProgress(ring.cdMain, p)
        ring.cdMain:SetSwipeColor(COLOR_XP[1], COLOR_XP[2], COLOR_XP[3], alpha)
        ring.cdMain:Show()
        if pRested and pRested > p + 0.002 then
            SetProgress(ring.cdRested, pRested)
            ring.cdRested:SetSwipeColor(COLOR_RESTED[1], COLOR_RESTED[2], COLOR_RESTED[3], alpha * 0.40)
            ring.cdRested:Show()
        else
            ring.cdRested:Hide()
        end
        ring._mode = "xp"
    else
        local p, name = self:GetReputation()
        if not p then ring.holder:Hide() return end
        SetProgress(ring.cdMain, p)
        ring.cdMain:SetSwipeColor(COLOR_REP[1], COLOR_REP[2], COLOR_REP[3], alpha)
        ring.cdMain:Show()
        ring.cdRested:Hide()
        ring._mode = "reputation"
        ring._repName = name
    end
    ring.holder:Show()
end

function X:FlashGain()
    local ring = self.ring
    if ring and ring.holder and ring.holder:IsShown() and ring.flash then
        pcall(ring.flash.Stop, ring.flash)
        pcall(ring.flash.Play, ring.flash)
    end
end

-- ── Tooltip ─────────────────────────────────────────────────────────────────

function X:ShowTooltip(owner)
    if not GameTooltip then return end
    local ring = self.ring
    if not (ring and ring.holder and ring.holder:IsShown()) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(function()
        if ring._mode == "xp" then
            local p, _, cur, maxv, rested = X:GetXP()
            GameTooltip:SetText("Expérience", 0.75, 0.45, 1.0)
            if p then
                GameTooltip:AddDoubleLine("Progression",
                    string.format("%d / %d (%d%%)", cur, maxv, math.floor(p * 100 + 0.5)),
                    0.8, 0.8, 0.8, 1, 1, 1)
                if rested and rested > 0 then
                    GameTooltip:AddDoubleLine("Repos",
                        string.format("+%d", rested), 0.8, 0.8, 0.8,
                        COLOR_RESTED[1], COLOR_RESTED[2], COLOR_RESTED[3])
                end
            end
        else
            local p, name, reaction, cur, maxv = X:GetReputation()
            GameTooltip:SetText(tostring(name or "Réputation"), 0.3, 0.85, 0.4)
            if reaction and _G["FACTION_STANDING_LABEL" .. tostring(reaction)] then
                GameTooltip:AddLine(_G["FACTION_STANDING_LABEL" .. tostring(reaction)], 0.9, 0.9, 0.9)
            end
            if p and cur and maxv and maxv > 0 then
                GameTooltip:AddDoubleLine("Progression",
                    string.format("%d / %d (%d%%)", cur, maxv, math.floor(p * 100 + 0.5)),
                    0.8, 0.8, 0.8, 1, 1, 1)
            end
        end
    end)
    if not ok then
        GameTooltip:SetText("Progression")
        GameTooltip:AddLine("Valeurs protégées (Midnight)", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- ── Events ──────────────────────────────────────────────────────────────────

function X:EnsureEventFrame()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "UPDATE_EXHAUSTION",
        "UPDATE_FACTION",
        "ENABLE_XP_GAIN",
        "DISABLE_XP_GAIN",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event)
        X:Update()
        if event == "PLAYER_XP_UPDATE" or event == "UPDATE_FACTION" then
            X:FlashGain()
        end
    end)
end

function X:Init()
    self:EnsureEventFrame()
    if C_Timer then
        C_Timer.After(0.50, function() X:Update() end)
        C_Timer.After(2.00, function() X:Update() end)
    end
end

function X:Refresh()
    self:Update()
end
