-------------------------------------------------------------------------------
-- SphereNameplates — Modules/PackOrb.lua
-- Grande sphère de cluster décorative (Pack Orb)
--
-- CONCEPT :
--   Quand N sphères se trouvent dans un rayon de R pixels à l'écran,
--   une grande orbe semi-transparente apparaît en arrière-plan à leur centroïde.
--   Elle est purement décorative : EnableMouse(false), FrameStrata BACKGROUND.
--   Les sphères individuelles restent entièrement cliquables et ciblables.
--
-- ARCHITECTURE :
--   - Pool de MAX_CLUSTER_FRAMES cluster frames (évite les CreateFrame dynamiques)
--   - Clustering : distance euclidienne à 4 FPS (poll Core.lua)
--   - Algorithme Union-Find simplifié : O(N²) mais N ≤ 25 en donjon
--   - Animation pulse : OnUpdate dédié sur le cadre packOrbTicker (séparé)
--   - Taint-safe : aucun appel Unit* ici, seulement frame:GetCenter()
--
-- HIÉRARCHIE FRAMES :
--   clusterFrame (Frame, BACKGROUND, EnableMouse false)
--     ├── bgTex      — sphère colorée (WHITE8x8 + circular mask, BLEND)
--     ├── glowTex    — halo externe (WHITE8x8 + circular mask, ADD)
--     └── countText  — texte "×8" (FontString, OVERLAY)
--
-- COMPATIBILITÉ WoW Midnight :
--   GetCenter() peut retourner nil si la frame est hors-écran ou invisible.
--   Tous les accès sont guardés. Le module ne touche jamais SP.Plates directement
--   (lecture seulement, via pairs() protégé dans UpdateClusters).
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.PackOrb = {}
local PKO = SP.PackOrb

-- ── Constantes ──────────────────────────────────────────────────────────────
local MAX_CLUSTER_FRAMES = 5    -- max clusters simultanés affichés
local CLUSTER_RADIUS_PX  = 130  -- rayon en pixels pour regrouper 2 sphères
local MIN_CLUSTER_SIZE   = 2    -- au moins 2 membres pour former un cluster

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE       = "Interface\\Buttons\\WHITE8x8"

-- ── Pool de frames cluster ──────────────────────────────────────────────────
PKO._frames   = {}  -- pool de clusterFrame
PKO._active   = {}  -- frames actuellement visibles (sous-ensemble de _frames)
PKO._pulseAcc = 0   -- accumulateur pour animation pulse

-- ── Création d'une frame cluster ────────────────────────────────────────────
local function CreateClusterFrame(idx)
    local f = CreateFrame("Frame", "SP_PackOrb_" .. idx, UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:EnableMouse(false)
    f:SetClampedToScreen(false)
    f:Hide()

    -- Texture de fond : grande sphère colorée avec masque circulaire
    local bgTex = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    bgTex:SetTexture(WHITE)
    bgTex:SetBlendMode("BLEND")
    bgTex:SetAllPoints(f)

    -- Masque circulaire : donne la forme sphérique
    local maskTex = nil
    local okMask = pcall(function()
        maskTex = f:CreateMaskTexture()
        maskTex:SetTexture(CIRCLE_MASK)
        maskTex:SetAllPoints(f)
        bgTex:AddMaskTexture(maskTex)
    end)
    if not okMask then maskTex = nil end

    -- Halo externe (ADD blend, légèrement plus grand que le fond)
    local glowTex = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    glowTex:SetTexture(WHITE)
    glowTex:SetBlendMode("ADD")
    glowTex:SetPoint("TOPLEFT",    f, "TOPLEFT",    -0.25, 0.25)
    glowTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0.25, -0.25)
    local glowMask = nil
    pcall(function()
        glowMask = f:CreateMaskTexture()
        glowMask:SetTexture(CIRCLE_MASK)
        glowMask:SetAllPoints(glowTex)
        glowTex:AddMaskTexture(glowMask)
    end)

    -- Texte compteur (×N)
    local cText = f:CreateFontString(nil, "OVERLAY")
    local fontSize = 13
    pcall(cText.SetFont, cText, "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    cText:SetPoint("CENTER", f, "CENTER", 0, 0)
    cText:SetTextColor(1, 1, 1, 0.90)
    cText:SetText("")

    f._bgTex   = bgTex
    f._glowTex = glowTex
    f._cText   = cText
    f._alpha   = 0     -- alpha courant (lerp)
    f._size    = 0     -- taille courante (lerp)
    f._targetAlpha = 0
    f._targetSize  = 0
    return f
end

-- Initialiser le pool
for i = 1, MAX_CLUSTER_FRAMES do
    PKO._frames[i] = CreateClusterFrame(i)
end

-- ── OnUpdate dédié pour l'animation pulse ────────────────────────────────────
-- Séparé du OnUpdate principal pour ne pas charger le loop 60 FPS.
-- Ce ticker tourne à ~20 FPS (dt >= 0.05).
local _ticker = CreateFrame("Frame", "SP_PackOrb_Ticker", UIParent)
_ticker:SetScript("OnUpdate", function(_, elapsed)
    PKO._pulseAcc = PKO._pulseAcc + elapsed
    if PKO._pulseAcc < 0.05 then return end
    local dt = PKO._pulseAcc
    PKO._pulseAcc = 0

    local db = SP.db or {}
    if not db.pack_mode_enabled then return end

    local baseAlpha  = db.pack_orb_alpha  or 0.36
    local r          = db.pack_orb_color_r or 0.55
    local g          = db.pack_orb_color_g or 0.18
    local b          = db.pack_orb_color_b or 0.85
    local doPulse    = db.pack_orb_pulse ~= false
    local showCount  = db.pack_orb_show_count ~= false
    local countSize  = db.pack_orb_count_size or 13

    local now = (GetTime and GetTime()) or 0
    -- Pulse : oscille entre 70% et 100% de l'alpha de base
    local pulseA = doPulse and (0.70 + 0.30 * math.abs(math.sin(now * 1.4))) or 1.0
    local glowA  = doPulse and (0.08 + 0.06 * math.abs(math.sin(now * 1.4))) or 0.10

    for _, f in ipairs(PKO._active) do
        if f._clusterSize and f._clusterSize > 0 then
            -- Lerp alpha vers la cible
            local ca = f._alpha
            local ta = f._targetAlpha
            ca = ca + (ta - ca) * math.min(0.95, dt * 6.0)
            if math.abs(ca - ta) < 0.005 then ca = ta end
            f._alpha = ca

            -- Lerp size
            local cs = f._size
            local ts = f._targetSize
            cs = cs + (ts - cs) * math.min(0.95, dt * 5.0)
            if math.abs(cs - ts) < 1 then cs = ts end
            f._size = cs

            if ca < 0.01 then
                f:Hide()
            else
                f:Show()
                f:SetSize(cs, cs)
                -- Appliquer couleur + alpha pulse sur bgTex
                if f._bgTex then
                    f._bgTex:SetVertexColor(r, g, b)
                    f._bgTex:SetAlpha(ca * pulseA)
                end
                -- Halo externe : plus transparent, ADD blend → glow lumineux
                if f._glowTex then
                    f._glowTex:SetVertexColor(r * 0.8, g * 0.8, b * 0.8)
                    f._glowTex:SetAlpha(ca * glowA)
                end
                -- Compteur
                if f._cText then
                    if showCount and f._clusterSize >= 2 then
                        local txt = "×" .. tostring(f._clusterSize)
                        f._cText:SetText(txt)
                        pcall(f._cText.SetFont, f._cText,
                            "Fonts\\FRIZQT__.TTF", countSize, "OUTLINE")
                        f._cText:SetAlpha(math.min(1.0, ca * 2.2))
                        f._cText:Show()
                    else
                        f._cText:Hide()
                    end
                end
            end
        else
            -- Fade out
            local ca = f._alpha
            ca = ca + (0 - ca) * math.min(0.95, dt * 8.0)
            if ca < 0.005 then ca = 0 end
            f._alpha = ca
            if ca < 0.01 then
                f:Hide()
            else
                f:SetAlpha(ca)
            end
        end
    end
end)

-- ── Algorithme de clustering ─────────────────────────────────────────────────
-- Entrée : SP.Plates (lu en lecture seule)
-- Sortie : liste de clusters [{cx, cy, radius, members}]
-- Algorithme : Union-Find simple basé sur distance entre centroïdes de frames.
-- Capped à 25 plates pour garantir O(N²) ≤ 625 opérations.
local function BuildClusters()
    -- 1. Collecter les positions (screen coords via GetCenter)
    local positions = {}
    local n = 0
    for _, data in pairs(SP.Plates) do
        if n >= 25 then break end  -- cap de sécurité performance
        if data.root and data.root:IsVisible() then
            local ok, cx, cy = pcall(function()
                return data.root:GetCenter()
            end)
            if ok and cx and cy then
                n = n + 1
                positions[n] = { x = cx, y = cy, group = n }
            end
        end
    end
    if n < MIN_CLUSTER_SIZE then return {} end

    -- 2. Union-Find : fusionner les points dans le rayon CLUSTER_RADIUS_PX
    local R2 = CLUSTER_RADIUS_PX * CLUSTER_RADIUS_PX
    local function findRoot(i)
        -- Path compression simple
        local root = i
        while positions[root].group ~= root do
            root = positions[root].group
        end
        -- Compression du chemin
        local cur = i
        while cur ~= root do
            local next = positions[cur].group
            positions[cur].group = root
            cur = next
        end
        return root
    end

    for i = 1, n do
        for j = i + 1, n do
            local dx = positions[i].x - positions[j].x
            local dy = positions[i].y - positions[j].y
            if (dx * dx + dy * dy) <= R2 then
                local ri = findRoot(i)
                local rj = findRoot(j)
                if ri ~= rj then
                    -- Fusionner les deux groupes
                    positions[rj].group = ri
                end
            end
        end
    end

    -- 3. Agréger par groupe racine
    local groups = {}  -- [root] = {sumX, sumY, count, minX, maxX, minY, maxY}
    for i = 1, n do
        local root = findRoot(i)
        local g = groups[root]
        if not g then
            g = {
                sumX=0, sumY=0, count=0,
                minX = math.huge, maxX = -math.huge,
                minY = math.huge, maxY = -math.huge,
            }
            groups[root] = g
        end
        g.sumX  = g.sumX + positions[i].x
        g.sumY  = g.sumY + positions[i].y
        g.count = g.count + 1
        if positions[i].x < g.minX then g.minX = positions[i].x end
        if positions[i].x > g.maxX then g.maxX = positions[i].x end
        if positions[i].y < g.minY then g.minY = positions[i].y end
        if positions[i].y > g.maxY then g.maxY = positions[i].y end
    end

    -- 4. Construire la liste de clusters (seulement si taille >= MIN_CLUSTER_SIZE)
    local clusters = {}
    local db = SP.db or {}
    local padding = db.pack_orb_padding or 0.38
    for _, g in pairs(groups) do
        if g.count >= MIN_CLUSTER_SIZE then
            local cx   = g.sumX / g.count
            local cy   = g.sumY / g.count
            -- Rayon = demi-diagonale du bounding box + padding
            local hw   = (g.maxX - g.minX) * 0.5
            local hh   = (g.maxY - g.minY) * 0.5
            local bRad = math.sqrt(hw * hw + hh * hh)
            -- Rayon minimum = CLUSTER_RADIUS_PX * 0.5 pour éviter les micro-orbes
            local radius = math.max(CLUSTER_RADIUS_PX * 0.45, bRad * (1 + padding))
            clusters[#clusters + 1] = {
                cx     = cx,
                cy     = cy,
                radius = radius,
                count  = g.count,
            }
        end
    end
    return clusters
end

-- ── UpdateClusters — appelé depuis Core.lua poll (2 FPS) ─────────────────────
function PKO:UpdateClusters()
    local db = SP.db or {}
    if not db.pack_mode_enabled or not db.pack_orb_enabled then
        self:HideAll()
        return
    end
    if not SP._packMode then
        self:HideAll()
        return
    end

    -- Construire les clusters depuis les positions actuelles des frames
    local clusters = {}
    local ok = pcall(function()
        clusters = BuildClusters()
    end)
    if not ok then
        self:HideAll()
        return
    end

    -- Réinitialiser les membres actifs
    PKO._active = {}

    -- Affecter un cluster frame à chaque cluster (dans la limite du pool)
    local fi = 0
    for _, cl in ipairs(clusters) do
        fi = fi + 1
        if fi > MAX_CLUSTER_FRAMES then break end
        local f = PKO._frames[fi]
        if f then
            -- Positionner au centroïde du cluster (coordonnées écran)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cl.cx, cl.cy)
            -- Taille = diamètre = 2 × rayon
            local targetSize = cl.radius * 2
            f._targetSize  = targetSize
            f._targetAlpha = db.pack_orb_alpha or 0.36
            f._clusterSize = cl.count
            -- Initialiser la taille si la frame vient d'être cachée
            if not f:IsShown() then
                f._size  = targetSize * 0.5  -- démarre à 50% pour un expand visuel
                f._alpha = 0
                f:SetSize(f._size, f._size)
            end
            PKO._active[#PKO._active + 1] = f
        end
    end

    -- Cacher les frames du pool non utilisées
    for i = fi + 1, MAX_CLUSTER_FRAMES do
        local f = PKO._frames[i]
        if f then
            f._targetAlpha = 0
            f._clusterSize = 0
        end
    end
end

-- ── HideAll — appelé quand le pack mode se désactive ─────────────────────────
function PKO:HideAll()
    PKO._active = {}
    for _, f in ipairs(PKO._frames) do
        f._targetAlpha = 0
        f._clusterSize = 0
        -- Le ticker OnUpdate fera le fade-out progressif
    end
end

-- ── Debug ────────────────────────────────────────────────────────────────────
function PKO:DebugPrint()
    local db = SP.db or {}
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cFF8B00FF[SP PackOrb]|r " ..
        "packMode=" .. tostring(SP._packMode) ..
        " plates=" .. tostring(SP._packPlateCount or 0) ..
        " active=" .. tostring(#PKO._active) ..
        " enabled=" .. tostring(db.pack_mode_enabled) ..
        " orbEnabled=" .. tostring(db.pack_orb_enabled))
    for i, f in ipairs(PKO._frames) do
        if f._clusterSize and f._clusterSize > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(
                "  Frame " .. i ..
                " size=" .. string.format("%.0f", f._size) ..
                " alpha=" .. string.format("%.2f", f._alpha) ..
                " members=" .. tostring(f._clusterSize))
        end
    end
end
