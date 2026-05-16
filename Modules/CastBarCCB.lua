-------------------------------------------------------------------------------
-- SphereNameplates — Modules/CastBarCCB.lua
--
-- Module CCB : intégration de la CircularCastbarLibrary (Holy / Medium)
-- Architecture Option B : Composite per-frame (SetTexture swap) +
--   couches Glow/Flash/Interrupt séparées en ADD blend.
--
-- Notes sur les assets :
--   · Bug générateur : les fichiers per-frame ont "undefinedpx" dans le nom
--     au lieu de "256px". Les couches statiques utilisent "256px" correctement.
--   · Cast "Interrupt" : aucun sous-dossier frames_/ — uniquement un Composite
--     statique "_256px_". Tous les autres casts ont 32 frames animées.
--   · La famille Holy est en minuscule dans le chemin du dossier ("holy\")
--     mais capitalisée dans les noms de fichiers ("_Holy_").
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.CCB = {}

local math_min   = math.min
local math_max   = math.max
local math_floor = math.floor
local GetTime    = GetTime

-- ─── Constantes asset ────────────────────────────────────────────────────────
local CCB_ROOT       = "Interface\\AddOns\\SphereNameplates\\media\\CircularCastbarLibrary\\holy\\"
local CCB_FAMILY     = "Holy"
local CCB_THICKNESS  = "Medium"
local CCB_FRAMECOUNT = 32

-- Casts avec animation per-frame (tous sauf Interrupt)
local CCB_ANIMATED = {
    Normal=true, Channel=true, Segmented=true, Pulse=true,
    Runes=true, Critical=true, Reverse=true, Collapse=true,
    Expanding=true, Charge=true, Particles=true,
}

-- Styles disponibles (utilisé par PSUI pour la liste)
SP.CCB_STYLES = {
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

-- ─── Résolution des chemins ───────────────────────────────────────────────────

local function _FramePath(cast, border, idx)
    -- Per-frame Composite — "undefinedpx" (bug générateur intentionnellement conservé)
    return string.format(
        "%s%s\\frames_256px_%s_%s\\CircularCast_%s_%s_%s_%s_Composite_undefinedpx_f%02dof%d.png",
        CCB_ROOT, cast,
        CCB_THICKNESS, border,
        cast, CCB_FAMILY, CCB_THICKNESS, border,
        idx, CCB_FRAMECOUNT
    )
end

local function _LayerPath(cast, border, layer)
    -- Couche statique — "256px" correct
    return string.format(
        "%s%s\\CircularCast_%s_%s_%s_%s_%s_256px.png",
        CCB_ROOT, cast,
        cast, CCB_FAMILY, CCB_THICKNESS, border, layer
    )
end

local function _InterruptPath(border)
    -- Interrupt : pas de frames_/, Composite statique avec "256px"
    return string.format(
        "%sInterrupt\\CircularCast_Interrupt_%s_%s_%s_Composite_256px.png",
        CCB_ROOT, CCB_FAMILY, CCB_THICKNESS, border
    )
end

-- ─── Détermine le style et la teinte CCB selon l'état du cast ───────────────

local function _ResolveStyle(isChannel, isImmune, notInt, cfg)
    if isImmune then
        return cfg.ccb_boss_style or "Critical"
    elseif isChannel then
        return cfg.ccb_channel_style or "Channel"
    elseif notInt then
        return cfg.ccb_notint_style or "Pulse"
    else
        return cfg.ccb_cast_style or "Normal"
    end
end

-- Retourne r,g,b depuis une clé tableau {r,g,b} ou {1,2,3} avec fallback blanc
local function _ResolveColor(cfg, key)
    local t = cfg and cfg[key]
    if type(t) == "table" then
        local r = t.r or t[1] or 1
        local g = t.g or t[2] or 1
        local b = t.b or t[3] or 1
        return r, g, b
    end
    return 1, 1, 1
end

local function _ResolveCastColor(isChannel, isImmune, notInt, cfg)
    if isImmune then
        return _ResolveColor(cfg, "ccb_color_boss")
    elseif isChannel then
        return _ResolveColor(cfg, "ccb_color_channel")
    elseif notInt then
        return _ResolveColor(cfg, "ccb_color_notint")
    else
        return _ResolveColor(cfg, "ccb_color_cast")
    end
end

-- ─── Create ──────────────────────────────────────────────────────────────────
-- Crée les frames CCB sur data._cb_ccb.
-- Appelé depuis CastBar:Create() quand mode == "ccb".
function SP.CCB:Create(data, cfg, rootFL, SIZE)
    local root = data.root
    if not root then return end

    local border   = cfg.ccb_border      or "Beveled"
    local sizeRatio = tonumber(cfg.ccb_size_ratio) or 2.5
    local ccbSize  = math_max(40, math_floor(SIZE * sizeRatio))
    local offX     = cfg.ccb_offset_x   or 0
    local offY     = cfg.ccb_offset_y   or 0
    local alpha    = tonumber(cfg.ccb_alpha) or 0.90
    local cdAnchor = data.orb or root

    -- ── Frame principal (Composite per-frame animé) ─────────────────────────
    -- Niveau rootFL+10 : au-dessus de borderOverlayFrame (root+8) et nameFrame (root+9)
    local mainFrame = CreateFrame("Frame", nil, root)
    mainFrame:SetSize(ccbSize, ccbSize)
    mainFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
    mainFrame:SetFrameLevel(rootFL + 10)
    pcall(mainFrame.SetFrameStrata, mainFrame, "HIGH")
    mainFrame:Hide()

    local mainTex = mainFrame:CreateTexture(nil, "ARTWORK")
    mainTex:SetAllPoints(mainFrame)
    mainTex:SetBlendMode("BLEND")
    mainTex:SetAlpha(alpha)
    -- Texture initiale (f00 Normal) — sera mise à jour à chaque Apply/Tick
    mainTex:SetTexture(_FramePath("Normal", border, 0))

    -- ── Couche Glow (ADD, visible pendant le cast) ──────────────────────────
    local glowTex = nil
    if cfg.ccb_glow ~= false then
        glowTex = mainFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        glowTex:SetAllPoints(mainFrame)
        glowTex:SetBlendMode("ADD")
        glowTex:SetAlpha(alpha * 0.50)
        glowTex:SetTexture(_LayerPath("Normal", border, "Glow"))
    end

    -- ── Couche Highlight (ADD, optionnelle) ─────────────────────────────────
    local hlTex = nil
    if cfg.ccb_highlight ~= false then
        hlTex = mainFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        hlTex:SetAllPoints(mainFrame)
        hlTex:SetBlendMode("ADD")
        hlTex:SetAlpha(alpha * 0.30)
        hlTex:SetTexture(_LayerPath("Normal", border, "Highlight"))
    end

    -- ── Couche Runes (ADD, optionnelle) ─────────────────────────────────────
    local runesTex = nil
    if cfg.ccb_runes == true then
        runesTex = mainFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        runesTex:SetAllPoints(mainFrame)
        runesTex:SetBlendMode("ADD")
        runesTex:SetAlpha(alpha * 0.60)
        runesTex:SetTexture(_LayerPath("Normal", border, "Runes"))
    end

    -- ── Frame Flash (cast complet, 0.3 s) ──────────────────────────────────
    -- Séparé de mainFrame → reste visible après Hide() du mainFrame
    local flashFrame = CreateFrame("Frame", nil, root)
    flashFrame:SetSize(ccbSize, ccbSize)
    flashFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
    flashFrame:SetFrameLevel(rootFL + 11)
    flashFrame:Hide()

    local flashTex = flashFrame:CreateTexture(nil, "OVERLAY")
    flashTex:SetAllPoints(flashFrame)
    flashTex:SetBlendMode("ADD")
    flashTex:SetAlpha(0)
    flashTex:SetTexture(_LayerPath("Normal", border, "Flash"))

    -- ── Frame Interrupt (0.7 s après kick) ─────────────────────────────────
    -- rootFL+12 : au-dessus de l'icône (+11) et de la sphère (+11), sous le nom (+13)
    local intRatio = tonumber(cfg.ccb_interrupt_size_ratio) or 1.0
    local intSize  = math_max(40, math_floor(ccbSize * intRatio))
    local intFrame = CreateFrame("Frame", nil, root)
    intFrame:SetSize(intSize, intSize)
    intFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
    intFrame:SetFrameLevel(rootFL + 12)
    intFrame:Hide()

    local intTex = intFrame:CreateTexture(nil, "OVERLAY")
    intTex:SetAllPoints(intFrame)
    intTex:SetBlendMode("ADD")
    intTex:SetAlpha(0)
    intTex:SetTexture(_InterruptPath(border))

    local intIr, intIg, intIb = _ResolveColor(cfg, "ccb_interrupt_color")
    pcall(intTex.SetVertexColor, intTex, intIr, intIg, intIb)

    -- Élever l'orbe au-dessus du ring CCB (root+11 > root+10)
    -- Les textures de l'orbe sont masquées circulairement → ring visible autour
    pcall(function()
        if data.orb then data.orb:SetFrameLevel(rootFL + 11) end
    end)

    -- ── Préchargement GPU des 32 frames (styles par défaut + configurés) ──────
    -- Un frame caché porte les textures pour les forcer en mémoire GPU avant
    -- le premier cast. Sans ça, le premier Tick charge chaque PNG depuis le
    -- disque et provoque un flash/saccade visible sur f00→f01.
    local preloadFrame = CreateFrame("Frame", nil, root)
    preloadFrame:SetSize(1, 1)
    preloadFrame:SetPoint("CENTER", root, "CENTER", 0, 0)
    preloadFrame:SetFrameLevel(rootFL)
    preloadFrame:Hide()

    local preloadStyles = {
        cfg.ccb_cast_style    or "Normal",
        cfg.ccb_notint_style  or "Pulse",
        cfg.ccb_boss_style    or "Critical",
        cfg.ccb_channel_style or "Channel",
    }
    local preloaded = {}
    for _, pCast in ipairs(preloadStyles) do
        if not preloaded[pCast] and CCB_ANIMATED[pCast] then
            preloaded[pCast] = true
            for fi = 0, CCB_FRAMECOUNT - 1 do
                local pt = preloadFrame:CreateTexture(nil, "ARTWORK")
                pt:SetSize(1, 1)
                pt:SetTexture(_FramePath(pCast, border, fi))
            end
        end
    end

    data._cb_ccb = {
        mainFrame      = mainFrame,
        mainTex        = mainTex,
        glowTex        = glowTex,
        hlTex          = hlTex,
        runesTex       = runesTex,
        flashFrame     = flashFrame,
        flashTex       = flashTex,
        intFrame       = intFrame,
        intTex         = intTex,
        preloadFrame   = preloadFrame,
        border         = border,
        ccbSize        = ccbSize,
        alpha          = alpha,
        currentCast    = "Normal",
        isStatic       = false,
        lastFrame      = -1,
        flashStart     = 0,
        intStart       = 0,
        showGlow       = cfg.ccb_glow ~= false,
        showHighlight  = cfg.ccb_highlight ~= false,
        showRunes      = cfg.ccb_runes == true,
        flashComplete  = cfg.ccb_flash_complete ~= false,
        flashInterrupt = (cfg.castbar_interrupt_visual or "classic_glow") == "classic_ccb",
        intColor       = {intIr, intIg, intIb},
    }
end

-- ─── Apply ───────────────────────────────────────────────────────────────────
-- Appelé depuis _ApplyCast quand mode == "ccb".
-- Sélectionne le style et initialise les textures.
function SP.CCB:Apply(data, isChannel, isImmune, notInt)
    local ccb = data._cb_ccb
    if not ccb then return end
    local cfg    = SP:GetCfg(data.unitType) or {}
    local cast   = _ResolveStyle(isChannel, isImmune, notInt, cfg)
    local border = ccb.border

    ccb.currentCast = cast
    ccb.isStatic    = not CCB_ANIMATED[cast]
    ccb.lastFrame   = -1

    -- Réinitialiser les effets post-cast
    ccb.flashStart = 0
    ccb.intStart   = 0
    ccb.flashTex:SetAlpha(0)
    ccb.intTex:SetAlpha(0)
    ccb.intFrame:Hide()
    ccb.flashFrame:Hide()

    -- Texture principale (frame 0 ou snapshot statique)
    if ccb.isStatic then
        ccb.mainTex:SetTexture(_InterruptPath(border))
    else
        ccb.mainTex:SetTexture(_FramePath(cast, border, 0))
    end
    ccb.mainTex:SetAlpha(ccb.alpha)

    -- Teinte par type de cast (SetVertexColor multiplie RGB du PNG)
    local cr, cg, cb = _ResolveCastColor(isChannel, isImmune, notInt, cfg)
    pcall(ccb.mainTex.SetVertexColor, ccb.mainTex, cr, cg, cb)

    -- Mettre à jour les couches additives au style actif
    if ccb.glowTex and ccb.showGlow then
        ccb.glowTex:SetTexture(_LayerPath(cast, border, "Glow"))
        ccb.glowTex:SetAlpha(ccb.alpha * 0.50)
        pcall(ccb.glowTex.SetVertexColor, ccb.glowTex, cr, cg, cb)
    end
    if ccb.hlTex and ccb.showHighlight then
        ccb.hlTex:SetTexture(_LayerPath(cast, border, "Highlight"))
        ccb.hlTex:SetAlpha(ccb.alpha * 0.30)
        pcall(ccb.hlTex.SetVertexColor, ccb.hlTex, cr, cg, cb)
    end
    if ccb.runesTex and ccb.showRunes then
        ccb.runesTex:SetTexture(_LayerPath(cast, border, "Runes"))
        ccb.runesTex:SetAlpha(ccb.alpha * 0.60)
        pcall(ccb.runesTex.SetVertexColor, ccb.runesTex, cr, cg, cb)
    end

    -- Préparer les textures flash/interrupt
    if ccb.flashComplete then
        ccb.flashTex:SetTexture(_LayerPath(cast, border, "Flash"))
    end
    -- L'interrupt utilise toujours le Composite Interrupt statique

    ccb.mainFrame:Show()
end

-- ─── Tick ────────────────────────────────────────────────────────────────────
-- Appelé depuis CastBar:Tick() — actif ET inactif (pour fade flash/interrupt).
function SP.CCB:Tick(data, progress, channeling, now)
    local ccb = data._cb_ccb
    if not ccb then return end

    -- Fade-out flash complétion (0.30 s)
    if ccb.flashStart > 0 then
        local elapsed = now - ccb.flashStart
        if elapsed < 0.30 then
            ccb.flashTex:SetAlpha(math_max(0, 0.85 * (1.0 - elapsed / 0.30)))
        else
            ccb.flashTex:SetAlpha(0)
            ccb.flashFrame:Hide()
            ccb.flashStart = 0
        end
    end

    -- Fade-out overlay interruption (0.70 s)
    if ccb.intStart > 0 then
        local elapsed = now - ccb.intStart
        if elapsed < 0.70 then
            ccb.intTex:SetAlpha(math_max(0, 0.90 * (1.0 - elapsed / 0.70)))
        else
            ccb.intTex:SetAlpha(0)
            ccb.intFrame:Hide()
            ccb.intStart = 0
        end
    end

    -- Swap de frame animée (uniquement si mainFrame visible)
    if not ccb.isStatic and ccb.mainFrame:IsShown() then
        local v = channeling and (1.0 - progress) or progress
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        local frameIdx = math_min(CCB_FRAMECOUNT - 1, math_floor(v * (CCB_FRAMECOUNT - 1) + 0.5))
        if frameIdx ~= ccb.lastFrame then
            ccb.lastFrame = frameIdx
            ccb.mainTex:SetTexture(_FramePath(ccb.currentCast, ccb.border, frameIdx))
        end
    end
end

-- ─── Stop ────────────────────────────────────────────────────────────────────
function SP.CCB:Stop(data, interrupted)
    local ccb = data._cb_ccb
    if not ccb then return end

    local now = GetTime()
    ccb.mainFrame:Hide()
    ccb.lastFrame = -1

    if interrupted and ccb.flashInterrupt then
        ccb.intStart = now
        local ic = ccb.intColor or {1, 0.25, 0.25}
        pcall(ccb.intTex.SetVertexColor, ccb.intTex, ic[1] or 1, ic[2] or 0.25, ic[3] or 0.25)
        ccb.intTex:SetAlpha(0.90)
        ccb.intFrame:Show()
    else
        ccb.intStart = 0
        ccb.intTex:SetAlpha(0)
        ccb.intFrame:Hide()
    end

    if (not interrupted) and ccb.flashComplete then
        ccb.flashStart = now
        ccb.flashTex:SetAlpha(0.85)
        ccb.flashFrame:Show()
    else
        ccb.flashStart = 0
        ccb.flashTex:SetAlpha(0)
        ccb.flashFrame:Hide()
    end
end

-- ─── Reset ───────────────────────────────────────────────────────────────────
function SP.CCB:Reset(data)
    local ccb = data._cb_ccb
    if not ccb then return end

    ccb.mainFrame:Hide()
    ccb.flashFrame:Hide()
    ccb.intFrame:Hide()
    ccb.flashTex:SetAlpha(0)
    ccb.intTex:SetAlpha(0)
    if ccb.glowTex   then ccb.glowTex:SetAlpha(0)   end
    if ccb.hlTex     then ccb.hlTex:SetAlpha(0)      end
    if ccb.runesTex  then ccb.runesTex:SetAlpha(0)   end
    ccb.flashStart = 0
    ccb.intStart   = 0
    ccb.lastFrame  = -1
end

-- ─── ApplySettings ───────────────────────────────────────────────────────────
-- Mise à jour légère sans rebuild : alpha, offsets, couches actives.
-- Pour ccb_border et ccb_size_ratio, un rebuild complet est nécessaire
-- (les frames doivent être recrées). Cette fonction ne gère pas ces cas.
function SP.CCB:ApplySettings(data, cfg)
    local ccb = data._cb_ccb
    if not ccb then return end
    cfg = cfg or {}

    -- Alpha
    local alpha = tonumber(cfg.ccb_alpha) or 0.90
    ccb.alpha = alpha
    if ccb.mainFrame:IsShown() then
        ccb.mainTex:SetAlpha(alpha)
        if ccb.glowTex  and ccb.showGlow      then ccb.glowTex:SetAlpha(alpha * 0.50) end
        if ccb.hlTex    and ccb.showHighlight  then ccb.hlTex:SetAlpha(alpha * 0.30)  end
        if ccb.runesTex and ccb.showRunes      then ccb.runesTex:SetAlpha(alpha * 0.60) end
    end

    -- Offsets (réancrage de toutes les frames)
    local offX    = cfg.ccb_offset_x or 0
    local offY    = cfg.ccb_offset_y or 0
    local anchor  = data.orb or data.root
    if anchor then
        ccb.mainFrame:ClearAllPoints()
        ccb.mainFrame:SetPoint("CENTER", anchor, "CENTER", offX, offY)
        ccb.flashFrame:ClearAllPoints()
        ccb.flashFrame:SetPoint("CENTER", anchor, "CENTER", offX, offY)
        ccb.intFrame:ClearAllPoints()
        ccb.intFrame:SetPoint("CENTER", anchor, "CENTER", offX, offY)
    end

    -- Flags de couches (pas de changement visuel immédiat : appliqué au prochain Apply)
    ccb.showGlow      = cfg.ccb_glow ~= false
    ccb.showHighlight = cfg.ccb_highlight ~= false
    ccb.showRunes     = cfg.ccb_runes == true
    ccb.flashComplete  = cfg.ccb_flash_complete ~= false
    ccb.flashInterrupt = (cfg.castbar_interrupt_visual or "classic_glow") == "classic_ccb"

    -- Overlay interruption : taille et couleur
    local intRatio = tonumber(cfg.ccb_interrupt_size_ratio) or 1.0
    local intSize  = math_max(40, math_floor(ccb.ccbSize * intRatio))
    ccb.intFrame:SetSize(intSize, intSize)
    local ir, ig, ib = _ResolveColor(cfg, "ccb_interrupt_color")
    ccb.intColor = {ir, ig, ib}
end
