-------------------------------------------------------------------------------
--  SphereNameplates / Sphere UI — MoiXP (Lot D, v5)
--
--  Anneau XP / réputation autour de la sphère "Moi".
--
--  v5 (design utilisateur) :
--  - RAIL : texture media/experience_circle.png (anneau métallique premium)
--    teinté selon l'état — VIOLET en xp normal, BLEU si rested, VERT réputation.
--  - PROGRESSION : arc doré/blanc façon aiguille de montre (départ 12h, sens
--    horaire), rendu par 64 segments rotatés quasi-jointifs (technique V8).
--  - GAIN : la progression avance en ANIMATION SMOOTH (lerp via Moi:TickHealth).
--  - LEVEL-UP : l'anneau s'illumine ~3 s (pulse doré) pour marquer le coup.
--
--  Toutes les lectures de valeurs passent par CleanNum (UntaintNum durci) :
--  valeur secrète → anneau caché proprement, jamais de crash.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.MoiXP = SP.MoiXP or {}
local X = SP.MoiXP

local UNIT = "player"
local SEG_COUNT = 64
local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
local RAIL_TEX = "Interface\\AddOns\\SphereNameplates\\media\\experience_circle.png"

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

local function CleanNum(raw)
    if raw == nil then return nil end
    if SP.UntaintNum then return SP:UntaintNum(raw) end
    local ok, n = pcall(function() return tonumber(tostring(raw)) end)
    return ok and n or nil
end

-- Teintes du rail selon l'état (convention Blizzard)
local RAIL_XP     = {0.56, 0.28, 0.92}   -- violet : xp normale
local RAIL_RESTED = {0.28, 0.52, 1.00}   -- bleu : repos actif
local RAIL_REP    = {0.22, 0.72, 0.34}   -- vert : réputation
-- Progression
local FILL_GOLD   = {1.00, 0.84, 0.38}   -- doré/blanc : arc de progression
local FILL_REP    = {0.55, 1.00, 0.62}   -- vert clair : progression réputation
local LEAD_RESTED = {0.45, 0.70, 1.00}   -- avance rested translucide

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

-- ── Lectures de données ──────────────────────────────────────────────────────

function X:ResolveMode()
    local cfg = CFG()
    local mode = cfg.moi_xp_ring_mode or "auto"
    if mode == "hidden" then return nil end
    if mode == "xp" or mode == "reputation" then return mode end
    local isMax, xpOff = false, false
    pcall(function()
        local maxL = CleanNum(GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 80
        local lvl  = CleanNum(UnitLevel(UNIT)) or 1
        isMax = lvl >= maxL
    end)
    pcall(function()
        xpOff = (IsXPUserDisabled and IsXPUserDisabled()) == true
    end)
    if not isMax and not xpOff then return "xp" end
    return "reputation"
end

function X:GetXP()
    local okC, rawCur = pcall(UnitXP, UNIT)
    local okM, rawMax = pcall(UnitXPMax, UNIT)
    if not (okC and okM) then return nil end
    local cur  = CleanNum(rawCur)
    local maxv = CleanNum(rawMax)
    if not cur or not maxv or maxv <= 0 then return nil end
    local rested = 0
    local okR, rawRested = pcall(function()
        return GetXPExhaustion and GetXPExhaustion() or 0
    end)
    if okR then rested = CleanNum(rawRested) or 0 end
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
    local lo       = CleanNum(fdata.currentReactionThreshold) or 0
    local hi       = CleanNum(fdata.nextReactionThreshold) or 0
    local standing = CleanNum(fdata.currentStanding) or 0
    local span = hi - lo
    if span <= 0 then
        return 1, fdata.name, fdata.reaction, 0, 0
    end
    return Clamp((standing - lo) / span, 0, 1), fdata.name, fdata.reaction, standing - lo, span
end

-- ── Construction ─────────────────────────────────────────────────────────────

function X:EnsureRing()
    local data = self:GetMoiData()
    if not (data and data.root and data.orbFrame) then return nil end
    if self.ring and self.ring._data == data then return self.ring end

    local holder = CreateFrame("Frame", nil, data.root)
    holder:SetFrameLevel((data.root:GetFrameLevel() or 1) + 31)
    holder:SetPoint("CENTER", data.orbFrame, "CENTER")

    -- Rail : l'anneau métallique fourni, teinté selon l'état
    local rail = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    rail:SetTexture(RAIL_TEX)
    rail:SetVertexColor(RAIL_XP[1], RAIL_XP[2], RAIL_XP[3], 1)

    -- Progression : segments rotatés sur le rayon du rail
    local segs = {}
    for i = 1, SEG_COUNT do
        local fill = holder:CreateTexture(nil, "ARTWORK", nil, 4)
        fill:SetTexture(WHITE_TEX)
        fill:SetAlpha(0)
        segs[i] = fill
    end

    -- Pulse level-up : illumination en boucle, stoppée après ~3 s
    local levelPulse = holder:CreateAnimationGroup()
    levelPulse:SetLooping("REPEAT")
    local lp1 = levelPulse:CreateAnimation("Alpha")
    lp1:SetFromAlpha(1.0); lp1:SetToAlpha(0.55); lp1:SetDuration(0.35); lp1:SetOrder(1)
    local lp2 = levelPulse:CreateAnimation("Alpha")
    lp2:SetFromAlpha(0.55); lp2:SetToAlpha(1.0); lp2:SetDuration(0.35); lp2:SetOrder(2)

    -- Flash de gain léger (one-shot)
    local flash = holder:CreateAnimationGroup()
    local a1 = flash:CreateAnimation("Alpha")
    a1:SetFromAlpha(1.0); a1:SetToAlpha(0.55); a1:SetDuration(0.08); a1:SetOrder(1)
    local a2 = flash:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.55); a2:SetToAlpha(1.0); a2:SetDuration(0.40); a2:SetOrder(2)
    a2:SetSmoothing("OUT")

    -- Hotspot tooltip en haut de l'anneau
    local hotspot = CreateFrame("Frame", nil, holder)
    hotspot:EnableMouse(true)
    hotspot:SetScript("OnEnter", function(f) X:ShowTooltip(f) end)
    hotspot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self.ring = {
        _data = data,
        holder = holder,
        rail = rail,
        segs = segs,
        flash = flash,
        levelPulse = levelPulse,
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
    if ring._size == size then return end
    ring._size = size

    ring.holder:SetSize(size, size)
    ring.rail:ClearAllPoints()
    ring.rail:SetSize(size, size)
    ring.rail:SetPoint("CENTER", ring.holder, "CENTER")

    -- L'anneau de la texture occupe ~87 %% du canvas → rayon des segments calé dessus
    local radius = size * 0.435
    local segLen = math.max(3, (2 * math.pi * radius / SEG_COUNT) * 0.96)
    local segThick = math.max(2.5, size * 0.035)
    for i, fill in ipairs(ring.segs) do
        local angle = (math.pi * 0.5) - ((i - 0.5) / SEG_COUNT) * 2 * math.pi
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        fill:SetSize(segLen, segThick)
        fill:ClearAllPoints()
        fill:SetPoint("CENTER", ring.holder, "CENTER", x, y)
        fill:SetRotation(-(angle - math.pi * 0.5))
    end

    ring.hotspot:SetSize(size * 0.6, math.max(14, size * 0.15))
    ring.hotspot:ClearAllPoints()
    ring.hotspot:SetPoint("CENTER", ring.holder, "CENTER", 0, radius)
end

-- Peint les segments : litCount pleins (dégradé vers la tête), lead translucide.
local function PaintFill(ring, litCount, leadCount, mainColor, leadColor, alpha)
    ring._litCount = litCount
    for i, fill in ipairs(ring.segs) do
        if i <= litCount then
            local k = 0.78 + 0.35 * (i / math.max(1, litCount))
            fill:SetVertexColor(
                math.min(1, mainColor[1] * k),
                math.min(1, mainColor[2] * k),
                math.min(1, mainColor[3] * k), 1)
            fill:SetAlpha(alpha)
        elseif leadColor and i <= leadCount then
            fill:SetVertexColor(leadColor[1], leadColor[2], leadColor[3], 1)
            fill:SetAlpha(alpha * 0.38)
        else
            fill:SetAlpha(0)
        end
    end
end

local function RepaintFromDisplay(ring, displayP)
    local lit  = math.floor(Clamp(displayP, 0, 1) * SEG_COUNT + 0.5)
    local lead = ring._leadP and math.floor(Clamp(ring._leadP, 0, 1) * SEG_COUNT + 0.5) or lit
    PaintFill(ring, lit, lead, ring._mainColor or FILL_GOLD,
        ring._leadColor, ring._alpha or 0.9)
end

-- ── Animation smooth (appelée ~60 FPS par Moi:TickHealth) ───────────────────

function X:Tick()
    local ring = self.ring
    if not (ring and ring.holder and ring.holder:IsShown()) then return end
    local target = self._targetP
    if target == nil then return end
    local disp = self._displayP
    if disp == nil then return end
    local diff = target - disp
    if math.abs(diff) > 0.0004 then
        disp = disp + diff * 0.07   -- progression douce (~1 s pour un gros gain)
        self._displayP = disp
        local lit = math.floor(Clamp(disp, 0, 1) * SEG_COUNT + 0.5)
        if lit ~= ring._litCount then
            RepaintFromDisplay(ring, disp)
        end
    elseif disp ~= target then
        self._displayP = target
        RepaintFromDisplay(ring, target)
    end
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

    local railColor, p, leadP
    if mode == "xp" then
        local xpP, restedP, _, _, rested = self:GetXP()
        if not xpP then ring.holder:Hide() return end
        p = xpP
        leadP = (restedP and restedP > xpP + 0.002) and restedP or nil
        railColor = (rested and rested > 0) and RAIL_RESTED or RAIL_XP
        ring._mainColor = FILL_GOLD
        ring._leadColor = leadP and LEAD_RESTED or nil
        ring._mode = "xp"
    else
        local repP, name = self:GetReputation()
        if not repP then ring.holder:Hide() return end
        p = repP
        leadP = nil
        railColor = RAIL_REP
        ring._mainColor = FILL_REP
        ring._leadColor = nil
        ring._mode = "reputation"
        ring._repName = name
    end

    ring._alpha = alpha
    ring._leadP = leadP
    -- Rail teinté (sauf pendant l'illumination level-up qui force le doré)
    if not self._levelUpActive then
        ring.rail:SetVertexColor(railColor[1], railColor[2], railColor[3], 1)
        ring.rail:SetAlpha(math.min(1, alpha * 0.95))
    end

    -- Cible de progression : le Tick anime _displayP vers _targetP.
    self._targetP = p
    if self._displayP == nil then
        self._displayP = p          -- premier affichage : pas d'animation
        RepaintFromDisplay(ring, p)
    elseif self._displayP > p + 0.01 then
        -- Régression (level-up : la barre repart de 0) → snap propre
        self._displayP = 0
    end
    ring.holder:Show()
end

function X:FlashGain()
    local ring = self.ring
    if ring and ring.holder and ring.holder:IsShown() and ring.flash and not self._levelUpActive then
        pcall(ring.flash.Stop, ring.flash)
        pcall(ring.flash.Play, ring.flash)
    end
end

-- Illumination de passage de niveau : rail doré pulsé pendant ~3 s.
function X:LevelUpFlash()
    local ring = self.ring
    if not (ring and ring.holder) then return end
    self._levelUpActive = true
    ring.rail:SetVertexColor(1.0, 0.86, 0.30, 1)
    ring.rail:SetAlpha(1)
    pcall(ring.levelPulse.Play, ring.levelPulse)
    if C_Timer then
        C_Timer.After(3.0, function()
            X._levelUpActive = nil
            if X.ring and X.ring.levelPulse then pcall(X.ring.levelPulse.Stop, X.ring.levelPulse) end
            if X.ring and X.ring.holder then X.ring.holder:SetAlpha(1) end
            X:Update()
        end)
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
                        RAIL_RESTED[1], RAIL_RESTED[2], RAIL_RESTED[3])
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
        if event == "PLAYER_LEVEL_UP" then
            X:LevelUpFlash()
        end
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
