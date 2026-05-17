-------------------------------------------------------------------------------
-- SphereNameplates v9.0 — Orb.lua
-- Moteur de rendu sphérique — WoW natif, sans LibOrb
--
-- TECHNIQUE DE REMPLISSAGE :
--   fillTex (WHITE8x8) ancré BOTTOM, hauteur = SIZE × ratio
--   → remplissage de bas en haut, masqué par cercle parfait
--
-- INTERPOLATION HP (lerp) :
--   data._lastRatio   = ratio cible (mis à jour immédiatement)
--   data._displayRatio = ratio affiché (interpolé vers _lastRatio à 60 FPS)
--
-- ANTI-TAINT v7.4 (WoW Midnight) :
--   UpdateLevelText utilise SP:ApplyHPText/ApplyHPTextPair exclusivement.
--   → SetFormattedText côté C, jamais de string Lua tainté.
--   UnitHealth / UnitHealthMax / GetValue / GetMinMaxValues = TOUS taints en 12.x
--   Seule voie sûre : UnitHealthPercent + SetFormattedText escape (rOrbs pattern)
--
-- VISUELS v7.4 (inspirés DiabolicUI2 / rOrbs) :
--   • Galaxy layers rotatifs (galaxy.tga, galaxy2.tga, galaxy3.tga)
--   • Spark ancré fillTex TOP → suit la ligne de flottaison HP
--   • Gloss overlay (orb_gloss.tga)
--   • Glow lowHP (<25%) rouge pulsé
--
-- CORRECTIONS v7.1→v7.4 :
--   • UpdateFill utilise data.unit pour class-color
--   • Power bar + bordure toujours créées (cachées si désactivées)
--   • SoftUpdate(), SetTargetRatio(), LerpTick() implémentés
--   • OnValueChanged hook supprimé (valeur taintée en 12.x)
--   • UpdateLevelText : FormatHPText → ApplyHPText/RenderHPText (taint-safe)
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.Orb = {}

-- ── Pooling ──────────────────────────────────────────────────────────────────
SP.Pool = {
    ENEMY = {},
    FRIENDLY = {},
    ENEMY_PLAYER = {},
    FRIENDLY_PLAYER = {},
    NEUTRAL = {},
}

local SafeUnitClass
local SafeSetVertexColor

function SP.Orb:Acquire(unitType, plate, cfg)
    local pool = SP.Pool[unitType]
    if pool and #pool > 0 then
        local data = table.remove(pool)
        data.plate = plate
        data.unitType = unitType
        data.root:SetParent(plate)
        data.root:SetPoint("CENTER", plate, "CENTER", cfg.offsetX or 0, cfg.offsetY or 0)
        data.root:Show()
        if SP.Orb.ApplySphereVisibility then
            SP.Orb:ApplySphereVisibility(data, cfg)
        end
        return data
    end
    return nil
end

SP.POOL_MAX_PER_TYPE = 12

function SP.Orb:Release(data)
    if not data then return end
    data.root:Hide()
    -- Reset couleur pooling : evite qu'une frame recyclee affiche la classe
    -- de son ancienne unite avant le premier update de la nouvelle.
    SafeSetVertexColor(data.fillTex, 1, 1, 1, 0.88)
    SafeSetVertexColor(data.fillSurface, 1, 1, 1, 1)
    SafeSetVertexColor(data.shimmer1, 1, 1, 1, 1)
    SafeSetVertexColor(data.shimmer2, 1, 1, 1, 1)
    SafeSetVertexColor(data.galaxy1, 1, 1, 1, 1)
    SafeSetVertexColor(data.galaxy2, 1, 1, 1, 1)
    SafeSetVertexColor(data.galaxy3, 1, 1, 1, 1)
    SafeSetVertexColor(data.waveT1, 1, 1, 1, 1)
    SafeSetVertexColor(data.waveT2, 1, 1, 1, 1)
    SafeSetVertexColor(data.borderOverlay, 1, 1, 1, 1)
    -- Champs HP / ratio
    data.unit          = nil
    data._cachedClass  = nil   -- classe joueur mise en cache (évite taint SafeUnitClass)
    data.targetHP      = nil
    data.displayHP     = nil
    data._lastRatio    = nil
    data._displayRatio = nil
    -- État logique
    data._aggroLevel   = 0
    data._isTarget     = false
    data._isFocus      = false
    data._inCombat     = false
    data._glowTime     = 0
    data._targetRippleTime = 0
    data.isQuestUnit   = false
    data._ringAuraCount = 0
    -- Pack mode — état initial neutre (pleine visibilité, lerp immédiat)
    data._packRank        = 3
    data._packAlpha       = 1.0   -- alpha cible pack mode (lerp)
    data._packScale       = 1.0   -- scale cible pack mode (lerp)
    data._packGalaxyAlpha = nil   -- alpha galaxy pack mode (nil = non initialisé)
    data._fadeAlpha       = 1.0   -- alpha distance-fade (stocké, combiné dans AnimTick)
    data._classRetryAcc   = 0     -- accumulateur pour le retry périodique de classe (Fix C)
    -- CC — effacer expiry ET overlay visuel
    data._ccExpiry     = nil
    data._ccActive     = false
    if data.ccOverlay then pcall(data.ccOverlay.SetAlpha, data.ccOverlay, 0) end
    if data.ccText    then pcall(data.ccText.Hide,        data.ccText)       end
    -- Glow unique — éteindre
    if data.singleGlow then pcall(data.singleGlow.SetAlpha, data.singleGlow, 0) end
    if data.targetRipples then
        for _, ripple in ipairs(data.targetRipples) do
            pcall(ripple.SetAlpha, ripple, 0)
            pcall(ripple.Hide, ripple)
        end
    end
    data._midnightStarAngle = 0
    if data.midnightStar then pcall(data.midnightStar.SetRotation, data.midnightStar, 0) end
    if data.raidIcon then pcall(data.raidIcon.SetAlpha, data.raidIcon, 0) end
    if data.raidIconFrame then pcall(data.raidIconFrame.Hide, data.raidIconFrame) end
    if data.bossEliteFrame then pcall(data.bossEliteFrame.Hide, data.bossEliteFrame) end
    -- Castbar — refs nullifiées (frames restent parentes du root et sont cachés)
    data.castbar       = nil
    data._cb_circ      = nil
    -- Autres états visuels
    data._lastFillR    = nil
    data._lastFillG    = nil
    data._lastFillB    = nil
    data._levelTextFontSize = nil
    -- Pool : insérer seulement si sous la limite
    local pool = SP.Pool[data.unitType]
    if pool and #pool < SP.POOL_MAX_PER_TYPE then
        table.insert(pool, data)
    end
    -- Au-delà de la limite : on abandonne la référence Lua (la frame WoW reste en
    -- mémoire C mais aucun code n'y accèdera — coût marginal acceptable).
end

local M     = function(n) return SP.MEDIA .. n end
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Masque circulaire : priorité au masque natif WoW (garanti disponible)
-- Le masque custom en fallback avec extension .tga explicite
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- isPlayer : hint optionnel (true si unitType == ENEMY_PLAYER/FRIENDLY_PLAYER).
-- Évite UnitIsPlayer() en contexte tainté WoW Midnight (secret boolean error).
-- ── Cache GUID global — survit aux recycles de nameplates ───────────────────
-- Problème : SafeUnitClass échoue à la milliseconde de NAME_PLATE_UNIT_ADDED
-- (WoW n'a pas encore chargé les données de l'unité). Les textures partent en
-- couleur fallback. Quand la nameplate réapparaît (rotation de caméra), _cachedClass
-- est effacé (Release) et le cycle recommence → orbes délavés jusqu'au retry 0.5s.
-- Solution : stocker la classe résolue par GUID. La réapparition de la même
-- nameplate est INSTANTANÉE sans aucun cycle d'attente.
-- Nettoyé sur PLAYER_LEAVING_WORLD (changement de zone).
local _guidClassCache = {}
SP._guidClassCache = _guidClassCache   -- expose pour nettoyage externe

SafeUnitClass = function(unit, isPlayer)
    if not unit then return nil end

    -- ── 0. Cache GUID : lookup avant tout appel WoW API ──────────────────────
    -- UnitGUID est non-tainté et retourne toujours une string stable.
    local guid = nil
    local okGuid, g = pcall(UnitGUID, unit)
    if okGuid and type(g) == "string" and g ~= "" then
        guid = g
        local cached = _guidClassCache[guid]
        if cached then return cached end  -- hit → retour immédiat, zéro latence
    end

    -- ── 1. Vérification joueur ────────────────────────────────────────────────
    if isPlayer == nil then
        -- Fallback : tenter UnitIsPlayer — peut échouer en contexte tainté
        local ok, res = pcall(function()
            return UnitIsPlayer(unit) and true or false
        end)
        isPlayer = ok and res or false
    end
    if not isPlayer then return nil end

    -- Appel unique UnitClass → (localizedName, classFilename, classID)
    local okClass, _, cls, classID = pcall(UnitClass, unit)
    if not okClass then return nil end

    -- ── Méthode 1 : classID (entier) → GetClassInfo ─────────────────────────
    -- Les entiers ne sont PAS des "secret values" en WoW Midnight.
    -- GetClassInfo est un lookup statique (pas unit-API) → retourne toujours
    -- des valeurs propres, comparables sans risque de taint.
    local resolved = nil
    if type(classID) == "number" and classID > 0 then
        local okInfo, _, classFile = pcall(GetClassInfo, classID)
        if okInfo and type(classFile) == "string" and classFile ~= "" then
            resolved = classFile
        end
    end

    -- ── Méthode 2 : comparaison directe du classFilename (fallback) ──────────
    -- Protégée par pcall : si cls est une secret-string en contexte tainté,
    -- la comparaison throw → okSame=false → on passe à la clé suivante.
    if not resolved and cls then
        for key in pairs(SP.CLASS_COLORS or {}) do
            local okSame, same = pcall(function() return cls == key end)
            if okSame and same then resolved = key; break end
        end
    end

    -- ── Stocker dans le cache GUID si résolu ─────────────────────────────────
    if resolved and guid then
        _guidClassCache[guid] = resolved
    end

    return resolved
end

SafeSetVertexColor = function(region, r, g, b, a)
    if region and region.SetVertexColor then
        pcall(region.SetVertexColor, region, r, g, b, a)
    end
end

local RAID_ICONS = {}
for i = 1, 8 do
    RAID_ICONS[i] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i
end

-- Wrapper SetFont taint-safe : si la police est introuvable (addon tiers désinstallé),
-- WoW lève "Invalid font file asset". On retombe sur FRIZQT__.TTF.
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local function SafeSetFont(fs, path, size, flags)
    if not fs then return end
    flags = flags or "OUTLINE"
    if not pcall(fs.SetFont, fs, path, size, flags) then
        pcall(fs.SetFont, fs, FALLBACK_FONT, size, flags)
    end
end

-- Couleurs de power type
local POWER_COLORS = {
    [0]  = {0.00, 0.00, 1.00}, -- MANA
    [1]  = {1.00, 0.00, 0.00}, -- RAGE
    [2]  = {1.00, 0.54, 0.00}, -- FOCUS
    [3]  = {1.00, 0.90, 0.00}, -- ENERGY
    [4]  = {0.30, 0.52, 0.90}, -- COMBO_POINTS
    [6]  = {0.00, 0.82, 1.00}, -- RUNIC_POWER
    [7]  = {0.00, 0.82, 0.50}, -- SOUL_SHARDS
    [11] = {0.60, 0.00, 0.80}, -- MAELSTROM
    [13] = {0.00, 0.90, 0.20}, -- INSANITY
    [16] = {1.00, 0.65, 0.00}, -- ASTRAL_POWER
    [18] = {0.30, 0.70, 0.10}, -- ESSENCE
}
local function GetPowerColor(ptype)
    local c = POWER_COLORS[ptype] or {0.6, 0.6, 0.6}
    return c[1], c[2], c[3]
end

-------------------------------------------------------------------------------
--  HELPERS ANIMATION (défensifs — WoW Midnight peut ne pas supporter
--  CreateAnimationGroup sur les textures. On tente, on ignore si ça échoue.
--  La sphère reste visible sans animations.)
-------------------------------------------------------------------------------
local function AddRotation(tex, degrees, duration, startDelay)
    local ok, ag = pcall(function()
        local g   = tex:CreateAnimationGroup()
        local rot = g:CreateAnimation("Rotation")
        rot:SetDegrees(degrees)
        rot:SetDuration(duration)
        if startDelay then rot:SetStartDelay(startDelay) end
        g:SetLooping("REPEAT")
        g:Play()
        return g
    end)
    return ok and ag or nil
end

local function AddAlphaPulse(tex, lo, hi, dur)
    local ok, ag = pcall(function()
        local g  = tex:CreateAnimationGroup()
        local a1 = g:CreateAnimation("Alpha")
        a1:SetFromAlpha(lo) ; a1:SetToAlpha(hi) ; a1:SetDuration(dur) ; a1:SetOrder(1)
        local a2 = g:CreateAnimation("Alpha")
        a2:SetFromAlpha(hi) ; a2:SetToAlpha(lo) ; a2:SetDuration(dur) ; a2:SetOrder(2)
        g:SetLooping("REPEAT")
        g:Play()
        return g
    end)
    return ok and ag or nil
end

-------------------------------------------------------------------------------
--  COULEUR DE BORDURE
--  Mode "classe" → couleur de classe du joueur ciblé
--  Mode "custom" (défaut) → borderR/G/B depuis la config
-------------------------------------------------------------------------------
local function GetBorderColor(cfg, unit)
    local useClass = (cfg.borderColorMode == "classe") or (cfg.borderClassColor == true)
    if useClass and unit then
        local cls = SafeUnitClass(unit)
        if cls then return SP:GetClassColor(cls) end
    end
    return cfg.borderR or 0.60, cfg.borderG or 0.48, cfg.borderB or 0.12
end

-------------------------------------------------------------------------------
--  COULEUR DE FILL
--  unit peut être nil (preview) ou data.unit pour la class-color correcte
-------------------------------------------------------------------------------
-- cachedClass : classe déjà résolue (data._cachedClass) — évite SafeUnitClass
--              en contexte tainté. nil = résolution dynamique normale.
-- isPlayer    : hint unitType pour SafeUnitClass (évite UnitIsPlayer tainté).
local function GetFillColor(cfg, unit, cachedClass, isPlayer)
    local mode = cfg.fill_color_mode
    if cfg.classColorSphere == true and (mode == nil or mode == "custom" or mode == "fixed") then
        mode = "class"
    end
    if mode == "class" then
        local cls = cachedClass or (unit and SafeUnitClass(unit, isPlayer))
        if cls then return SP:GetClassColor(cls) end
    end
    return cfg.fillR or 1, cfg.fillG or 0.1, cfg.fillB or 0.1
end

local function ApplySaturation(r, g, b, sat)
    sat = sat or 1
    local gray = (r * 0.299) + (g * 0.587) + (b * 0.114)
    local nr = gray + (r - gray) * sat
    local ng = gray + (g - gray) * sat
    local nb = gray + (b - gray) * sat
    return math.max(0, math.min(1, nr)),
           math.max(0, math.min(1, ng)),
           math.max(0, math.min(1, nb))
end

local function Clamp01(v, fallback)
    v = tonumber(v)
    if v == nil then return fallback or 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function GetFillMode(cfg)
    local mode = cfg and cfg.fill_color_mode or "fixed"
    if mode == "custom" then mode = "fixed" end
    if cfg and cfg.classColorSphere == true and (mode == nil or mode == "fixed") then
        mode = "class"
    end
    if mode ~= "class" and mode ~= "progressive" then mode = "fixed" end
    return mode
end

local function GetProgressiveFillColor(cfg, ratio)
    ratio = tonumber(ratio) or 1
    if ratio >= 0.75 then
        return cfg.fill_prog_highR or 0.20, cfg.fill_prog_highG or 1.00, cfg.fill_prog_highB or 0.20
    elseif ratio >= 0.50 then
        return cfg.fill_prog_midR or 1.00, cfg.fill_prog_midG or 0.82, cfg.fill_prog_midB or 0.00
    elseif ratio >= 0.25 then
        return cfg.fill_prog_lowR or 1.00, cfg.fill_prog_lowG or 0.50, cfg.fill_prog_lowB or 0.00
    end
    return cfg.fill_prog_critR or 1.00, cfg.fill_prog_critG or 0.15, cfg.fill_prog_critB or 0.15
end

-- cachedClass : data._cachedClass pré-résolu (évite SafeUnitClass en contexte tainté).
-- isPlayer    : hint isPlayer pour SafeUnitClass (depuis data.unitType).
local function ResolveFillColor(cfg, unit, ratio, cachedClass, isPlayer)
    cfg = cfg or {}
    local mode = GetFillMode(cfg)
    local r, g, b
    if mode == "class" then
        r, g, b = GetFillColor(cfg, unit, cachedClass, isPlayer)
    elseif mode == "progressive" then
        r, g, b = GetProgressiveFillColor(cfg, ratio)
    else
        r, g, b = cfg.fillR or 1, cfg.fillG or 0.1, cfg.fillB or 0.1
    end
    r, g, b = ApplySaturation(r, g, b, cfg.fill_saturation or 1)
    return r, g, b, Clamp01(cfg.fill_alpha, 0.88), mode
end

-- ─── Couleurs progressives du nom (4 paliers par ratio HP) ──────────────────
local function GetProgressiveNameColor(cfg, ratio)
    ratio = tonumber(ratio) or 1
    if ratio >= 0.75 then
        return cfg.name_prog_highR or 1.0, cfg.name_prog_highG or 1.0, cfg.name_prog_highB or 1.0
    elseif ratio >= 0.50 then
        return cfg.name_prog_midR or 1.0, cfg.name_prog_midG or 0.82, cfg.name_prog_midB or 0.0
    elseif ratio >= 0.25 then
        return cfg.name_prog_lowR or 1.0, cfg.name_prog_lowG or 0.50, cfg.name_prog_lowB or 0.0
    end
    return cfg.name_prog_critR or 1.0, cfg.name_prog_critG or 0.15, cfg.name_prog_critB or 0.15
end

-- Résout la couleur finale du nom : mode + saturation + alpha.
-- isPlayer = true pour les types ENEMY_PLAYER / FRIENDLY_PLAYER.
-- ratio = data.displayHP or 1 (HP ratio propre, jamais tainté).
local function ResolveNameColor(cfg, unit, ratio, isPlayer)
    cfg = cfg or {}

    -- Déterminer le mode effectif
    local mode = cfg.name_color_mode
    if mode == nil or mode == "" then
        -- Migration legacy : profil sauvegardé sans name_color_mode
        if cfg.classColorName and isPlayer then
            mode = "class"
        elseif cfg.nameR then
            mode = "fixed"
        else
            mode = "auto"
        end
    end
    -- "class" n'existe pas pour les PNJ → fallback "fixed"
    if mode == "class" and not isPlayer then mode = "fixed" end

    local r, g, b
    if mode == "class" and isPlayer then
        local cls = SafeUnitClass(unit)
        if cls then r, g, b = SP:GetClassColor(cls) end
    elseif mode == "progressive" then
        r, g, b = GetProgressiveNameColor(cfg, ratio)
    end

    if not r then
        -- mode "fixed", "auto", ou fallback classe inconnue
        r = cfg.nameR or 1
        g = cfg.nameG or 1
        b = cfg.nameB or 1
    end

    r, g, b = ApplySaturation(r, g, b, cfg.name_saturation or 1)
    return r, g, b, Clamp01(cfg.name_alpha, 1.0), mode
end

-------------------------------------------------------------------------------
--  CREATE — construit l'orbe et tous ses éléments visuels
--
--  unit     : token WoW (ex: "nameplate3") ou nil en mode preview
--  plate    : frame nameplate parente ou nil en preview
--  unitType : "ENEMY" | "FRIENDLY" | "ENEMY_PLAYER" | "FRIENDLY_PLAYER"
--
--  TOUS les éléments optionnels (power bar, bordure) sont TOUJOURS créés
--  et simplement cachés si désactivés. Cela permet à SoftUpdate de les
--  afficher/cacher sans rebuild.
-------------------------------------------------------------------------------
function SP.Orb:Create(unit, plate, unitType)
    local cfg  = SP:GetCfg(unitType)

    local SIZE = cfg.size or 64
    local bW   = math.max(4, math.floor(SIZE * 0.09))  -- anneau proportionnel à SIZE (~9%)
    local fr, fg, fb, fa = ResolveFillColor(cfg, unit, 1)

    -- ── 1. Frame racine (parente : nameplate ou UIParent en preview) ─────────
    -- Note : masquage Blizzard géré par SP:HideBlizzardElements() dans Core.lua
    local root = CreateFrame("Frame", nil, plate or UIParent)
    root:SetSize(SIZE * 3, SIZE * 2.8)
    if plate then
        root:SetPoint("CENTER", plate, "CENTER",
            cfg.offsetX or 0, cfg.offsetY or 0)
        root:SetFrameLevel(math.max(10, (plate:GetFrameLevel() or 0) + 10))
    else
        root:SetFrameStrata("DIALOG")
        root:SetFrameLevel(200)
        root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- ── 2. Container circulaire (orbFrame) ───────────────────────────────────
    local orbFrame = CreateFrame("Frame", nil, root)
    orbFrame:SetSize(SIZE, SIZE)
    orbFrame:SetPoint("CENTER", root, "CENTER", 0, 0)
    orbFrame:SetFrameLevel(root:GetFrameLevel() + 2)

    -- Masque circulaire — plein cercle orbFrame (SIZE×SIZE).
    -- L'orbe remplit entièrement son cercle ; le style décoratif (borderOverlayFrame)
    -- est le seul élément de bordure visible — il dépasse de bW px au-delà.
    local maskInner = SIZE
    local mask = orbFrame:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(orbFrame)

    -- Fond — frame DÉDIÉ à root+1 pour garantir le rendu DERRIÈRE tout le reste.
    -- ⚠ NE PAS mettre bgTex sur orbFrame (root+2) : en WoW Midnight, SetDrawLayer()
    -- dans SoftUpdate peut perturber l'ordre de rendu → fond opaque par-dessus le fill.
    -- Solution structurelle : bgFrame à root+1, strictement sous orbFrame et hpBar.
    local bgFrame = CreateFrame("Frame", nil, root)
    bgFrame:SetSize(SIZE, SIZE)
    bgFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    bgFrame:SetFrameLevel(root:GetFrameLevel() + 1)

    local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetTexture(WHITE)
    bgTex:SetAllPoints(bgFrame)
    bgTex:SetVertexColor(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0)
    bgTex:SetAlpha(cfg.bgAlpha or 1.0)
    bgTex:AddMaskTexture(mask)   -- mask sur orbFrame — cross-frame masks supportés

    -- bgTex2 : léger relief dans le vide (presque invisible, sert uniquement à "creuser")
    local bgTex2 = bgFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgTex2:SetTexture(M("orb-backdrop2"))
    bgTex2:SetAllPoints(bgFrame)
    bgTex2:SetBlendMode("ADD")
    bgTex2:SetVertexColor(0.04, 0.04, 0.07)
    bgTex2:SetAlpha(0.04)   -- quasi invisible
    bgTex2:AddMaskTexture(mask)

    -- FILL HP — StatusBar vertical (taint-safe, WoW Midnight 12.x)
    -- Parente : root (pas orbFrame) afin de maîtriser le frame level.
    -- Hiérarchie : bgFrame(L+1) < orbFrame(L+2) < hpBar(fill,L+3) < overlayOrbFrame(galaxy,L+4) < [iconFrame castbar L+5] < glassFrame(L+6)
    -- SetMinMaxValues/SetValue acceptent les valeurs "secret number tainted".
    local hpBar = CreateFrame("StatusBar", nil, root)
    hpBar:SetSize(SIZE, SIZE)
    hpBar:SetPoint("BOTTOM", orbFrame, "BOTTOM", 0, 0)
    hpBar:SetOrientation("VERTICAL")
    hpBar:SetStatusBarTexture(WHITE)
    hpBar:SetMinMaxValues(0, 100)
    hpBar:SetValue(100)
    hpBar:SetFrameLevel(root:GetFrameLevel() + 3)
    local fillTex = hpBar:GetStatusBarTexture()
    fillTex:SetVertexColor(fr, fg, fb, fa)
    fillTex:AddMaskTexture(mask)   -- masque circulaire cross-frame (supporté par WoW)

    -- Frame overlay : galaxy, shimmer, glass — doit être AU-DESSUS du fill (L+4)
    local overlayOrbFrame = CreateFrame("Frame", nil, root)
    overlayOrbFrame:SetSize(SIZE, SIZE)
    overlayOrbFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    overlayOrbFrame:SetFrameLevel(root:GetFrameLevel() + 4)

    -- ── Galaxy layers (inspirés rOrbs) — tournent lentement sous le fill ───────
    local gA = cfg.orb_galaxy_alpha or 0.15   -- réduit : évite le disque lumineux dans le vide

    -- Couche 1 : galaxy.tga rotation lente (sens horaire)
    local galaxy1 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    galaxy1:SetTexture(M("galaxy"))
    galaxy1:SetSize(SIZE * 1.4, SIZE * 1.4)
    galaxy1:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    galaxy1:SetBlendMode("ADD")
    galaxy1:SetAlpha(gA)
    galaxy1:SetVertexColor(fr, fg, fb)
    galaxy1:AddMaskTexture(mask)
    if cfg.orb_galaxies ~= false then AddRotation(galaxy1, 360, 28) end

    -- Couche 2 : galaxy2.tga contre-rotation
    local galaxy2 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    galaxy2:SetTexture(M("galaxy2"))
    galaxy2:SetSize(SIZE * 1.2, SIZE * 1.2)
    galaxy2:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    galaxy2:SetBlendMode("ADD")
    galaxy2:SetAlpha(gA * 0.80)
    galaxy2:SetVertexColor(fr * 0.7, fg * 0.7, math.min(1, fb * 1.3))
    galaxy2:AddMaskTexture(mask)
    if cfg.orb_galaxies ~= false then AddRotation(galaxy2, -360, 40, 4) end

    -- Couche 3 : galaxy3.tga rotation plus rapide
    local galaxy3 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 3)
    galaxy3:SetTexture(M("galaxy3"))
    galaxy3:SetSize(SIZE * 1.1, SIZE * 1.1)
    galaxy3:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    galaxy3:SetBlendMode("ADD")
    galaxy3:SetAlpha(gA * 0.65)
    galaxy3:SetVertexColor(fr, math.min(1, fg * 1.1), fb)
    galaxy3:AddMaskTexture(mask)
    if cfg.orb_galaxies ~= false then
        AddRotation(galaxy3, 360, 18, 8)
        AddAlphaPulse(galaxy3, gA * 0.4, gA, 6)
    end
    if cfg.orb_galaxies == false then
        galaxy1:Hide() ; galaxy2:Hide() ; galaxy3:Hide()
    end

    local midnightStar = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 4)
    midnightStar:SetTexture("Interface\\AddOns\\SphereNameplates\\media\\midnigt_star.png")
    midnightStar:SetSize(SIZE * (cfg.orb_midnight_star_scale or 1.18), SIZE * (cfg.orb_midnight_star_scale or 1.18))
    midnightStar:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    midnightStar:SetBlendMode("ADD")
    midnightStar:SetAlpha(cfg.orb_midnight_star_alpha or 0.55)
    midnightStar:AddMaskTexture(mask)
    if cfg.orb_midnight_star == false then midnightStar:Hide() end

    local sA = cfg.orb_shimmer_alpha or 0.22   -- réduit : évite le disque lumineux dans le vide

    -- Shimmer 1 (rotation anti-horaire) — par-dessus les galaxies
    local shimmer1 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 5)
    shimmer1:SetTexture(M("orb1"))
    shimmer1:SetAllPoints(orbFrame)
    shimmer1:SetBlendMode("ADD")
    shimmer1:SetAlpha(sA)
    shimmer1:SetVertexColor(fr, fg, fb)
    shimmer1:AddMaskTexture(mask)
    AddRotation(shimmer1, -360, 20)
    AddAlphaPulse(shimmer1, sA * 0.55, sA, 5)

    -- Shimmer 2 (contra-rotation)
    local shimmer2 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 6)
    shimmer2:SetTexture(M("orb2"))
    shimmer2:SetAllPoints(orbFrame)
    shimmer2:SetBlendMode("ADD")
    shimmer2:SetAlpha(sA * 0.60)
    shimmer2:SetVertexColor(fr * 0.8, fg * 0.8, math.min(1, fb * 1.1))
    shimmer2:AddMaskTexture(mask)
    AddRotation(shimmer2, 360, 30, 3)

    -- ── Spark — ligne de flottaison HP (ancré fillTex TOP, cross-frame) ─────────
    -- fillTex = hpBar:GetStatusBarTexture() — sa hauteur varie avec SetValue.
    -- Anchor cross-frame : le spark SUIT physiquement le niveau HP sans ratio Lua.
    local spark = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 7)
    spark:SetTexture(M("orb_spark"))
    spark:SetSize(SIZE * 0.88, SIZE * 0.10)
    spark:SetPoint("CENTER", fillTex, "TOP", 0, 0)
    spark:SetBlendMode("ADD")
    spark:SetAlpha(0.80)
    spark:AddMaskTexture(mask)
    if cfg.orb_spark == false then spark:Hide() end

    -- ── Textures DiabolicUI (orb_filling) — couches rotatives animées ───────────
    -- orb_filling1 / orb_filling4 : textures sphère pré-rendues de DiabolicUI2.
    -- Utilisées comme overlays ADD+rotation → donnent l'effet "liquide 3D" animé.
    -- L'animation est gérée NATIVEMENT par WoW (AddRotation = AnimationGroup).
    -- Pas de SetTexCoord/REPEAT — simple et stable.
    local wA = cfg.orb_wave_alpha or 0.38

    local waveT1 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 7)
    waveT1:SetTexture(M("orb_filling1"))
    waveT1:SetAllPoints(orbFrame)             -- même zone que l'orbe, masqué au cercle
    waveT1:SetBlendMode("ADD")
    waveT1:SetAlpha(wA)
    waveT1:SetVertexColor(fr, fg, fb)
    waveT1:AddMaskTexture(mask)
    if cfg.orb_wave ~= false then
        AddRotation(waveT1, 360, 22)          -- rotation complète en 22 secondes
    end

    local waveT2 = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 7)  -- 8 = invalide (max WoW = 7)
    waveT2:SetTexture(M("orb_filling4"))
    waveT2:SetAllPoints(orbFrame)
    waveT2:SetBlendMode("ADD")
    waveT2:SetAlpha(wA * 0.65)
    waveT2:SetVertexColor(fr * 0.85, fg * 0.85, math.min(1, fb * 1.15))
    waveT2:AddMaskTexture(mask)
    if cfg.orb_wave ~= false then
        AddRotation(waveT2, -360, 31, 3)      -- contre-rotation, légèrement décalée
    end

    if cfg.orb_wave == false then waveT1:Hide() ; waveT2:Hide() end

    -- ── glassFrame (root+6) — frame dédié pour glass/gloss/shadow/specular ──────
    -- Séparation intentionnelle de overlayOrbFrame (root+4) :
    --   root+4 (overlayOrbFrame) : effets dynamiques colorés (galaxy, shimmer, wave)
    --   root+5 : icône castbar (CastBar.lua) — entre les deux
    --   root+6 (glassFrame)     : effets statiques de verre (glass, gloss, shadow, specular)
    -- Cela permet à l'icône du sort d'être SOUS le glass visuellement sans être
    -- saturée par les couleurs ADD des galaxies/shimmer.
    -- Cross-frame masks supportés dans WoW : mask sur orbFrame (root+2) fonctionne. ──
    local glassFrame = CreateFrame("Frame", nil, root)
    glassFrame:SetSize(SIZE, SIZE)
    glassFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    glassFrame:SetFrameLevel(root:GetFrameLevel() + 6)

    -- ── Glass overlay (alpha volontairement bas pour ne pas créer un disque ────
    -- dans la zone "vide" au-dessus du fill HP quand les PV baissent).
    -- À alpha élevé, ces textures ADD rendent tout le cercle lumineux même à vide.
    -- Slider orb_gloss_alpha dans le config pour ajuster.
    local gOA = cfg.orb_gloss_alpha or 0.20   -- réduit : 0.45 créait le "disque persistant"
    local glassTex = glassFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    glassTex:SetTexture(M("orb-glass"))
    glassTex:SetAllPoints(orbFrame)
    glassTex:SetBlendMode("ADD")
    glassTex:SetAlpha(gOA)
    glassTex:AddMaskTexture(mask)

    local glassTex2 = glassFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    glassTex2:SetTexture(M("orb-glass-1"))
    glassTex2:SetAllPoints(orbFrame)
    glassTex2:SetBlendMode("ADD")
    glassTex2:SetAlpha(gOA * 0.50)
    glassTex2:AddMaskTexture(mask)

    -- ── Gloss rOrbs-style (orb_gloss.tga) ────────────────────────────────────
    local glossTex = glassFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    glossTex:SetTexture(M("orb_gloss"))
    glossTex:SetAllPoints(orbFrame)
    glossTex:SetBlendMode("ADD")
    glossTex:SetAlpha(math.min(1, gOA * 1.20))
    glossTex:AddMaskTexture(mask)
    if cfg.orb_gloss == false then
        glassTex:Hide() ; glassTex2:Hide() ; glossTex:Hide()
    end

    -- ── Inner shadow (configurable, défaut 0.35) ────────────────────────────
    -- Codex 2026-04-30: était hardcodé 0.62 → orbe trop sombre. Maintenant
    -- piloté par cfg.orb_shadow_alpha. Mettre à 0 pour désactiver.
    local shadowTex = glassFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    shadowTex:SetTexture(M("orb_innershadow"))
    shadowTex:SetAllPoints(orbFrame)
    shadowTex:SetAlpha(cfg.orb_shadow_alpha or 0.35)
    shadowTex:AddMaskTexture(mask)

    -- Inner shadow v2 (directionnel bas-droit) — DÉSACTIVÉ par défaut tant
    -- que la texture orb-innershadow-v2.tga est absente du dossier media.
    -- Crée seulement si orb_shadow2_enabled = true (sinon tex invalide invisible).
    local shadowTex2 = nil
    if cfg.orb_shadow2_enabled then
        shadowTex2 = glassFrame:CreateTexture(nil, "OVERLAY", nil, 5)
        shadowTex2:SetTexture(M("orb-innershadow-v2"))
        shadowTex2:SetAllPoints(orbFrame)
        shadowTex2:SetAlpha(cfg.orb_shadow2_alpha or 0.0)
        shadowTex2:AddMaskTexture(mask)
    end

    -- ── Specular highlight (haut-gauche) — point de lumière spéculaire ─────────
    -- Simule un reflet dur de lumière sur la sphère : rendu 3D naturel.
    -- orb_gloss positionné en quart supérieur-gauche, alpha modéré.
    local specular = glassFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    specular:SetTexture(M("orb_gloss"))
    specular:SetSize(SIZE * 0.65, SIZE * 0.65)
    specular:SetPoint("TOPLEFT", orbFrame, "TOPLEFT", SIZE * 0.04, -SIZE * 0.04)
    specular:SetBlendMode("ADD")
    specular:SetAlpha(0.28)
    specular:AddMaskTexture(mask)

    -- ── Fill surface glow — effet "liquide" à la surface du fill HP ─────────────
    -- Ancré sur fillTex:TOP : suit automatiquement le niveau HP.
    -- Crée un reflet doux juste en-dessous de la surface du liquide.
    -- Étendu de 30% de SIZE vers le bas depuis la surface.
    local fillSurface = overlayOrbFrame:CreateTexture(nil, "ARTWORK", nil, 6)
    fillSurface:SetTexture(M("orb-glass"))
    fillSurface:SetSize(SIZE * 0.80, SIZE * 0.32)
    fillSurface:SetPoint("TOP", fillTex, "TOP", 0, 0)   -- suit la ligne de flottaison
    fillSurface:SetBlendMode("ADD")
    fillSurface:SetAlpha(0.22)
    fillSurface:SetVertexColor(fr, fg, fb)
    fillSurface:AddMaskTexture(mask)

    -- ── 3. Style décoratif bordure (root+8) ──────────────────────────────────
    -- Taille SIZE+bW×2 : le ring de la texture déborde de bW px autour de l'orbe.
    -- Le masque circulaire de l'orbe est maintenant plein (SetAllPoints → SIZE),
    -- donc l'orbe remplit exactement jusqu'à SIZE — plus de gap noir.
    -- La texture ring a son centre transparent aligné sur SIZE : ring visible au-delà.
    -- BLEND mode : transparence native de la texture respectée.
    -- root+8 : au-dessus du glassFrame (root+6) et de l'iconFrame castbar (root+5), sous les textes (root+9).
    local br, bg, bb = GetBorderColor(cfg, unit)
    local bOScale = cfg.borderOverlayScale or 1.5
    local bOSize  = math.floor(SIZE * bOScale)
    local borderOverlayFrame = CreateFrame("Frame", nil, root)
    borderOverlayFrame:SetSize(bOSize, bOSize)
    borderOverlayFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    borderOverlayFrame:SetFrameLevel(root:GetFrameLevel() + 8)

    local borderOverlay = borderOverlayFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    local bInfo = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(cfg.borderStyle)
    local bPath = bInfo and bInfo.path
    if bPath then
        borderOverlay:SetTexture(bPath)
        borderOverlay:SetAllPoints(borderOverlayFrame)
        -- UV spritesheet : applique la région si définie, sinon texture entière
        if bInfo.uv then
            borderOverlay:SetTexCoord(bInfo.uv[1], bInfo.uv[2], bInfo.uv[3], bInfo.uv[4])
        else
            borderOverlay:SetTexCoord(0, 1, 0, 1)
        end
        borderOverlay:SetBlendMode(bInfo.blend or "BLEND")
        if bInfo.tint == false then
            borderOverlay:SetVertexColor(1, 1, 1, 1)
        else
            borderOverlay:SetVertexColor(br, bg, bb, 1)
        end
        borderOverlay:SetAlpha(cfg.borderEnabled ~= false and 1.0 or 0)
    else
        borderOverlay:SetAlpha(0)
    end

    -- ── 3b. Ombre circulaire (option indépendante, root+8 sub-layer 0) ───────
    local shadeOverlay = borderOverlayFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    shadeOverlay:SetTexture(SP.SHADE_CIRCLE_PATH)
    shadeOverlay:SetSize(SIZE, SIZE)
    shadeOverlay:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    shadeOverlay:SetBlendMode("BLEND")
    shadeOverlay:SetAlpha(cfg.shadeCircleEnabled and (cfg.shadeCircleAlpha or 0.6) or 0)

    -- ── 3c. Overlay CC (violet uniforme sur toute la sphère) ─────────────────
    -- Doit être au-dessus de overlayOrbFrame (root+4) ET de borderOverlayFrame (root+8).
    -- Création sur un frame dédié root+8+1 avec son propre masque circulaire SIZE.
    -- BLEND mode : le violet se superpose uniformément sur toute la sphère.
    local ccOverlayFrame = CreateFrame("Frame", nil, root)
    ccOverlayFrame:SetSize(SIZE, SIZE)
    ccOverlayFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    ccOverlayFrame:SetFrameLevel(root:GetFrameLevel() + 8)
    local ccMask = ccOverlayFrame:CreateMaskTexture()
    ccMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ccMask:SetAllPoints(ccOverlayFrame)
    local ccOverlay = ccOverlayFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    ccOverlay:SetTexture(WHITE)
    ccOverlay:SetAllPoints(ccOverlayFrame)
    ccOverlay:SetVertexColor(0.55, 0.0, 0.85)
    ccOverlay:SetBlendMode("BLEND")
    ccOverlay:SetAlpha(0)
    ccOverlay:AddMaskTexture(ccMask)

    -- Timer CC (durée restante du contrôle, centré dans la sphère)
    local ccFrame = CreateFrame("Frame", nil, root)
    ccFrame:SetAllPoints(orbFrame)
    ccFrame:SetFrameLevel(root:GetFrameLevel() + 9)
    local ccText = ccFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(ccText, "Fonts\\FRIZQT__.TTF", math.max(9, math.floor(SIZE * 0.22)))
    ccText:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    ccText:SetTextColor(0.90, 0.60, 1.00, 1)
    ccText:SetShadowColor(0, 0, 0, 1)
    ccText:SetShadowOffset(1, -1)
    ccText:Hide()

    -- ── 4. Barre de power (TOUJOURS créée, cachée si désactivée) ────────────
    local pw = SIZE
    local ph = 4
    local powerBar = CreateFrame("Frame", nil, root)
    powerBar:SetSize(pw, ph)
    powerBar:SetPoint("TOP", orbFrame, "BOTTOM", 0,
        -(cfg.powerOffsetY or 3) - bW)
    powerBar:SetFrameLevel(root:GetFrameLevel() + 7)
    if not cfg.showPower then powerBar:Hide() end

    local pbg = powerBar:CreateTexture(nil, "BACKGROUND")
    pbg:SetTexture(WHITE)
    pbg:SetAllPoints(powerBar)
    pbg:SetVertexColor(0, 0, 0, 0.6)

    local powerFill = powerBar:CreateTexture(nil, "ARTWORK")
    powerFill:SetTexture(WHITE)
    powerFill:SetPoint("LEFT", powerBar, "LEFT", 0, 0)
    powerFill:SetHeight(ph)
    powerFill:SetWidth(pw)
    powerFill:SetVertexColor(0, 0.4, 1)

    -- ── 5. Texte dans l'orbe (niveau / HP) ──────────────────────────────────
    local overlayFrame = CreateFrame("Frame", nil, root)
    overlayFrame:SetAllPoints(orbFrame)
    overlayFrame:SetFrameLevel(root:GetFrameLevel() + 9)

    local levelText = overlayFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(levelText, SP:GetFont(cfg.levelFont), cfg.levelFontSize or 11)
    levelText:SetPoint("CENTER", overlayFrame, "CENTER", 0, 0)
    levelText:SetJustifyH("CENTER")
    levelText:SetTextColor(1, 1, 1, 1)
    levelText:SetShadowColor(0, 0, 0, 1)
    levelText:SetShadowOffset(1, -1)
    if not cfg.showLevelOrHP then levelText:Hide() end

    local hpSubText = overlayFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(hpSubText, SP:GetFont(cfg.levelFont), math.max(7, (cfg.levelFontSize or 11) - 2))
    hpSubText:SetPoint("TOP", levelText, "BOTTOM", 0, -1)
    hpSubText:SetJustifyH("CENTER")
    hpSubText:SetTextColor(0.85, 0.85, 0.85, 0.9)
    hpSubText:SetShadowColor(0, 0, 0, 1)
    hpSubText:SetShadowOffset(1, -1)
    hpSubText:Hide()

    -- ── 6. Nom ────────────────────────────────────────────────────────────────
    -- name_maxWidth > 0 → utilise la valeur config ; sinon auto (2.6×SIZE)
    local nameW = (cfg.name_maxWidth and cfg.name_maxWidth > 0)
                  and cfg.name_maxWidth
                  or  math.max(SIZE * 2.6, 120)
    local nameFrame = CreateFrame("Frame", nil, root)
    nameFrame:SetSize(nameW, 22)
    nameFrame:SetFrameLevel(root:GetFrameLevel() + 13)

    -- Position selon nameDisplay (offsetX/Y appliqués)
    local nd = cfg.nameDisplay or "above"
    local nox = cfg.nameOffsetX or 0
    if nd == "center" then
        nameFrame:SetPoint("CENTER", orbFrame, "CENTER", nox, 0)
    else
        -- "above" et "hover" : au-dessus
        nameFrame:SetPoint("BOTTOM", orbFrame, "TOP", nox,
            (cfg.nameOffsetY or 6) + bW)
    end

    local nameText = nameFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(nameText, SP:GetFont(cfg.nameFont), cfg.nameFontSize or 12)
    nameText:SetAllPoints(nameFrame)
    nameText:SetJustifyH("CENTER")
    nameText:SetJustifyV("MIDDLE")
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    nameText:SetTextColor(1, 1, 1, 1)
    if not cfg.showName then nameText:Hide() end

    local subText = nameFrame:CreateFontString(nil, "OVERLAY")
    SafeSetFont(subText, SP:GetFont(cfg.nameFont), math.max(8, (cfg.nameFontSize or 12) - 2))
    subText:SetPoint("TOP", nameText, "BOTTOM", 0, 0)
    subText:SetJustifyH("CENTER")
    subText:SetTextColor(0.80, 0.80, 0.80, 0.85)
    subText:SetShadowColor(0, 0, 0, 1)
    subText:SetShadowOffset(1, -1)
    subText:Hide()

    -- ── 8. Glow contextuel unique ────────────────────────────────────────────
    -- UN seul glow auto-dimensionné par ancrage TOPLEFT/BOTTOMRIGHT proportionnel.
    -- La couleur et l'alpha sont gérés dans AnimTick selon priorité :
    --   aggro totale > aggro partielle > cible > focus > HP critique > fade out
    -- Padding proportionnel à SIZE — s'adapte automatiquement à la taille de l'orbe.
    local sgPad = math.floor(SIZE * 0.08)   -- ~5px à SIZE=64, reste dans l'orbe
    local singleGlow = root:CreateTexture(nil, "OVERLAY", nil, 3)
    singleGlow:SetTexture(M("orb_glow"))
    singleGlow:SetPoint("TOPLEFT",     orbFrame, "TOPLEFT",     -sgPad,  sgPad)
    singleGlow:SetPoint("BOTTOMRIGHT", orbFrame, "BOTTOMRIGHT",  sgPad, -sgPad)
    singleGlow:SetBlendMode("ADD")
    singleGlow:SetAlpha(0)

    local targetRipples = {}
    for i = 1, 4 do
        -- Sublevels 4,5,6,7 — max WoW = 7, donc 4 ripples max avec offset 3
        local ripple = root:CreateTexture(nil, "OVERLAY", nil, 3 + i)
        ripple:SetTexture("Interface\\Cooldown\\ping4")
        ripple:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
        ripple:SetBlendMode("ADD")
        ripple:SetAlpha(0)
        ripple:Hide()
        targetRipples[i] = ripple
    end

    -- ── 9. Icône Raid Mark ───────────────────────────────────────────────────
    local raidIconFrame = CreateFrame("Frame", nil, root)
    raidIconFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    raidIconFrame:SetSize(SIZE, SIZE)
    raidIconFrame:SetFrameLevel(root:GetFrameLevel() + 14)
    raidIconFrame:Hide()

    local raidIcon = raidIconFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    raidIcon:SetSize(SIZE * 0.45, SIZE * 0.45)
    raidIcon:SetPoint("TOP", orbFrame, "TOP", 0, SIZE * 0.22)
    raidIcon:SetAlpha(0)

    -- ── 10. Dragons élite ────────────────────────────────────────────────────
    local dragonL = root:CreateTexture(nil, "BORDER")
    dragonL:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")
    dragonL:SetSize(SIZE * 0.70, SIZE * 0.95)
    dragonL:SetPoint("RIGHT", orbFrame, "LEFT", SIZE * 0.09, 0)
    dragonL:SetAlpha(0)

    local dragonR = root:CreateTexture(nil, "BORDER")
    dragonR:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-EliteRight")
    dragonR:SetSize(SIZE * 0.70, SIZE * 0.95)
    dragonR:SetPoint("LEFT", orbFrame, "RIGHT", -SIZE * 0.09, 0)
    dragonR:SetAlpha(0)

    local bossEliteFrame = CreateFrame("Frame", nil, root)
    bossEliteFrame:SetPoint("CENTER", orbFrame, "CENTER", 0, 0)
    bossEliteFrame:SetSize(SIZE * 1.85, SIZE * 1.85)
    bossEliteFrame:SetFrameLevel(root:GetFrameLevel() + 10)
    bossEliteFrame:Hide()

    local bossEliteTex = bossEliteFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    bossEliteTex:SetTexture(SP.BOSS_ELITE_FRAME_PATH or (SP.MEDIA .. "Dragon_boss_elite.png"))
    bossEliteTex:SetAllPoints(bossEliteFrame)
    bossEliteTex:SetBlendMode("ADD")
    bossEliteTex:SetAlpha(1)

    -- ── 11. DATA TABLE ───────────────────────────────────────────────────────
    local data = {
        root         = root,
        orb          = orbFrame,
        bgFrame      = bgFrame,    -- frame dédié root+1 — strictement derrière orbFrame
        orbFrame     = orbFrame,
        mask         = mask,
        fillTex      = fillTex,
        bgTex        = bgTex,
        bgTex2       = bgTex2,
        galaxy1      = galaxy1,
        galaxy2      = galaxy2,
        galaxy3      = galaxy3,
        midnightStar = midnightStar,
        shimmer1     = shimmer1,
        shimmer2     = shimmer2,
        spark        = spark,
        waveT1       = waveT1,     -- vague DiabolicUI couche 1 (scroll horizontal)
        waveT2       = waveT2,     -- vague DiabolicUI couche 2 (phase opposée)
        overlayOrbFrame = overlayOrbFrame,
        glassFrame   = glassFrame,    -- frame dédié root+6 : glass/gloss/shadow/specular
        glassTex     = glassTex,
        glassTex2    = glassTex2,
        glossTex     = glossTex,
        shadowTex    = shadowTex,
        borderOverlay      = borderOverlay,
        borderOverlayFrame = borderOverlayFrame,
        shadeOverlay       = shadeOverlay,
        ccOverlayFrame     = ccOverlayFrame,
        ccOverlay          = ccOverlay,
        ccFrame            = ccFrame,
        ccText             = ccText,
        maskInner    = maskInner,    -- diamètre du masque interne (SIZE - bW*2)
        powerBar     = powerBar,
        powerFill    = powerFill,
        shadowTex2   = shadowTex2,
        specular     = specular,
        fillSurface  = fillSurface,
        singleGlow   = singleGlow,   -- glow contextuel unique (aggro/cible/focus/lowHP)
        targetRipples = targetRipples,
        raidIconFrame = raidIconFrame,
        raidIcon     = raidIcon,
        dragonL      = dragonL,
        dragonR      = dragonR,
        bossEliteFrame = bossEliteFrame,
        bossEliteTex = bossEliteTex,
        levelText       = levelText,
        hpSubText       = hpSubText,
        overlayFrame    = overlayFrame,
        nameFrame       = nameFrame,
        nameText        = nameText,
        subText         = subText,
        unitType     = unitType,
        hpBar        = hpBar,      -- StatusBar vertical (fill taint-safe)
        orbSize      = SIZE,
        plate        = plate,
        unit         = nil,        -- rempli par OnPlateAdded
        targetHP     = nil,
        displayHP    = nil,
        _lastRatio   = nil,
        _displayRatio= nil,
        _glowTime    = 0,   -- accumulateur temps partagé pour singleGlow
        _midnightStarAngle = 0,
        _isTarget    = false,
        _isFocus     = false,
        _inCombat    = false,
        _aggroLevel  = 0,   -- 0=neutre, 1=faible, 2=moyen, 3=aggro totale
    }

    SP.Orb:ApplySphereVisibility(data, cfg)
    return data
end

-------------------------------------------------------------------------------
--  VISIBILITE SPHERE
--  Le root, le nom, les auras et la castbar restent disponibles afin que
--  Text/Name garde son autonomie. La sphere visuelle suit sphere_display_mode.
-------------------------------------------------------------------------------
function SP.Orb:GetSphereDisplayMode(cfg)
    cfg = cfg or {}
    local mode = cfg.sphere_display_mode
    if mode == "never" or cfg.enabled == false then return "never" end
    if mode == "combat" or mode == "target" or mode == "always" then return mode end
    return "always"
end

function SP.Orb:ShouldShowSphere(data, cfg)
    cfg = cfg or (data and SP:GetCfg(data.unitType)) or {}
    local mode = self:GetSphereDisplayMode(cfg)
    if mode == "never" then return false end
    if mode == "always" then return true end

    local inCombat = (SP.InCombat == true) or (data and data._inCombat == true)
    if mode == "combat" then return inCombat end

    if mode == "target" then
        local isTarget = data and data._isTarget == true
        if not isTarget and data and data.unit then
            local ok, same = pcall(UnitIsUnit, data.unit, "target")
            isTarget = ok and same == true
        end
        return isTarget or inCombat
    end

    return true
end

function SP.Orb:ApplySphereVisibility(data, cfg)
    if not data then return end
    cfg = cfg or SP:GetCfg(data.unitType)
    local visible = self:ShouldShowSphere(data, cfg)

    local function setShown(frame, state)
        if not frame then return end
        if frame.SetShown then
            pcall(frame.SetShown, frame, state)
        elseif state then
            pcall(frame.Show, frame)
        else
            pcall(frame.Hide, frame)
        end
    end

    setShown(data.orbFrame, visible)
    setShown(data.hpBar, visible)
    setShown(data.overlayOrbFrame, visible)
    setShown(data.glassFrame, visible)
    setShown(data.borderOverlayFrame, visible)
    setShown(data.overlayFrame, visible)
    setShown(data.ccOverlayFrame, visible)
    setShown(data.ccFrame, visible)
    setShown(data.powerBar, visible and cfg.showPower == true)

    if not visible then
        if data.singleGlow then pcall(data.singleGlow.SetAlpha, data.singleGlow, 0) end
        if data.ccOverlay then pcall(data.ccOverlay.SetAlpha, data.ccOverlay, 0) end
        if data.ccText then pcall(data.ccText.Hide, data.ccText) end
        if data.dragonL then pcall(data.dragonL.SetAlpha, data.dragonL, 0) end
        if data.dragonR then pcall(data.dragonR.SetAlpha, data.dragonR, 0) end
        if data.bossEliteFrame then pcall(data.bossEliteFrame.Hide, data.bossEliteFrame) end
    end

    if data.unit and SP.Orb.UpdateRaidMark then pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, data.unit) end

    data._sphereVisible = visible
    return visible
end

-------------------------------------------------------------------------------
--  LERP — fixe le ratio cible, le LerpTick interpole vers cette valeur
--
--  Cas spéciaux traités immédiatement (sans lerp) :
--   • Premier appel (_displayRatio == nil)
--   • Saut > 50% (résurrection, apparition d'unité, etc.)
-------------------------------------------------------------------------------
function SP.Orb:SetTargetRatio(data, ratio)
    if not data then return end
    ratio = math.max(0, math.min(1, ratio))

    local isFirst   = (data._displayRatio == nil)
    local isBigJump = (not isFirst and
                       math.abs(ratio - data._displayRatio) > 0.5)

    if isFirst or isBigJump then
        -- Mise à jour immédiate : pas de lerp pour les cas extrêmes
        data._displayRatio = ratio
        SP.Orb:UpdateFill(data, ratio)
    end

    -- Stocker la cible — LerpTick() gère l'interpolation progressive
    data._lastRatio = ratio
end

-- Appelé depuis Core OnUpdate (~60 FPS)
--
-- hp_lerp_speed (1–30) est lu depuis la config de chaque unité.
-- Conversion : k = speed * 0.018 → vitesse=1 → k≈0.02 (lent) / 8 → k≈0.14 (défaut) / 30 → k≈0.54 (rapide)
-- Le clamp à 0.90 évite les overshoots à très haute vitesse.
function SP.Orb:LerpTick()
    for _, data in pairs(SP.Plates) do
        local target  = data._lastRatio    or 1
        local current = data._displayRatio or target
        local diff    = target - current

        if math.abs(diff) > 0.0005 then
            -- Lire la vitesse depuis la config (per-unit, sans GC — GetCfg = simple table lookup)
            local cfg   = SP:GetCfg(data.unitType)
            local speed = cfg.hp_lerp_speed or 8.0
            local lerpK = math.min(0.90, speed * 0.018)

            local newRatio = current + diff * lerpK
            data._displayRatio = newRatio
            SP.Orb:UpdateFill(data, newRatio)
        elseif current ~= target then
            -- Snap final pour éliminer les micro-drifts
            data._displayRatio = target
            SP.Orb:UpdateFill(data, target)
        end
    end
end

-------------------------------------------------------------------------------
--  FILL HP (ratio 0→1)
--  Technique : SetHeight sur fillTex (ancre BOTTOM fixe) + masque circulaire
--  CORRECTION : utilise data.unit (stocké dans OnPlateAdded) pour class-color
-------------------------------------------------------------------------------
function SP.Orb:UpdateFill(data, ratio)
    if not data then return end
    -- Ratio par défaut : dernier ratio clean connu, ou 1 (plein) si inconnu
    if ratio == nil then
        ratio = data._displayRatio or data._lastRatio or data.targetHP or 1
    end
    ratio = math.max(0, math.min(1, ratio))

    -- NOTE : data.hpBar (StatusBar) gère la hauteur du fill directement via SetValue.
    -- UpdateFill met à jour uniquement les effets visuels (couleur, glow, spark).
    -- Ne pas appeler ft:SetHeight / ft:Hide / ft:Show — le StatusBar le fait nativement.

    -- Spark : toujours visible — ancré sur fillTex:TOP (cross-frame, cf. Create).
    -- Il suit automatiquement la ligne de flottaison du StatusBar sans qu'on
    -- connaisse le ratio exact (qui est tainté en WoW Midnight 12.x).
    -- On ne change pas son alpha dynamiquement pour la même raison.
    if data.spark then
        local cfg_spark = SP:GetCfg(data.unitType)
        if cfg_spark.orb_spark ~= false then
            data.spark:Show()
        else
            data.spark:Hide()
        end
    end

    local cfg = SP:GetCfg(data.unitType) or {}
    -- Utiliser la classe cachée pour éviter SafeUnitClass en contexte tainté (60fps)
    local isPlayer = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
    if not data._cachedClass and isPlayer and data.unit then
        local cls = SafeUnitClass(data.unit, true)
        if cls then data._cachedClass = cls end
    end
    local fillR, fillG, fillB, fillA = ResolveFillColor(cfg, data.unit, ratio, data._cachedClass, isPlayer)

    -- ── Seuils HP depuis la config (convertis en ratio 0–1) ───────────────────

    -- NOTE : le glow HP bas est désormais géré par singleGlow dans AnimTick.
    -- UpdateFill ne touche plus aux glows ; il gère uniquement la couleur du fill.

    -- ── Couleur dynamique selon HP — paliers orange/rouge depuis la config ─────
    if data.fillTex then data.fillTex:SetVertexColor(fillR, fillG, fillB, fillA) end
    -- Stocker la couleur de fill pour applyHPColor (proxy quand ratio Lua est indisponible)
    data._lastFillR, data._lastFillG, data._lastFillB = fillR, fillG, fillB

    -- Fill surface : suit la couleur HP (orange/rouge inclus) — CORRIGÉ : était avant la définition de fillR/fillG/fillB
    if data.fillSurface then
        data.fillSurface:SetVertexColor(fillR, fillG, fillB)
        local sfA = (0.22 - (1 - ratio) * 0.08) * fillA   -- 0.22 (plein) → 0.14 (vide)
        data.fillSurface:SetAlpha(math.max(0.06, sfA))
    end

    if data.shimmer1 then
        data.shimmer1:SetVertexColor(fillR, fillG, fillB)
    end

    -- Galaxy : teinte selon état HP
    if data.galaxy1 then
        data.galaxy1:SetVertexColor(fillR, fillG, fillB)
    end
    if data.galaxy2 then
        data.galaxy2:SetVertexColor(fillR * 0.7, fillG * 0.7, math.min(1, fillB * 1.3))
    end
    if data.galaxy3 then
        data.galaxy3:SetVertexColor(fillR, math.min(1, fillG * 1.1), fillB)
    end
end

-------------------------------------------------------------------------------
--  SOFT UPDATE — met à jour couleurs/textes/visibilité SANS recréer les frames
--  Appelé par RefreshAll() quand orbSize ne change pas
--
--  FIX v7.2 : root:Show() explicite au début pour éviter qu'une plaque reste
--  cachée si OnPlateRemoved avait été appelé sans OnPlateAdded dans la foulée
-------------------------------------------------------------------------------
function SP.Orb:RefreshUnitColors(data, unit, ratio)
    if not data then return end
    unit = unit or data.unit
    local cfg = SP:GetCfg(data.unitType)
    -- Résoudre et cacher la classe joueur (contexte propre lors de l'appel depuis OnPlateAdded)
    local isPlayer = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
    if not data._cachedClass then
        local cls = SafeUnitClass(unit, isPlayer)
        if cls then data._cachedClass = cls end
    end
    local fr, fg, fb = ResolveFillColor(cfg, unit, ratio or data._displayRatio or data.displayHP or data.targetHP or 1, data._cachedClass, isPlayer)

    data.unit = unit
    SP.Orb:UpdateFill(data, ratio or data._displayRatio or data.displayHP or data.targetHP or 1)

    SafeSetVertexColor(data.shimmer2, fr * 0.8, fg * 0.8, math.min(1, fb * 1.1), 1)
    SafeSetVertexColor(data.waveT1, fr, fg, fb, 1)
    SafeSetVertexColor(data.waveT2, fr * 0.85, fg * 0.85, math.min(1, fb * 1.15), 1)

    if data.borderOverlay and not data._inCombat then
        local bInfo2 = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(cfg.borderStyle)
        if not bInfo2 or bInfo2.tint ~= false then
            local br, bg, bb = GetBorderColor(cfg, unit)
            SafeSetVertexColor(data.borderOverlay, br, bg, bb, 1)
        end
    end

    data._lastColorUnit = unit
    data._lastColorUnitType = data.unitType
end

function SP.Orb:SoftUpdate(data, unit)
    if not data or not data.root then return end
    -- S'assurer que le root reste visible : cfg.enabled ne masque que l'orbe.
    data.root:Show()
    local cfg  = SP:GetCfg(data.unitType)
    -- SoftUpdate est appelé depuis un contexte UI propre — opportunité de cacher la classe
    local isPlayer = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
    if not data._cachedClass and isPlayer and unit then
        local cls = SafeUnitClass(unit, true)
        if cls then data._cachedClass = cls end
    end
    local fr, fg, fb = ResolveFillColor(cfg, unit, data._displayRatio or data.displayHP or data.targetHP or 1, data._cachedClass, isPlayer)

    -- Fond : couleur configurable (noir par défaut)
    if data.bgTex then
        -- bgTex est sur bgFrame (root+1) → draw order garanti, SetDrawLayer inutile
        data.bgTex:SetVertexColor(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0)
        data.bgTex:SetAlpha(cfg.bgAlpha or 1.0)
    end
    -- bgTex2 est sur bgFrame (root+1) — draw order garanti, SetDrawLayer inutile

    -- Shimmer/Galaxy/Glow : re-teinter selon fill color de l'unité.
    if data.shimmer2 then
        data.shimmer2:SetVertexColor(fr*0.8, fg*0.8, math.min(1, fb*1.1))
    end
    local gA = cfg.orb_galaxy_alpha or 0.20
    if data.galaxy1 then
        data.galaxy1:SetVertexColor(fr, fg, fb)
        data.galaxy1:SetAlpha(gA)
        data.galaxy1:SetShown(cfg.orb_galaxies ~= false)
    end
    if data.galaxy2 then
        data.galaxy2:SetVertexColor(fr*0.7, fg*0.7, math.min(1, fb*1.3))
        data.galaxy2:SetAlpha(gA * 0.80)
        data.galaxy2:SetShown(cfg.orb_galaxies ~= false)
    end
    if data.galaxy3 then
        data.galaxy3:SetVertexColor(fr, math.min(1, fg*1.1), fb)
        data.galaxy3:SetAlpha(gA * 0.65)
        data.galaxy3:SetShown(cfg.orb_galaxies ~= false)
    end
    if data.midnightStar then
        local msScale = math.max(0.50, math.min(2.50, tonumber(cfg.orb_midnight_star_scale) or 1.18))
        data.midnightStar:SetSize((data.orbSize or 64) * msScale, (data.orbSize or 64) * msScale)
        data.midnightStar:SetAlpha(math.max(0, math.min(1, tonumber(cfg.orb_midnight_star_alpha) or 0.55)))
        data.midnightStar:SetShown(cfg.orb_midnight_star == true)
    end
    -- Shimmer alpha depuis cfg
    local sA = cfg.orb_shimmer_alpha or 0.40
    if data.shimmer1 then data.shimmer1:SetAlpha(sA) end
    if data.shimmer2 then data.shimmer2:SetAlpha(sA * 0.60) end
    -- Gloss : afficher/cacher + alpha
    local gOA = cfg.orb_gloss_alpha or 0.45
    if data.glassTex  then data.glassTex:SetAlpha(gOA) ; data.glassTex:SetShown(cfg.orb_gloss ~= false) end
    if data.glassTex2 then data.glassTex2:SetAlpha(gOA * 0.50) ; data.glassTex2:SetShown(cfg.orb_gloss ~= false) end
    if data.glossTex  then data.glossTex:SetAlpha(math.min(1, gOA * 1.15)) ; data.glossTex:SetShown(cfg.orb_gloss ~= false) end
    -- Textures DiabolicUI (filling) : afficher/cacher + recoulorer
    local show_wave = cfg.orb_wave ~= false
    local wA2 = cfg.orb_wave_alpha or 0.38
    if data.waveT1 then
        data.waveT1:SetShown(show_wave)
        data.waveT1:SetAlpha(wA2)
        data.waveT1:SetVertexColor(fr, fg, fb)
    end
    if data.waveT2 then
        data.waveT2:SetShown(show_wave)
        data.waveT2:SetAlpha(wA2 * 0.65)
        data.waveT2:SetVertexColor(fr * 0.85, fg * 0.85, math.min(1, fb * 1.15))
    end
    -- Specular highlight : toujours visible, alpha fixe
    if data.specular then data.specular:SetAlpha(0.28) end

    -- Fill surface : re-teinter selon nouvelle couleur fill
    if data.fillSurface then
        data.fillSurface:SetVertexColor(fr, fg, fb)
    end

    -- Recalculer effets visuels (spark, lowHP glow, fill color)
    SP.Orb:UpdateFill(data, nil)

    -- Bordure décorative : redimensionner + mettre à jour texture / couleur / alpha
    local br2, bg2, bb2 = GetBorderColor(cfg, unit)
    if data.borderOverlayFrame then
        local bOScale2 = cfg.borderOverlayScale or 1.5
        local bOSize2  = math.floor(data.orbSize * bOScale2)
        data.borderOverlayFrame:SetSize(bOSize2, bOSize2)
    end
    if data.borderOverlay then
        local bInfo = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(cfg.borderStyle)
        local bPath = bInfo and bInfo.path
        if bPath then
            data.borderOverlay:SetTexture(bPath)
            -- UV spritesheet : applique la région si définie, sinon texture entière
            if bInfo.uv then
                data.borderOverlay:SetTexCoord(bInfo.uv[1], bInfo.uv[2], bInfo.uv[3], bInfo.uv[4])
            else
                data.borderOverlay:SetTexCoord(0, 1, 0, 1)
            end
            data.borderOverlay:SetBlendMode(bInfo.blend or "BLEND")
            if bInfo.tint == false then
                data.borderOverlay:SetVertexColor(1, 1, 1, 1)
            else
                data.borderOverlay:SetVertexColor(br2, bg2, bb2, 1)
            end
            data.borderOverlay:SetAlpha(cfg.borderEnabled ~= false and 1.0 or 0)
            data.borderOverlay:SetAllPoints(data.borderOverlayFrame)
        else
            data.borderOverlay:SetAlpha(0)
        end
    end

    if data.shadeOverlay then
        local shadeSize = data.orbSize
        data.shadeOverlay:SetSize(shadeSize, shadeSize)
        data.shadeOverlay:SetAlpha(cfg.shadeCircleEnabled and (cfg.shadeCircleAlpha or 0.6) or 0)
    end

    -- SetFont dynamique : les sliders de taille / police prennent effet immédiatement
    -- sans retarget ni /reload. Chaque changement de slider passe par refresh() → SoftUpdate.
    if data.levelText then
        SafeSetFont(data.levelText, SP:GetFont(cfg.levelFont), cfg.levelFontSize or 11)
    end
    if data.hpSubText then
        SafeSetFont(data.hpSubText, SP:GetFont(cfg.levelFont), math.max(7, (cfg.levelFontSize or 11) - 2))
    end
    if data.nameText then
        SafeSetFont(data.nameText, SP:GetFont(cfg.nameFont), cfg.nameFontSize or 12)
    end
    if data.subText then
        SafeSetFont(data.subText, SP:GetFont(cfg.nameFont), math.max(8, (cfg.nameFontSize or 12) - 2))
    end

    -- Power bar
    if data.powerBar then
        data.powerBar:SetShown(cfg.showPower == true)
        if cfg.showPower and unit then
            SP.Orb:UpdatePower(data, unit)
        end
    end

    -- Position de la sphère sur la plaque (offsetX/Y changeable sans rebuild)
    if data.plate and data.root then
        data.root:ClearAllPoints()
        data.root:SetPoint("CENTER", data.plate, "CENTER",
            cfg.offsetX or 0, cfg.offsetY or 0)
    end

    -- Nom : position selon nameDisplay
    if data.nameText then
        local nd = cfg.nameDisplay or "above"
        local nf = data.nameFrame or data.nameText:GetParent()  -- nameFrame
        if nf then
            nf:ClearAllPoints()
            local nox2 = cfg.nameOffsetX or 0
            if nd == "center" then
                nf:SetPoint("CENTER", data.orbFrame, "CENTER", nox2, 0)
            else
                local bW = math.max(4, math.floor(data.orbSize * 0.09))
                nf:SetPoint("BOTTOM", data.orbFrame, "TOP", nox2,
                    (cfg.nameOffsetY or 6) + bW)
            end
            -- Feature 3 : largeur max dynamique
            local maxW = (cfg.name_maxWidth and cfg.name_maxWidth > 0)
                         and cfg.name_maxWidth
                         or  math.max(data.orbSize * 2.6, 120)
            nf:SetWidth(maxW)
        end
    end

    -- ── CastBar : gestion enable/disable + changement de mode ───────────────────
    -- SoftUpdate est appelé à chaque changement de config UI.
    -- On reconstruit le CastBar si : activé→désactivé, désactivé→activé, ou mode changé.
    -- Les options de rendu (showName/showTime/fontSize) prennent effet au prochain cast.
    do
        local cbEnabled = cfg.castbar_enabled
        local cbMode    = SP.NormalizeCastbarMode and SP:NormalizeCastbarMode(cfg.castbar_mode) or (cfg.castbar_mode or "classic")
        if data.castbar then
            local needRebuild = false
            if not cbEnabled then
                needRebuild = true   -- castbar désactivé → nettoyer
            elseif data.castbar._createdMode ~= cbMode then
                needRebuild = true   -- mode changé (circular ↔ classic) → recréer
            else
                -- Mode circulaire : tout changement de style nécessite un rebuild
                local circ = data._cb_circ
                if circ then
                    if circ.cast_style    ~= (cfg.castbar_cast_style or "smooth")
                    or circ.channel_style ~= (cfg.castbar_channel_style or "swipe")
                    or circ.preset        ~= (cfg.castbar_preset or "minimal")
                    or (circ.v8_enabled == true) ~= ((cbMode == "circular") or (cbMode == "segments") or (cbMode == "dotted") or (cbMode == "collapse") or (cbMode == "collapse_glow") or (cfg.castbar_v8_segments == true))
                    or (circ.v8Count or 0) ~= ((cbMode == "circular") and 64 or (((cbMode == "segments") or (cfg.castbar_v8_segments == true)) and (cfg.castbar_v8_count or 20) or 0))
                    or (circ.dottedCount or 0) ~= ((cbMode == "dotted") and (cfg.castbar_dotted_count or 18) or 0)
                    or (circ.dottedSize or 0) ~= ((cbMode == "dotted") and (cfg.castbar_dotted_size or 5) or 0)
                    or (circ.collapseTex ~= nil) ~= (cbMode == "collapse")
                    or (circ.collapseGlow ~= nil) ~= (cbMode == "collapse_glow")
                    or (circ.ticks ~= nil) ~= (cfg.castbar_show_ticks == true)
                    or (circ.bevelOut ~= nil) ~= (cfg.castbar_show_bevel ~= false)
                    or (circ.trackCD ~= nil) ~= (cfg.castbar_show_track ~= false)
                    or (circ.pin12 ~= nil) ~= (cfg.castbar_show_pin12 ~= false)
                    or (circ.completeRing ~= nil) ~= (cfg.castbar_complete_flash ~= false)
                    or (circ.kickShards ~= nil) ~= (cfg.castbar_show_kick_fx ~= false)
                    then needRebuild = true end
                end
                if data.castbar and data.castbar.barTexture and data.castbar.barTexture ~= (cfg.castbar_texture or "white") then
                    needRebuild = true
                end
            end
            if needRebuild then
                pcall(SP.CastBar.Reset, SP.CastBar, data)
                data.castbar    = nil
                data._cb_circ   = nil
                data._cb_sprite = nil
                data._cb_ccb    = nil
            end
        end
        if cbEnabled and not data.castbar then
            local ok_cb, cb_res = pcall(SP.CastBar.Create, SP.CastBar, data)
            if ok_cb and cb_res then data.castbar = cb_res end
        end
    end

    -- Mise à jour textes et indicateurs
    SP.Orb:UpdateName(data, unit)
    SP.Orb:UpdateLevelText(data, unit)
    SP.Orb:UpdateElite(data, unit)
    SP.Orb:UpdateCombat(data, unit)
    SP.Orb:UpdateRaidMark(data, unit)
    if SP.Auras and unit then
        pcall(SP.Auras.UpdateUnit, SP.Auras, data, unit, nil)
    end
    SP.Orb:ApplySphereVisibility(data, cfg)
end

-------------------------------------------------------------------------------
--  FILL POWER
-------------------------------------------------------------------------------
function SP.Orb:UpdatePower(data, unit)
    if not data.powerFill then return end
    if not unit then return end
    local cfg = SP:GetCfg(data.unitType)
    if not SP.Orb:ShouldShowSphere(data, cfg) or not cfg.showPower then
        if data.powerBar then data.powerBar:Hide() end
        return
    end

    local ptype  = UnitPowerType(unit)
    local pw     = UnitPower(unit, ptype) or 0
    local pwMax  = UnitPowerMax(unit, ptype) or 1
    if pwMax <= 0 then pwMax = 1 end

    local ratio = pw / pwMax
    local SIZE  = data.orbSize
    data.powerFill:SetWidth(math.max(1, SIZE * ratio))

    local pr, pg, pb = GetPowerColor(ptype)
    data.powerFill:SetVertexColor(pr, pg, pb)
    if data.powerBar then
        data.powerBar:SetAlpha(pwMax > 0 and 1 or 0)
    end
end

-------------------------------------------------------------------------------
--  TEXTE ORBE (niveau / HP%) — v7.2
--
--  Logique :
--   • En dehors du combat (ou allié) : affiche le niveau si disponible
--   • En combat (ennemi) : affiche HP% directement
--   • Si pas de niveau (max level, preview, etc.) : affiche toujours HP%
--   • showHPAlsoInOrb : sous-texte HP% sous le niveau
--   • Toujours afficher quelque chose (jamais vide)
-------------------------------------------------------------------------------
function SP.Orb:UpdateLevelText(data, unit)
    local lt = data.levelText
    if not lt then return end
    local cfg = SP:GetCfg(data.unitType)

    if not SP.Orb:ShouldShowSphere(data, cfg) or not cfg.showLevelOrHP then
        lt:Hide()
        if data.hpSubText then data.hpSubText:Hide() end
        return
    end

    -- Ajustement de taille du texte central en mode ring avec auras actives :
    -- les icônes encerclent l'orbe au plus près → on réduit le texte central
    -- pour équilibrer visuellement. Change seulement si l'état a changé.
    do
        local baseFS   = cfg.levelFontSize or 11
        local auraMode = cfg.auras_mode or "icons"
        local ringOn   = (auraMode == "ring" or auraMode == "segments")
                         and (data._ringAuraCount or 0) > 0
        local targetFS = ringOn and math.max(7, baseFS - 3) or baseFS
        local curFS    = data._levelTextFontSize
        if curFS ~= targetFS then
            data._levelTextFontSize = targetFS
            SafeSetFont(lt, SP:GetFont(cfg.levelFont or "Friz Quadrata TT"), targetFS)
        end
    end

    local utype    = data.unitType
    local isAlly   = (utype == "FRIENDLY" or utype == "FRIENDLY_PLAYER")
    local isPlayer = (utype == "FRIENDLY_PLAYER" or utype == "ENEMY_PLAYER")

    -- Mode preview (unit=nil) : texte fictif
    if not unit then
        SP:ApplyHPTextPair(lt, data.hpSubText, data, nil, cfg.hpFormat or "percent", cfg.hp_show_percent)
        return
    end

    -- PRIORITÉ 1 : JOUEUR au NIVEAU MAX → iLvL ou "MAX"
    -- (PNJ au niveau max passent directement aux priorités HP/niveau)
    local maxLvl  = GetMaxPlayerLevel and GetMaxPlayerLevel() or 90
    local unitLvl = UnitLevel(unit) or 0
    if isPlayer and unitLvl >= maxLvl then
        local ratio  = data.targetHP or data.displayHP or data._displayRatio or data._lastRatio
        local fullHP = true
        if ratio then pcall(function() fullHP = ratio >= 0.98 end) end

        if isPlayer and cfg.show_ilvl ~= false and fullHP then
            local ilvl = SP:GetUnitItemLevel(unit)
            if ilvl then
                local hex = (SP.GetIlvlColorHex and SP:GetIlvlColorHex(ilvl)) or "FFD700"
                lt:SetTextColor(1, 1, 1, 1)
                lt:SetText("|cFF" .. hex .. tostring(ilvl) .. "|r")
                lt:Show()
                if data.hpSubText then
                    if cfg.show_hp_under_maxlvl then
                        local subFmt = cfg.hpFormat or "percent"
                        if subFmt == "both" then subFmt = "absolute" end
                        SP:ApplyHPText(data.hpSubText, data, unit, subFmt, cfg.hp_show_percent)
                        data.hpSubText:Show()
                    else
                        data.hpSubText:Hide()
                    end
                end
                return
            end
        end

        -- Pas d'iLvL (ou PNJ) → "MAX" grisé pour indiquer niveau maximum
        lt:SetTextColor(1, 1, 1, 1)
        lt:SetText("|cFF888888" .. maxLvl .. "|r")
        lt:Show()
        if data.hpSubText then
            if cfg.show_hp_under_maxlvl then
                local subFmt = cfg.hpFormat or "percent"
                if subFmt == "both" then subFmt = "absolute" end
                SP:ApplyHPText(data.hpSubText, data, unit, subFmt, cfg.hp_show_percent)
                data.hpSubText:Show()
            else
                data.hpSubText:Hide()
            end
        end
        return
    end

    -- PRIORITÉ 2 : showHPAlsoInOrb → HP toujours affiché comme texte principal
    if cfg.showHPAlsoInOrb then
        local fmt = cfg.hpFormat or "percent"
        SP:ApplyHPTextPair(lt, data.hpSubText, data, unit, fmt, cfg.hp_show_percent)
        return
    end

    -- PRIORITÉ 3 : ennemi en combat → HP directement (format configuré)
    local inCombat = not isAlly and UnitAffectingCombat(unit)
    if inCombat then
        local fmt = cfg.hpFormat or "percent"
        SP:ApplyHPTextPair(lt, data.hpSubText, data, unit, fmt, cfg.hp_show_percent)
        return
    end

    -- PRIORITÉ 4 : niveau (retourne nil pour max-level)
    local lvlStr = SP:GetLevelText(unit)
    if lvlStr then
        lt:SetTextColor(1, 1, 1, 1)
        lt:SetText(lvlStr)
        lt:Show()
        if data.hpSubText then
            if cfg.showHPAlsoInOrb and not isAlly then
                local subFmt = cfg.hpFormat or "percent"
                if subFmt == "both" then subFmt = "absolute" end
                SP:ApplyHPText(data.hpSubText, data, unit, subFmt, cfg.hp_show_percent)
                data.hpSubText:Show()
            else
                data.hpSubText:Hide()
            end
        end
        return
    end

    -- PRIORITÉ 5 / FALLBACK : HP (max-level PNJ, ou joueur sans données iLvL)
    local fmt2 = cfg.hpFormat or "percent"
    SP:ApplyHPTextPair(lt, data.hpSubText, data, unit, fmt2, cfg.hp_show_percent)
end

-------------------------------------------------------------------------------
--  NOM + SOUS-TITRE
-------------------------------------------------------------------------------
function SP.Orb:UpdateName(data, unit)
    local nt = data.nameText
    if not nt then return end
    local cfg = SP:GetCfg(data.unitType)

    -- ── Tout masquer si désactivé ─────────────────────────────────────────────
    if not cfg.showName then
        nt:Hide()
        if data.subText then data.subText:Hide() end
        return
    end

    local name  = (unit and UnitName(unit)) or "Prévisualisation"
    local utype = data.unitType

    -- ── Couleur : ResolveNameColor (mode + saturation + alpha) ──────────────
    local isPlayer = (utype == "ENEMY_PLAYER" or utype == "FRIENDLY_PLAYER")
    local ratio    = data.displayHP or 1
    local nr, ng, nb, nameColorAlpha, nameMode = ResolveNameColor(cfg, unit, ratio, isPlayer)

    -- Mode "auto" / "fixed" sans couleur custom : classification implicite WoW
    if (nameMode == "auto" or nameMode == "fixed") and not cfg.nameR then
        local cl = unit and UnitClassification(unit) or ""
        if     cl == "worldboss"                   then nr, ng, nb = 1.0, 0.40, 0.0
        elseif cl == "elite" or cl == "rareelite"  then nr, ng, nb = 1.0, 0.84, 0.0
        elseif cl == "rare"                        then nr, ng, nb = 0.70, 0.50, 1.0
        elseif utype == "FRIENDLY" or utype == "FRIENDLY_PLAYER" then
            nr, ng, nb = 0.40, 1.0, 0.40
        elseif utype == "ENEMY_PLAYER"             then nr, ng, nb = 1.0, 0.40, 0.40
        end
        -- Réappliquer saturation sur la couleur de classification
        nr, ng, nb = ApplySaturation(nr, ng, nb, cfg.name_saturation or 1)
    end

    -- ── Couleur quête : bleu si PNJ de quête (priorité sur classification) ──────
    if data.isQuestUnit and cfg.quest_color_name ~= false then
        nr, ng, nb = 0.40, 0.70, 1.0
    end

    -- ── Alpha "hover" : visible seulement sur la cible ───────────────────────
    local nameAlpha = nameColorAlpha
    if (cfg.nameDisplay or "above") == "hover" then
        local isTarget = unit and UnitIsUnit(unit, "target")
        nameAlpha = isTarget and nameColorAlpha or 0.0
    end

    -- ── Aggro → surcharge couleur en rouge/orange (priorité absolue) ─────────
    local aggroLevel = data._aggroLevel or 0
    if aggroLevel >= 3 then
        nr, ng, nb = 1.0, 0.20, 0.20
    elseif aggroLevel == 2 then
        nr, ng, nb = 1.0, 0.55, 0.20
    end

    nt:SetTextColor(nr, ng, nb, 1)
    nt:SetAlpha(nameAlpha)
    nt:SetText(name)
    nt:Show()

    -- ── Sous-titre ────────────────────────────────────────────────────────────
    if data.subText and cfg.showSubTitle and unit then
        local parts = {}
        local guild = GetGuildInfo and GetGuildInfo(unit)
        if guild and cfg.showGuild then
            parts[#parts+1] = "|cFFAAAAFF<" .. guild .. ">|r"
        end
        if UnitIsPlayer(unit) and cfg.showHonor then
            local honorLevel = UnitHonorLevel and UnitHonorLevel(unit)
            if honorLevel and honorLevel > 0 then
                parts[#parts+1] = "|cFFFF8C00PvP " .. honorLevel .. "|r"
            end
        end
        if #parts > 0 then
            data.subText:SetText(table.concat(parts, "  "))
            data.subText:Show()
        else
            data.subText:Hide()
        end
    elseif data.subText then
        data.subText:Hide()
    end
end

-------------------------------------------------------------------------------
--  ÉLITE / DRAGONS
-------------------------------------------------------------------------------
function SP.Orb:UpdateElite(data, unit)
    local cfg = SP:GetCfg(data.unitType)
    local visible = SP.Orb:ShouldShowSphere(data, cfg)
    if not visible then
        if data.dragonL then data.dragonL:SetAlpha(0) end
        if data.dragonR then data.dragonR:SetAlpha(0) end
        if data.bossEliteFrame then data.bossEliteFrame:Hide() end
        return
    end

    local cl = unit and UnitClassification(unit) or ""
    local isBoss = cl == "worldboss"
    local bossCfg = SP.db or {}
    local showBossFrame = isBoss and bossCfg.boss_elite_frame_enabled ~= false and data.bossEliteFrame
    if showBossFrame then
        local scale = tonumber(bossCfg.boss_elite_frame_scale) or 1.85
        local alpha = tonumber(bossCfg.boss_elite_frame_alpha) or 1.0
        scale = math.max(0.5, math.min(3.0, scale))
        alpha = math.max(0, math.min(1, alpha))
        local size = (data.orbSize or (cfg.size or 64)) * scale
        data.bossEliteFrame:SetSize(size, size)
        data.bossEliteFrame:SetAlpha(alpha)
        data.bossEliteFrame:Show()
    elseif data.bossEliteFrame then
        data.bossEliteFrame:Hide()
    end

    if not cfg.showEliteDragon or showBossFrame then
        data.dragonL:SetAlpha(0) ; data.dragonR:SetAlpha(0) ; return
    end

    local isElite = cl == "elite" or cl == "worldboss" or cl == "rareelite"
    if isElite then
        local r, g, b
        if cl == "worldboss" then
            r, g, b = 1.0, 0.30, 0.0
        else
            r, g, b = 1.0, 0.84, 0.0
        end
        data.dragonL:SetVertexColor(r, g, b)
        data.dragonR:SetVertexColor(r, g, b)
        data.dragonL:SetAlpha(0.90)
        data.dragonR:SetAlpha(0.90)
    else
        data.dragonL:SetAlpha(0)
        data.dragonR:SetAlpha(0)
    end
end

-------------------------------------------------------------------------------
--  INDICATEUR COMBAT
-------------------------------------------------------------------------------
function SP.Orb:UpdateCombat(data, unit)
    local inCombat = unit and UnitAffectingCombat(unit)
    data._inCombat = inCombat or false
    -- Mettre à jour la couleur de bordure menace
    SP.Orb:UpdateThreatBorder(data, unit)
    SP.Orb:ApplySphereVisibility(data, SP:GetCfg(data.unitType))
end

-------------------------------------------------------------------------------
--  BORDURE MENACE (rouge si engagé, dorée si neutre)
--
--  Activé par cfg.border_threat_color = true.
--  La couleur dorée par défaut = la couleur bordure config (borderR/G/B).
--  Si la bordure est masquée ou border_threat_color désactivé : no-op.
--  Appelé depuis UpdateCombat → déclenché automatiquement via SoftUpdate.
-------------------------------------------------------------------------------
function SP.Orb:UpdateThreatBorder(data, unit)
    if not data.borderOverlay then return end
    local cfg = SP:GetCfg(data.unitType)
    if not SP.Orb:ShouldShowSphere(data, cfg) then return end
    if not cfg.border_threat_color or not cfg.borderEnabled then return end
    if not SP:GetBorderTexturePath(cfg.borderStyle) then return end

    -- Ne pas teinter les styles décor dont tint=false (motifs bruts)
    local bInfoT = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(cfg.borderStyle)
    if bInfoT and bInfoT.tint == false then return end

    local br, bg, bb
    if data._inCombat then
        br, bg, bb = 1.0, 0.10, 0.10
    else
        br, bg, bb = GetBorderColor(cfg, data.unit)
    end

    data.borderOverlay:SetVertexColor(br, bg, bb)
end

-------------------------------------------------------------------------------
--  GLOWS CIBLE / FOCUS
-------------------------------------------------------------------------------
function SP.Orb:SetTargetGlow(data, on)
    data._isTarget = on
    -- singleGlow sera mis à jour dans AnimTick (prochain tick à 30 FPS)
end

function SP.Orb:SetFocusGlow(data, on)
    data._isFocus = on
    -- singleGlow sera mis à jour dans AnimTick (prochain tick à 30 FPS)
end

-------------------------------------------------------------------------------
--  AGGRO — UnitThreatSituation (appelé depuis Core.lua sur PLAYER_REGEN_DISABLED/ENABLED
--  et via poll 0.5s dans OnUpdate pour les mobs qui changent de cible)
-------------------------------------------------------------------------------
function SP.Orb:UpdateAggro(data, unit)
    if not unit then return end
    local utype = data.unitType
    -- L'aggro ne concerne que les ennemis
    if utype ~= "ENEMY" and utype ~= "ENEMY_PLAYER" then
        data._aggroLevel = 0
        -- singleGlow fera le fade dans AnimTick
        return
    end

    local ok, level = pcall(UnitThreatSituation, "player", unit)
    if not ok then level = nil end
    data._aggroLevel = level or 0
    -- singleGlow sera mis à jour dans AnimTick (prochain tick à 30 FPS)

    -- Mise à jour couleur du nom selon aggro
    SP.Orb:UpdateName(data, unit)
    -- Mise à jour bordure menace
    SP.Orb:UpdateThreatBorder(data, unit)
end

-------------------------------------------------------------------------------
--  MARQUE DE RAID
-------------------------------------------------------------------------------
local BLIZZARD_RAID_MARKER_ATLAS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function SafeRaidMark(token)
    if not token or not GetRaidTargetIndex then return nil end
    local ok, mark = pcall(GetRaidTargetIndex, token)
    if not ok or mark == nil then return nil end
    if canaccessvalue and not canaccessvalue(mark) then return nil end
    mark = tonumber(mark)
    if mark and mark > 0 then return mark end
    return nil
end

local function RawRaidMark(token)
    if not token or not GetRaidTargetIndex then return nil end
    local ok, mark = pcall(GetRaidTargetIndex, token)
    if ok and mark ~= nil then return mark end
    return nil
end

local function SafeSameUnit(unit, token)
    if not unit or not token or not UnitIsUnit then return false end
    local ok, same = pcall(UnitIsUnit, unit, token)
    return ok and same == true
end

local function AddUniqueToken(tokens, seen, token)
    if token and not seen[token] then
        seen[token] = true
        tokens[#tokens + 1] = token
    end
end

local function BuildRaidMarkerReadTokens(data, unit)
    local tokens, seen = {}, {}
    AddUniqueToken(tokens, seen, unit)
    AddUniqueToken(tokens, seen, data and data.displayedUnit)
    AddUniqueToken(tokens, seen, data and data.unit)
    for _, alias in ipairs({ "target", "mouseover", "focus" }) do
        if SafeSameUnit(unit or (data and data.unit), alias) then
            AddUniqueToken(tokens, seen, alias)
        end
    end
    return tokens
end

local function ResolveRaidMarkerIndex(data, unit)
    if not GetRaidTargetIndex then return nil, "unavailable" end

    local tokens = BuildRaidMarkerReadTokens(data, unit)
    local secretMark, secretSource
    for i = 1, #tokens do
        local token = tokens[i]
        local mark = SafeRaidMark(token)
        if mark then
            return mark, token, token
        end
        if not secretMark then
            local raw = RawRaidMark(token)
            if raw ~= nil then
                secretMark, secretSource = raw, token
            end
        end
    end

    if secretMark ~= nil then
        return secretMark, secretSource or "secret", secretSource, true
    end

    return nil, "none"
end

local function ApplyRaidMarkerTexture(texture, mark, db, forceAtlas)
    if not texture or mark == nil then return nil, nil, nil end

    local tex, uv, isAtlas
    if not forceAtlas and db.raidmark_custom_enabled ~= false and SP.GetRaidMarkerIcon then
        tex, uv, isAtlas = SP:GetRaidMarkerIcon(mark, db.raidmark_pack)
    end
    if not tex then
        tex, isAtlas = BLIZZARD_RAID_MARKER_ATLAS, true
    end

    texture:SetTexture(tex)
    if isAtlas and SetRaidTargetIconTexture then
        texture:SetTexCoord(0, 1, 0, 1)
        pcall(SetRaidTargetIconTexture, texture, mark)
    elseif uv then
        texture:SetTexCoord(uv[1] or 0, uv[2] or 1, uv[3] or 0, uv[4] or 1)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end

    return tex, uv, isAtlas
end

function SP.Orb:RefreshAllRaidMarks(delay)
    local function run()
        for unit, data in pairs(SP.Plates or {}) do
            pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, unit)
        end
    end
    if delay and delay > 0 and C_Timer and C_Timer.After then
        C_Timer.After(delay, run)
    else
        run()
    end
end

function SP.Orb:ResolveRaidMarkerIndex(data, unit)
    return ResolveRaidMarkerIndex(data, unit)
end

function SP.Orb:UpdateRaidMark(data, unit)
    if not data or not data.raidIcon then return end
    unit = unit or data.unit
    local cfg = SP:GetCfg(data.unitType) or {}
    local db = SP.db or {}
    if db.raidmark_global_enabled == false
        or (db.raidmark_show_all_types ~= true and cfg.raidmark_enabled == false) then
        data.raidIcon:SetAlpha(0)
        if data.raidIconFrame then data.raidIconFrame:Hide() end
        data._raidMarkDebug = { reason = "disabled", unit = unit }
        return
    end

    local mark, markSource, markToken, markSecret = ResolveRaidMarkerIndex(data, unit)
    if mark ~= nil then
        local mode = db.raidmark_position_mode or "sphere"
        if mode == "name" and cfg.showName == false then
            data.raidIcon:SetAlpha(0)
            if data.raidIconFrame then data.raidIconFrame:Hide() end
            data._raidMarkDebug = { reason = "name_hidden", unit = unit, mark = mark, source = markSource, token = markToken }
            return
        end

        local baseSize = tonumber(db.raidmark_size) or 24
        local scale = tonumber(db.raidmark_scale) or 1
        local alpha = tonumber(db.raidmark_alpha) or 1
        local offX = tonumber(db.raidmark_offset_x) or 0
        local offY = tonumber(db.raidmark_offset_y) or 0
        local spacing = tonumber(db.raidmark_spacing) or 4
        baseSize = math.max(8, math.min(80, baseSize))
        scale = math.max(0.25, math.min(3.0, scale))
        alpha = math.max(0, math.min(1, alpha))

        data.raidIcon:ClearAllPoints()
        data.raidIcon:SetSize(baseSize * scale, baseSize * scale)
        if mode == "name" and data.nameFrame then
            local pos = db.raidmark_name_position or "above"
            if pos == "left" then
                data.raidIcon:SetPoint("RIGHT", data.nameFrame, "LEFT", -(spacing - offX), offY)
            elseif pos == "right" then
                data.raidIcon:SetPoint("LEFT", data.nameFrame, "RIGHT", spacing + offX, offY)
            elseif pos == "below" then
                data.raidIcon:SetPoint("TOP", data.nameFrame, "BOTTOM", offX, -(spacing - offY))
            else
                data.raidIcon:SetPoint("BOTTOM", data.nameFrame, "TOP", offX, spacing + offY)
            end
        else
            data.raidIcon:SetPoint("CENTER", data.orbFrame or data.orb, "CENTER", offX, offY)
        end
        local tex, uv, isAtlas = ApplyRaidMarkerTexture(data.raidIcon, mark, db, markSecret)
        data.raidIcon:SetAlpha(alpha)
        if data.raidIconFrame then
            data.raidIconFrame:SetFrameLevel((data.root and data.root:GetFrameLevel() or 1) + 30)
            data.raidIconFrame:SetAlpha(1)
            data.raidIconFrame:Show()
        end
        data._raidMarkDebug = { reason = markSecret and "shown_secret_atlas" or "shown", unit = unit, mark = markSecret and "secret" or mark, source = markSource, token = markToken, tex = tex, atlas = isAtlas, mode = mode }
    else
        data.raidIcon:SetAlpha(0)
        if data.raidIconFrame then data.raidIconFrame:Hide() end
        data._raidMarkDebug = { reason = "no_marker", unit = unit, source = markSource }
    end
end

-------------------------------------------------------------------------------
--  ANIMATION TICK (30 FPS) — glow contextuel unique (singleGlow)
--
--  Priorité :   aggro totale > aggro partielle > cible > focus > HP critique > fade out
--  Un seul glow change de couleur/intensité selon l'état le plus urgent.
-------------------------------------------------------------------------------
local function HideTargetRipples(data)
    if not data or not data.targetRipples then return end
    data._targetRippleTime = 0
    for _, ripple in ipairs(data.targetRipples) do
        ripple:SetAlpha(0)
        ripple:Hide()
    end
end

local function UpdateTargetRipples(data, cfg, dt, r, g, b, alpha)
    if not data or not data.targetRipples then return end
    local baseSize = data.orbSize or 64
    local speed = math.max(0.20, math.min(3.00, tonumber(cfg.target_ripple_speed) or 1.25))
    local maxScale = math.max(1.05, math.min(3.00, tonumber(cfg.target_ripple_size) or 2.20))
    local trail = math.max(0.05, math.min(1.00, tonumber(cfg.target_ripple_trail) or 0.82))
    local intensity = math.max(0.20, math.min(3.00, tonumber(cfg.target_ripple_intensity) or 1.35))
    local saturation = math.max(0.00, math.min(2.50, tonumber(cfg.target_ripple_saturation) or 1.25))
    local width = math.max(0.40, math.min(2.00, tonumber(cfg.target_ripple_width) or 1.20))
    local grey = (r + g + b) / 3
    r = math.max(0, math.min(1, grey + (r - grey) * saturation))
    g = math.max(0, math.min(1, grey + (g - grey) * saturation))
    b = math.max(0, math.min(1, grey + (b - grey) * saturation))
    local t = (data._targetRippleTime or 0) + (dt or 0) * speed
    data._targetRippleTime = t % 1

    local count = #data.targetRipples
    for i, ripple in ipairs(data.targetRipples) do
        local p = (data._targetRippleTime + (i - 1) / count) % 1
        local scale = 0.42 + (maxScale - 0.42) * p
        local size = baseSize * scale
        local fade = 1 - p
        local crest = 0.45 + 0.55 * math.sin((1 - p) * math.pi)
        local a = math.min(1, alpha * trail * intensity * math.pow(fade, 1.35 / width) * crest)
        ripple:SetSize(size, size)
        ripple:SetVertexColor(r, g, b, 1)
        ripple:SetAlpha(a)
        ripple:Show()
    end
end

function SP.Orb:AnimTick(dt)
    for _, data in pairs(SP.Plates) do
        local sg = data.singleGlow
        if sg then
            local al       = data._aggroLevel or 0
            local isTarget = data._isTarget
            local isFocus  = data._isFocus
            local ratio    = data.displayHP or 1
            local cfg      = SP:GetCfg(data.unitType)
            local thrCrit  = (cfg.hp_threshold_crit or 20) / 100
            if isTarget and cfg.target_priority == "target_first" then
                al = 0
            end

            -- Accumulateur de temps partagé (réinitialisé à 0 quand inactif)
            data._glowTime = (data._glowTime or 0) + dt
            local useTargetRipple = isTarget and cfg.target_glow_enabled ~= false
                and cfg.target_glow_style == "ripple" and data._sphereVisible ~= false
            if not useTargetRipple then HideTargetRipples(data) end
            if data.midnightStar then
                if cfg.orb_midnight_star == true then
                    local msScale = math.max(0.50, math.min(2.50, tonumber(cfg.orb_midnight_star_scale) or 1.18))
                    local msAlpha = math.max(0.00, math.min(1.00, tonumber(cfg.orb_midnight_star_alpha) or 0.55))
                    local msSpeed = math.max(0, math.min(360, tonumber(cfg.orb_midnight_star_speed) or 45))
                    local msDir = cfg.orb_midnight_star_dir == "ccw" and -1 or 1
                    data._midnightStarAngle = ((data._midnightStarAngle or 0) + dt * msSpeed * msDir) % 360
                    data.midnightStar:SetSize((data.orbSize or 64) * msScale, (data.orbSize or 64) * msScale)
                    data.midnightStar:SetRotation(math.rad(data._midnightStarAngle))
                    data.midnightStar:SetAlpha(msAlpha)
                    data.midnightStar:Show()
                else
                    data._midnightStarAngle = 0
                    data.midnightStar:SetAlpha(0)
                    data.midnightStar:Hide()
                end
            end

            -- ── Pack Mode + Scale hors-cible (Solutions A+B+C) ─────────────────
            -- Résout la scale et l'alpha cibles selon le rang et le mode actif,
            -- puis lerpe vers eux de façon fluide.
            --
            -- Priorité de résolution :
            --  1. Pack mode actif → scale/alpha pilotés par _packRank
            --  2. non_target_scale activé (mode legacy) → fallback simple
            --  3. Aucun mode → scale=1, alpha=1
            --
            -- L'alpha final est le produit de _packAlpha × _fadeAlpha
            -- pour ne pas écraser le distance-fade qui stocke sa valeur dans
            -- data._fadeAlpha (mise à jour 4 FPS par le loop de Core.lua).
            do
                local db = SP.db or {}
                local packOn = db.pack_mode_enabled and SP._packMode

                -- Déterminer la cible de scale et d'alpha
                local targetScale, targetAlpha
                local rank = data._packRank or 3

                if packOn then
                    -- Solution B+C : scale/alpha selon rang de priorité
                    if rank >= 3 then
                        -- Cible/focus : boost léger
                        targetScale = db.pack_target_scale_boost or 1.12
                        targetAlpha = 1.0
                    elseif rank == 2 then
                        -- Boss/marqué/aggro totale : légèrement réduit mais visible
                        targetScale = 0.88
                        targetAlpha = 0.90
                    elseif rank == 1 then
                        -- En combat : réduit intermédiaire
                        targetScale = db.pack_non_target_scale or 0.68
                        targetAlpha = math.max((db.pack_non_target_alpha or 0.50) + 0.15, 0.65)
                    else
                        -- Rank 0 : background mob
                        targetScale = db.pack_non_target_scale or 0.68
                        targetAlpha = db.pack_non_target_alpha or 0.50
                    end
                elseif cfg.non_target_scale_enabled then
                    -- Mode legacy non_target_scale (fallback si pack désactivé)
                    targetScale = isTarget and 1.0 or (cfg.non_target_scale or 0.75)
                    targetAlpha = 1.0
                else
                    targetScale = 1.0
                    targetAlpha = 1.0
                end

                -- Lerp fluide vers la cible
                -- lerpK ≈ dt × (pack_lerp_speed ou 8) donne ~0.14 par tick à 30 FPS
                local lerpK = math.min(0.95, dt * ((db.pack_lerp_speed or 8.0) * 1.2))
                local cs = data._packScale or 1.0
                local ca = data._packAlpha or 1.0
                cs = cs + (targetScale - cs) * lerpK
                ca = ca + (targetAlpha - ca) * lerpK
                -- Snap final : éviter l'oscillation infinie à 0.001 de la cible
                if math.abs(cs - targetScale) < 0.005 then cs = targetScale end
                if math.abs(ca - targetAlpha) < 0.005 then ca = targetAlpha end
                data._packScale = cs
                data._packAlpha = ca

                -- Appliquer la scale (local scale, Frame only)
                data.root:SetScale(cs)

                -- Appliquer l'alpha composé : pack × fade
                local fadeA = data._fadeAlpha or 1.0
                data.root:SetAlpha(ca * fadeA)

                -- ── Atténuation des couches galaxy (Solution C) ───────────────
                -- En mode pack, les galaxies des rangs 0-1 sont atténuées pour
                -- réduire le bruit visuel. Rangs 2-3 : alpha normal de la config.
                if packOn and (db.pack_galaxy_attenuate ~= false) and cfg.orb_galaxies ~= false then
                    local baseGA = cfg.orb_galaxy_alpha or 0.20
                    local packGA = db.pack_galaxy_alpha or 0.22
                    local galaxyAlpha
                    if rank >= 2 then
                        galaxyAlpha = baseGA
                    elseif rank == 1 then
                        galaxyAlpha = baseGA * 0.50
                    else
                        galaxyAlpha = packGA
                    end
                    -- Lerp de l'alpha galaxy (même vitesse que pack lerp)
                    local cgA = data._packGalaxyAlpha or baseGA
                    cgA = cgA + (galaxyAlpha - cgA) * lerpK
                    if math.abs(cgA - galaxyAlpha) < 0.003 then cgA = galaxyAlpha end
                    data._packGalaxyAlpha = cgA
                    if data.galaxy1 then data.galaxy1:SetAlpha(cgA) end
                    if data.galaxy2 then data.galaxy2:SetAlpha(cgA * 0.80) end
                    if data.galaxy3 then data.galaxy3:SetAlpha(cgA * 0.65) end
                else
                    -- Hors pack mode : restaurer l'alpha galaxy config si on sortait du mode
                    if data._packGalaxyAlpha then
                        local baseGA = cfg.orb_galaxy_alpha or 0.20
                        local cgA = data._packGalaxyAlpha
                        local lk2 = math.min(0.95, dt * 5.0)
                        cgA = cgA + (baseGA - cgA) * lk2
                        if math.abs(cgA - baseGA) < 0.003 then cgA = baseGA end
                        data._packGalaxyAlpha = cgA
                        if data.galaxy1 then data.galaxy1:SetAlpha(cgA) end
                        if data.galaxy2 then data.galaxy2:SetAlpha(cgA * 0.80) end
                        if data.galaxy3 then data.galaxy3:SetAlpha(cgA * 0.65) end
                    end
                end

                -- ── Visibilité des noms non-cibles en mode pack ────────────────
                -- nameDisplay "hover" est déjà géré dans UpdateName.
                -- Ici on court-circuite pour masquer en mode pack si pack_name_hide.
                if packOn and (db.pack_name_hide ~= false) and rank < 3 then
                    if data.nameText then
                        local curA = data.nameText:GetAlpha()
                        local lk3 = math.min(0.95, dt * 5.0)
                        local newA = curA + (0 - curA) * lk3
                        if newA < 0.01 then newA = 0 end
                        data.nameText:SetAlpha(newA)
                    end
                elseif data.nameText and data.nameText:GetAlpha() < 0.99 and not packOn then
                    -- Restauration progressive quand pack mode se désactive
                    local curA = data.nameText:GetAlpha()
                    local lk3 = math.min(0.95, dt * 5.0)
                    local targetNA = cfg.name_alpha or 1.0
                    local newA = curA + (targetNA - curA) * lk3
                    if math.abs(newA - targetNA) < 0.01 then newA = targetNA end
                    data.nameText:SetAlpha(newA)
                end
            end

            -- ── Fix C : résolution de classe différée ──────────────────────────
            -- Pour les joueurs alliés à 100% HP (pas de UNIT_HEALTH), UpdateFill
            -- n'est jamais rappelé après l'échec initial → _cachedClass reste nil.
            -- On retente SafeUnitClass toutes les 2s jusqu'à succès, puis
            -- on force RefreshUnitColors (pas seulement UpdateFill) pour que
            -- shimmer2, waveT1, waveT2 soient aussi mis à jour (évite l'aspect délavé).
            local isPlayerType = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
            if not data._cachedClass and isPlayerType and data.unit then
                data._classRetryAcc = (data._classRetryAcc or 0) + dt
                if data._classRetryAcc >= 2.0 then
                    data._classRetryAcc = 0
                    local cls = SafeUnitClass(data.unit, true)
                    if cls then
                        data._cachedClass = cls
                        pcall(SP.Orb.RefreshUnitColors, SP.Orb, data,
                              data.unit, data._displayRatio or data.displayHP or 1)
                    end
                end
            end

            if not SP.Orb:ShouldShowSphere(data, cfg) then
                sg:SetAlpha(0)
                if data.ccOverlay then data.ccOverlay:SetAlpha(0) end
                if data.ccText then data.ccText:Hide() end

            elseif al >= 3 then
                -- Aggro totale → rouge intense, pulsé rapide
                sg:SetVertexColor(1.0, 0.10, 0.05)
                sg:SetAlpha(0.55 + 0.40 * math.abs(math.sin(data._glowTime * 5.5)))

            elseif al == 2 then
                -- Aggro partielle → rouge modéré, pulsé moyen
                sg:SetVertexColor(1.0, 0.35, 0.10)
                sg:SetAlpha(0.25 + 0.20 * math.abs(math.sin(data._glowTime * 3.0)))

            elseif isTarget and cfg.target_glow_enabled ~= false then
                -- Cible → jaune, pulsé doux
                local tr, tg, tb = 1.0, 0.88, 0.0
                local ta = cfg.target_glow_alpha or 0.85
                if cfg.target_custom_enabled then
                    tr = cfg.target_glowR or tr
                    tg = cfg.target_glowG or tg
                    tb = cfg.target_glowB or tb
                end
                sg:SetVertexColor(tr, tg, tb)
                if cfg.target_glow_style == "ripple" then
                    local pulseAlpha = ta
                    if cfg.target_glow_pulse ~= false then
                        pulseAlpha = (ta * 0.35) + (ta * 0.25) * math.abs(math.sin(data._glowTime * 2.0))
                    end
                    sg:SetAlpha(pulseAlpha)
                    UpdateTargetRipples(data, cfg, dt, tr, tg, tb, ta)
                elseif cfg.target_glow_pulse == false then
                    sg:SetAlpha(ta)
                else
                    sg:SetAlpha((ta * 0.52) + (ta * 0.48) * math.abs(math.sin(data._glowTime * 2.5)))
                end

            elseif isFocus then
                -- Focus → bleu, pulsé doux
                sg:SetVertexColor(0.20, 0.60, 1.0)
                sg:SetAlpha(0.35 + 0.32 * math.abs(math.sin(data._glowTime * 2.0)))

            elseif cfg.orb_lowhp_glow ~= false and ratio <= thrCrit then
                -- HP critiques → rouge ténu, pulsé lent
                sg:SetVertexColor(1.0, 0.10, 0.10)
                sg:SetAlpha(0.20 + 0.18 * math.abs(math.sin(data._glowTime * 2.0)))

            else
                -- Aucun état actif → fade out progressif, puis reset le timer
                local a = sg:GetAlpha()
                if a > 0 then
                    sg:SetAlpha(math.max(0, a - dt * 2.5))
                else
                    data._glowTime = 0   -- reset pour éviter l'accumulation
                    data._targetRippleTime = 0
                end
            end
        end

        -- Pulsation de l'overlay décoratif de bordure (border_glow_pulse)
        if data.borderOverlay then
            local bcfg = SP:GetCfg(data.unitType)
            if bcfg.border_glow_pulse and bcfg.borderEnabled ~= false
               and SP:GetBorderTexturePath(bcfg.borderStyle) then
                -- Pulsation alpha uniquement ; ne pas teinter les motifs bruts (tint=false)
                local bInfoP = SP.GetBorderStyleInfo and SP:GetBorderStyleInfo(bcfg.borderStyle)
                if not bInfoP or bInfoP.tint ~= false then
                    data.borderOverlay:SetAlpha(0.55 + 0.35 * math.abs(math.sin((data._glowTime or 0) * 1.8)))
                end
            end
        end

        -- Overlay CC + timer texte (violet pulsé pendant contrôle)
        if data._ccExpiry then
            -- _ccExpiry peut être un secret number tainted → toute arithmétique dans pcall
            local remaining = nil
            local timedOut  = false
            pcall(function()
                remaining = data._ccExpiry - GetTime()
                timedOut  = remaining <= 0
            end)
            if timedOut then
                -- CC expiré (calcul réussi, durée dépassée)
                data._ccExpiry = nil
                data._ccActive = false
                if data.ccOverlay then data.ccOverlay:SetAlpha(0) end
                if data.ccText   then data.ccText:Hide() end
            else
                -- CC actif — pulsation violette (glowTime est un plain number, safe)
                data._ccActive = true
                if data.ccOverlay then
                    -- BLEND mode : alpha plus élevé pour que le violet soit visible
                    -- Pulse : 0.38 → 0.58 → donne une teinture violette bien perceptible
                    data.ccOverlay:SetAlpha(0.38 + 0.20 * math.abs(math.sin((data._glowTime or 0) * 3.5)))
                end
                if data.ccText then
                    -- Timer : si remaining est disponible (calcul réussi), on l'affiche
                    if remaining and remaining >= 0 then
                        pcall(function()
                            data.ccText:SetText(remaining >= 10
                                and string.format("%.0f", remaining)
                                or  string.format("%.1f", remaining))
                        end)
                    end
                    data.ccText:Show()
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  UPDATE CC — appelé par Auras.lua quand un contrôle est détecté/supprimé
-------------------------------------------------------------------------------
function SP.Orb:UpdateCC(data, ccExpiry)
    local cfg = SP:GetCfg(data.unitType)
    local enabled = cfg.cc_effect_enabled ~= false
    if not enabled or not ccExpiry then
        data._ccExpiry = nil
        data._ccActive = false
        if data.ccOverlay then data.ccOverlay:SetAlpha(0) end
        if data.ccText    then data.ccText:Hide() end
        return
    end
    -- ccExpiry peut être un secret number tainted → comparaison dans pcall
    local isExpired = false
    pcall(function() isExpired = ccExpiry <= GetTime() end)
    if isExpired then
        data._ccExpiry = nil
        data._ccActive = false
        if data.ccOverlay then data.ccOverlay:SetAlpha(0) end
        if data.ccText    then data.ccText:Hide() end
    else
        data._ccExpiry = ccExpiry
    end
end
