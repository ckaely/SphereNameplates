-------------------------------------------------------------------------------
-- SphereNameplates v7.4 — Config.lua
-- Namespace global, couleurs, utilitaires, defaults AceDB
--
-- CORRECTIONS v7.4 (WoW Midnight taint definitive fix) :
--   • GetHPRatio(unit) : seule technique fiable confirmée par rOrbs/DiabolicUI2
--     → UnitHealthPercent + SetFormattedText (escape C-side) + tonumber
--     → GetValue/GetMinMaxValues sont AUSSI taintés — jamais utilisés
--   • RenderHPText(unit) : retourne uniquement le texte HP
--   • ApplyHPText/ApplyHPTextPair : applique texte + couleur aux FontStrings HP
--   • FormatHPText : conservé pour compat, utilise GetHPRatio en interne
--   • GetUnitHealthPct : utilise GetHPRatio
--
-- BASE DE CONNAISSANCE WoW MIDNIGHT (taint) :
--   • UnitHealth(unit)             → "secret number tainted"
--   • UnitHealthMax(unit)          → "secret number tainted"
--   • UnitHealthPercent(unit, ...) → "secret number tainted"
--   • bar:GetValue()               → tainté après SetValue(secret)
--   • bar:GetMinMaxValues()        → tainté, pcall NE RÉSOUT PAS
--   • OnValueChanged value param   → tainté
--   • Toute arithmétique (+/-/*)   → ERREUR sur secret values
--   • Toute comparaison (</>)      → ERREUR sur secret values
--
--   ✓ UnitIsDead, UnitExists, UnitIsConnected → booleans propres
--   ✓ UnitReaction, UnitLevel, UnitName, UnitClass → valeurs propres
--   ✓ Passer valeur taintée à C-API → OK (SetValue, SetMinMaxValues, etc.)
--
--   ═══ SEUL ESCAPE FIABLE ═══════════════════════════════════════════
--   scratchFS:SetFormattedText("%.10f", tainted_pct)  -- C-side
--   local s = scratchFS:GetText()                     -- string propre
--   local ratio = tonumber(s) / 100                   -- arithmétique safe
-------------------------------------------------------------------------------

local ADDON = "SphereNameplates"
local SP    = {}
_G[ADDON]   = SP

SP.Version = "9.2.0"
SP.MEDIA   = "Interface\\AddOns\\SphereNameplates\\media\\"
SP.MEDIA2  = "Interface\\AddOns\\SphereNameplates\\media2\\"
SP.ASSETS  = "Interface\\AddOns\\SphereNameplates\\media2\\Assets\\"

-------------------------------------------------------------------------------
--  BORDER STYLES — catalogue des textures décoratives disponibles
--  path = nil → style "Solide" (aucune texture overlay, uniquement la couleur)
--  path fourni → texture ADD blendée au root+5, taille orbFrame, centrée
-------------------------------------------------------------------------------
SP.BORDER_STYLES = {
    solide    = { name="Solide",    path=nil },
    classique = { name="Classique", path=SP.MEDIA  .. "orb-border" },
    shadowcircle = { name="Shadow Circle", path=SP.MEDIA .. "shadowcircle" },
    -- Spritesheet wow_style.png : grille 3×2, chaque cellule 512×512 px, fond alpha=0
    -- uv = { left, right, top, bottom } normalisé [0..1]
    wow_horde    = { name="Horde",        path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0,        0.3333, 0,   0.5} },
    wow_alliance = { name="Alliance",     path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0.3333,  0.6667, 0,   0.5} },
    wow_evil     = { name="Evil",         path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0.6667,  1,      0,   0.5} },
    wow_beast    = { name="Beast",        path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0,       0.3333, 0.5, 1  } },
    wow_stone    = { name="Simple Stone", path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0.3333,  0.6667, 0.5, 1  } },
    wow_gold     = { name="Simple Gold",  path=SP.MEDIA.."wow_style.png", blend="BLEND", tint=false, uv={0.6667,  1,      0.5, 1  } },
    -- Spritesheet cadre_sphere_new_style.png : grille 3x2, chaque cellule 1/3 x 1/2, fond alpha=0
    ns_horde     = { name="Horde Fer",    path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0,       0.3333, 0,   0.5} },
    ns_alliance  = { name="Alliance Or",  path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.3333,  0.6667, 0,   0.5} },
    ns_void      = { name="Vide",         path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.6667,  1,      0,   0.5} },
    ns_beast     = { name="Bete",         path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0,       0.3333, 0.5, 1  } },
    ns_obsidian  = { name="Obsidienne",   path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.3333,  0.6667, 0.5, 1  } },
    ns_gold_ring = { name="Anneau Or",    path=SP.MEDIA.."cadre_sphere_new_style.png", blend="BLEND", tint=false, uv={0.6667,  1,      0.5, 1  } },
    detail    = { name="Détail",    path=SP.ASSETS .. "orb-border-2" },
}

-- Texture de l'ombre circulaire (option indépendante du style décoratif)
SP.SHADE_CIRCLE_PATH = SP.ASSETS .. "shade-circle"
SP.SHADOW_CIRCLE_PATH = SP.MEDIA .. "shadowcircle"
SP.BOSS_ELITE_FRAME_PATH = SP.MEDIA .. "Dragon_boss_elite.png"
SP.PLAYER_MENU_LABEL_CAPSULE_PATH = SP.MEDIA .. "player_menu_label_capsule.png"

function SP:GetBorderTexturePath(style)
    if not SP.BORDER_STYLES then return nil end
    local s = SP.BORDER_STYLES[style] or SP.BORDER_STYLES["solide"]
    return s and s.path or nil
end

function SP:GetBorderStyleInfo(style)
    if not SP.BORDER_STYLES then return nil end
    -- Si le style demandé existe, le retourner directement.
    -- Si le style est nil ou invalide (clé absente), retourner "solide" (pas de texture overlay).
    -- On évite le fallback "classique" qui appliquait une texture inattendue sur les nouveaux profils.
    local s = SP.BORDER_STYLES[style]
    if s then return s end
    return SP.BORDER_STYLES["solide"]  -- fallback sûr : path=nil → overlay caché
end

-------------------------------------------------------------------------------
--  RAID MARKER PACKS — atlas custom pour les marqueurs WoW
--  Ordre WoW: 1 star, 2 circle, 3 diamond, 4 triangle, 5 moon, 6 square,
--             7 cross, 8 skull.
-------------------------------------------------------------------------------
SP.RAID_MARKER_PACKS = {
    blizzard = {
        name = "Blizzard",
        blizzard = true,
    },
    sign_mark = {
        name = "Sign Mark Glow",
        texture = SP.MEDIA .. "sign_mark.png",
        cols = 4,
        rows = 2,
        order = { 1, 2, 3, 4, 5, 6, 7, 8 },
    },
    grid1_row1 = { name = "Grid Style 1 - Or",      texture = SP.MEDIA .. "sign_mark_grid_style1.png", cols = 8, rows = 4, row = 1 },
    grid1_row2 = { name = "Grid Style 1 - Peint",   texture = SP.MEDIA .. "sign_mark_grid_style1.png", cols = 8, rows = 4, row = 2 },
    grid1_row3 = { name = "Grid Style 1 - Metal",   texture = SP.MEDIA .. "sign_mark_grid_style1.png", cols = 8, rows = 4, row = 3 },
    grid1_row4 = { name = "Grid Style 1 - Bois",    texture = SP.MEDIA .. "sign_mark_grid_style1.png", cols = 8, rows = 4, row = 4 },
    grid2_row1 = { name = "Grid Style 2 - Contour", texture = SP.MEDIA .. "sign_mark_grid_style2.png", cols = 8, rows = 4, row = 1 },
    grid2_row2 = { name = "Grid Style 2 - Plein",   texture = SP.MEDIA .. "sign_mark_grid_style2.png", cols = 8, rows = 4, row = 2 },
    grid2_row3 = { name = "Grid Style 2 - Rune",    texture = SP.MEDIA .. "sign_mark_grid_style2.png", cols = 8, rows = 4, row = 3 },
    grid2_row4 = { name = "Grid Style 2 - Brush",   texture = SP.MEDIA .. "sign_mark_grid_style2.png", cols = 8, rows = 4, row = 4 },
}

SP.RAID_MARKER_PACK_ORDER = {
    "sign_mark",
    "grid1_row1", "grid1_row2", "grid1_row3", "grid1_row4",
    "grid2_row1", "grid2_row2", "grid2_row3", "grid2_row4",
    "blizzard",
}

function SP:GetRaidMarkerPack(packId)
    local packs = SP.RAID_MARKER_PACKS
    return packs and (packs[packId or "sign_mark"] or packs.sign_mark)
end

function SP:GetRaidMarkerIcon(markIndex, packId)
    markIndex = tonumber(markIndex)
    if not markIndex or markIndex < 1 or markIndex > 8 then return nil end

    local pack = self:GetRaidMarkerPack(packId)
    if not pack or pack.blizzard then
        return "Interface\\TargetingFrame\\UI-RaidTargetingIcons", nil, true
    end

    local cols = pack.cols or 8
    local rows = pack.rows or 1
    local row = pack.row
    local col
    if row then
        col = markIndex
    else
        local orderIndex = markIndex
        if pack.order then
            for i, v in ipairs(pack.order) do
                if v == markIndex then orderIndex = i break end
            end
        end
        row = math.floor((orderIndex - 1) / cols) + 1
        col = ((orderIndex - 1) % cols) + 1
    end

    local left = (col - 1) / cols
    local right = col / cols
    local top = (row - 1) / rows
    local bottom = row / rows
    return pack.texture, { left, right, top, bottom }
end

function SP:GetRaidMarkerPackOptions()
    local out = {}
    for _, id in ipairs(SP.RAID_MARKER_PACK_ORDER or {}) do
        local pack = SP.RAID_MARKER_PACKS and SP.RAID_MARKER_PACKS[id]
        if pack then
            out[#out + 1] = { value = id, label = pack.name or id }
        end
    end
    return out
end

function SP:NormalizeCastbarMode(mode)
    if mode == "segmented" then return "segments" end
    if mode == "dotted_segments" then return "dotted" end
    if mode == "collapse_ring" or mode == "inner_collapse" then return "collapse" end
    if mode == "collapse_glow_ring" or mode == "inner_collapse_glow" then return "collapse_glow" end
    return mode or "classic"
end

SP.Plates      = {}   -- [unit] = data
SP.ActiveUnits = {}   -- [unit] = unitType
SP.UnitFrames  = {}   -- [unit token fixe] = data, hors nameplates (Moi, futur focus/pet)
SP.ActiveOrbData = {} -- rendu commun Orb.AnimTick: nameplates + unitframes fixes
SP.InCombat    = false
SP.Initialized = false
SP._isRefreshing = false  -- flag anti-flash lors des refreshs

-------------------------------------------------------------------------------
--  COULEURS DE CLASSE
-------------------------------------------------------------------------------
SP.CLASS_COLORS = {
    WARRIOR     = {0.78,0.61,0.43}, PALADIN      = {0.96,0.55,0.73},
    HUNTER      = {0.67,0.83,0.45}, ROGUE        = {1.00,0.96,0.41},
    PRIEST      = {1.00,1.00,1.00}, DEATHKNIGHT  = {0.77,0.12,0.23},
    SHAMAN      = {0.00,0.44,0.87}, MAGE         = {0.41,0.80,0.94},
    WARLOCK     = {0.58,0.51,0.79}, MONK         = {0.00,1.00,0.60},
    DRUID       = {1.00,0.49,0.04}, DEMONHUNTER  = {0.64,0.19,0.79},
    EVOKER      = {0.20,0.58,0.50},
}
function SP:GetClassColor(cls)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
        local c = RAID_CLASS_COLORS[cls]
        return c.r, c.g, c.b
    end
    local c = SP.CLASS_COLORS[cls or ""]
    return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1
end

-------------------------------------------------------------------------------
--  SCRATCH FONTSTRING (escape taint via C-side SetFormattedText)
--
--  Un FontString caché, utilisé comme buffer C-side pour convertir une
--  "secret number tainted" en string Lua ordinaire via SetFormattedText.
--  Jamais affiché. Initialisé au premier appel (lazy, après CreateFrame OK).
-------------------------------------------------------------------------------
--  SCRATCH FONTSTRING (utilisé en fallback HP)
--  ⚠️  SetAlpha(0) et NON Hide() — un frame caché ne calcule pas le texte
-------------------------------------------------------------------------------
local _scratchFrame = nil
local _scratchFS    = nil

local function GetScratchFS()
    if _scratchFS then return _scratchFS end
    _scratchFrame = CreateFrame("Frame", nil, UIParent)
    _scratchFrame:SetSize(300, 20)
    _scratchFrame:SetAlpha(0)   -- invisible mais visible pour le moteur WoW
    _scratchFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 2)
    _scratchFS = _scratchFrame:CreateFontString(nil, "ARTWORK")
    _scratchFS:SetFont("Fonts\\FRIZQT__.TTF", 10)
    _scratchFS:SetAllPoints(_scratchFrame)
    return _scratchFS
end

-------------------------------------------------------------------------------
--  SCRATCH STATUSBAR — CONSERVÉ UNIQUEMENT POUR COMPAT
--
--  Ne plus utiliser GetStatusBarTexture():GetWidth() comme ratio HP texte:
--  une barre verticale peut garder une largeur pleine et renvoyer 1.0.
-------------------------------------------------------------------------------
local _hpScratchBar = nil

local function GetHPScratchBar()
    if _hpScratchBar then return _hpScratchBar end
    _hpScratchBar = CreateFrame("StatusBar", "SPHPScratchBar", UIParent)
    _hpScratchBar:SetSize(1000, 1)
    _hpScratchBar:SetAlpha(0)   -- invisible mais visible pour le layout WoW
    _hpScratchBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 2)
    _hpScratchBar:SetFrameStrata("BACKGROUND")
    _hpScratchBar:SetFrameLevel(1)
    _hpScratchBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    -- Initialisation neutre
    _hpScratchBar:SetMinMaxValues(0, 100)
    _hpScratchBar:SetValue(100)
    return _hpScratchBar
end

-- Compteur de log HP pour diagnostics (réinitialisé à chaque succès)
SP._hpDiagCount = 0

local function CleanRatio(value)
    local ok, ratio = pcall(function()
        if value == nil then return nil end
        local n = nil
        if SP.UntaintNum then
            n = SP:UntaintNum(value)
        end
        if n == nil then n = tonumber(value) end
        if n == nil then return nil end
        if n < 0 then return 0 end
        if n > 1 then
            if n <= 100 then return n / 100 end
            return 1
        end
        return n
    end)
    if ok and ratio ~= nil then return ratio end
    return nil
end

-------------------------------------------------------------------------------
--  GetHPRatio(unit) → 0.0–1.0 ou nil
--
--  Méthode 1 (principale) : StatusBar scratch — taint-safe via C-API geometry
--  Méthode 2 (fallback)   : UnitHealthPercent + SetFormattedText escape
--  Méthode 3 (dernier)    : lecture directe du healthBar Blizzard de la plaque
-------------------------------------------------------------------------------
function SP:GetHPRatio(unit)
    if not unit then return nil end

    -- ══════════════════════════════════════════════════════════════════════════
    --  RÈGLE ABSOLUE WoW Midnight 12.0.1 :
    --  Toute ARITHMETIC ou COMPARAISON (<, >, >=, <=, ==, ~=, +, -, *, /)
    --  sur un "secret number tainted" lève une Lua error.
    --  MÊME GetStatusBarTexture():GetWidth() est tainté quand SetValue()
    --  a reçu une valeur taintée.
    --  ▶ Chaque méthode est dans son propre pcall hermétique.
    --  ▶ Si une méthode crashe, pcall = false → on tombe à la suivante.
    -- ══════════════════════════════════════════════════════════════════════════

    -- ── Méthode 0 : UnitHealthPercent + conversion C-side ────────────────────
    -- Cette valeur est la plus directe pour le texte: si l'API retourne 72 ou
    -- 0.72, CleanRatio normalise vers 0.72.
    local p0ok, p0val = pcall(function()
        if type(UnitHealthPercent) ~= "function" then return nil end
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if ok then return SP:UntaintNum(pct) end
        end
        ok, pct = pcall(UnitHealthPercent, unit)
        if ok then return SP:UntaintNum(pct) end
        return nil
    end)
    local clean = p0ok and CleanRatio(p0val) or nil
    if clean ~= nil then
        SP._hpDiagCount = 0
        return clean
    end

    -- ── Méthode 1 : UntaintNum sur UnitHealth/Max ─────────────────────────────
    -- UntaintNum échappe les secret numbers via SetFormattedText (C-side) →
    -- retourne des plain Lua numbers → division safe.
    -- Même technique que la conversion startMS/endMS en CastBar.lua.
    local m0ok, m0val = pcall(function()
        local safeHP  = SP:UntaintNum(UnitHealth(unit))
        local safeMax = SP:UntaintNum(UnitHealthMax(unit))
        if safeHP and safeMax and safeMax > 0 then
            return safeHP / safeMax
        end
        return nil
    end)
    clean = m0ok and CleanRatio(m0val) or nil
    if clean ~= nil then
        SP._hpDiagCount = 0
        return clean
    end

    -- ── Méthode 2 : UnitHealthPercent + SetFormattedText (escape C-side) ─────
    -- UnitHealthPercent retourne un tainted number → on l'échappe via C-API :
    -- SetFormattedText(tainted) → le C lit la valeur et l'écrit en string propre
    -- GetText() → string Lua ordinaire → tonumber() → nombre Lua propre → safe
    -- ⚠️  scratchFrame doit être SetAlpha(0) et PAS Hide() pour que GetText() marche.
    local m2ok, m2val = pcall(function()
        local pct
        -- Tentative avec CurveConstants.ScaleTo100 (API WoW Midnight)
        if CurveConstants and CurveConstants.ScaleTo100 then
            local ok, v = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if ok then pct = SP:UntaintNum(v) end
        end
        -- Fallback : appel simple sans curve
        if pct == nil then
            local ok, v = pcall(UnitHealthPercent, unit)
            if ok then pct = SP:UntaintNum(v) end
        end
        if pct == nil then return nil end
        -- Escape : passe la valeur taintée côté C, récupère une string propre
        local fs = GetScratchFS()
        if not fs then return nil end
        fs:SetFormattedText("%.10f", pct)
        local s = fs:GetText()
        local n = s and tonumber(s)
        if not n then return nil end
        if n > 1 then return n / 100 end
        return n
    end)
    clean = m2ok and CleanRatio(m2val) or nil
    if clean ~= nil then
        SP._hpDiagCount = 0
        return clean
    end

    -- ── Méthode 4 : AbbreviateNumbers ratio (approximatif mais taint-safe) ──────
    -- AbbreviateNumbers() est C-side : elle accepte les secret numbers et retourne
    -- une string propre ("15K", "1.5M", "250"…). On parse les deux strings et on
    -- calcule le ratio avec de l'arithmétique sur des plain Lua numbers → safe.
    local m4ok, m4val = pcall(function()
        if not AbbreviateNumbers then return nil end
        local hpStr  = AbbreviateNumbers(UnitHealth(unit))
        local maxStr = AbbreviateNumbers(UnitHealthMax(unit))
        if not hpStr or not maxStr then return nil end
        local function parseAbbrev(s)
            -- Normalise : espaces, virgules décimales → point, minuscules
            s = s:gsub("%s+", ""):gsub(",", "."):lower()
            local n, suf = s:match("^([%d%.]+)([kmbt]?)$")
            local num = n and tonumber(n)
            if not num then return nil end
            if     suf == "k" then return num * 1e3
            elseif suf == "m" then return num * 1e6
            elseif suf == "b" then return num * 1e9
            elseif suf == "t" then return num * 1e12
            end
            return num
        end
        local hp, mx = parseAbbrev(hpStr), parseAbbrev(maxStr)
        if not hp or not mx or mx <= 0 then return nil end
        return hp / mx
    end)
    clean = m4ok and CleanRatio(m4val) or nil
    if clean ~= nil then
        SP._hpDiagCount = 0
        return clean
    end

    -- ── Toutes les méthodes ont échoué ──────────────────────────────────────
    if not SP._hpFailWarned then
        SP._hpFailWarned = true
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFF7700[SphereNameplates]|r HP ratio indisponible en WoW Midnight 12.x "
            .. "— couleur HP dynamique désactivée. Le fill reste correct visuellement.")
    end
    return nil
end

-------------------------------------------------------------------------------
--  UntaintNum(v) → number|nil
--
--  Convertit un "secret number tainted" WoW Midnight en plain Lua number.
--  Stratégie 1 (rapide) : tostring→tonumber (marche pour taint simple).
--  Stratégie 2 (C-side)  : scratchFS:SetFormattedText→GetText (marche pour
--  les secret numbers stricts : duration, expirationTime, startMS, endMS…).
-------------------------------------------------------------------------------
-- Valide qu'une valeur est un nombre Lua ORDINAIRE : l'arithmétique sur un
-- secret number crash (alors que type() == "number" passe). pcall = filtre.
local function IsPlainNumber(n)
    if n == nil then return false end
    local ok = pcall(function() return n + 0 end)
    return ok
end
SP.IsPlainNumber = IsPlainNumber

function SP:UntaintNum(v)
    if v == nil then return nil end
    -- Court-circuit : déjà un nombre ordinaire.
    if IsPlainNumber(v) then return tonumber(v) end
    -- Stratégie C-side: SetFormattedText lit la valeur côté moteur
    -- et GetText rend une string Lua ordinaire.
    local fs = GetScratchFS()
    if fs then
        local ok = pcall(function() fs:SetFormattedText("%.10f", v) end)
        if ok then
            local s = fs:GetText()
            -- GARDE BUG-039bis : en Midnight, GetText peut rendre une SECRET
            -- STRING → tonumber() rend alors un SECRET number. Valider avant
            -- de retourner, sinon l'appelant crash sur sa première opération.
            local okN, n = pcall(function() return s and tonumber(s) end)
            if okN and IsPlainNumber(n) then return n end
        end
    end
    -- Fallback : valide uniquement si le résultat est un nombre ordinaire.
    local okFast, fast = pcall(function() return tonumber(tostring(v)) end)
    if okFast and IsPlainNumber(fast) then return fast end
    return nil
end

-------------------------------------------------------------------------------
--  Safe Unit API wrappers
--
--  WoW Midnight can expose secret values through ordinary Unit* calls. Keep all
--  comparisons and table keys behind pcall/canaccessvalue-friendly checks.
-------------------------------------------------------------------------------
function SP:SafeUnitIsUnit(unit, other)
    if not (unit and other and UnitIsUnit) then return false end
    local ok, same = pcall(UnitIsUnit, unit, other)
    return ok and same == true
end

function SP:SafeUnitIsPlayer(unit)
    if not (unit and UnitIsPlayer) then return false end
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    return ok and isPlayer == true
end

function SP:SafeUnitIsPVP(unit)
    if not (unit and UnitIsPVP) then return false end
    local ok, isPVP = pcall(UnitIsPVP, unit)
    return ok and isPVP == true
end

function SP:SafeUnitReaction(unitA, unitB)
    if not (unitA and unitB and UnitReaction) then return nil end
    local ok, reaction = pcall(UnitReaction, unitA, unitB)
    if ok then return SP:UntaintNum(reaction) end
    return nil
end

function SP:SafeUnitLevel(unit)
    if not (unit and UnitLevel) then return 0 end
    local ok, level = pcall(UnitLevel, unit)
    local clean = ok and SP:UntaintNum(level) or nil
    return clean or 0
end

function SP:SafeUnitClassification(unit)
    if not (unit and UnitClassification) then return "" end
    local ok, classification = pcall(UnitClassification, unit)
    if ok and type(classification) == "string" then return classification end
    return ""
end

function SP:SafeUnitAffectingCombat(unit)
    if not (unit and UnitAffectingCombat) then return false end
    local ok, inCombat = pcall(UnitAffectingCombat, unit)
    return ok and inCombat == true
end

function SP:SafeUnitGUID(unit)
    if not (unit and UnitGUID) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" then return nil end
    local okCmp, notEmpty = pcall(function() return guid ~= "" end)
    if okCmp and notEmpty then return guid end
    return nil
end

-------------------------------------------------------------------------------
--  TEXTE / COULEUR HP
--
--  Separation stricte :
--    RenderHPText()    -> retourne uniquement le texte.
--    GetHPTextColor()  -> retourne uniquement la couleur.
--    ApplyHPText()     -> applique texte + couleur au FontString.
--
--  Formats supportés (cfg.hpFormat) :
--    "percent"  → "75" ou "75%"
--    "absolute" → "1.2K" / "250K" / "1.5M"
--    "both"     → "75%" + "1.2K" (deux lignes)
-------------------------------------------------------------------------------
local function _HPNum(value)
    if value == nil then return nil end
    local out = nil
    pcall(function()
        out = SP.UntaintNum and SP:UntaintNum(value) or tonumber(value)
    end)
    return out
end

local function _HPRatio(value)
    return CleanRatio(value)
end

-- Texte HP%: chemin live restaure depuis le backup 20260430_232407.
-- Ne passe pas par data.targetHP/displayHP, car ces valeurs peuvent etre lissees
-- ou stale. UnitHealthPercent est lu puis echappe via UntaintNum avant calcul.
local function _ReadLiveHPPercent(unit)
    if not (unit and type(UnitHealthPercent) == "function") then return nil, nil end

    local pct
    if CurveConstants and CurveConstants.ScaleTo100 then
        local ok, v = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if ok then pct = _HPNum(v) end
    end
    if pct == nil then
        local ok, v = pcall(UnitHealthPercent, unit)
        if ok then pct = _HPNum(v) end
    end
    if pct == nil then return nil, nil end

    local ratio = _HPRatio(pct)
    if ratio == nil then return nil, nil end

    local okPct, normalizedPct = pcall(function()
        if pct > 1 then return pct end
        return ratio * 100
    end)
    if okPct and normalizedPct ~= nil then
        return normalizedPct, ratio
    end
    return nil, ratio
end

local function _ReadHPTextRatio(data, unit)
    local _, liveRatio = _ReadLiveHPPercent(unit)
    if liveRatio ~= nil then return liveRatio end
    if data then
        local ratio = _HPRatio(data.targetHP)
        if ratio ~= nil then return ratio end
        ratio = _HPRatio(data.displayHP)
        if ratio ~= nil then return ratio end
    end
    return 1
end

local function _HPColorHex(r, g, b, a)
    local function byte(v, fallback)
        v = tonumber(v)
        if v == nil then v = fallback or 1 end
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return math.floor(v * 255 + 0.5)
    end
    return string.format("%02X%02X%02X%02X", byte(a, 1), byte(r, 1), byte(g, 1), byte(b, 1))
end

local function _HPClampColor(v, fallback)
    v = tonumber(v)
    if v == nil then v = fallback or 1 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function _WriteLiveHPPercent(fontString, data, unit, showPercent)
    if not (fontString and unit and type(UnitHealthPercent) == "function") then return false end

    local function writePct(pct)
        if showPercent then
            fontString:SetFormattedText("%.0f%%", pct)
        else
            fontString:SetFormattedText("%.0f", pct)
        end
    end

    local function writeWithCurve()
        if not (CurveConstants and CurveConstants.ScaleTo100) then return false end
        local ok = pcall(function()
            local callOK, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if not callOK then error("UnitHealthPercent curve failed") end
            writePct(pct)
        end)
        return ok
    end

    local function writeSimple()
        local ok = pcall(function()
            local callOK, pct = pcall(UnitHealthPercent, unit)
            if not callOK then error("UnitHealthPercent failed") end
            writePct(pct)
        end)
        return ok
    end

    return writeWithCurve() or writeSimple()
end

function SP:GetHPTextRatio(data, unit)
    local ratio = nil
    if unit and SP.GetHPRatio then
        local ok, liveRatio = pcall(SP.GetHPRatio, SP, unit)
        if ok then ratio = _HPRatio(liveRatio) end
    end
    if ratio == nil and data then ratio = _HPRatio(data.targetHP) end
    if ratio == nil and data then ratio = _HPRatio(data.displayHP) end
    if ratio == nil and unit then
        local ok, hp, maxHP = pcall(function()
            return SP:UntaintNum(UnitHealth(unit)), SP:UntaintNum(UnitHealthMax(unit))
        end)
        if ok then
            local okRatio, computed = pcall(function()
                if hp and maxHP and maxHP > 0 then
                    return hp / maxHP
                end
                return nil
            end)
            if okRatio then ratio = _HPRatio(computed) end
        end
    end
    if ratio == nil and unit and type(UnitHealthPercent) == "function" then
        local ok, pct = pcall(UnitHealthPercent, unit)
        if ok then ratio = _HPRatio(pct) end
    end
    if ratio == nil then return 1 end
    return ratio
end

local function _GetHPColorMode(cfg, kind)
    if kind == "absolute" then return cfg.hp_absolute_color_mode or "fixed" end
    local mode = cfg.hp_percent_color_mode
    if mode == nil then mode = cfg.hp_color_dynamic and "dynamic" or "fixed" end
    return mode
end

local function _GetFixedHPTextColor(cfg, kind)
    if kind == "absolute" then
        return _HPClampColor(cfg.hpAbsoluteTextR or cfg.hpTextR, 1),
               _HPClampColor(cfg.hpAbsoluteTextG or cfg.hpTextG, 1),
               _HPClampColor(cfg.hpAbsoluteTextB or cfg.hpTextB, 1),
               _HPClampColor(cfg.hpAbsoluteTextA, 1)
    end
    return _HPClampColor(cfg.hpPercentTextR or cfg.hpTextR, 1),
           _HPClampColor(cfg.hpPercentTextG or cfg.hpTextG, 1),
           _HPClampColor(cfg.hpPercentTextB or cfg.hpTextB, 1),
           _HPClampColor(cfg.hpPercentTextA, 1)
end

local function _GetDynamicHPTextColorFromRatio(cfg, kind, ratio)
    local idx = 1
    local okBucket = pcall(function()
        if ratio >= 0.75 then idx = 1
        elseif ratio >= 0.50 then idx = 2
        elseif ratio >= 0.25 then idx = 3
        else idx = 4 end
    end)
    if not okBucket then idx = 1 end

    local prefix = (kind == "absolute") and "hp_abs_col" or "hp_col"
    local alphaKey = (kind == "absolute") and "hpAbsoluteTextA" or "hpPercentTextA"
    return _HPClampColor(cfg[prefix .. idx .. "_r"], 1),
           _HPClampColor(cfg[prefix .. idx .. "_g"], 1),
           _HPClampColor(cfg[prefix .. idx .. "_b"], 1),
           _HPClampColor(cfg[alphaKey], 1),
           idx
end

local _hpColorCurveCache = setmetatable({}, { __mode = "k" })

local function _HPColorCurveSignature(cfg, kind)
    local prefix = (kind == "absolute") and "hp_abs_col" or "hp_col"
    local parts = {}
    for i = 1, 4 do
        parts[#parts + 1] = tostring(_HPClampColor(cfg[prefix .. i .. "_r"], 1))
        parts[#parts + 1] = tostring(_HPClampColor(cfg[prefix .. i .. "_g"], 1))
        parts[#parts + 1] = tostring(_HPClampColor(cfg[prefix .. i .. "_b"], 1))
    end
    return table.concat(parts, "/")
end

local function _AddHPColorCurvePoint(curve, x, cfg, kind, idx)
    local prefix = (kind == "absolute") and "hp_abs_col" or "hp_col"
    curve:AddPoint(x, CreateColor(
        _HPClampColor(cfg[prefix .. idx .. "_r"], 1),
        _HPClampColor(cfg[prefix .. idx .. "_g"], 1),
        _HPClampColor(cfg[prefix .. idx .. "_b"], 1),
        1))
end

function SP:CreateHPColorCurve(cfg, kind)
    if type(UnitHealthPercent) ~= "function" then
        return nil, "no_unit_health_percent"
    end
    if type(C_CurveUtil) ~= "table" or type(C_CurveUtil.CreateColorCurve) ~= "function" then
        return nil, "no_create_color_curve"
    end
    if type(CreateColor) ~= "function" then
        return nil, "no_create_color"
    end
    if type(Enum) ~= "table" or type(Enum.LuaCurveType) ~= "table" or Enum.LuaCurveType.Step == nil then
        return nil, "no_step_curve_type"
    end

    cfg = cfg or {}
    kind = (kind == "absolute") and "absolute" or "percent"
    local sig = _HPColorCurveSignature(cfg, kind)
    local byKind = _hpColorCurveCache[cfg]
    if byKind and byKind[kind] and byKind[kind].sig == sig then
        return byKind[kind].curve, "curve_cached"
    end

    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then
        return nil, "create_color_curve_failed"
    end

    local okBuild, err = pcall(function()
        curve:SetType(Enum.LuaCurveType.Step)
        -- UnitHealthPercent travaille sur 0..1. Step: la couleur change au
        -- seuil suivant sans interpolation Lua ni comparaison sur secret value.
        _AddHPColorCurvePoint(curve, 0.00, cfg, kind, 4) -- 0-24
        _AddHPColorCurvePoint(curve, 0.25, cfg, kind, 3) -- 25-49
        _AddHPColorCurvePoint(curve, 0.50, cfg, kind, 2) -- 50-74
        _AddHPColorCurvePoint(curve, 0.75, cfg, kind, 1) -- 75-100
    end)
    if not okBuild then
        return nil, "build_color_curve_failed:" .. tostring(err)
    end

    byKind = byKind or {}
    byKind[kind] = { sig = sig, curve = curve }
    _hpColorCurveCache[cfg] = byKind
    return curve, "curve_created"
end

local function _ColorObjectRGBA(color)
    if color == nil then return nil, nil, nil, nil, "curve_no_color" end
    if type(color.GetRGBA) == "function" then
        local ok, r, g, b, a = pcall(color.GetRGBA, color)
        if ok then return r, g, b, a, nil end
    end
    if type(color.GetRGB) == "function" then
        local ok, r, g, b = pcall(color.GetRGB, color)
        if ok then return r, g, b, 1, nil end
    end
    return nil, nil, nil, nil, "curve_rgba_unavailable"
end

local function _TryHPTextColorCurve(SPRef, cfg, unit, kind)
    local curve, curveReason = SPRef:CreateHPColorCurve(cfg, kind)
    if not curve then return nil, nil, nil, nil, "unavailable_secret", curveReason end

    local okColor, color = pcall(UnitHealthPercent, unit, true, curve)
    if not okColor then return nil, nil, nil, nil, "unavailable_secret", "curve_failed" end

    local r, g, b, a, rgbaReason = _ColorObjectRGBA(color)
    if rgbaReason then return nil, nil, nil, nil, "unavailable_secret", rgbaReason end
    return r, g, b, a, "curve", "curve_ok"
end

function SP:GetHPTextColor(data, unit, kind)
    kind = (kind == "absolute") and "absolute" or "percent"
    local cfg = (data and data.unitType and SP:GetCfg(data.unitType)) or {}
    local mode = _GetHPColorMode(cfg, kind)

    if mode ~= "dynamic" then
        local r, g, b, a = _GetFixedHPTextColor(cfg, kind)
        return r, g, b, a, "fixed", "fixed_mode"
    end

    -- Preview/config: pas de secret values, on peut utiliser le ratio du data mock.
    if not unit then
        local ratio = _ReadHPTextRatio(data, nil)
        local r, g, b, a, idx = _GetDynamicHPTextColorFromRatio(cfg, kind, ratio)
        return r, g, b, a, "preview_dynamic", "preview_ratio_" .. tostring(idx)
    end

    -- Runtime WoW Midnight: ne pas lire FontString, ne pas parser, ne pas comparer
    -- UnitHealthPercent en Lua. Seule voie acceptee ici: une curve compatible
    -- retour couleur. Si absente, fallback fixe explicite et stable.
    local r, g, b, a, source, reason = _TryHPTextColorCurve(SP, cfg, unit, kind)
    if source == "curve" then
        local alphaKey = (kind == "absolute") and "hpAbsoluteTextA" or "hpPercentTextA"
        return r, g, b, _HPClampColor(cfg[alphaKey], a or 1), source, reason
    end

    local fr, fg, fb, fa = _GetFixedHPTextColor(cfg, kind)
    return fr, fg, fb, fa, "fallback_fixed", tostring(reason or source)
end

function SP:ApplyHPTextColor(fontString, data, unit, kind)
    if not fontString then return false, "no_fontstring", "no_fontstring" end
    local r, g, b, a, source, reason = SP:GetHPTextColor(data, unit, kind)
    local ok, err = pcall(fontString.SetTextColor, fontString, r, g, b, a)
    if not ok then
        local cfg = (data and data.unitType and SP:GetCfg(data.unitType)) or {}
        local fr, fg, fb, fa = _GetFixedHPTextColor(cfg, kind)
        pcall(fontString.SetTextColor, fontString, fr, fg, fb, fa)
        source = "fallback_fixed"
        reason = "set_text_color_failed"
    end
    SP._hpColorTrace = {
        unit = tostring(unit),
        unitType = data and data.unitType or nil,
        mode = tostring((data and data.unitType) and _GetHPColorMode(SP:GetCfg(data.unitType), kind) or "fixed"),
        kind = tostring(kind),
        source = tostring(source),
        reason = tostring(reason),
        setTextColor = tostring(ok),
        error = tostring(err),
    }
    return ok, source, reason
end

function SP:RenderHPText(unit, fmt, showPercent, data)
    fmt = fmt or "percent"
    if unit and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
        return "Dead"
    end

    local livePct, liveRatio = _ReadLiveHPPercent(unit)
    local ratio = liveRatio or _ReadHPTextRatio(data, unit)
    local okPct, pct = pcall(function()
        local value = livePct or (ratio * 100)
        return math.floor(value + 0.5)
    end)
    if not okPct then pct = 100 end

    local function absText()
        if unit and AbbreviateNumbers then
            local okAbs, txt = pcall(function()
                return tostring(AbbreviateNumbers(UnitHealth(unit)))
            end)
            if okAbs and txt ~= nil then return txt end
        end
        if data and data._previewAbsHP ~= nil then return tostring(data._previewAbsHP) end
        return "166k"
    end

    if fmt == "absolute" then
        return absText()
    end

    if fmt == "both" then
        local pctText = showPercent and (tostring(pct) .. "%") or tostring(pct)
        return pctText .. "\n" .. absText()
    end

    return showPercent and (tostring(pct) .. "%") or tostring(pct)
end

function SP:ApplyHPText(fontString, data, unit, fmt, showPercent)
    if not fontString then return end
    local kind = (fmt == "absolute") and "absolute" or "percent"
    SP:ApplyHPTextColor(fontString, data, unit, kind)
    if fmt == "percent" and _WriteLiveHPPercent(fontString, data, unit, showPercent) then
        return
    end
    fontString:SetText(SP:RenderHPText(unit, fmt, showPercent, data))
end

function SP:ApplyHPTextPair(primary, secondary, data, unit, fmt, showPercent)
    if not primary then return end
    if fmt == "both" and secondary then
        SP:ApplyHPText(primary, data, unit, "percent", showPercent)
        SP:ApplyHPText(secondary, data, unit, "absolute", showPercent)
        primary:Show()
        secondary:Show()
        return
    end
    SP:ApplyHPText(primary, data, unit, fmt, showPercent)
    primary:Show()
    if secondary then secondary:Hide() end
end

-------------------------------------------------------------------------------
--  FORMATAGE HP (API compat — utilisé par l'UI de config)
--
--  Retourne une string HP formatée. Utilise GetHPRatio() en interne.
--  Pour "absolute" : retourne un texte approché si GetHPRatio disponible,
--  sinon "?%". Pour affichage dans l'orbe, préférer RenderHPText().
-------------------------------------------------------------------------------
function SP:FormatHPText(unit, fmt, data)
    -- Utiliser GetHPRatio (taint-safe) pour obtenir le ratio
    local ratio = SP:GetHPRatio(unit)

    if not ratio then
        return "?%"
    end

    local pct = math.floor(ratio * 100)

    if fmt == "absolute" then
        -- Pour l'absolu, on ne peut pas récupérer hp/maxHP sans taint
        -- On affiche le % comme fallback
        return tostring(pct) .. "%"
    elseif fmt == "both" then
        return tostring(pct) .. "%"
    else
        return tostring(pct) .. "%"
    end
end

function SP:FormatAbs(n)
    if n >= 1000000 then return string.format("%.1fM", n/1000000)
    elseif n >= 10000 then return string.format("%.0fK", n/1000)
    elseif n >= 1000  then return string.format("%.1fK", n/1000)
    else return tostring(math.floor(n)) end
end

function SP:GetUnitHealthPct(unit, data)
    return SP:GetHPRatio(unit) or 1
end

-------------------------------------------------------------------------------
--  NIVEAU
-------------------------------------------------------------------------------
function SP:GetLevelText(unit)
    local lvl = SP:SafeUnitLevel(unit)
    if lvl <= 0 then return nil end
    local maxLvl = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
    if lvl >= maxLvl then return nil end
    local col = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
        or {r=1,g=1,b=1}
    return string.format("|cff%02x%02x%02x%d|r",
        math.floor((col.r or 1)*255),
        math.floor((col.g or 1)*255),
        math.floor((col.b or 1)*255), lvl)
end

-------------------------------------------------------------------------------
--  TYPE D'UNITÉ
-------------------------------------------------------------------------------
function SP:GetUnitType(unit)
    -- WoW Midnight : UnitExists peut retourner false pour les tokens nameplate
    -- alors qu'UnitReaction fonctionne. On n'exige plus UnitExists.
    local reaction = SP:SafeUnitReaction("player", unit)
    local isPlayer = SP:SafeUnitIsPlayer(unit)

    if not reaction then
        -- Fallback PvP : réaction inconnue mais unité joueur identifiée
        if isPlayer then
            local isPVP = SP:SafeUnitIsPVP(unit)
            -- En zone PvP (BG/arène), les joueurs sans réaction = ennemis par défaut
            return isPVP and "ENEMY_PLAYER" or "FRIENDLY_PLAYER"
        end
        return nil
    end

    local isFriendly = reaction >= 5
    if isPlayer then
        return isFriendly and "FRIENDLY_PLAYER" or "ENEMY_PLAYER"
    else
        if reaction == 4 then return "NEUTRAL" end
        return isFriendly and "FRIENDLY" or "ENEMY"
    end
end

function SP:GetCfg(unitType)
    if SP.db and SP.db[unitType] then return SP.db[unitType] end
    local def = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile[unitType]
    return def or {enabled=true, size=64}
end

function SP:EnsureProfileDefaults()
    if not (SP.db and SP.DEFAULTS and SP.DEFAULTS.profile) then return end
    for key, value in pairs(SP.DEFAULTS.profile) do
        if SP.db[key] == nil then
            if type(value) == "table" then
                SP.db[key] = {}
                for k, v in pairs(value) do SP.db[key][k] = v end
            else
                SP.db[key] = value
            end
        elseif type(value) == "table" and type(SP.db[key]) == "table" then
            for k, v in pairs(value) do
                if SP.db[key][k] == nil then SP.db[key][k] = v end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  POLICES
--  Bibliothèque de base + enrichissement automatique via LibSharedMedia-3.0
--  (élargit la liste avec les polices d'ElvUI, Plater, Krak, etc.)
-------------------------------------------------------------------------------
SP.FONT_LIST = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]           = "Fonts\\skurri.TTF",
    ["SP Alte"]          = SP.MEDIA .. "Alte.ttf",
    ["SP Dajova"]        = SP.MEDIA .. "Dajova.ttf",
    ["SP Rotund"]        = SP.MEDIA .. "rotund.ttf",
    ["SP Rotundo"]       = SP.MEDIA .. "rotundo.ttf",
}

function SP:BuildFontList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local fonts = LSM:HashTable("font")
    if not fonts then return end
    for name, path in pairs(fonts) do
        if not SP.FONT_LIST[name] then
            SP.FONT_LIST[name] = path
        end
    end
end

SP.CASTBAR_TEXTURES = {
    { value = "white",           label = "Blizzard - Plat",        path = "Interface\\Buttons\\WHITE8x8" },
    { value = "blizzard_status", label = "Blizzard - Status",      path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "bigwigs_banto",   label = "BigWigs - Banto",        path = "Interface\\AddOns\\BigWigs\\Media\\Textures\\BantoBar.tga" },
    { value = "details_best",    label = "Details - Best",         path = "Interface\\AddOns\\Details\\images\\bar_textures\\bar_best.png" },
    { value = "details_round",   label = "Details - Rounded",      path = "Interface\\AddOns\\Details\\images\\bar_textures\\bar_rounded.png" },
    { value = "details_split",   label = "Details - Split",        path = "Interface\\AddOns\\Details\\images\\bar_textures\\split_bar.tga" },
    { value = "gw2_status",      label = "GW2 UI - Status",        path = "Interface\\AddOns\\GW2_UI\\Textures\\bartextures\\statusbar.tga" },
    { value = "gw2_cast",        label = "GW2 UI - Cast",          path = "Interface\\AddOns\\GW2_UI\\Textures\\hud\\castingbar.tga" },
    { value = "gw2_cast_white",  label = "GW2 UI - Cast White",    path = "Interface\\AddOns\\GW2_UI\\Textures\\hud\\castinbar-white.tga" },
    { value = "gw2_dark",        label = "GW2 UI - Dark",          path = "Interface\\AddOns\\GW2_UI\\Textures\\uistuff\\gwstatusbar.tga" },
    { value = "kaliels_flat",    label = "Kaliel - Flat",          path = "Interface\\AddOns\\!KalielsTracker\\Media\\KT-statusbar-flat.tga" },
}

SP.CASTBAR_RING_SHAPES = {
    { value = "soft",        label = "Soft Glow" },
    { value = "thin_arcane", label = "Anneau fin arcane" },
    { value = "double",      label = "Double Glow" },
    { value = "performance", label = "Performance" },
}

SP.CASTBAR_INTERRUPT_MARK_SHAPES = {
    { value = "none",    label = "Aucun" },
    { value = "cross",   label = "Croix" },
    { value = "x",       label = "X" },
    { value = "slash",   label = "Slash" },
    { value = "square",  label = "Carre" },
    { value = "diamond", label = "Losange" },
    { value = "rune",    label = "Rune simple" },
}

function SP:GetCastBarTextureOptions()
    local out, seen = {}, {}
    for _, tex in ipairs(self.CASTBAR_TEXTURES or {}) do
        if tex.value and not seen[tex.value] then
            out[#out + 1] = tex
            seen[tex.value] = true
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local bars = LSM and LSM:HashTable("statusbar")
    if bars then
        local names = {}
        for name in pairs(bars) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local value = "lsm:" .. name
            if not seen[value] then
                out[#out + 1] = { value = value, label = name, path = bars[name] }
                seen[value] = true
            end
        end
    end
    return out
end

function SP:GetCastBarTexturePath(key)
    key = key or "white"
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local name = key:sub(5)
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name)
            if ok and path then return path end
        end
    end
    for _, tex in ipairs(self.CASTBAR_TEXTURES or {}) do
        if tex.value == key then
            return tex.path or "Interface\\Buttons\\WHITE8x8"
        end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

-- Appel après PLAYER_LOGIN : toutes les polices d'addons tiers sont enregistrées
do
    local _fontBoot = CreateFrame("Frame")
    _fontBoot:RegisterEvent("PLAYER_LOGIN")
    _fontBoot:SetScript("OnEvent", function(self)
        SP:BuildFontList()
        self:UnregisterAllEvents()
    end)
end

function SP:GetFont(name)
    return SP.FONT_LIST[name] or "Fonts\\FRIZQT__.TTF"
end

-------------------------------------------------------------------------------
--  DEBUG
-------------------------------------------------------------------------------
function SP:Debug(msg)
    if SP.db and SP.db.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00CCFF[SP-DBG]|r " .. tostring(msg))
    end
end

-------------------------------------------------------------------------------
--  DEFAULTS ACEDB v7.4
-------------------------------------------------------------------------------
local function U(o)
    local base = {
        enabled            = true,
        sphere_display_mode = "always", -- "never" | "combat" | "always" | "target"
        -- Orbe
        size               = 64,
        offsetX            = 0,
        offsetY            = 0,
        -- Couleur fill
        fillR              = 1.0,
        fillG              = 0.10,
        fillB              = 0.10,
        fill_color_mode    = "fixed", -- "fixed" | "progressive" | "class" (legacy: "custom")
        fill_saturation    = 1.0,
        fill_alpha         = 0.88,   -- opacité du fill HP
        orb_hp_fill_alpha  = 0.0,    -- fill HP invisible: le StatusBar pilote seulement le masque/ligne de vie
        fill_prog_highR    = 0.20, fill_prog_highG = 1.00, fill_prog_highB = 0.20, -- 75-100
        fill_prog_midR     = 1.00, fill_prog_midG  = 0.82, fill_prog_midB  = 0.00, -- 50-74
        fill_prog_lowR     = 1.00, fill_prog_lowG  = 0.50, fill_prog_lowB  = 0.00, -- 25-49
        fill_prog_critR    = 1.00, fill_prog_critG = 0.15, fill_prog_critB = 0.15, -- 0-24
        classColorSphere   = false,
        -- Animation HP
        hp_lerp_speed      = 8.0,
        -- ── Effets visuels (style DiabolicUI2 / rOrbs) ──────────────────────
        -- Galaxies rotatives
        orb_galaxies       = true,
        orb_galaxy_alpha   = 0.15,   -- réduit : évite le disque lumineux dans le vide
        orb_midnight_star  = false,
        orb_midnight_star_alpha = 0.55,
        orb_midnight_star_scale = 1.18,
        orb_midnight_star_speed = 45,
        orb_midnight_star_dir = "cw",
        orb_midnight_star_class_color = false,
        -- Shimmer (reflets animés)
        orb_shimmer_alpha  = 0.22,   -- réduit : évite le disque lumineux dans le vide
        -- Vague liquide (DiabolicUI filling textures) — scrolle à la ligne d'eau
        orb_wave           = true,
        orb_wave_alpha     = 0.38,   -- intensité vague
        orb_wave_speed     = 0.18,   -- vitesse de scroll (0=immobile, 0.5=rapide)
        -- Gloss
        orb_gloss          = true,
        orb_gloss_alpha    = 0.20,   -- réduit : 0.45 créait le "disque persistant"
        -- Spark (étincelle à la ligne d'eau HP)
        orb_spark          = true,
        -- Lueur HP critique
        orb_lowhp_glow     = true,
        -- Cible actuelle
        target_custom_enabled = false,
        target_glow_enabled   = true,
        target_glowR          = 1.00,
        target_glowG          = 0.88,
        target_glowB          = 0.00,
        target_glow_alpha     = 0.85,
        target_glow_style     = "pulse", -- "pulse" | "ripple"
        target_glow_pulse     = true,
        target_ripple_speed   = 1.25,
        target_ripple_size    = 2.20,
        target_ripple_trail   = 0.82,
        target_ripple_wavelength = 0.25,
        target_ripple_intensity = 1.35,
        target_ripple_saturation = 1.25,
        target_ripple_width   = 1.20,
        target_scale_enabled  = false,
        target_scale          = 1.0,
        target_priority       = "normal",
        -- Réduction d'échelle hors-cible
        non_target_scale_enabled = false,
        non_target_scale         = 0.75,
        -- Seuils de couleur HP
        hp_threshold_low   = 50,     -- % → couleur orange
        hp_threshold_crit  = 20,     -- % → couleur rouge + pulse
        -- ── Bordure ─────────────────────────────────────────────────────────
        borderEnabled      = true,
        borderR            = 0.90,
        borderG            = 0.72,
        borderB            = 0.10,
        borderWidth        = 6,         -- taille de la bordure en pixels
        borderColorMode    = "custom",  -- "custom" | "classe"
        borderClassColor   = false,     -- alias legacy — dérivé de borderColorMode
        border_threat_color = false,    -- rouge si engagé, doré (borderR/G/B) si neutre
        borderStyle        = "solide",     -- style décoratif overlay (SP.BORDER_STYLES) — "solide" = anneau couleur seul, sans texture
        borderOverlayScale = 1.5,    -- taille du cadre décoratif en multiple de SIZE (1.0=orbe, 1.5=défaut, 2.0=grand)
        border_glow_pulse  = false,  -- pulsation alpha de l'overlay décoratif
        showEliteDragon    = false,
        -- ── Ancre / Pointeur ─────────────────────────────────────────────────
        anchor_enabled     = true,   -- flèche / pin visuel sous l'orbe
        anchor_alpha       = 0.75,   -- opacité du pointeur
        -- Texte orbe
        showLevelOrHP      = true,
        showHPAlsoInOrb    = false,
        hpFormat           = "percent",
        levelFont          = "Friz Quadrata TT",
        levelFontSize      = 11,
        hpTextOffsetX      = 0,
        hpTextOffsetY      = 0,
        hpSubTextOffsetX   = 0,
        hpSubTextOffsetY   = 0,
        hpTextR            = nil,    -- legacy: couleur texte HP/niveau (nil = blanc auto)
        hpTextG            = nil,
        hpTextB            = nil,
        hpPercentTextR     = nil,    -- couleur personnalisee du pourcentage HP
        hpPercentTextG     = nil,
        hpPercentTextB     = nil,
        hpPercentTextA     = 1,
        hpAbsoluteTextR    = nil,    -- couleur personnalisee de la valeur absolue HP
        hpAbsoluteTextG    = nil,
        hpAbsoluteTextB    = nil,
        hpAbsoluteTextA    = 1,
        hp_color_dynamic   = false,  -- couleur dynamique par palier HP
        hp_show_percent    = false,  -- afficher le symbole % après la valeur HP
        hp_percent_color_mode  = "fixed",   -- "fixed" | "dynamic"
        hp_absolute_color_mode = "fixed",   -- "fixed" | "dynamic"
        -- Couleurs des 4 paliers HP dynamiques (utilisées si hp_color_dynamic = true)
        hp_col1_r = 0.20, hp_col1_g = 1.0,  hp_col1_b = 0.20,  -- 75-100% : vert
        hp_col2_r = 1.0,  hp_col2_g = 0.82, hp_col2_b = 0.0,   -- 50-74%  : jaune
        hp_col3_r = 1.0,  hp_col3_g = 0.50, hp_col3_b = 0.0,   -- 25-49%  : orange
        hp_col4_r = 1.0,  hp_col4_g = 0.15, hp_col4_b = 0.15,  -- 0-24%   : rouge
        hp_abs_col1_r = 0.20, hp_abs_col1_g = 1.0,  hp_abs_col1_b = 0.20,
        hp_abs_col2_r = 1.0,  hp_abs_col2_g = 0.82, hp_abs_col2_b = 0.0,
        hp_abs_col3_r = 1.0,  hp_abs_col3_g = 0.50, hp_abs_col3_b = 0.0,
        hp_abs_col4_r = 1.0,  hp_abs_col4_g = 0.15, hp_abs_col4_b = 0.15,
        -- Nom
        showName           = true,
        nameDisplay        = "above",
        nameFont           = "Friz Quadrata TT",
        nameFontSize       = 12,
        nameOffsetY        = 6,
        nameOffsetX        = 0,
        name_maxWidth      = 0,      -- largeur max px (0 = auto)
        name_distance_enabled = false,
        name_distance_mode    = "limit", -- "limit" | "fade"
        name_distance_max     = 20,      -- cache le nom au-dela (yards)
        name_fade_full        = 2,       -- alpha nom max a cette distance
        name_fade_hidden      = 20,      -- alpha nom 0 au-dela
        show_ilvl          = true,   -- iLvL quand joueur hors combat + HP plein (≥ 98%)
        -- Mode couleur du nom : "fixed" | "progressive" | "class"
        -- "class" n'est pertinent que pour les joueurs (PNJ → fallback "fixed")
        name_color_mode    = "fixed",
        name_saturation    = 1.0,    -- 0 = gris, 1 = normal, 2 = hyper-saturé
        name_alpha         = 1.0,    -- opacité du texte nom (compose avec hover)
        -- Paliers progressifs (analogues à fill_prog_*)
        name_prog_highR    = 1.0,  name_prog_highG = 1.0,  name_prog_highB = 1.0,  -- 75-100%
        name_prog_midR     = 1.0,  name_prog_midG  = 0.82, name_prog_midB  = 0.0,  -- 50-74%
        name_prog_lowR     = 1.0,  name_prog_lowG  = 0.50, name_prog_lowB  = 0.0,  -- 25-49%
        name_prog_critR    = 1.0,  name_prog_critG = 0.15, name_prog_critB = 0.15, -- 0-24%
        -- Legacy (conservés pour compat profils sauvegardés)
        classColorName     = true,
        nameR              = nil,    -- couleur nom custom (nil = auto selon type/classe)
        nameG              = nil,
        nameB              = nil,
        -- Sous-titre
        showSubTitle       = false,
        showGuild          = false,
        showHonor          = false,
        -- Indicateurs
        showCombatIndicator = true,
        -- Power bar
        showPower          = false,
        powerOffsetY       = 3,
        -- Auras
        auras_enabled      = true,
        auras_debuff       = true,
        auras_buff         = false,
        auras_debuff_priority = true,
        auras_control      = true,
        auras_maxDebuff    = 5,
        auras_maxBuff      = 3,
        auras_size         = 20,
        auras_offsetY      = 4,
        auras_layout       = "line",
        auras_cols         = 5,
        auras_side         = "below",  -- "below" | "left" | "right"
        auras_mode         = "icons",  -- "icons" (arc) | "ring" (icones fixes) | "segments" (5 portions fixes)
        auras_segment_alpha = 0.92,
        auras_segment_glow  = true,
        -- Debuffs: options separees (fallback garde les anciens auras_*)
        auras_debuff_mine_only  = false,
        auras_debuff_size       = 20,
        auras_debuff_offsetY    = 4,
        auras_debuff_side       = "below",
        auras_debuff_timer      = true,
        auras_debuff_timer_alpha = 0.92,
        auras_debuff_timer_edge = true,
        auras_debuff_timer_text = true,
        auras_debuff_text_size  = 8,
        auras_debuff_timerR     = 1.00,
        auras_debuff_timerG     = 0.22,
        auras_debuff_timerB     = 0.08,
        auras_debuff_textR      = 1.00,
        auras_debuff_textG      = 0.92,
        auras_debuff_textB      = 0.75,
        -- Buffs
        auras_buff_mine_only    = false,
        auras_buff_size         = 20,
        auras_buff_offsetY      = 4,
        auras_buff_side         = "above",
        auras_buff_timer        = true,
        auras_buff_timer_alpha  = 0.78,
        auras_buff_timer_edge   = true,
        auras_buff_timer_text   = true,
        auras_buff_text_size    = 8,
        auras_buff_timerR       = 0.12,
        auras_buff_timerG       = 0.72,
        auras_buff_timerB       = 1.00,
        auras_buff_textR        = 0.78,
        auras_buff_textG        = 0.92,
        auras_buff_textB        = 1.00,
        -- CastBar
        castbar_enabled        = true,
        castbar_arc_thickness  = 14,  -- anneau visible = (arcSize - borderSize) / 2 = (SIZE+28 - SIZE+12) / 2 = 8px
        castbar_showName       = true,
        castbar_showTime       = true,
        castbar_nameFontSize   = 10,
        castbar_nameOffsetY    = 5,
        castbar_offset_x       = 0,    -- décalage horizontal de l'arc (px)
        castbar_offset_y       = 0,    -- décalage vertical de l'arc (px)
        castbar_scale          = 1.0,  -- échelle de l'arc (1.0 = taille normale)
        castbar_mode           = "classic",   -- "classic" | "circular" | "segments" | "dotted" | "collapse" | "collapse_glow"
        -- ── Castbar circulaire v2 (CCB-inspired) ────────────────────────────
        castbar_cast_style     = "smooth",   -- "smooth" | "segments" | "twin"
        castbar_channel_style  = "swipe",    -- "swipe" | "comets" | "radar" | "pulse"
        castbar_glow_intensity = 1.0,        -- 0.0..2.0
        castbar_color_by_class = true,       -- couleur primary = classe du caster (joueur)
        castbar_show_track     = true,       -- anneau de fond toujours visible
        castbar_show_pin12     = true,       -- point au top (départ de la progression)
        castbar_show_bevel     = true,       -- liserés interne/externe
        castbar_show_ticks     = false,      -- 24 ticks gradués
        castbar_complete_flash = true,       -- flash anneau à 100%
        castbar_show_kick_fx   = true,       -- shards rouges + texte sur interrupt
        castbar_segments_count = 12,         -- compat legacy
        castbar_v8_segments    = false,      -- compat: force les segments V8 dans le mode circulaire
        castbar_v8_count       = 12,         -- nombre de segments alignes (3-24)
        castbar_dotted_count   = 18,         -- nombre de points dotted (6-36)
        castbar_dotted_size    = 5,          -- taille des points dotted
        castbar_dotted_radius  = 0,          -- offset rayon dotted
        castbar_dotted_alpha   = 0.95,
        castbar_dotted_glow    = true,
        castbar_collapse_color_mode = "dynamic", -- "fixed" | "dynamic"
        castbar_collapse_fixedR = 1.00,
        castbar_collapse_fixedG = 0.25,
        castbar_collapse_fixedB = 0.85,
        castbar_collapse_alpha  = 0.92,
        castbar_collapse_start_scale = 1.75,
        castbar_collapse_end_scale   = 0.72,
        castbar_collapse_interrupt_flash = true,
        castbar_collapse_complete_flash  = true,
        castbar_collapse_glow_color_mode = "cast", -- "cast" | "custom" | "progressive"
        castbar_collapse_glow_shape = "soft", -- "soft" | "thin_arcane" | "double" | "performance"
        castbar_collapse_glowR = 0.30,
        castbar_collapse_glowG = 1.00,
        castbar_collapse_glowB = 0.45,
        castbar_collapse_glow_startR = 1.00,
        castbar_collapse_glow_startG = 0.22,
        castbar_collapse_glow_startB = 0.78,
        castbar_collapse_glow_endR = 0.22,
        castbar_collapse_glow_endG = 1.00,
        castbar_collapse_glow_endB = 0.62,
        castbar_collapse_glow_saturation = 1.00,
        castbar_collapse_glow_alpha = 0.85,
        castbar_collapse_glow_intensity = 1.00,
        castbar_collapse_glow_start_scale = 1.65,
        castbar_collapse_glow_end_scale = 0.45,
        castbar_collapse_glow_thickness = 1.00,
        castbar_collapse_glow_pulse = true,
        castbar_collapse_glow_interrupt_flash = true,
        castbar_collapse_glow_complete_flash = true,
        castbar_interrupt_fallback = true,
        castbar_interrupt_fallback_grace = 0.12,
        castbar_interrupt_mark_enabled = true,
        castbar_interrupt_mark_shape = "x",
        castbar_interrupt_mark_size = 18,
        castbar_interrupt_mark_alpha = 0.92,
        castbar_interrupt_mark_duration = 0.42,
        castbar_interrupt_mark_custom_color = false,
        castbar_interrupt_markR = 0.95,
        castbar_interrupt_markG = 0.20,
        castbar_interrupt_markB = 0.20,
        castbar_texture        = "white",    -- texture du fill de la castbar classique
        castbar_classic_width  = 120,
        castbar_classic_height = 12,
        castbar_classic_scale  = 1.0,
        castbar_classic_bgR    = 0.04,
        castbar_classic_bgG    = 0.04,
        castbar_classic_bgB    = 0.07,
        castbar_classic_bgA    = 0.88,
        castbar_classic_fillR  = 1.00,
        castbar_classic_fillG  = 0.65,
        castbar_classic_fillB  = 0.00,
        castbar_classic_border = true,
        castbar_classic_borderR = 1.00,
        castbar_classic_borderG = 0.76,
        castbar_classic_borderB = 0.28,
        castbar_preset         = "minimal",  -- "minimal"|"overwatch"|"techno"
        castbar_icon_position  = "top",      -- "top"|"center"|"bottomright"|"left"|"right"
        castbar_icon_size      = 0.42,       -- ratio de SIZE (0.20–0.80)
        castbar_icon_offset_x  = 0,          -- décalage X de l'icône (px)
        castbar_icon_offset_y  = 0,          -- décalage Y de l'icône (px)
        castbar_show_icon      = true,       -- afficher l'icône du sort
        castbar_focus_mode     = false,      -- masquer HP/ilvl/castTime pendant le cast, réafficher après
        castbar_text_position  = "bottom",   -- "center"|"top"|"bottom"|"left"|"right"
        castbar_text_offset_x  = 0,
        castbar_text_offset_y  = 0,
        castbar_text_colorR    = 1.00,
        castbar_text_colorG    = 0.88,
        castbar_text_colorB    = 0.45,
        castbar_text_font      = "Friz Quadrata TT",
        castbar_time_offset_y  = 0,
        castbar_text_mode      = "separate", -- "separate" | "replace_name"
        -- Couleurs personnalisées (utilisées si castbar_color_by_class = false ou caster non-joueur)
        castbar_color_cast     = {1.00, 0.65, 0.00},  -- interruptible (orange)
        castbar_color_nonint   = {0.72, 0.18, 1.00},  -- non-interruptible joueur (violet)
        castbar_color_immune   = {0.88, 0.10, 0.08},  -- immune/boss (rouge)
        castbar_color_channel  = {0.10, 0.55, 0.95},  -- channel (bleu)
        castbar_color_finish   = {0.30, 1.00, 0.30},  -- complétion (vert)
        castbar_color_broken   = {0.95, 0.20, 0.20},  -- interruption (rouge)
        castbar_color_track    = {0.10, 0.10, 0.12, 0.55}, -- fond track (rgba)
        -- ── Circular Castbar (CCB) — mode "ccb" ─────────────────────────────
        -- Styles par état de cast (12 valeurs possibles : voir SP.CCB_STYLES)
        ccb_cast_style         = "Normal",    -- cast interruptible
        ccb_notint_style       = "Pulse",     -- cast non-interruptible joueur
        ccb_boss_style         = "Critical",  -- immune / boss
        ccb_channel_style      = "Channel",   -- canalisation
        -- Apparence
        ccb_border             = "Beveled",   -- Runic|Beveled|Elite|Sculpted|Notched|Thin|Doubled
        ccb_size_ratio         = 2.5,         -- taille = SIZE * ratio
        ccb_alpha              = 0.90,        -- opacité Composite
        ccb_offset_x           = 0,
        ccb_offset_y           = 0,
        -- Couches additives
        ccb_glow               = true,        -- couche Glow (ADD)
        ccb_highlight          = true,        -- couche Highlight (ADD)
        ccb_runes              = false,       -- couche Runes (ADD)
        -- Effets post-cast
        ccb_flash_complete     = true,        -- flash Flash (0.30 s) à 100%
        ccb_flash_interrupt    = true,        -- overlay Interrupt (0.70 s) sur kick [legacy, remplacé par castbar_interrupt_visual]
        -- Mode visuel interruption CCB
        castbar_interrupt_visual  = "classic_glow",  -- "classic_glow" | "classic_ccb"
        ccb_interrupt_size_ratio  = 1.0,             -- taille overlay = ccbSize * ratio
        ccb_interrupt_color       = {1.0, 0.25, 0.25},
        -- Teintes par type de cast (SetVertexColor ; {1,1,1} = palette Holy native sans teinte)
        ccb_color_cast         = {1, 1, 1},   -- cast interruptible
        ccb_color_notint       = {1, 1, 1},   -- cast non-interruptible
        ccb_color_boss         = {1, 1, 1},   -- immune / boss
        ccb_color_channel      = {1, 1, 1},   -- canalisation
        -- Quête / marques
        quest_enabled      = true,
        quest_sound        = false,  -- son à l'apparition d'un PNJ de quête
        quest_color_name   = true,   -- nom en bleu pour les PNJ de quête
        quest_proximity_sound = false,
        quest_proximity_sound_distance = 30,
        quest_proximity_sound_cooldown = 12,
        quest_proximity_sound_unit_cooldown = 75,
        quest_proximity_sound_in_combat = false,
        quest_proximity_sound_enemies_only = true,
        quest_proximity_sound_active_only = true,
        quest_proximity_sound_id = "quest_item",
        raidmark_enabled   = true,
        -- Ombre circulaire (indépendante du style décoratif)
        shadeCircleEnabled = false,
        shadeCircleAlpha   = 0.6,
        -- Arrière-plan de la sphère (couleur du fond noir)
        bgR                = 0.0,
        bgG                = 0.0,
        bgB                = 0.0,
        bgAlpha            = 0.75,           -- 1.0 → 0.75 (Codex 2026-04-30: rendu trop noir)
        orb_empty_clear_enabled = true,      -- coupe le fond/FX internes dans la portion vide
        orb_empty_shade_enabled = false,     -- optionnel: voile de couleur sur la portion vide
        orb_empty_shadeR  = 0.0,
        orb_empty_shadeG  = 0.0,
        orb_empty_shadeB  = 0.0,
        orb_empty_shade_alpha = 0.0,
        -- Ombres internes (configurables, étaient hardcodées 0.62 / 0.50)
        orb_shadow_alpha   = 0.35,           -- ancien hardcode 0.62 → 0.35 (lisibilité)
        orb_shadow2_alpha  = 0.0,            -- 0.50 → 0.0 (texture orb-innershadow-v2 absente du dossier media)
        orb_shadow2_enabled = false,         -- créer la texture seulement si true
        -- Icônes PNJ contextuelles (type: vendeur, forgeron, etc.)
        npcIconsEnabled    = false,
        -- Effet visuel CC (sphère violette + timer quand contrôle actif)
        cc_effect_enabled  = true,
        -- Afficher HP sous le texte niveau max
        show_hp_under_maxlvl = false,
        -- Distance fade
        fade_enabled       = false,
        fade_start         = 25,
        fade_end           = 40,
        fade_min_alpha     = 0.55,           -- 0.15 (hardcode) → 0.55 (Codex: orbe lointaine restait trop transparente)
        ignore_parent_alpha = true,          -- V3: ignorer alpha nameplate parent (anti-assombrissement Blizzard)
    }
    if o then for k,v in pairs(o) do base[k]=v end end
    return base
end

SP.DEFAULTS = { profile = {
    addonEnabled  = true,
    debugMode     = false,
    minimap_angle = 220,
    behavior_force_friendly_players_instance = true,
    boss_elite_frame_enabled = true,
    boss_elite_frame_scale   = 1.85,
    boss_elite_frame_alpha   = 1.00,

    -- Sphère joueur fixe ("Moi") : UnitFrame personnelle hors nameplates
    moi_enabled              = false,
    moi_display_mode         = "always", -- "always" | "combat"
    moi_locked               = false,
    moi_x                    = -280,
    moi_y                    = -170,
    moi_scale                = 1.0,
    moi_hide_blizzard_player = true,
    moi_hide_blizzard_migrated = 0,
    snp_edit_mode            = false,

    -- UnitFrames Cible / Cible de la cible (Lot G)
    tuf_target_enabled       = true,
    tuf_target_x             = 280,
    tuf_target_y             = -170,
    tuf_target_scale         = 1.0,
    tuf_target_locked        = false,
    tuf_tot_enabled          = true,
    tuf_tot_x                = 470,
    tuf_tot_y                = -120,
    tuf_tot_scale            = 1.0,
    tuf_tot_locked           = false,
    tuf_hide_blizzard_target = true,

    -- Barres d'actions personnelles (Moi > Barres). Desactivees par defaut,
    -- mais quand elles sont activees elles remplacent les barres Blizzard.
    actionbars = {
        enabled = false,
        hideBlizzard = true, -- legacy alias
        replaceBlizzard = true,
        lock = true,
        selected = 1,
        editGrid = true,
        editSnap = true,
        editGridSize = 16,
        primaryPairAnchor = true,
        primaryPairGap = 28,
        primaryPairYOffset = 0,
        bars = {
            [1] = { enabled=true,  buttons=12, firstSlot=1,   followPaging=true,  orientation="horizontal", columns=12, size=36, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="always", x=-220, y=-300, anchorMode="moi_left", showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [2] = { enabled=false, buttons=12, firstSlot=13,  followPaging=false, orientation="horizontal", columns=12, size=36, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="always", x=-220, y=-344, showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [3] = { enabled=false, buttons=12, firstSlot=25,  followPaging=false, orientation="vertical",   columns=1,  size=36, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="always", x=430,  y=-120, showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [4] = { enabled=false, buttons=12, firstSlot=37,  followPaging=false, orientation="vertical",   columns=1,  size=36, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="always", x=476,  y=-120, showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [5] = { enabled=false, buttons=12, firstSlot=49,  followPaging=false, orientation="grid",       columns=6,  size=34, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="combat_target", x=-160, y=-390, showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [6] = { enabled=false, buttons=12, firstSlot=61,  followPaging=false, orientation="grid",       columns=6,  size=34, spacing=4, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="combat_target", x=160,  y=-390, anchorMode="moi_right", showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [7] = { enabled=false, buttons=12, firstSlot=73,  followPaging=false, orientation="horizontal", columns=12, size=32, spacing=3, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="mouseover", x=-220, y=220,  showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
            [8] = { enabled=false, buttons=12, firstSlot=85,  followPaging=false, orientation="horizontal", columns=12, size=32, spacing=3, scale=1.0, alpha=1.0, inactiveAlpha=0.25, visibility="mouseover", x=-220, y=260,  showEmpty=true, emptyAlpha=0.00, showHotkey=true, showCount=true, showMacro=false, showCooldown=true, clickOnDown=false, hoverScale=1.08 },
        },
    },

    -- Menu radial joueur (clic droit sur sphere joueur)
    player_menu_enabled        = true,
    player_menu_position       = "sphere", -- "sphere" | "cursor"
    player_menu_radius         = 58,
    player_menu_icon_size      = 38,
    player_menu_icon_zoom      = 1.0,
    player_menu_alpha          = 1.0,
    player_menu_scale          = 1.0,
    player_menu_open_duration  = 0.16,
    player_menu_close_duration = 0.10,
    player_menu_hover_glow     = true,
    player_menu_select_glow_size = 1.12,
    player_menu_select_glow_alpha = 0.62,
    player_menu_select_color_auto = true,
    player_menu_select_rotation = true,
    player_menu_select_rotation_speed = 180,
    player_menu_select_particles = true,
    player_menu_select_particle_alpha = 0.75,
    player_menu_label_bg       = true,
    player_menu_label_bg_alpha = 0.42,
    player_menu_label_padding  = 7,
    player_menu_label_text_size = 15,
    player_menu_tooltips       = false,
    player_menu_close_after_action = true,
    player_menu_debug          = false,
    player_menu_action_invite      = true,
    player_menu_action_duel        = true,
    player_menu_action_trade       = true,
    player_menu_action_inspect     = true,
    player_menu_action_follow      = true,
    player_menu_action_achievement = true,
    player_menu_action_whisper     = true,

    -- Marqueurs WoW natifs (raid target icons)
    raidmark_global_enabled = true,
    raidmark_show_all_types = true,
    raidmark_position_mode  = "sphere", -- "sphere" | "name"
    raidmark_name_position  = "above",  -- "above" | "left" | "right" | "below"
    raidmark_size           = 24,
    raidmark_scale          = 1.0,
    raidmark_alpha          = 1.0,
    raidmark_offset_x       = 0,
    raidmark_offset_y       = 20,
    raidmark_spacing        = 4,
    raidmark_custom_enabled = true,
    raidmark_pack           = "sign_mark",
    raidmark_menu_enabled   = true,
    raidmark_menu_players   = false,
    raidmark_menu_double_click_ms = 350,
    raidmark_menu_radius    = 58,
    raidmark_menu_icon_size = 38,
    raidmark_menu_alpha     = 1.0,
    raidmark_menu_scale     = 1.0,
    raidmark_menu_hover_glow = true,
    raidmark_menu_select_color_auto = true,
    raidmark_menu_select_glow_size = 1.12,
    raidmark_menu_select_glow_alpha = 0.62,
    raidmark_menu_select_rotation = true,
    raidmark_menu_select_rotation_speed = 180,
    raidmark_menu_select_particles = true,
    raidmark_menu_select_particle_alpha = 0.75,
    raidmark_menu_close_after_action = true,
    raidmark_menu_debug     = false,

    -- ── Mode Densité / Pack ───────────────────────────────────────────────────
    -- Activé automatiquement quand N sphères sont visibles simultanément.
    -- A : CVars nameplate recalibrés pour sphères (espacement Blizzard)
    -- B : Scale/alpha adaptatifs + masquage noms non-cibles
    -- C : Priorité visuelle par rang + atténuation galaxies + Pack Orb
    pack_mode_enabled          = false,   -- master switch
    pack_threshold             = 6,       -- nb sphères pour déclencher le mode
    pack_lerp_speed            = 8.0,     -- vitesse lerp alpha/scale (unités/sec)
    -- B : non-cibles en mode pack
    pack_non_target_alpha      = 0.50,   -- alpha sphères non-cibles
    pack_non_target_scale      = 0.68,   -- scale sphères non-cibles
    pack_name_hide             = true,   -- masquer noms non-cibles
    pack_galaxy_attenuate      = true,   -- atténuer couches galaxy
    pack_galaxy_alpha          = 0.22,   -- opacité galaxy rank-0 en mode pack
    -- B : cible en mode pack (contraste)
    pack_target_scale_boost    = 1.12,   -- scale multiplicatif de la cible
    -- A : ajustement CVars Blizzard pour espacement sphérique
    pack_cvar_adjust           = true,
    pack_cvar_overlap_h        = 1.25,
    pack_cvar_overlap_v        = 1.55,
    -- Pack Orb (grande sphère de cluster décorative, click-through)
    pack_orb_enabled           = true,
    pack_orb_alpha             = 0.36,
    pack_orb_color_r           = 0.55,
    pack_orb_color_g           = 0.18,
    pack_orb_color_b           = 0.85,
    pack_orb_pulse             = true,
    pack_orb_show_count        = true,
    pack_orb_count_size        = 13,
    pack_orb_padding           = 0.38,   -- ratio extra-radius autour du cluster

    -- ── Modules actifs (ON/OFF isolement FPS) ─────────────────────────────────
    modules_orbanim_enabled   = true,
    modules_castbar_enabled   = true,
    modules_auras_enabled     = true,
    modules_hplerp_enabled    = true,
    modules_fade_enabled      = true,
    modules_inspectilvl_enabled = true,
    modules_quest_enabled     = true,
    modules_moi_enabled       = true,

    -- ── Logs internes ─────────────────────────────────────────────────────────
    logs_enabled        = false,
    logs_max_entries    = 200,
    logs_level_info     = true,
    logs_level_warn     = true,
    logs_level_error    = true,
    logs_level_debug    = false,
    logs_level_perf     = true,
    logs_persist        = false,

    -- ── Performance Monitor ───────────────────────────────────────────────────
    spdebug_enabled     = true,
    spdebug_fps_enabled = true,
    spdebug_memory_enabled = true,
    spdebug_refresh_sec = 0.5,
    spdebug_alert_throttle = 3.0,
    spdebug_log_filter_level = "ALL",
    spdebug_log_filter_module = "ALL",
    perf_enabled        = false,
    perf_seuil_ms       = 5.0,
    perf_panel_visible  = false,

    ENEMY = U({
        size=64, fillR=1.0, fillG=0.10, fillB=0.10,
        borderR=0.95, borderG=0.70, borderB=0.08, borderWidth=6,
        classColorSphere=false, classColorName=false,
        name_color_mode="fixed",
        showLevelOrHP=true, showEliteDragon=true,
        showCombatIndicator=true,
        auras_enabled=true, auras_debuff=true, castbar_enabled=true,
        quest_enabled=true, raidmark_enabled=true,
        hp_threshold_low=50, hp_threshold_crit=20,
    }),
    FRIENDLY = U({
        size=48, fillR=0.10, fillG=0.80, fillB=0.15,
        borderR=0.10, borderG=0.85, borderB=0.22, borderWidth=5,
        name_color_mode="fixed",
        showLevelOrHP=true, showEliteDragon=false,
        showCombatIndicator=false,
        auras_enabled=false, castbar_enabled=true,  -- activé : alliés castent aussi
        quest_enabled=true, raidmark_enabled=false,
        orb_wave=false,  -- vague désactivée pour les alliés (moins de bruit visuel)
    }),
    NEUTRAL = U({
        size=58, fillR=0.95, fillG=0.70, fillB=0.12,
        borderR=0.95, borderG=0.72, borderB=0.12, borderWidth=5,
        classColorSphere=false, classColorName=false,
        name_color_mode="fixed",
        showLevelOrHP=true, showEliteDragon=false,
        showCombatIndicator=false,
        auras_enabled=true, auras_debuff=true, auras_buff=false,
        castbar_enabled=true, quest_enabled=true, raidmark_enabled=false,
        hp_threshold_low=50, hp_threshold_crit=20,
    }),
    ENEMY_PLAYER = U({
        size=68, fillR=0.85, fillG=0.08, fillB=0.08,
        borderR=1.00, borderG=0.18, borderB=0.18, borderWidth=6,
        borderColorMode="classe", borderClassColor=true,
        classColorSphere=true, classColorName=true,
        name_color_mode="class",
        showLevelOrHP=true, hpFormat="percent",
        showCombatIndicator=true, showHonor=true,
        auras_enabled=true, auras_debuff=true,
        castbar_enabled=true, raidmark_enabled=true,
        hp_threshold_low=50, hp_threshold_crit=20,
    }),
    FRIENDLY_PLAYER = U({
        size=52, fillR=0.10, fillG=0.70, fillB=0.30,
        borderR=0.10, borderG=0.55, borderB=1.00, borderWidth=5,
        borderColorMode="classe", borderClassColor=true,
        classColorSphere=true, classColorName=true,
        name_color_mode="class",
        showLevelOrHP=true, showHonor=false,
        showCombatIndicator=false,
        auras_enabled=false, castbar_enabled=true,  -- activé : joueurs alliés castent
        raidmark_enabled=true,
        orb_wave=false,
    }),
    PLAYER_SELF = U({
        size=74, fillR=0.80, fillG=0.10, fillB=0.10,
        borderR=0.92, borderG=0.72, borderB=0.16, borderWidth=6,
        borderColorMode="classe", borderClassColor=true,
        classColorSphere=true, classColorName=true,
        name_color_mode="class",
        showName=true, nameDisplay="above", showSubTitle=false,
        showLevelOrHP=true, showHPAlsoInOrb=true, hpFormat="both",
        hp_percent_color_mode="dynamic", hp_absolute_color_mode="fixed",
        show_hp_under_maxlvl=true, show_ilvl=false,
        showPower=true, powerOffsetY=4,
        -- Shadow Circle par défaut pour les unitframes : c'est l'anneau de
        -- classe ET le support visuel de l'anneau ressource (BUG-036).
        borderStyle="shadowcircle",
        moi_resource_ring_enabled=true,
        moi_resource_ring_alpha=0.86,
        moi_resource_ring_split=true,
        moi_resource_ring_scale=1.08,
        moi_resource_ring_min_alpha=0.10,
        -- "smart" = visible en combat ou pendant ~5s après un sort; "combat" = combat seul; "always" = toujours
        moi_resource_ring_visibility="smart",
        -- Arc XP / réputation autour de la sphère (Lot D)
        moi_xp_ring_enabled=true,
        moi_xp_ring_mode="auto",      -- auto | xp | reputation | hidden
        moi_xp_ring_alpha=0.75,
        moi_xp_ring_scale=1.22,
        moi_behavior_glow_enabled=true,
        moi_behavior_glow_aggro=true,
        moi_behavior_glow_cast=true,
        moi_behavior_glow_lowhp=true,
        moi_behavior_glow_heal=true,
        moi_behavior_glow_cc=true,
        moi_behavior_lowhp_threshold=35,
        moi_behavior_glow_alpha=0.70,
        moi_behavior_glow_size=1.80,
        moi_behavior_glow_cooldown=1.20,
        auras_enabled=true, auras_debuff=true, auras_buff=true,
        auras_maxDebuff=5, auras_maxBuff=5,
        castbar_enabled=true, castbar_mode="collapse_glow",
        raidmark_enabled=false, quest_enabled=false,
        showCombatIndicator=false, showEliteDragon=false,
        target_glow_enabled=false, anchor_enabled=false,
        sphere_display_mode="always",
        hp_lerp_speed=10.0,
    }),

    -- UnitFrame Cible (Lot G) — pages épurées : pas de ressources/XP/ilvl/
    -- barres/comportement Moi. Classification élite + castbar + auras.
    TARGET = U({
        size=74, fillR=0.80, fillG=0.10, fillB=0.10,
        borderR=0.92, borderG=0.72, borderB=0.16, borderWidth=6,
        borderColorMode="classe", borderClassColor=true,
        borderStyle="shadowcircle",
        classColorSphere=true, classColorName=true,
        name_color_mode="class",
        showName=true, nameDisplay="above", showSubTitle=false,
        showLevelOrHP=true, showHPAlsoInOrb=true, hpFormat="both",
        hp_percent_color_mode="dynamic", hp_absolute_color_mode="fixed",
        show_hp_under_maxlvl=true, show_ilvl=false,
        showPower=false, powerOffsetY=4,
        auras_enabled=true, auras_debuff=true, auras_buff=true,
        auras_maxDebuff=5, auras_maxBuff=3,
        castbar_enabled=true, castbar_mode="collapse_glow",
        raidmark_enabled=true, quest_enabled=false,
        showCombatIndicator=false, showEliteDragon=true,
        target_glow_enabled=false, anchor_enabled=false,
        sphere_display_mode="always",
        hp_lerp_speed=10.0,
    }),

    -- UnitFrame Cible de la cible — version compacte, sans castbar/auras.
    TARGET_TARGET = U({
        size=52, fillR=0.80, fillG=0.10, fillB=0.10,
        borderR=0.92, borderG=0.72, borderB=0.16, borderWidth=4,
        borderColorMode="classe", borderClassColor=true,
        borderStyle="shadowcircle",
        classColorSphere=true, classColorName=true,
        name_color_mode="class",
        showName=true, nameDisplay="above", showSubTitle=false,
        showLevelOrHP=true, showHPAlsoInOrb=false, hpFormat="percent",
        hp_percent_color_mode="dynamic", hp_absolute_color_mode="fixed",
        show_hp_under_maxlvl=true, show_ilvl=false,
        showPower=false, powerOffsetY=4,
        auras_enabled=false, auras_debuff=false, auras_buff=false,
        auras_maxDebuff=0, auras_maxBuff=0,
        castbar_enabled=false, castbar_mode="collapse_glow",
        raidmark_enabled=true, quest_enabled=false,
        showCombatIndicator=false, showEliteDragon=false,
        target_glow_enabled=false, anchor_enabled=false,
        sphere_display_mode="always",
        hp_lerp_speed=10.0,
    }),
}}

-------------------------------------------------------------------------------
--  ITEM LEVEL (iLvL) — WoW Midnight
--
--  C_PaperDollInfo.GetInspectItemLevel(unit) retourne l'iLvL moyen de l'unité
--  si elle est dans la zone d'inspection (généralement ≤ 40 yards).
--  Retourne nil si l'API n'existe pas ou si les données ne sont pas disponibles.
--  Enveloppé dans pcall : toute erreur API est silencieuse.
-------------------------------------------------------------------------------
function SP:GetUnitItemLevel(unit)
    if not unit then return nil end

    -- Préférence : cache du module Inspect (rempli après NotifyInspect → INSPECT_READY)
    if SP.Inspect and SP.Inspect.GetCached then
        local cached = SP.Inspect:GetCached(unit)
        if cached and cached > 0 then return cached end
    end

    -- Tentative directe : parfois Blizzard a déjà la donnée
    -- (autre addon, fenêtre inspect ouverte précédemment, etc.)
    local ok, ilvl = pcall(function()
        if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
            return C_PaperDollInfo.GetInspectItemLevel(unit)
        end
        return nil
    end)
    if ok and ilvl and type(ilvl) == "number" and ilvl > 0 then
        local v = math.floor(ilvl)
        -- Mémoriser dans le cache pour les prochaines lectures
        if SP.Inspect and SP.Inspect.SetCached then
            local guid = SP.SafeUnitGUID and SP:SafeUnitGUID(unit) or nil
            if guid then SP.Inspect:SetCached(guid, v) end
        end
        return v
    end

    -- Miss : déclencher une inspection asynchrone, le résultat arrivera plus tard
    if SP.Inspect and SP.Inspect.Queue then
        SP.Inspect:Queue(unit)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Couleur ilvl déléguée au module Inspect
-------------------------------------------------------------------------------
function SP:GetIlvlColorHex(ilvl)
    if SP.Inspect and SP.Inspect.GetIlvlColorHex then
        return SP.Inspect:GetIlvlColorHex(ilvl)
    end
    return "FFD700"  -- fallback doré (ancien comportement)
end

-------------------------------------------------------------------------------
--  UTILITAIRE CHAT
-------------------------------------------------------------------------------
function SP:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cFF8B0000Sphere|r|cFFFF7A00Plates|r » " .. tostring(msg))
end
