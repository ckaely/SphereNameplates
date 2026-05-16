-------------------------------------------------------------------------------
-- SphereNameplates v3.0 — Nameplate.lua
-- Construction des frames : sphère, castbar circulaire, auras, niveau, nom
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]

local CreateFrame     = CreateFrame
local math_cos        = math.cos
local math_sin        = math.sin
local math_rad        = math.rad
local math_floor      = math.floor
local math_max        = math.max
local math_random     = math.random
local math_pi         = math.pi

local MASK_TEXTURE  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TEXTURE_DRAG_L= "Interface\\TargetingFrame\\UI-TargetingFrame-Elite"
local TEXTURE_DRAG_R= "Interface\\TargetingFrame\\UI-TargetingFrame-EliteRight"
local TEXTURE_STAR  = "Interface\\Minimap\\MinimapArrow"

-- ═══════════════════════════════════════════════════════════════════
--  UTILITAIRE MASQUE CIRCULAIRE
-- ═══════════════════════════════════════════════════════════════════
local function ApplyCircleMask(texture, maskHolder)
    local mask = maskHolder:CreateMaskTexture()
    mask:SetTexture(MASK_TEXTURE,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(maskHolder)
    texture:AddMaskTexture(mask)
    return mask
end

-- ═══════════════════════════════════════════════════════════════════
--  CRÉATION DE LA PLAQUE
-- ═══════════════════════════════════════════════════════════════════
function SP:CreateSpherePlate(unit, plate)
    if SP.ActivePlates[unit] then return end

    local db   = SP.db
    local SIZE = db.sphereSize

    -- Masquer le frame Blizzard
    if plate.UnitFrame then
        plate.UnitFrame:SetAlpha(0)
        plate.UnitFrame:Hide()
    end

    -- Conteneur racine
    local root = CreateFrame("Frame", nil, plate)
    root:SetSize(SIZE * 2.4, SIZE * 2.4)
    root:SetPoint("CENTER", plate, "CENTER", 0, 0)
    root:SetFrameLevel((plate:GetFrameLevel() or 0) + 5)

    -- Holder sphère (masque appliqué ici)
    local holder = CreateFrame("Frame", nil, root)
    holder:SetSize(SIZE, SIZE)
    holder:SetPoint("CENTER", root, "CENTER", 0, 0)
    holder:SetAlpha(db.sphereAlpha)

    -- ── Fond noir ────────────────────────────────────────────
    local bg = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetColorTexture(0.04, 0.04, 0.09, 1)
    bg:SetAllPoints(holder)
    ApplyCircleMask(bg, holder)

    -- ── Remplissage eau (HP) ──────────────────────────────────
    local fill = holder:CreateTexture(nil, "ARTWORK", nil, 0)
    fill:SetColorTexture(0.05, 0.95, 0.25, 0.92)
    fill:SetPoint("BOTTOMLEFT",  holder, "BOTTOMLEFT",  0, 0)
    fill:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    fill:SetHeight(SIZE)
    ApplyCircleMask(fill, holder)

    -- ── Onde surface ─────────────────────────────────────────
    local wave1 = holder:CreateTexture(nil, "ARTWORK", nil, 1)
    wave1:SetColorTexture(0.5, 1.0, 0.5, 0.28)
    wave1:SetPoint("BOTTOMLEFT",  holder, "BOTTOMLEFT",  0, 0)
    wave1:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    wave1:SetHeight(math_max(4, SIZE * 0.10))
    ApplyCircleMask(wave1, holder)

    local wave2 = holder:CreateTexture(nil, "ARTWORK", nil, 1)
    wave2:SetColorTexture(0.7, 1.0, 0.7, 0.13)
    wave2:SetPoint("BOTTOMLEFT",  holder, "BOTTOMLEFT",  0, 0)
    wave2:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    wave2:SetHeight(math_max(3, SIZE * 0.07))
    ApplyCircleMask(wave2, holder)

    -- ── Reflet (gloss top-gauche) ─────────────────────────────
    local gloss = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    gloss:SetColorTexture(1, 1, 1, db.glossIntensity)
    gloss:SetSize(SIZE * 0.50, SIZE * 0.50)
    gloss:SetPoint("TOPLEFT", holder, "TOPLEFT", SIZE * 0.06, -SIZE * 0.05)
    ApplyCircleMask(gloss, holder)

    -- ── Ombre intérieure radiale ──────────────────────────────
    local innerShadow = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    innerShadow:SetColorTexture(0, 0, 0, 0.52)
    innerShadow:SetAllPoints(holder)
    -- Masque spécial : on laisse transparent le centre
    -- (simple couche noire semi-trans sur les bords via gradient pas dispo en pur Lua)
    -- On utilise une texture de vignette si disponible, sinon transparent
    innerShadow:SetColorTexture(0, 0, 0, 0)  -- désactivé visuellement (géré en animation)

    -- ── Liseré extérieur ────────────────────────────────────
    -- Rim sur holder (même frame que le mask — requis par WoW API)
    local rim = holder:CreateTexture(nil, "BORDER", nil, -1)
    rim:SetColorTexture(0.05, 0.95, 0.25, db.rimIntensity)
    rim:SetAllPoints(holder)
    ApplyCircleMask(rim, holder)

    -- Ring de ciblage sur holder (même frame que le mask — requis par WoW API)
    local targetRing = holder:CreateTexture(nil, "OVERLAY", nil, 5)
    targetRing:SetColorTexture(db.targetGlowR, db.targetGlowG, db.targetGlowB, 1)
    targetRing:SetAllPoints(holder)
    targetRing:SetAlpha(0)
    ApplyCircleMask(targetRing, holder)

    -- ══════════════════════════════════════════════════════════
    --  CASTBAR CIRCULAIRE (Cooldown sweep)
    -- ══════════════════════════════════════════════════════════
    local castBar = CreateFrame("Cooldown", nil, holder)
    castBar:SetAllPoints(holder)
    castBar:SetFrameLevel(holder:GetFrameLevel() + 6)
    castBar:SetDrawSwipe(false)
    castBar:SetDrawEdge(false)
    castBar:SetHideCountdownNumbers(true)
    castBar:SetReverse(true)
    castBar:SetSwipeColor(db.castbarColorR, db.castbarColorG, db.castbarColorB, db.castbarAlpha)
    castBar:Hide()

    -- ══════════════════════════════════════════════════════════
    --  TEXTES
    -- ══════════════════════════════════════════════════════════

    -- % Santé
    local pctText = root:CreateFontString(nil, "OVERLAY")
    pctText:SetFont(db.percentFont, db.percentFontSize, "OUTLINE")
    pctText:SetPoint("CENTER", holder, "CENTER", 0, 0)
    pctText:SetTextColor(1, 1, 1, 1)
    pctText:SetShadowColor(0, 0, 0, 0.8)
    pctText:SetShadowOffset(1, -1)
    if not db.showPercentText then pctText:Hide() end

    -- HP absolu
    local absText = root:CreateFontString(nil, "OVERLAY")
    absText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    absText:SetPoint("TOP", holder, "BOTTOM", 0, -14)
    absText:SetTextColor(0.75, 0.75, 0.75, 0.9)
    if not db.showAbsoluteHP then absText:Hide() end

    -- Nom
    local nameText = root:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(db.nameFont, db.nameFontSize, db.nameFontOutline)
    nameText:SetPoint("BOTTOM", holder, "TOP", 0, 4)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetShadowColor(0, 0, 0, 0.95)
    nameText:SetShadowOffset(1, -1)

    -- Niveau
    local levelText = root:CreateFontString(nil, "OVERLAY")
    levelText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    levelText:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 3, 3)
    levelText:SetShadowColor(0, 0, 0, 1)
    levelText:SetShadowOffset(1, -1)
    if not db.showLevel then levelText:Hide() end

    -- Nom du sort (castbar)
    local castName = root:CreateFontString(nil, "OVERLAY")
    castName:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    castName:SetPoint("TOP", holder, "BOTTOM", 0, -2)
    castName:SetTextColor(1.0, 0.55, 0.15, 1)
    castName:SetShadowColor(0, 0, 0, 0.9)
    castName:SetShadowOffset(1, -1)
    if not db.showCastName then castName:Hide() end

    -- ══════════════════════════════════════════════════════════
    --  DÉCORATIONS ÉLITE / DRAGON
    -- ══════════════════════════════════════════════════════════
    local drLeft = root:CreateTexture(nil, "BORDER")
    drLeft:SetTexture(TEXTURE_DRAG_L)
    drLeft:SetSize(SIZE * 0.72, SIZE * 1.0)
    drLeft:SetPoint("RIGHT", holder, "LEFT", SIZE * 0.10, 0)
    drLeft:Hide()

    local drRight = root:CreateTexture(nil, "BORDER")
    drRight:SetTexture(TEXTURE_DRAG_R)
    drRight:SetSize(SIZE * 0.72, SIZE * 1.0)
    drRight:SetPoint("LEFT", holder, "RIGHT", -SIZE * 0.10, 0)
    drRight:Hide()

    local drGlow = root:CreateTexture(nil, "BACKGROUND", nil, -3)
    drGlow:SetSize(SIZE * 1.9, SIZE * 1.9)
    drGlow:SetPoint("CENTER", holder, "CENTER", 0, 0)
    drGlow:SetColorTexture(1.0, 0.75, 0.0, 0)

    -- Étoile rare
    local rareStar = root:CreateTexture(nil, "OVERLAY", nil, 3)
    rareStar:SetTexture("Interface\\TargetingFrame\\UI-RareElite-Texture")
    rareStar:SetSize(SIZE * 0.40, SIZE * 0.40)
    rareStar:SetPoint("TOPLEFT", holder, "TOPLEFT", -6, 6)
    rareStar:Hide()

    -- ══════════════════════════════════════════════════════════
    --  AURAS EN ARC
    -- ══════════════════════════════════════════════════════════
    local auraFrames = SP:CreateAuraFrames(root, holder, SIZE)

    -- ══════════════════════════════════════════════════════════
    --  ENREGISTREMENT
    -- ══════════════════════════════════════════════════════════
    local initHP = SP:GetUnitHealthPct(unit)

    SP.ActivePlates[unit] = {
        root         = root,
        sphereHolder = holder,
        fill         = fill,
        wave1        = wave1,
        wave2        = wave2,
        rim          = rim,
        gloss        = gloss,
        targetRing   = targetRing,
        castBar      = castBar,
        pctText      = pctText,
        absText      = absText,
        nameText     = nameText,
        levelText    = levelText,
        castName     = castName,
        dragonLeft   = drLeft,
        dragonRight  = drRight,
        dragonGlow   = drGlow,
        rareStar     = rareStar,
        auraFrames   = auraFrames,
        -- Animation state
        currentHP    = initHP,
        targetHP     = initHP,
        waveTime     = math_random() * math_pi * 2,
        wave2Time    = math_random() * math_pi * 2,
        glossTime    = math_random() * math_pi * 2,
        waveOffsetX  = 0,
        wave2OffsetX = 0,
        targetPulse  = 0,
        critTimer    = 0,
        critFlash    = 0,
        damageFlash  = 0,
        interruptFlash = 0,
        lastHP       = initHP,
        sphereSize   = SIZE,
    }
end

-- ═══════════════════════════════════════════════════════════════════
--  AURAS EN ARC GAUCHE
-- ═══════════════════════════════════════════════════════════════════
function SP:CreateAuraFrames(root, holder, sphereSize)
    local db      = SP.db
    local maxA    = db.maxAuras
    local aSize   = db.auraSize
    local aRadius = db.auraRadius + sphereSize * 0.5
    local frames  = {}

    local startAngle = math_rad(20)
    local endAngle   = math_rad(160)

    for i = 1, maxA do
        local t     = (maxA == 1) and 0.5 or (i - 1) / (maxA - 1)
        local angle = startAngle + t * (endAngle - startAngle)
        local ox    = -math_cos(angle) * aRadius
        local oy    =  math_sin(angle) * aRadius

        local af = CreateFrame("Frame", nil, root)
        af:SetSize(aSize, aSize)
        af:SetPoint("CENTER", holder, "CENTER", ox, oy)
        af:SetFrameLevel(root:GetFrameLevel() + 8)

        -- Fond
        local bg = af:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0.04, 0.04, 0.12, 0.9)
        bg:SetAllPoints(af)
        ApplyCircleMask(bg, af)

        -- Icône
        local icon = af:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT",     af, "TOPLEFT",     1, -1)
        icon:SetPoint("BOTTOMRIGHT", af, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ApplyCircleMask(icon, af)

        -- Timer Cooldown
        local cd = CreateFrame("Cooldown", nil, af)
        cd:SetAllPoints(af)
        cd:SetSwipeColor(0, 0, 0, 0.72)
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(false)
        cd:SetHideCountdownNumbers(true)
        cd:Hide()

        -- Bord débuff
        local border = af:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        border:SetAllPoints(af)
        border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        border:SetVertexColor(0.9, 0.1, 0.1, 1)

        -- Stacks
        local stacks = af:CreateFontString(nil, "OVERLAY")
        stacks:SetFont("Fonts\\FRIZQT__.TTF", math_max(7, math_floor(aSize * 0.36)), "OUTLINE")
        stacks:SetPoint("BOTTOMRIGHT", af, "BOTTOMRIGHT", 1, 1)
        stacks:SetTextColor(1, 1, 1, 1)
        stacks:Hide()

        af:Hide()

        frames[i] = {
            frame     = af,
            icon      = icon,
            cooldown  = cd,
            border    = border,
            stackText = stacks,
        }
    end
    return frames
end

-- ═══════════════════════════════════════════════════════════════════
--  REDIMENSIONNEMENT (changement de taille en config)
-- ═══════════════════════════════════════════════════════════════════
function SP:ResizePlate(unit)
    local data = SP.ActivePlates[unit]
    if not data then return end
    local SIZE = SP.db.sphereSize
    data.root:SetSize(SIZE * 2.4, SIZE * 2.4)
    data.sphereHolder:SetSize(SIZE, SIZE)
    -- targetRing uses SetAllPoints(holder) so it resizes with holder automatically
    data.dragonLeft:SetSize(SIZE * 0.72, SIZE * 1.0)
    data.dragonRight:SetSize(SIZE * 0.72, SIZE * 1.0)
    data.sphereSize = SIZE
end
