-------------------------------------------------------------------------------
--  SphereNameplates / Sphere UI — MoiXP (Lot D, v2)
--
--  Arc de progression XP / réputation autour de la sphère "Moi".
--
--  v2 (BUG-040) : l'approche disque Cooldown rendait un CARRÉ NOIR autour de
--  l'orbe (swipe par défaut carré en 12.x — AP-24 confirmé). Remplacée par un
--  anneau de SEGMENTS (perles ping4) positionnés par trigonométrie : départ en
--  haut (12h), sens horaire. Zéro Cooldown, zéro OnUpdate, textures pures.
--
--  Violet = XP · perles bleues translucides = avance rested · vert = réputation.
--  Toutes les valeurs passent par SP:UntaintNum (secret numbers Midnight).
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.MoiXP = SP.MoiXP or {}
local X = SP.MoiXP

local UNIT = "player"
local RING_TEX = nil   -- résolu au runtime : SP.SHADOW_CIRCLE_PATH

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

-- Échappe une valeur potentiellement secrète vers un nombre Lua propre.
local function CleanNum(raw)
    if raw == nil then return nil end
    if SP.UntaintNum then return SP:UntaintNum(raw) end
    local ok, n = pcall(function() return tonumber(tostring(raw)) end)
    return ok and n or nil
end

local COLOR_XP     = {0.58, 0.22, 0.95}
local COLOR_RESTED = {0.25, 0.55, 1.00}
local COLOR_REP    = {0.20, 0.78, 0.32}
local COLOR_OFF    = {0.10, 0.09, 0.14}

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

-- ── Lectures de données — UntaintNum sur tout ───────────────────────────────

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
        return 1, fdata.name, fdata.reaction, 0, 0   -- rang max → anneau plein
    end
    return Clamp((standing - lo) / span, 0, 1), fdata.name, fdata.reaction, standing - lo, span
end

-- ── Construction de l'anneau lisse (v3) ─────────────────────────────────────
-- Même langage visuel que l'anneau ressource : texture shadowcircle pleine,
-- découpée par un masque vertical BOTTOM (pattern BUG-038, prouvé en jeu).
-- L'anneau se remplit de bas en haut avec un DÉGRADÉ vertical ; une piste
-- sombre rend la portion restante lisible. Rested = remplissage translucide
-- en avance, sous le fill principal.

-- Texture de l'anneau XP : ping4 = CERCLE FIN ET NET (pas le shadow circle
-- épais/flou réservé à la bordure de classe et à l'anneau ressource).
-- Distinction visuelle immédiate : XP = trait fin, ressources = anneau épais.
local XP_RING_TEX = "Interface\\Cooldown\\ping4"

local function MakeRingLayer(holder, sub)
    local tex = holder:CreateTexture(nil, "ARTWORK", nil, sub)
    tex:SetTexture(XP_RING_TEX)
    tex:SetBlendMode("ADD")
    local mask = holder:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pcall(tex.AddMaskTexture, tex, mask)
    return { tex = tex, mask = mask }
end

-- Dégradé vertical (sombre en bas → vif en haut). Fallback couleur unie.
local function ApplyGradient(tex, color, alpha)
    local r, g, b = color[1], color[2], color[3]
    local ok = pcall(function()
        tex:SetGradient("VERTICAL",
            CreateColor(r * 0.45, g * 0.45, b * 0.45, alpha),
            CreateColor(math.min(1, r * 1.25), math.min(1, g * 1.25), math.min(1, b * 1.25), alpha))
    end)
    if not ok then
        tex:SetVertexColor(r, g, b, 1)
        tex:SetAlpha(alpha)
    end
end

function X:EnsureRing()
    local data = self:GetMoiData()
    if not (data and data.root and data.orbFrame) then return nil end
    if self.ring and self.ring._data == data then return self.ring end

    -- Sphère reconstruite (changement de taille) : on recrée sur le nouveau root.
    local holder = CreateFrame("Frame", nil, data.root)
    -- root+31 : PREMIER PLAN, juste au-dessus de l'anneau ressource (+30).
    holder:SetFrameLevel((data.root:GetFrameLevel() or 1) + 31)
    holder:SetPoint("CENTER", data.orbFrame, "CENTER")

    -- Piste : cercle fin discret (la révolution complète, portion non gagnée)
    local track = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    track:SetTexture(XP_RING_TEX)
    track:SetBlendMode("ADD")
    track:SetVertexColor(0.30, 0.28, 0.38, 1)
    track:SetAlpha(0.22)

    local rested = MakeRingLayer(holder, 3)   -- avance rested, sous le fill
    local fill   = MakeRingLayer(holder, 4)   -- progression principale

    -- Flash de gain (AnimationGroup, pas d'OnUpdate)
    local flash = holder:CreateAnimationGroup()
    local a1 = flash:CreateAnimation("Alpha")
    a1:SetFromAlpha(1.0); a1:SetToAlpha(0.45); a1:SetDuration(0.10); a1:SetOrder(1)
    local a2 = flash:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.45); a2:SetToAlpha(1.0); a2:SetDuration(0.45); a2:SetOrder(2)
    a2:SetSmoothing("OUT")

    -- Hotspot tooltip : bande supérieure de l'anneau, large et facile à viser
    local hotspot = CreateFrame("Frame", nil, holder)
    hotspot:EnableMouse(true)
    hotspot:SetScript("OnEnter", function(f) X:ShowTooltip(f) end)
    hotspot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self.ring = {
        _data = data,
        holder = holder,
        track = track,
        fill = fill,
        rested = rested,
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
    if ring._size == size then return end
    ring._size = size
    ring.holder:SetSize(size, size)
    ring.track:ClearAllPoints()
    ring.track:SetSize(size, size)
    ring.track:SetPoint("CENTER", ring.holder, "CENTER")
    for _, layer in ipairs({ring.fill, ring.rested}) do
        layer.tex:ClearAllPoints()
        layer.tex:SetSize(size, size)
        layer.tex:SetPoint("CENTER", ring.holder, "CENTER")
        layer.mask:ClearAllPoints()
        layer.mask:SetSize(size * 1.1, size)
        layer.mask:SetPoint("BOTTOM", ring.holder, "BOTTOM", 0, -size * 0.05)
    end
    ring.hotspot:SetSize(size * 0.7, math.max(14, size * 0.18))
    ring.hotspot:ClearAllPoints()
    ring.hotspot:SetPoint("CENTER", ring.holder, "CENTER", 0, size * 0.5)
end

-- Remplissage bas → haut : hauteur du masque = ratio (léger débord bas -5%).
local function SetRingFill(ring, layer, ratio)
    ratio = Clamp(ratio, 0, 1)
    local size = ring._size or 74
    layer.mask:SetHeight(math.max(0.5, size * 1.05 * ratio))
    layer.tex:SetShown(ratio > 0.004)
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
        SetRingFill(ring, ring.fill, p)
        ApplyGradient(ring.fill.tex, COLOR_XP, alpha)
        if pRested and pRested > p + 0.002 then
            SetRingFill(ring, ring.rested, pRested)
            ApplyGradient(ring.rested.tex, COLOR_RESTED, alpha * 0.40)
        else
            ring.rested.tex:Hide()
        end
        ring._mode = "xp"
    else
        local p, name = self:GetReputation()
        if not p then ring.holder:Hide() return end
        SetRingFill(ring, ring.fill, p)
        ApplyGradient(ring.fill.tex, COLOR_REP, alpha)
        ring.rested.tex:Hide()
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
