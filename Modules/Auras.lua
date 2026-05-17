-------------------------------------------------------------------------------
-- SphereNameplates v7.2 — Modules/Auras.lua
-- Affichage des auras (debuffs / buffs / contrôles) autour de l'orbe
--
-- CORRECTIONS v7.2 :
--   • Filtre SANS INCLUDE_NAME_PLATE_ONLY (trop restrictif en WoW Midnight —
--     la plupart des auras n'ont pas ce flag et n'apparaissaient jamais)
--     → Fallback automatique si la version NAMEPLATE_ONLY ne retourne rien
--   • Layout grille implémenté (auras_layout="grid", auras_cols=N)
--   • Delta UNIT_AURA robuste : fusion des cas addedAuras/removedAuraInstanceIDs
--   • AcquireIcon : le parent est défini même quand on reprend du pool
--   • RepositionIcons : gère correctement ligne et grille
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.Auras = {}

-- Couleurs de bordure par type de dispel
local DISPEL_COLORS = {
    Magic   = {r=0.20, g=0.60, b=1.00},
    Curse   = {r=0.60, g=0.00, b=1.00},
    Disease = {r=0.60, g=0.40, b=0.00},
    Poison  = {r=0.00, g=0.60, b=0.00},
    Bleed   = {r=0.80, g=0.00, b=0.00},
}

local SEGMENT_COLORS = {
    playerDebuff = {r=1.00, g=0.18, b=0.04},
    important    = {r=1.00, g=0.48, b=0.04},
    dot          = {r=0.92, g=0.08, b=0.08},
    buff         = {r=0.08, g=0.62, b=1.00},
    other        = {r=0.58, g=0.58, b=0.64},
}

local LANDING_TEX = "Interface\\AddOns\\Plumber\\Art\\ExpansionLandingPage\\ExpansionLandingPage"
local AURA_TIMER_LOW = {x = 360/1024, y = 20/1024}
local AURA_TIMER_HIGH = {x = 520/1024, y = 180/1024}
local _ceil = math.ceil

local function AuraPrefix(auraType)
    return auraType == "help" and "auras_buff_" or "auras_debuff_"
end

local function AuraSetting(cfg, auraType, suffix, fallbackKey, fallbackValue)
    cfg = cfg or {}
    local v = cfg[AuraPrefix(auraType) .. suffix]
    if v ~= nil then return v end
    if fallbackKey and cfg[fallbackKey] ~= nil then return cfg[fallbackKey] end
    return fallbackValue
end

local function SafeBool(v, fallback)
    local ok, result = pcall(function()
        return v and true or false
    end)
    if ok then return result end
    return fallback
end

local function SafeString(v)
    local okNil, isNil = pcall(function() return v == nil end)
    if okNil and isNil then return nil end
    local ok, result = pcall(tostring, v)
    if ok then return result end
    return nil
end

local function SafeDispelName(v)
    local ok, result = pcall(function()
        if v == "Magic" then return "Magic" end
        if v == "Curse" then return "Curse" end
        if v == "Disease" then return "Disease" end
        if v == "Poison" then return "Poison" end
        if v == "Bleed" then return "Bleed" end
        return nil
    end)
    if ok then return result end
    return nil
end

local function SafeAuraNumber(v)
    return SP:UntaintNum(v)
end

local function ReadAuraField(aura, key)
    local ok, value = pcall(function() return aura[key] end)
    if ok then return value end
    return nil
end

local function SafeIsNil(v)
    local ok, result = pcall(function() return v == nil end)
    return ok and result or false
end

local function ConfigureAuraCooldown(cd, r, g, b, alpha, edge)
    if not cd then return end
    cd:SetSwipeColor(r or 1, g or 0.2, b or 0.08, alpha or 0.86)
    pcall(function()
        cd:SetSwipeTexture(LANDING_TEX)
        if cd.SetTexCoordRange then
            cd:SetTexCoordRange(AURA_TIMER_LOW, AURA_TIMER_HIGH)
        end
    end)
    pcall(function() cd:SetDrawEdge(edge ~= false) end)
end

local function UpdateTimerText(icon)
    if not (icon and icon.timer) then return end
    local exp = icon._timerExp
    if not icon._timerTextEnabled or not exp then
        icon.timer:SetText("")
        icon.timer:Hide()
        return
    end
    -- exp est issu de UntaintNum (plain number), mais pcall défensif au cas où
    -- le scratchFS a échoué et retourné une valeur encore tainted.
    local ok, remain = pcall(function() return exp - GetTime() end)
    if not ok or remain <= 0 then
        icon.timer:SetText("")
        icon.timer:Hide()
        return
    end
    if remain >= 60 then
        icon.timer:SetText(tostring(_ceil(remain / 60)) .. "m")
    else
        icon.timer:SetText(tostring(_ceil(remain)))
    end
    icon.timer:Show()
end

local function HasFilterToken(filter, token)
    return type(filter) == "string" and filter:find(token, 1, true) ~= nil
end

-------------------------------------------------------------------------------
--  DÉTECTION API (WoW Midnight — C_UnitAuras)
-------------------------------------------------------------------------------
local _UA             = C_UnitAuras
local GetAuraSlots    = _UA and _UA.GetAuraSlots
local GetAuraBySlot   = _UA and _UA.GetAuraDataBySlot
local GetAuraByInstID = _UA and _UA.GetAuraDataByAuraInstanceID
local GetUnitAuras    = _UA and _UA.GetUnitAuras

-- Détection des APIs legacy (UnitDebuff/UnitBuff) disponibles en WoW classique+
local _hasLegacyAura  = (type(UnitDebuff) == "function")

-------------------------------------------------------------------------------
--  FETCH AURAS
--
--  Stratégie :
--   1. Essayer avec INCLUDE_NAME_PLATE_ONLY (filtre natif Blizzard)
--   2. Si retourne 0 résultats → retenter sans (WoW Midnight moins strict)
--   3. Fallback legacy GetUnitAuras
-------------------------------------------------------------------------------
local function FetchAuras(unit, baseFilter)
    local result = {}
    local seen = {}

    local function addAura(aura)
        if not aura then return end
        local auraID = SafeAuraNumber(ReadAuraField(aura, "auraInstanceID"))
        local spellID = SafeAuraNumber(ReadAuraField(aura, "spellId"))
        local key = auraID or (spellID and (tostring(baseFilter) .. ":" .. tostring(spellID))) or nil
        if key and seen[key] then return end
        if key then seen[key] = true end
        result[#result + 1] = aura
    end

    if GetAuraSlots then
        -- GetAuraSlots retourne : continuationToken, slot1, slot2, ...
        -- pcall retourne     : ok, continuationToken, slot1, slot2, ...
        -- Il faut capturer TOUS les retours via {...} pour récupérer les slots.
        local function tryGetSlots(filter)
            local returns = {}
            local function capture(...)
                local n = select("#", ...)
                returns.n = n
                for i = 1, n do returns[i] = select(i, ...) end
            end
            local ok = pcall(function() capture(GetAuraSlots(unit, filter)) end)
            if not ok then return nil end  -- erreur Lua
            -- returns[1]=continuationToken, returns[2..n]=slot IDs.
            -- Ne pas utiliser #table : continuationToken peut etre nil.
            local slots = {}
            for i = 2, (returns.n or 0) do
                if returns[i] ~= nil then slots[#slots + 1] = returns[i] end
            end
            return slots
        end

        local filters = {}
        local function addFilter(filter)
            if not filter then return end
            for _, existing in ipairs(filters) do
                if existing == filter then return end
            end
            filters[#filters + 1] = filter
        end

        if not HasFilterToken(baseFilter, "INCLUDE_NAME_PLATE_ONLY") then
            addFilter(baseFilter .. "|INCLUDE_NAME_PLATE_ONLY")
        end
        addFilter(baseFilter)
        if HasFilterToken(baseFilter, "HARMFUL") and not HasFilterToken(baseFilter, "PLAYER") then
            addFilter(baseFilter .. "|PLAYER")
        end

        local seenSlots = {}
        for _, filter in ipairs(filters) do
            local slots = tryGetSlots(filter)
            if slots then
                for _, slot in ipairs(slots) do
                    if slot ~= nil and not seenSlots[slot] then
                        seenSlots[slot] = true
                        local ok3, aura = pcall(GetAuraBySlot, unit, slot)
                        if ok3 and aura then addAura(aura) end
                    end
                end
            end
        end

        if GetUnitAuras then
            local ok, auras = pcall(GetUnitAuras, unit, baseFilter, nil)
            if ok and type(auras) == "table" then
                for _, a in ipairs(auras) do addAura(a) end
            end
        end

    elseif GetUnitAuras then
        -- Fallback Dragonflight/Shadowlands
        local ok, auras = pcall(GetUnitAuras, unit, baseFilter, nil)
        if ok and type(auras) == "table" then
            for _, a in ipairs(auras) do addAura(a) end
        end

    elseif _hasLegacyAura then
        -- Fallback legacy UnitDebuff/UnitBuff (WoW classique+)
        local getter = (baseFilter == "HARMFUL") and UnitDebuff or UnitBuff
        local i = 1
        while true do
            local ok, name, icon, count, dispelType, dur, expTime = pcall(getter, unit, i)
            if not ok or not name then break end
            result[#result + 1] = {
                icon = icon, applications = count, dispelName = dispelType,
                duration = dur, expirationTime = expTime,
            }
            i = i + 1
            if i > 40 then break end
        end
    end

    return result
end

SP.Auras.FetchAuras = FetchAuras

-------------------------------------------------------------------------------
--  POOL D'ICÔNES (réutilisation des frames — économise les allocations)
-------------------------------------------------------------------------------
local pool = {}
local CIRCLE_MASK_AURA = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function AcquireIcon(parent)
    local f = table.remove(pool)
    if not f then
        -- Créer un nouveau frame d'icône
        -- Guard combat : CreateFrame interdit en InCombatLockdown (génère un taint en cascade).
        -- Le pool doit être pré-peuplé hors combat (PrewarmPool appelé sur PLAYER_ENTERING_WORLD).
        if InCombatLockdown() then
            return nil  -- échouer gracieusement, pas d'icône ce cycle
        end
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(24, 24)

        -- Masque circulaire — appliqué sur le frame lui-même (comme Nameplates addon)
        -- Toutes les textures enfants de f doivent appeler AddMaskTexture(f._mask)
        local mask = f:CreateMaskTexture()
        pcall(function()
            mask:SetTexture(CIRCLE_MASK_AURA, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(f)
        end)
        f._mask = mask

        -- Fond sombre (sous l'icône)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetTexture(LANDING_TEX)
        bg:SetTexCoord(200/1024, 360/1024, 20/1024, 180/1024)
        bg:SetVertexColor(0.18, 0.16, 0.13, 0.95)
        if f._mask then pcall(bg.AddMaskTexture, bg, f._mask) end
        f.plumberBg = bg

        -- Icône sort
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("CENTER")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if f._mask then pcall(f.icon.AddMaskTexture, f.icon, f._mask) end

        f.plumberGlow = f:CreateTexture(nil, "OVERLAY", nil, 1)
        f.plumberGlow:SetPoint("CENTER")
        f.plumberGlow:SetTexture(LANDING_TEX)
        f.plumberGlow:SetTexCoord(0/1024, 200/1024, 416/1024, 616/1024)
        f.plumberGlow:SetBlendMode("ADD")
        f.plumberGlow:SetAlpha(0)

        -- Bordure couleur debuff (sur le bord de l'icône, pas masquée → visible)
        f.border = f:CreateTexture(nil, "OVERLAY")
        f.border:SetPoint("CENTER")
        f.border:SetTexture(LANDING_TEX)
        f.border:SetTexCoord(544/1024, 672/1024, 128/1024, 256/1024)
        f.border:SetAlpha(0.95)

        -- Stack count
        f.count = f:CreateFontString(nil, "OVERLAY")
        f.count:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        f.count:SetTextColor(1, 1, 1, 1)
        f.count:SetShadowColor(0, 0, 0, 1)
        f.count:SetShadowOffset(1, -1)

        -- Timer numerique optionnel, separe du compteur de stacks.
        f.timer = f:CreateFontString(nil, "OVERLAY")
        f.timer:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.timer:SetTextColor(1, 0.92, 0.75, 1)
        f.timer:SetShadowColor(0, 0, 0, 1)
        f.timer:SetShadowOffset(1, -1)
        f.timer:Hide()
        f:SetScript("OnUpdate", function(self, elapsed)
            self._timerTick = (self._timerTick or 0) + (elapsed or 0)
            if self._timerTick >= 0.20 then
                self._timerTick = 0
                UpdateTimerText(self)
            end
        end)

        -- Timer circulaire : anneau qui se vide dans le sens des aiguilles d'une montre.
        -- SetReverse(true) : commence plein → se vide (comportement attendu pour les durées).
        -- SetHideCountdownNumbers(true) : on masque les chiffres WoW natifs (illisibles à cette taille).
        -- SetDrawEdge(true) : ligne lumineuse à la limite du temps restant → plus lisible.
        f.cd = CreateFrame("Cooldown", nil, f)
        f.cd:SetAllPoints(f)
        f.cd:SetDrawSwipe(true)
        f.cd:SetReverse(true)
        f.cd:SetHideCountdownNumbers(true)
        ConfigureAuraCooldown(f.cd, 1, 0.20, 0.08)
        pcall(function() f.cd:SetDrawEdge(true) end)
    else
        -- Réutiliser depuis le pool — reparenter correctement
        f:SetParent(parent)
    end
    f:ClearAllPoints()
    f:Hide()
    return f
end

local function ReleaseIcon(f)
    f:Hide()
    f:ClearAllPoints()
    f.auraID   = nil
    f.auraType = nil
    f._isCc    = nil
    f._ccExpiry= nil
    f._segment = nil
    if f.count  then f.count:SetText("") end
    if f.timer  then f.timer:SetText(""); f.timer:Hide() end
    if f.border then f.border:SetAlpha(0) end
    if f.plumberGlow then f.plumberGlow:SetAlpha(0) end
    if f.cd     then f.cd:Clear() end
    f._timerExp = nil
    f._timerTextEnabled = nil
    f._timerTick = 0
    table.insert(pool, f)
end

local function LayoutAuraIconVisual(icon, size)
    if not icon then return end
    size = size or icon:GetWidth() or 24
    -- Zoom +20% vs 0.68 d'origine : icône plus lisible, toujours contenue dans le masque (≤ size).
    local inner = math.max(8, math.floor(size * 0.82 + 0.5))
    local border = math.max(size + 8, math.floor(size * 1.42 + 0.5))
    local glow = math.max(size + 16, math.floor(size * 1.85 + 0.5))

    if icon._mask then
        icon._mask:ClearAllPoints()
        icon._mask:SetAllPoints(icon)
    end
    if icon.icon then
        icon.icon:ClearAllPoints()
        icon.icon:SetPoint("CENTER")
        icon.icon:SetSize(inner, inner)
    end
    if icon.border then
        icon.border:ClearAllPoints()
        icon.border:SetPoint("CENTER")
        icon.border:SetSize(border, border)
    end
    if icon.plumberGlow then
        icon.plumberGlow:ClearAllPoints()
        icon.plumberGlow:SetPoint("CENTER")
        icon.plumberGlow:SetSize(glow, glow)
    end
    if icon.count then
        icon.count:ClearAllPoints()
        icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    end
    if icon.timer then
        icon.timer:ClearAllPoints()
        icon.timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end
    if icon.cd then
        icon.cd:ClearAllPoints()
        icon.cd:SetAllPoints(icon)
    end
end

-------------------------------------------------------------------------------
--  MISE À JOUR D'UNE ICÔNE
--
--  Toutes les lectures de champs auraData sont dans un pcall défensif :
--  en WoW Midnight, les données peuvent être "tainted" (secret values) et
--  l'accès à certains champs ou leur utilisation comme index de table échoue.
--  Les valeurs lues sont converties en types Lua sûrs avant utilisation.
-------------------------------------------------------------------------------
local function UpdateAuraIcon(icon, auraData, auraType, cfg)
    cfg = cfg or {}
    -- Lire les champs dans un pcall — toute valeur tainted reste piégée dedans
    -- IMPORTANT : nameplateShowAll est dans un pcall SÉPARÉ pour ne pas empêcher
    -- dispelName d'être lu si le champ n'existe pas ou est protégé en WoW Midnight.
    -- Lecture séparée : en WoW Midnight chaque champ peut être tainté indépendamment.
    -- Un pcall monolithique fait perdre TOUS les champs si UN seul crash.
    local iconTex, applications, duration, expTime
    pcall(function() iconTex      = auraData.icon end)
    pcall(function() applications = auraData.applications end)
    pcall(function() duration     = auraData.duration end)
    pcall(function() expTime      = auraData.expirationTime end)
    -- dispelName : peut etre une valeur secrete; conversion separee sans test booleen direct.
    local dispelName = SafeDispelName(ReadAuraField(auraData, "dispelName"))
    -- nameplateShowAll lu séparément — champ booléen WoW Midnight, peut être absent
    local nameplateShowAll
    pcall(function() nameplateShowAll = auraData.nameplateShowAll end)
    local showAllAllowed = true
    local okShowAll, safeShowAll = pcall(function()
        return nameplateShowAll ~= false
    end)
    if okShowAll then showAllAllowed = safeShowAll end

    -- Détection CC : stun, fear, sleep, root, incapacitate…
    -- Critères :
    --   1. Pas de dispelName (CC purs non-dispellables)
    --   2. nameplateShowAll ~= false : exclut Taunt/Provocation (nameplateShowAll=false)
    --      Si le champ n'existe pas (nil) → on autorise (compatibilité API)
    --   3. Durée 1s–30s : exclut les effets de fond (>30s) et les flashs instantanés
    local isCc = false
    local ccExpiry_val = nil
    local dur = SP:UntaintNum(duration)
    local exp = SP:UntaintNum(expTime)
    if not dispelName and dur and exp and showAllAllowed then
        if dur and dur >= 1.0 and dur <= 30 then
            isCc = true
            ccExpiry_val = exp
        end
    end
    icon._isCc     = isCc
    icon._ccExpiry = ccExpiry_val

    -- Icône
    local safeIconTex = 134400
    pcall(function()
        if iconTex ~= nil then safeIconTex = iconTex end
    end)
    pcall(icon.icon.SetTexture, icon.icon, safeIconTex)

    -- Bordure : dispelName est maintenant un string Lua ordinaire (ou nil)
    local dc = dispelName and DISPEL_COLORS[dispelName]
    local tr = AuraSetting(cfg, auraType, "timerR", nil, auraType == "help" and 0.12 or 1.00)
    local tg = AuraSetting(cfg, auraType, "timerG", nil, auraType == "help" and 0.72 or 0.24)
    local tb = AuraSetting(cfg, auraType, "timerB", nil, auraType == "help" and 1.00 or 0.08)
    local ta = AuraSetting(cfg, auraType, "timer_alpha", nil, auraType == "help" and 0.78 or 0.92)
    local edge = AuraSetting(cfg, auraType, "timer_edge", nil, true)
    if dc then
        icon.border:SetVertexColor(dc.r, dc.g, dc.b)
        icon.border:SetAlpha(1)
        if icon.plumberGlow then
            icon.plumberGlow:SetVertexColor(dc.r, dc.g, dc.b, 1)
            icon.plumberGlow:SetAlpha(0.22)
        end
        ConfigureAuraCooldown(icon.cd, tr, tg, tb, ta, edge)
    elseif auraType == "control" then
        icon.border:SetVertexColor(0.4, 0.4, 1.0)
        icon.border:SetAlpha(0.9)
        if icon.plumberGlow then
            icon.plumberGlow:SetVertexColor(0.4, 0.4, 1.0, 1)
            icon.plumberGlow:SetAlpha(0.22)
        end
        ConfigureAuraCooldown(icon.cd, tr, tg, tb, ta, edge)
    elseif auraType == "help" then
        icon.border:SetVertexColor(0.12, 0.72, 1.0)
        icon.border:SetAlpha(0.86)
        if icon.plumberGlow then
            icon.plumberGlow:SetVertexColor(0.12, 0.72, 1.0, 1)
            icon.plumberGlow:SetAlpha(0.16)
        end
        ConfigureAuraCooldown(icon.cd, tr, tg, tb, ta, edge)
    else
        icon.border:SetVertexColor(1, 0.24, 0.08)
        icon.border:SetAlpha(0.86)
        if icon.plumberGlow then
            icon.plumberGlow:SetVertexColor(1, 0.24, 0.08, 1)
            icon.plumberGlow:SetAlpha(0.16)
        end
        ConfigureAuraCooldown(icon.cd, tr, tg, tb, ta, edge)
    end

    -- Stack count : applications peut être tainted → comparer via pcall
    local textSize = AuraSetting(cfg, auraType, "text_size", nil, 8)
    local textR = AuraSetting(cfg, auraType, "textR", nil, auraType == "help" and 0.78 or 1.00)
    local textG = AuraSetting(cfg, auraType, "textG", nil, auraType == "help" and 0.92 or 0.92)
    local textB = AuraSetting(cfg, auraType, "textB", nil, auraType == "help" and 1.00 or 0.75)

    if icon.count then
        icon.count:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
        icon.count:SetTextColor(textR, textG, textB, 1)
        local countStr = ""
        local appCount = SafeAuraNumber(applications)
        if appCount and appCount > 1 then
            countStr = tostring(appCount)
        end
        icon.count:SetText(countStr)
    end

    -- Cooldown swipe — utilise les valeurs BRUTES (duration, expTime) au lieu de
    -- UntaintNum'd (dur, exp). Raison : en WoW Midnight 12.x, UntaintNum utilise
    -- SetFormattedText sur un FontString enfant de UIParent ; depuis un contexte
    -- d'exécution tainted (nameplate en combat), cet appel throw → UntaintNum retourne
    -- nil → guard "dur and exp" échoue → cooldown et timer désactivés.
    -- Solution : passer les valeurs brutes directement à SetCooldown (API C-side qui
    -- accepte les secret numbers nativement). Toute arithmétique Lua est dans le pcall
    -- pour capturer les throws si les valeurs sont effectivement tainted.
    if icon.cd then
        local showCd = false
        if AuraSetting(cfg, auraType, "timer", nil, true)
           and duration ~= nil and expTime ~= nil then
            pcall(function()
                local remaining = expTime - GetTime()
                if remaining > 0 and duration > 0 then
                    icon.cd:SetCooldown(expTime - duration, duration)
                    icon.cd:Show()
                    showCd = true
                end
            end)
        end
        if not showCd then
            pcall(icon.cd.Clear, icon.cd)
            pcall(icon.cd.Hide,  icon.cd)
        end
    end
    if icon.timer then
        icon.timer:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
        icon.timer:SetTextColor(textR, textG, textB, 1)
        -- Priorité : exp (UntaintNum, plain number) si disponible, sinon expTime brut.
        -- UpdateTimerText gère le cas tainted via son propre pcall interne.
        icon._timerExp = exp or expTime
        icon._timerTextEnabled = AuraSetting(cfg, auraType, "timer_text", nil, true)
                                 and (exp ~= nil or expTime ~= nil)
        UpdateTimerText(icon)
    end
end

-------------------------------------------------------------------------------
--  REPOSITIONNEMENT — arc épousant la sphère
--
--  auras_side = "below"  : arc inférieur (défaut) — icônes en demi-cercle sous l'orbe
--               "above"  : arc supérieur
--               "left"   : arc gauche
--               "right"  : arc droit
--
--  auras_mode = "icons" (défaut) : arc
--               "ring"           : 5 emplacements fixes répartis sur tout le pourtour
--
--  Les icônes sont placées à rayon R = orbRadius + gap + iconRadius de l'orbe.
-------------------------------------------------------------------------------
local _sin = math.sin
local _cos = math.cos
local _pi  = math.pi

-- Mode "ring" : 5 slots fixes à 72° d'écart, départ bas (270°)
-- Angles en radians, repère WoW (+X=droite, +Y=haut) :
--   Slot 1 : 270° = bas
--   Slot 2 : 198° = bas-gauche
--   Slot 3 : 342° = bas-droite
--   Slot 4 : 126° = haut-gauche
--   Slot 5 :  54° = haut-droite
local RING_ANGLES_DEG = {270, 198, 342, 126, 54}
local RING_ANGLES = {}
for i = 1, 5 do
    RING_ANGLES[i] = RING_ANGLES_DEG[i] * _pi / 180
end

local function EnsureSegmentSlots(data)
    if data.segmentSlots then return data.segmentSlots end
    data.segmentSlots = {}
    local root = data.root
    if not root then return data.segmentSlots end

    for i = 1, 5 do
        local f = CreateFrame("Frame", nil, root)
        f:SetFrameStrata(root:GetFrameStrata() or "HIGH")
        f:SetFrameLevel((root:GetFrameLevel() or 10) + 12)
        f:SetAlpha(0)
        f:Hide()

        local fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
        fill:SetAllPoints(f)
        fill:SetTexture(SP.ASSETS .. "aura-segment-" .. i)
        fill:SetBlendMode("BLEND")

        local glow = f:CreateTexture(nil, "OVERLAY", nil, 2)
        glow:SetAllPoints(f)
        glow:SetTexture(SP.ASSETS .. "aura-segment-" .. i)
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)

        local border = f:CreateTexture(nil, "OVERLAY", nil, 3)
        border:SetAllPoints(f)
        border:SetTexture(SP.ASSETS .. "aura-segment-border-" .. i)
        border:SetBlendMode("BLEND")
        border:SetVertexColor(0, 0, 0, 0.90)

        local count = f:CreateFontString(nil, "OVERLAY")
        count:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        count:SetTextColor(1, 1, 1, 1)
        count:SetShadowColor(0, 0, 0, 1)
        count:SetShadowOffset(1, -1)
        count:Hide()

        data.segmentSlots[i] = {
            frame = f,
            fill = fill,
            glow = glow,
            border = border,
            count = count,
            angle = RING_ANGLES[i],
        }
    end
    return data.segmentSlots
end

local function ClearSegmentSlots(data)
    local slots = data and data.segmentSlots
    if not slots then return end
    for _, slot in ipairs(slots) do
        if slot.frame then
            slot.frame:SetAlpha(0)
            slot.frame:Hide()
        end
        if slot.count then
            slot.count:SetText("")
            slot.count:Hide()
        end
        slot.aura = nil
    end
    data._ringAuraCount = 0
end

local function ApplySegmentStyle(data, slot, auraSlot, cfg)
    if not (data and slot and slot.frame and auraSlot and data.orb) then return end
    local size = data.orbSize or 64
    local auraType = auraSlot.auraType or "harm"
    local auraSize = AuraSetting(cfg, auraType, "size", "auras_size", 20)
    local gap = AuraSetting(cfg, auraType, "offsetY", "auras_offsetY", 4)
    local frameSize = math.floor(((size + gap * 2) / 0.62) + 0.5)
    local minFrame = size + auraSize * 2 + gap * 2
    frameSize = math.max(minFrame, frameSize)

    local angle = slot.angle
    local R = (size * 0.5) + gap + auraSize * 0.5
    local cx = R * _cos(angle)
    local cy = R * _sin(angle)

    slot.frame:SetSize(frameSize, frameSize)
    slot.frame:ClearAllPoints()
    slot.frame:SetPoint("CENTER", data.orb, "CENTER", 0, 0)
    slot.frame:SetFrameStrata((data.root and data.root:GetFrameStrata()) or "HIGH")
    slot.frame:SetFrameLevel(((data.root and data.root:GetFrameLevel()) or 10) + 12)
    slot.frame:SetAlpha(cfg.auras_segment_alpha or 0.92)
    slot.frame:Show()

    local c = auraSlot.color or SEGMENT_COLORS.other
    slot.fill:SetVertexColor(c.r, c.g, c.b, cfg.auras_segment_alpha or 0.92)
    slot.border:SetAlpha(0.95)
    slot.glow:SetVertexColor(c.r, c.g, c.b, 1)
    slot.glow:SetAlpha((cfg.auras_segment_glow ~= false and auraSlot.important) and 0.35 or 0)

    slot.count:ClearAllPoints()
    slot.count:SetPoint("CENTER", data.orb, "CENTER", cx, cy)
    local textSize = AuraSetting(cfg, auraType, "text_size", nil, 8)
    local textR = AuraSetting(cfg, auraType, "textR", nil, auraType == "help" and 0.78 or 1.00)
    local textG = AuraSetting(cfg, auraType, "textG", nil, auraType == "help" and 0.92 or 0.92)
    local textB = AuraSetting(cfg, auraType, "textB", nil, auraType == "help" and 1.00 or 0.75)
    slot.count:SetFont("Fonts\\FRIZQT__.TTF", textSize, "OUTLINE")
    slot.count:SetTextColor(textR, textG, textB, 1)
    if auraSlot.count and auraSlot.count > 1 then
        slot.count:SetText(tostring(auraSlot.count))
        slot.count:Show()
    else
        slot.count:SetText("")
        slot.count:Hide()
    end
    slot.aura = auraSlot
end

local function RepositionSegments(data, auraSlots)
    local cfg = SP:GetCfg(data.unitType)
    local slots = EnsureSegmentSlots(data)
    ClearSegmentSlots(data)
    for i = 1, 5 do
        if auraSlots[i] and slots[i] then
            ApplySegmentStyle(data, slots[i], auraSlots[i], cfg)
        end
    end
    data._ringAuraCount = math.min(#auraSlots, 5)
end

local function RepositionIcons(data)
    local cfg     = SP:GetCfg(data.unitType)
    local baseSize = cfg.auras_size or 20
    local icons   = data.auraIcons
    local n       = #icons
    if n == 0 then
        data._ringAuraCount = 0
        ClearSegmentSlots(data)
        return
    end

    local orbRadius = (data.orbSize or 64) * 0.5
    -- Rayon du centre des icônes par rapport au centre de la sphère
    local R = orbRadius + (cfg.auras_offsetY or 4) + baseSize * 0.5

    if (cfg.auras_mode or "icons") == "segments" then
        local segmentAuras = {}
        local maxSlots = math.min(n, 5)
        for i = 1, maxSlots do
            local ic = icons[i]
            ic:Hide()
            segmentAuras[i] = ic._segment
        end
        for i = maxSlots + 1, n do
            icons[i]:Hide()
        end
        RepositionSegments(data, segmentAuras)
        return
    end

    ClearSegmentSlots(data)

    -- ── Mode anneau : 5 emplacements fixes autour de l'orbe complet ──────────
    if (cfg.auras_mode or "icons") == "ring" then
        local maxSlots = math.min(n, 5)
        for i = 1, maxSlots do
            local ic  = icons[i]
            local auraType = ic.auraType or "harm"
            local size = AuraSetting(cfg, auraType, "size", "auras_size", baseSize)
            local R = orbRadius + AuraSetting(cfg, auraType, "offsetY", "auras_offsetY", 4) + size * 0.5
            local ang = RING_ANGLES[i]
            local x   = R * _cos(ang)
            local y   = R * _sin(ang)
            ic:SetSize(size, size)
            LayoutAuraIconVisual(ic, size)
            ic:ClearAllPoints()
            ic:SetPoint("CENTER", data.orb, "CENTER", x, y)
            ic:Show()
        end
        -- Cacher les icônes au-delà du 5ème emplacement
        for i = maxSlots + 1, n do
            icons[i]:Hide()
        end
        -- Mémoriser le nombre d'auras actives (pour HP text)
        data._ringAuraCount = maxSlots
        return
    end

    -- ── Mode arc (défaut) ─────────────────────────────────────────────────────
    data._ringAuraCount = 0

    local function centerForSide(sideName)
        if sideName == "above" then return _pi * 0.5 end
        if sideName == "left" then return _pi end
        if sideName == "right" then return 0 end
        return _pi * 1.5
    end

    local groups = { harm = {}, help = {} }
    for _, ic in ipairs(icons) do
        if ic.auraType == "help" then
            groups.help[#groups.help + 1] = ic
        else
            groups.harm[#groups.harm + 1] = ic
        end
    end

    local function placeGroup(list, auraType)
        local count = #list
        if count == 0 then return end
        local gSize = AuraSetting(cfg, auraType, "size", "auras_size", baseSize)
        local gap = AuraSetting(cfg, auraType, "offsetY", "auras_offsetY", 4)
        local sideName = AuraSetting(cfg, auraType, "side", "auras_side", auraType == "help" and "above" or "below")
        local radius = orbRadius + gap + gSize * 0.5
        if sideName == "full" then
            -- Distribution 360° : départ en bas (270° = 3π/2), sens trigonométrique
            local step = (count > 1) and (2 * _pi / count) or 0
            local startAngle = _pi * 1.5  -- 270°
            for i, ic in ipairs(list) do
                local angle = startAngle + (i - 1) * step
                ic:SetSize(gSize, gSize)
                LayoutAuraIconVisual(ic, gSize)
                ic:ClearAllPoints()
                ic:SetPoint("CENTER", data.orb, "CENTER", radius * _cos(angle), radius * _sin(angle))
                ic:Show()
            end
        else
            local center = centerForSide(sideName)
            local spread = math.min(150, (count - 1) * 30) * _pi / 180
            for i, ic in ipairs(list) do
                local frac  = (count > 1) and ((i - 1) / (count - 1)) or 0.5
                local angle = center - spread * 0.5 + frac * spread
                ic:SetSize(gSize, gSize)
                LayoutAuraIconVisual(ic, gSize)
                ic:ClearAllPoints()
                ic:SetPoint("CENTER", data.orb, "CENTER", radius * _cos(angle), radius * _sin(angle))
                ic:Show()
            end
        end
    end

    placeGroup(groups.harm, "harm")
    placeGroup(groups.help, "help")
    return
end

-------------------------------------------------------------------------------
--  INTERFACE PUBLIQUE
-------------------------------------------------------------------------------
function SP.Auras:Init(data)
    data.auraIcons = data.auraIcons or {}
    data.auraMap   = data.auraMap   or {}  -- [auraInstanceID] → icon
end

function SP.Auras:RemoveAll(data)
    if not data.auraIcons then return end
    for _, ic in ipairs(data.auraIcons) do ReleaseIcon(ic) end
    data.auraIcons      = {}
    data.auraMap        = {}
    data._ringAuraCount = 0
    ClearSegmentSlots(data)
end

local function AnalyzeAura(aura, auraType, unit, fromPlayerFilter)
    local info = {
        aura = aura,
        auraType = auraType,
        priority = 10,
        important = false,
        color = SEGMENT_COLORS.other,
        count = nil,
    }

    local dispelName = SafeDispelName(ReadAuraField(aura, "dispelName"))
    local sourceUnit = SafeString(ReadAuraField(aura, "sourceUnit"))
    local applications = ReadAuraField(aura, "applications")
    local duration = ReadAuraField(aura, "duration")
    local expTime = ReadAuraField(aura, "expirationTime")
    local spellId = ReadAuraField(aura, "spellId")
    local isBossAura = ReadAuraField(aura, "isBossAura")
    local canDispel = ReadAuraField(aura, "canActivePlayerDispel")
    local isFromPlayerOrPet = ReadAuraField(aura, "isFromPlayerOrPlayerPet")
    local isHarmful = ReadAuraField(aura, "isHarmful")
    local isHelpful = ReadAuraField(aura, "isHelpful")
    local nameplateShowDebuff = ReadAuraField(aura, "nameplateShowDebuff")
    if SafeIsNil(nameplateShowDebuff) then nameplateShowDebuff = ReadAuraField(aura, "nameplateShowAll") end
    if SafeIsNil(nameplateShowDebuff) then nameplateShowDebuff = ReadAuraField(aura, "nameplateShowPersonal") end

    local count = SafeAuraNumber(applications)
    info.count = count

    local dur = SafeAuraNumber(duration)
    local exp = SafeAuraNumber(expTime)
    local id = SafeAuraNumber(spellId)
    local fromPlayer = fromPlayerFilter == true or SafeBool(isFromPlayerOrPet, false)
    if sourceUnit then
        local ok, same = pcall(UnitIsUnit, sourceUnit, "player")
        if ok and same then fromPlayer = true end
    end

    local boss = SafeBool(isBossAura, false)
    local dispellable = dispelName ~= nil or SafeBool(canDispel, false)
    local nameplateDebuff = SafeBool(nameplateShowDebuff, false)
    local hasDuration = dur and dur > 0 and exp and exp > 0
    local isBleed = dispelName == "Bleed"
    if SafeBool(isHarmful, false) then
        auraType = "harm"
        info.auraType = "harm"
    elseif SafeBool(isHelpful, false) then
        auraType = "help"
        info.auraType = "help"
    end

    if auraType == "harm" then
        if fromPlayer then
            info.priority = 100
            info.color = SEGMENT_COLORS.playerDebuff
            info.important = true
        elseif boss or dispellable or nameplateDebuff then
            info.priority = 80
            info.color = SEGMENT_COLORS.important
            info.important = true
        elseif hasDuration or isBleed or id then
            info.priority = 60
            info.color = SEGMENT_COLORS.dot
        else
            info.priority = 35
            info.color = SEGMENT_COLORS.dot
        end
    elseif auraType == "help" then
        info.priority = 40
        info.color = SEGMENT_COLORS.buff
    end

    info.duration = dur
    info.expirationTime = exp
    info.fromPlayer = fromPlayer
    return info
end

-------------------------------------------------------------------------------
--  UPDATE UNIT
--
--  WoW Midnight 12.0.1 : le paramètre updateInfo (delta UNIT_AURA) contient
--  des champs tainted (secret values) — isHarmful, dispelName, icon, etc.
--  Tout usage de ces champs lève des erreurs Lua.
--
--  Solution : toujours faire un FULL SCAN via C_UnitAuras.GetAuraDataBySlot,
--  qui retourne des données non-tainted directement depuis l'API C.
--  Le delta path est désactivé pour WoW Midnight.
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  SIMULATION AURAS — utilisée par Preview.lua mode émulation
--  Crée 3 icônes de débuffs fictifs (Magic, Poison, Disease) sans API WoW
-------------------------------------------------------------------------------
function SP.Auras:SimulateAuras(data)
    SP.Auras:RemoveAll(data)
    SP.Auras:Init(data)

    local now = GetTime()
    local cfg = SP:GetCfg(data.unitType)
    local fakeAuras = {
        { icon=136168, dispelName="Bleed",   applications=2, duration=18, expirationTime=now+18, spellId=999001, isHarmful=true, isFromPlayerOrPlayerPet=true, sourceUnit="player" },
        { icon=136116, dispelName="Magic",   applications=3, duration=15, expirationTime=now+15, spellId=999002, isHarmful=true, isBossAura=true },
        { icon=136189, dispelName="Poison",  applications=0, duration=8,  expirationTime=now+8,  spellId=999003, isHarmful=true },
        { icon=135795, dispelName="Disease", applications=0, duration=30, expirationTime=now+30, spellId=999004, isHarmful=true },
        { icon=136076, applications=0, duration=12, expirationTime=now+12, spellId=999005, isHelpful=true, _previewType="help" },
    }

    for _, fa in ipairs(fakeAuras) do
        local auraType = fa._previewType or "harm"
        if (auraType == "help" and cfg.auras_buff) or (auraType ~= "help" and (cfg.auras_debuff or cfg.auras_control)) then
            local ic = AcquireIcon(data.root)
            if not ic then break end  -- pool vide en combat : skip
            UpdateAuraIcon(ic, fa, auraType, cfg)
            ic.auraType = auraType
            ic._segment = AnalyzeAura(fa, auraType, nil)
            table.insert(data.auraIcons, ic)
        end
    end
    RepositionIcons(data)
end

function SP.Auras:UpdateUnit(data, unit, updateInfo)
    local cfg = SP:GetCfg(data.unitType)
    if not cfg.auras_enabled then
        SP.Auras:RemoveAll(data)
        return
    end

    -- Throttle anti-flickering : en combat, UNIT_AURA se déclenche très fréquemment
    -- (chaque tick de DoT, chaque application). Le cycle RemoveAll+rebuild constant
    -- provoque cd:Clear()+SetCooldown() à chaque event → animation de timer instable.
    -- On limite les rebuilds à 1 toutes les 150 ms sauf sur un full update explicite.
    local now = GetTime()
    if updateInfo and not updateInfo.isFullUpdate then
        data._auraLastUpdate = data._auraLastUpdate or 0
        if (now - data._auraLastUpdate) < 0.15 then return end
    end
    data._auraLastUpdate = now

    SP.Auras:Init(data)

    local maxDebuff = cfg.auras_maxDebuff or 5
    local maxBuff   = cfg.auras_maxBuff   or 3

    -- Full scan systématique (delta désactivé — données tainted en WoW Midnight)
    SP.Auras:RemoveAll(data)

    if (cfg.auras_mode or "icons") == "segments" then
        local candidates = {}
        local seen = {}

        local function AddCandidates(baseFilter, auraType, enabled)
            if not enabled then return end
            local mineOnly = auraType == "harm" and cfg.auras_debuff_mine_only
                          or auraType == "help" and cfg.auras_buff_mine_only
            -- Filtre "mes sorts uniquement" : délégué au moteur C via token |PLAYER.
            -- isFromPlayerOrPlayerPet est une secret boolean taintée en WoW Midnight —
            -- toute comparaison Lua dessus throw. Le token |PLAYER de GetAuraSlots
            -- filtre côté engine sans exposer le champ à Lua.
            local effectiveFilter = (mineOnly and not HasFilterToken(baseFilter, "PLAYER"))
                                    and (baseFilter .. "|PLAYER")
                                    or  baseFilter
            local auras = FetchAuras(unit, effectiveFilter)
            local fromPlayerFilter = auraType == "harm" and HasFilterToken(effectiveFilter, "PLAYER")
            for _, aura in ipairs(auras) do
                local auraID = SafeAuraNumber(ReadAuraField(aura, "auraInstanceID"))
                local spellID = SafeAuraNumber(ReadAuraField(aura, "spellId"))
                local key = auraID or (spellID and (auraType .. ":" .. spellID)) or nil
                if not key or not seen[key] then
                    if key then seen[key] = true end
                    candidates[#candidates + 1] = AnalyzeAura(aura, auraType, unit, fromPlayerFilter)
                end
            end
        end

        AddCandidates("HARMFUL|PLAYER", "harm", cfg.auras_debuff or cfg.auras_control)
        AddCandidates("HARMFUL", "harm", cfg.auras_debuff or cfg.auras_control)
        AddCandidates("HELPFUL", "help", cfg.auras_buff)

        table.sort(candidates, function(a, b)
            local ap = a.priority or 0
            local bp = b.priority or 0
            if cfg.auras_debuff_priority ~= false and a.auraType ~= b.auraType then
                if a.auraType == "harm" then ap = ap + 25 end
                if b.auraType == "harm" then bp = bp + 25 end
            end
            if ap ~= bp then return ap > bp end
            return (a.expirationTime or 0) > (b.expirationTime or 0)
        end)

        for i = 1, math.min(5, #candidates) do
            local cand = candidates[i]
            local ic = AcquireIcon(data.root)
            if not ic then break end  -- pool vide en combat : stop l'allocation
            UpdateAuraIcon(ic, cand.aura, cand.auraType, cfg)
            ic.auraType = cand.auraType
            ic._segment = cand
            ic:Hide()
            table.insert(data.auraIcons, ic)
        end

        RepositionIcons(data)

        local ccExpiry = nil
        for _, ic in ipairs(data.auraIcons) do
            if ic._isCc and ic._ccExpiry then
                local isLonger = false
                if not ccExpiry then
                    isLonger = true
                else
                    pcall(function() isLonger = ic._ccExpiry > ccExpiry end)
                end
                if isLonger then ccExpiry = ic._ccExpiry end
            end
        end
        pcall(SP.Orb.UpdateCC, SP.Orb, data, ccExpiry)
        return
    end

    local function AddBatch(baseFilter, auraType, maxCount)
        local mineOnly = auraType == "harm" and cfg.auras_debuff_mine_only
                      or auraType == "help" and cfg.auras_buff_mine_only
        -- Filtre "mes sorts uniquement" : délégué au moteur C via token |PLAYER.
        -- isFromPlayerOrPlayerPet est une secret boolean taintée en WoW Midnight —
        -- toute comparaison Lua dessus throw. Le token |PLAYER de GetAuraSlots
        -- filtre côté engine sans exposer le champ à Lua.
        local effectiveFilter = (mineOnly and not HasFilterToken(baseFilter, "PLAYER"))
                                and (baseFilter .. "|PLAYER")
                                or  baseFilter
        local auras = FetchAuras(unit, effectiveFilter)
        local added = 0
        for _, aura in ipairs(auras) do
            if added >= maxCount then break end
            local ic = AcquireIcon(data.root)
            if not ic then break end  -- pool vide en combat : stop l'allocation
            UpdateAuraIcon(ic, aura, auraType, cfg)
            ic.auraType = auraType
            -- auraInstanceID : lire via pcall (peut être tainted)
            local ok, instID = pcall(function() return aura.auraInstanceID end)
            ic.auraID = ok and SP:UntaintNum(instID) or nil
            if ic.auraID then data.auraMap[ic.auraID] = ic end
            table.insert(data.auraIcons, ic)
            added = added + 1
        end
    end

    if cfg.auras_debuff or cfg.auras_control then
        AddBatch("HARMFUL", "harm", maxDebuff)
    end
    if cfg.auras_buff then
        AddBatch("HELPFUL", "help", maxBuff)
    end

    RepositionIcons(data)

    -- Détection CC : cherche le debuff sans dispelName avec la plus longue expiration

    -- _ccExpiry est stocké comme plain number (UntaintNum) — la comparaison est safe.
    local ccExpiry = nil
    for _, ic in ipairs(data.auraIcons) do
        if ic._isCc and ic._ccExpiry then
            -- pcall défensif au cas où _ccExpiry serait encore tainted (UntaintNum échoué)
            local isLonger = false
            if not ccExpiry then
                isLonger = true
            else
                pcall(function() isLonger = ic._ccExpiry > ccExpiry end)
            end
            if isLonger then ccExpiry = ic._ccExpiry end
        end
    end
    pcall(SP.Orb.UpdateCC, SP.Orb, data, ccExpiry)
end

-------------------------------------------------------------------------------
--  PRÉ-CHAUFFE DU POOL — à appeler hors combat (PLAYER_ENTERING_WORLD)
--  Évite CreateFrame en InCombatLockdown lors du premier cycle d'auras.
--  On utilise UIParent comme parent temporaire ; les frames seront reparentées
--  par AcquireIcon lors de leur première utilisation réelle.
-------------------------------------------------------------------------------
function SP.Auras:PrewarmPool(count)
    count = count or 24
    local toCreate = count - #pool
    if toCreate <= 0 then return end
    for _ = 1, toCreate do
        -- AcquireIcon avec UIParent comme parent temporaire crée et retourne une frame.
        -- On la remet immédiatement dans le pool via ReleaseIcon (chemin interne).
        local f = AcquireIcon(UIParent)
        if f then
            f:Hide()
            f:ClearAllPoints()
            f:SetParent(UIParent)
            table.insert(pool, f)
        end
    end
end
