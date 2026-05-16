-------------------------------------------------------------------------------
--  SphereNameplates · InspectIlvl
--
--  Système d'inspection asynchrone pour récupérer l'iLvL des joueurs adverses
--  affichés en nameplate. Blizzard ne renseigne C_PaperDollInfo.GetInspectItemLevel
--  qu'après un cycle NotifyInspect → INSPECT_READY. Sans ce flow, l'API retourne 0.
--
--  Architecture :
--    SP.Inspect.cache[guid]   = { ilvl, t, name }      → cache par GUID, TTL long
--    SP.Inspect.queue         = liste FIFO de GUID     → en attente d'inspection
--    SP.Inspect.queueIndex    = { [guid] = unitToken } → dédup + lookup token
--    SP.Inspect.pending       = GUID en cours
--    SP.Inspect.pendingT      = timestamp NotifyInspect
--
--  Throttle :
--    REQUEST_COOLDOWN = 2.0 s entre deux NotifyInspect
--    PENDING_TIMEOUT  = 3.0 s avant d'abandonner la requête courante
--    CACHE_TTL        = 600 s (10 min)
--
--  Couleur ilvl : graduée selon le cap dynamique (SP.Inspect:GetIlvlCap()) qui
--  s'adapte automatiquement au max observé (joueur local + autres joueurs vus).
-------------------------------------------------------------------------------

local addonName, _ = ...
local SP = _G["SphereNameplates"]
if not SP then return end

SP.Inspect = SP.Inspect or {}
local Inspect = SP.Inspect

Inspect.cache         = Inspect.cache         or {}
Inspect.queue         = Inspect.queue         or {}
Inspect.queueIndex    = Inspect.queueIndex    or {}
Inspect.pending       = nil
Inspect.pendingUnit   = nil
Inspect.pendingT      = 0
Inspect.observedMaxIlvl = Inspect.observedMaxIlvl or 0

Inspect.REQUEST_COOLDOWN = 2.0
Inspect.PENDING_TIMEOUT  = 3.0
Inspect.CACHE_TTL        = 600

-- Cap initial = ilvl Mythique 6 (palier max actuel du jeu).
-- Référence utilisateur (Midnight 12.x) :
--   Aventurier 1-6 : 220-237
--   Vétéran    1-6 : 233-250  (chevauchement avec Aventurier)
--   Champion   1-6 : 246-263
--   Héro       1-6 : 259-276
--   Mythe      1-6 : 272-289   ← cap = Mythe 6 = 289
-- Le cap se relève automatiquement via observedMaxIlvl si on observe plus haut
-- (futures extensions). Bumper BASE_ILVL_CAP au changement d'extension reste
-- la solution la plus propre et instantanée.
Inspect.BASE_ILVL_CAP    = 289

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function safeGUID(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    if type(guid) ~= "string" then return nil end
    -- En WoW Midnight, UnitGUID peut retourner une "secret string value" taintée.
    -- type() fonctionne (C-builtin), mais guid ~= "" throw sur une secret string.
    -- On vérifie la non-vacuité via pcall défensif ; si tainté → nil (pas d'inspection).
    local okCmp, notEmpty = pcall(function() return guid ~= "" end)
    if not okCmp or not notEmpty then return nil end
    return guid
end

local function safeIsPlayer(unit)
    if not unit then return false end
    local ok, v = pcall(UnitIsPlayer, unit)
    return ok and v == true
end

local function safeUnitLevel(unit)
    if not unit then return 0 end
    local ok, v = pcall(UnitLevel, unit)
    if ok and type(v) == "number" then return v end
    return 0
end

local function safeMaxLevel()
    if GetMaxPlayerLevel then
        local ok, v = pcall(GetMaxPlayerLevel)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return 90
end

local function safeCanInspect(unit)
    if not unit then return false end
    local ok, v = pcall(CanInspect, unit, false)
    return ok and v == true
end

local function safeInspectIlvl(unit)
    if not unit then return nil end
    if not (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then return nil end
    local ok, v = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if ok and type(v) == "number" and v > 0 then
        return math.floor(v + 0.5)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Cap dynamique : retourne le cap ilvl courant pour la gradation couleur
--
--  Logique : on prend le max entre
--    (a) la base hardcodée (BASE_ILVL_CAP) — sécurité minimale
--    (b) l'ilvl du joueur local (souvent ≈ cap si le joueur joue le jeu actuel)
--    (c) le max observé sur les autres joueurs inspectés
--  Cela permet à l'addon de s'auto-calibrer sans connaître l'extension active.
-------------------------------------------------------------------------------
function Inspect:GetPlayerIlvl()
    -- GetAverageItemLevel retourne (overall, equipped, pvp) sur retail
    local ok, overall = pcall(function()
        if GetAverageItemLevel then return GetAverageItemLevel() end
        return nil
    end)
    if ok and type(overall) == "number" and overall > 0 then
        return math.floor(overall + 0.5)
    end
    return 0
end

function Inspect:GetIlvlCap()
    -- Cap = Mythe 6 du contenu courant.
    -- On NE prend PAS GetAverageItemLevel(player) car un joueur sous-équipé
    -- abaisserait artificiellement le cap. Seule la base + le max observé
    -- (potentiellement Mythique) entrent en jeu.
    local cap = self.BASE_ILVL_CAP
    if self.observedMaxIlvl > cap then cap = self.observedMaxIlvl end
    return cap
end

function Inspect:NoteObservedIlvl(ilvl)
    if type(ilvl) == "number" and ilvl > self.observedMaxIlvl then
        self.observedMaxIlvl = ilvl
    end
end

-------------------------------------------------------------------------------
--  Couleur graduée selon le palier d'équipement (Aventurier → Mythe)
--
--  Référentiel utilisateur (Midnight 12.x, cap Mythe 6 = 289) :
--    Aventurier  220-237   → doré    (E6CC80)
--    Vétéran     240-250   → vert    (1EFF00)
--    Champion    253-263   → bleu    (0070DD)
--    Héro        266-276   → violet  (A335EE)
--    Mythe       279-289   → orange  (FF8000)
--    < 220                 → blanc   (FFFFFF, sous-équipé)
--
--  Pour rester valide aux futures extensions, les seuils sont stockés en RATIO
--  par rapport au cap Mythe 6. Quand BASE_ILVL_CAP est bumpé (ou que
--  observedMaxIlvl monte), les bornes des paliers se recalculent automatiquement.
--
--    Mythe       ≥ 279/289 ≈ 0.9654
--    Héro        ≥ 266/289 ≈ 0.9204
--    Champion    ≥ 253/289 ≈ 0.8754
--    Vétéran     ≥ 240/289 ≈ 0.8304
--    Aventurier  ≥ 220/289 ≈ 0.7612
--
--  Note : les chevauchements (ex. ilvl 233 = Aventurier 5 / Vétéran 1) sont
--  résolus en faveur du palier "dominant" visible dans l'image utilisateur :
--  le palier dont la couleur est affichée prime. Comme la couleur de l'image
--  pour 233 est verte → reste Aventurier. Idem 246 = bleu = Vétéran.
-------------------------------------------------------------------------------
Inspect.TIER_RATIOS = {
    -- Ordre du plus haut au plus bas (parsing top-down)
    { name = "Mythe",      ratio = 279/289, color = "FF8000" },  -- orange
    { name = "Hero",       ratio = 266/289, color = "A335EE" },  -- violet
    { name = "Champion",   ratio = 253/289, color = "0070DD" },  -- bleu
    { name = "Veteran",    ratio = 240/289, color = "1EFF00" },  -- vert
    { name = "Aventurier", ratio = 220/289, color = "E6CC80" },  -- doré
}
Inspect.TIER_BELOW_COLOR = "FFFFFF"  -- sous-équipé : blanc

function Inspect:GetIlvlTier(ilvl)
    if type(ilvl) ~= "number" or ilvl <= 0 then return nil end
    local cap = self:GetIlvlCap()
    if cap <= 0 then return nil end
    local r = ilvl / cap
    for _, tier in ipairs(self.TIER_RATIOS) do
        if r >= tier.ratio then return tier end
    end
    return nil
end

function Inspect:GetIlvlColorHex(ilvl)
    local tier = self:GetIlvlTier(ilvl)
    if tier then return tier.color end
    return self.TIER_BELOW_COLOR
end

-------------------------------------------------------------------------------
--  Cache lookup / write
-------------------------------------------------------------------------------
function Inspect:GetCachedByGUID(guid)
    if not guid then return nil end
    local c = self.cache[guid]
    if not c then return nil end
    if (GetTime() - c.t) > self.CACHE_TTL then
        self.cache[guid] = nil
        return nil
    end
    return c.ilvl
end

function Inspect:GetCached(unit)
    local guid = safeGUID(unit)
    if not guid then return nil end
    return self:GetCachedByGUID(guid)
end

function Inspect:SetCached(guid, ilvl, name)
    if not guid or type(ilvl) ~= "number" or ilvl <= 0 then return end
    self.cache[guid] = { ilvl = ilvl, t = GetTime(), name = name }
    self:NoteObservedIlvl(ilvl)
end

-------------------------------------------------------------------------------
--  Queue management
-------------------------------------------------------------------------------
local function isWorthInspecting(unit)
    if not safeIsPlayer(unit) then return false end
    if safeUnitLevel(unit) < safeMaxLevel() then return false end
    if not safeCanInspect(unit) then return false end
    return true
end

function Inspect:Queue(unit)
    if not unit then return end
    local guid = safeGUID(unit)
    if not guid then return end
    if self:GetCachedByGUID(guid) then return end       -- déjà connu
    if self.pending == guid then return end             -- déjà en cours
    if self.queueIndex[guid] then                       -- déjà en file → mettre à jour token
        self.queueIndex[guid] = unit
        return
    end
    if not isWorthInspecting(unit) then return end
    table.insert(self.queue, guid)
    self.queueIndex[guid] = unit
end

function Inspect:Dequeue()
    while #self.queue > 0 do
        local guid = table.remove(self.queue, 1)
        local unit = self.queueIndex[guid]
        self.queueIndex[guid] = nil
        if unit and safeGUID(unit) == guid and isWorthInspecting(unit) then
            return guid, unit
        end
        -- sinon : token périmé / unité plus là → on saute
    end
    return nil, nil
end

-------------------------------------------------------------------------------
--  Tick : appelé ~5 Hz par Core.lua
-------------------------------------------------------------------------------
function Inspect:Tick(now)
    now = now or GetTime()

    -- Timeout de la requête en cours
    if self.pending and (now - self.pendingT) > self.PENDING_TIMEOUT then
        -- Tentative opportuniste avant d'abandonner :
        -- parfois GetInspectItemLevel a déjà la donnée même sans INSPECT_READY explicite.
        local u = self.pendingUnit
        if u and safeGUID(u) == self.pending then
            local ilvl = safeInspectIlvl(u)
            if ilvl and ilvl > 0 then
                self:SetCached(self.pending, ilvl)
            end
        end
        self.pending = nil
        self.pendingUnit = nil
        self.pendingT = 0
    end

    if self.pending then return end

    -- Cooldown global entre deux NotifyInspect (pendingT = timestamp du dernier)
    if self.pendingT > 0 and (now - self.pendingT) < self.REQUEST_COOLDOWN then
        return
    end

    local guid, unit = self:Dequeue()
    if not guid then return end

    -- Déclencher l'inspection
    local ok = pcall(NotifyInspect, unit)
    if not ok then return end

    self.pending = guid
    self.pendingUnit = unit
    self.pendingT = now
end

-------------------------------------------------------------------------------
--  INSPECT_READY handler
-------------------------------------------------------------------------------
function Inspect:OnInspectReady(guid)
    if not guid then return end

    -- Trouver une unité qui matche ce GUID parmi nameplates / target / mouseover / focus
    local unit = nil
    if SP.Plates then
        for u, _ in pairs(SP.Plates) do
            if safeGUID(u) == guid then unit = u; break end
        end
    end
    if not unit then
        for _, u in ipairs({ "target", "focus", "mouseover" }) do
            if safeGUID(u) == guid then unit = u; break end
        end
    end

    if unit then
        local ilvl = safeInspectIlvl(unit)
        if ilvl and ilvl > 0 then
            local name = (UnitName and UnitName(unit)) or nil
            self:SetCached(guid, ilvl, name)

            -- Refresh nameplate text immédiatement
            if SP.Plates and SP.Orb and SP.Orb.UpdateLevelText then
                for u, data in pairs(SP.Plates) do
                    if safeGUID(u) == guid and data then
                        pcall(SP.Orb.UpdateLevelText, SP.Orb, data, u)
                    end
                end
            end
        end
    end

    if self.pending == guid then
        self.pending = nil
        self.pendingUnit = nil
        -- pendingT reste pour servir de "last NotifyInspect" → cooldown
    end
end

-------------------------------------------------------------------------------
--  Event frame dédié
-------------------------------------------------------------------------------
local f = CreateFrame("Frame", "SphereInspectFrame")
f:RegisterEvent("INSPECT_READY")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_FOCUS_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        Inspect:OnInspectReady(arg1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Inspect:Queue("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Inspect:Queue("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Inspect:Queue("mouseover")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Ré-évaluer notre propre cap quand on s'équipe
        Inspect.observedMaxIlvl = math.max(Inspect.observedMaxIlvl, Inspect:GetPlayerIlvl())
    end
end)

-- Tick dispatcher (Core.lua appellera Inspect:Tick si présent ; on ajoute aussi un
-- OnUpdate de secours léger ici au cas où Core.lua ne câble pas le tick).
local _acc = 0
f:SetScript("OnUpdate", function(_, elapsed)
    _acc = _acc + (elapsed or 0)
    if _acc < 0.2 then return end
    _acc = 0
    Inspect:Tick(GetTime())
end)
