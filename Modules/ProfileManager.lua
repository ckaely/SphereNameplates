-------------------------------------------------------------------------------
-- SphereNameplates — Modules/ProfileManager.lua
-- SP.Profiles — Gestionnaire de profils (façade AceDB + export/import)
--
-- API publique :
--   SP.Profiles:GetList()                        → {name, ...} ordonné
--   SP.Profiles:GetCurrentName()                 → string
--   SP.Profiles:Create(name)                     → ok, nameOrErr
--   SP.Profiles:Delete(name)                     → ok, nameOrErr
--   SP.Profiles:Rename(oldName, newName)          → ok, nameOrErr
--   SP.Profiles:Duplicate(name[, newName])       → ok, nameOrErr
--   SP.Profiles:Load(name)                       → ok, nameOrErr
--   SP.Profiles:SaveCurrent()                    → ok
--   SP.Profiles:Reset([name])                    → ok, err
--   SP.Profiles:Export([name])                   → string|nil, err
--   SP.Profiles:ImportString(str)                → ok, summary, envelope
--   SP.Profiles:ApplyImport(envelope, target, overwrite) → ok, nameOrErr
--   SP.Profiles:Validate(envelope)               → ok, summary
--   SP.Profiles:Sanitize(data)                   → cleanData
--   SP.Profiles:MigrateIfNeeded()
--   SP.Profiles:Init()
--   SP.Profiles:RegisterCallback(fn)
--
-- Sécurité : aucun loadstring / load / dofile — désérialisation par parseur
-- custom. Whitelist stricte des clés exportées.
--
-- Format export : préfixe "SP1!" + Base64(JSON-like)
-- JSON géré : objects, arrays, strings, numbers, booleans, null.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.Profiles = {}
local P = SP.Profiles

-------------------------------------------------------------------------------
--  CONSTANTES
-------------------------------------------------------------------------------
local SCHEMA_VERSION  = 1
local EXPORT_PREFIX   = "SP1!"
local DEFAULT_PROFILE = "Default"
local MAX_NAME_LEN    = 40

-- Clés globales exportées (hors logs_*, perf_*, debugMode, runtime)
local GLOBAL_EXPORT_KEYS = {
    "addonEnabled",
    "minimap_angle",
    "behavior_force_friendly_players_instance",
    "modules_orbanim_enabled",
    "modules_castbar_enabled",
    "modules_auras_enabled",
    "modules_hplerp_enabled",
    "modules_fade_enabled",
    "modules_inspectilvl_enabled",
    "modules_quest_enabled",
}
local GLOBAL_EXPORT_SET = {}
for _, k in ipairs(GLOBAL_EXPORT_KEYS) do GLOBAL_EXPORT_SET[k] = true end

-- Types d'unités (construits dynamiquement depuis DEFAULTS à l'Init)
local UNIT_TYPES     = {}   -- array: {"ENEMY","FRIENDLY",...}
local UNIT_TYPE_SET  = {}   -- hash : {ENEMY=true,...}

-------------------------------------------------------------------------------
--  ACCÈS DB
-------------------------------------------------------------------------------
local function _db()
    return SP.dbObj
end
local function _gbl()
    if not (SP.dbObj and SP.dbObj.global) then return nil end
    return SP.dbObj.global
end

-------------------------------------------------------------------------------
--  VALIDATION DU NOM
-------------------------------------------------------------------------------
local function _validateName(name)
    if type(name) ~= "string" then
        return false, "Le nom doit être une chaîne"
    end
    name = name:match("^%s*(.-)%s*$")   -- trim
    if #name == 0 then
        return false, "Le nom ne peut pas être vide"
    end
    if #name > MAX_NAME_LEN then
        return false, "Nom trop long (max " .. MAX_NAME_LEN .. " caractères)"
    end
    if not name:match("^[%w%s%-%_%(%)%.]+$") then
        return false, "Caractères non autorisés (alphanum, espaces, - _ ( ) . uniquement)"
    end
    return true, name
end

-------------------------------------------------------------------------------
--  API — LECTURE
-------------------------------------------------------------------------------

function P:GetCurrentName()
    if not _db() then return DEFAULT_PROFILE end
    return _db():GetCurrentProfile()
end

--- Retourne la liste ordonnée des profils. "Default" en premier.
function P:GetList()
    if not _db() then return { DEFAULT_PROFILE } end
    local g = _gbl()
    local rawList = _db():GetProfiles()
    -- Indexer les profils AceDB réels
    local inAce = {}
    for _, n in ipairs(rawList) do inAce[n] = true end
    -- S'assurer que le profil actif est dans la liste
    inAce[self:GetCurrentName()] = true

    if g and g.profile_order and #g.profile_order > 0 then
        -- Construire à partir de l'ordre mémorisé + orphelins
        local result, inOrder = {}, {}
        for _, n in ipairs(g.profile_order) do
            if inAce[n] then
                result[#result+1] = n
                inOrder[n] = true
            end
        end
        -- Ajouter les profils AceDB absents de l'ordre (orphelins)
        for _, n in ipairs(rawList) do
            if not inOrder[n] then
                result[#result+1] = n
            end
        end
        return result
    end

    -- Fallback : tri alphabétique avec Default en tête
    table.sort(rawList, function(a, b)
        if a == DEFAULT_PROFILE then return true end
        if b == DEFAULT_PROFILE then return false end
        return a < b
    end)
    return rawList
end

--- Retourne les métadonnées d'un profil (createdAt, copiedFrom...)
function P:GetMeta(name)
    local g = _gbl()
    if g and g.profile_meta then
        return g.profile_meta[name] or {}
    end
    return {}
end

-------------------------------------------------------------------------------
--  API — CRÉATION / SUPPRESSION / RENOMMAGE / DUPLICATION
-------------------------------------------------------------------------------

function P:Create(name)
    if not _db() then return false, "AceDB non initialisé" end
    local ok, cleanName = _validateName(name)
    if not ok then return false, cleanName end
    name = cleanName
    -- Vérifier unicité
    for _, n in ipairs(self:GetList()) do
        if n == name then return false, "Le profil '" .. name .. "' existe déjà" end
    end

    local prevName = self:GetCurrentName()
    SP._profileBulkOp = true

    -- SetProfile crée le profil si inexistant et y switche
    local ok1, e1 = pcall(_db().SetProfile, _db(), name)
    if not ok1 then
        SP._profileBulkOp = false
        return false, "AceDB SetProfile : " .. tostring(e1)
    end
    SP:EnsureProfileDefaults()

    -- Méta + ordre
    local g = _gbl()
    if g then
        g.profile_meta  = g.profile_meta  or {}
        g.profile_order = g.profile_order or {}
        g.profile_meta[name] = { createdAt = date("%Y-%m-%d") }
        -- Insérer après le profil précédent
        local inserted = false
        for i, n in ipairs(g.profile_order) do
            if n == prevName then
                table.insert(g.profile_order, i + 1, name)
                inserted = true; break
            end
        end
        if not inserted then table.insert(g.profile_order, name) end
    end

    SP._profileBulkOp = false
    SP.db = _db().profile
    SP:RefreshAll()
    if SP.Log then SP.Log:Info("Profiles", "Créé : " .. name) end
    P:_Notify("created", name)
    return true, name
end

function P:Delete(name)
    if not _db() then return false, "AceDB non initialisé" end
    local list = self:GetList()
    if #list <= 1 then
        return false, "Impossible de supprimer le dernier profil"
    end
    -- Vérifier existence
    local exists = false
    for _, n in ipairs(list) do if n == name then exists = true; break end end
    if not exists then return false, "Profil introuvable : " .. tostring(name) end

    -- Si profil actif → switcher d'abord
    if self:GetCurrentName() == name then
        local fallback = DEFAULT_PROFILE
        if fallback == name then
            for _, n in ipairs(list) do
                if n ~= name then fallback = n; break end
            end
        end
        SP._profileBulkOp = true
        pcall(_db().SetProfile, _db(), fallback)
        SP:EnsureProfileDefaults()
        SP._profileBulkOp = false
    end

    -- Supprimer (ne peut PAS être le profil actif à ce stade)
    local delOk, delErr = pcall(_db().DeleteProfile, _db(), name)
    if not delOk then
        SP.db = _db().profile
        SP:RefreshAll()
        return false, "AceDB DeleteProfile : " .. tostring(delErr)
    end

    -- Méta + ordre
    local g = _gbl()
    if g then
        if g.profile_meta  then g.profile_meta[name] = nil end
        if g.profile_order then
            for i, n in ipairs(g.profile_order) do
                if n == name then table.remove(g.profile_order, i); break end
            end
        end
    end

    SP.db = _db().profile
    SP:RefreshAll()
    if SP.Log then SP.Log:Info("Profiles", "Supprimé : " .. name) end
    P:_Notify("deleted", name)
    return true, name
end

function P:Rename(oldName, newName)
    if not _db() then return false, "AceDB non initialisé" end
    local ok, cleanNew = _validateName(newName)
    if not ok then return false, cleanNew end
    newName = cleanNew
    if oldName == newName then return true, newName end
    -- Vérifier que newName n'existe pas
    for _, n in ipairs(self:GetList()) do
        if n == newName then return false, "Le profil '" .. newName .. "' existe déjà" end
    end

    local wasCurrent = (self:GetCurrentName() == oldName)
    local prevCurrent = self:GetCurrentName()
    SP._profileBulkOp = true

    -- Créer newName = switch + copy depuis oldName
    local ok1, e1 = pcall(_db().SetProfile, _db(), newName)
    if not ok1 then
        SP._profileBulkOp = false
        return false, "AceDB SetProfile : " .. tostring(e1)
    end
    -- CopyProfile copie oldName dans le profil actif (newName)
    -- silent=true car oldName peut être vide (profil jamais modifié)
    local ok2, e2 = pcall(_db().CopyProfile, _db(), oldName, true)
    if not ok2 then
        pcall(_db().SetProfile, _db(), prevCurrent)
        SP._profileBulkOp = false
        SP.db = _db().profile; SP:RefreshAll()
        return false, "AceDB CopyProfile : " .. tostring(e2)
    end
    -- Supprimer oldName (n'est plus le profil actif)
    local ok3, e3 = pcall(_db().DeleteProfile, _db(), oldName)
    if not ok3 then
        SP._profileBulkOp = false
        SP.db = _db().profile; SP:RefreshAll()
        return false, "AceDB DeleteProfile : " .. tostring(e3)
    end
    -- Si oldName n'était pas le profil actif, retourner au profil original
    if not wasCurrent then
        pcall(_db().SetProfile, _db(), prevCurrent)
    end

    -- Méta + ordre
    local g = _gbl()
    if g then
        if g.profile_meta then
            g.profile_meta[newName] = g.profile_meta[oldName] or { createdAt = date("%Y-%m-%d") }
            g.profile_meta[oldName] = nil
        end
        if g.profile_order then
            for i, n in ipairs(g.profile_order) do
                if n == oldName then g.profile_order[i] = newName; break end
            end
        end
    end

    SP._profileBulkOp = false
    SP.db = _db().profile
    SP:EnsureProfileDefaults()
    SP:RefreshAll()
    if SP.Log then SP.Log:Info("Profiles", "Renommé : " .. oldName .. " → " .. newName) end
    P:_Notify("renamed", newName)
    return true, newName
end

function P:Duplicate(sourceName, newName)
    if not _db() then return false, "AceDB non initialisé" end
    -- Générer un nom unique si non fourni ou déjà pris
    newName = newName or ("Copie de " .. sourceName)
    local nameSet = {}
    for _, n in ipairs(self:GetList()) do nameSet[n] = true end
    if nameSet[newName] then
        local base, suffix = newName, 2
        repeat
            newName = base .. " (" .. suffix .. ")"
            suffix  = suffix + 1
        until not nameSet[newName]
    end
    local ok, cleanNew = _validateName(newName)
    if not ok then return false, cleanNew end
    newName = cleanNew

    local prevCurrent = self:GetCurrentName()
    SP._profileBulkOp = true

    -- Switch vers le nouveau profil (vide)
    local ok1, e1 = pcall(_db().SetProfile, _db(), newName)
    if not ok1 then
        SP._profileBulkOp = false
        return false, "AceDB SetProfile : " .. tostring(e1)
    end
    -- Copier sourceName dans le nouveau (actif)
    local ok2, e2 = pcall(_db().CopyProfile, _db(), sourceName, true)
    if not ok2 then
        pcall(_db().SetProfile, _db(), prevCurrent)
        SP._profileBulkOp = false
        SP.db = _db().profile; SP:RefreshAll()
        return false, "AceDB CopyProfile : " .. tostring(e2)
    end
    -- Retour au profil original
    pcall(_db().SetProfile, _db(), prevCurrent)

    -- Méta + ordre
    local g = _gbl()
    if g then
        g.profile_meta  = g.profile_meta  or {}
        g.profile_order = g.profile_order or {}
        g.profile_meta[newName] = { createdAt = date("%Y-%m-%d"), copiedFrom = sourceName }
        -- Insérer après la source dans l'ordre
        local inserted = false
        for i, n in ipairs(g.profile_order) do
            if n == sourceName then
                table.insert(g.profile_order, i + 1, newName)
                inserted = true; break
            end
        end
        if not inserted then table.insert(g.profile_order, newName) end
    end

    SP._profileBulkOp = false
    SP.db = _db().profile
    SP:EnsureProfileDefaults()
    SP:RefreshAll()
    if SP.Log then SP.Log:Info("Profiles", "Dupliqué : " .. sourceName .. " → " .. newName) end
    P:_Notify("duplicated", newName)
    return true, newName
end

-------------------------------------------------------------------------------
--  API — CHARGEMENT / SAUVEGARDE / RÉINITIALISATION
-------------------------------------------------------------------------------

function P:Load(name)
    if not _db() then return false, "AceDB non initialisé" end
    if self:GetCurrentName() == name then return true, name end
    local ok, err = pcall(_db().SetProfile, _db(), name)
    if not ok then return false, "AceDB SetProfile : " .. tostring(err) end
    -- SP.db + RefreshAll gérés par le callback OnProfileChanged de Core.lua
    if SP.Log then SP.Log:Info("Profiles", "Chargé : " .. name) end
    P:_Notify("loaded", name)
    return true, name
end

function P:SaveCurrent()
    SP:EnsureProfileDefaults()
    local name = self:GetCurrentName()
    if SP.Log then SP.Log:Info("Profiles", "Sauvegardé : " .. name) end
    P:_Notify("saved", name)
    return true
end

function P:Reset(name)
    if not _db() then return false, "AceDB non initialisé" end
    if name and name ~= self:GetCurrentName() then
        -- Réinitialiser un profil inactif : switch → reset → retour
        local prev = self:GetCurrentName()
        SP._profileBulkOp = true
        pcall(_db().SetProfile,   _db(), name)
        pcall(_db().ResetProfile, _db())
        pcall(_db().SetProfile,   _db(), prev)
        SP._profileBulkOp = false
        SP.db = _db().profile
        SP:EnsureProfileDefaults()
        SP:RefreshAll()
    else
        -- Réinitialiser le profil actif (callback OnProfileReset gère le reste)
        local ok, err = pcall(_db().ResetProfile, _db())
        if not ok then return false, "AceDB ResetProfile : " .. tostring(err) end
    end
    local target = name or self:GetCurrentName()
    if SP.Log then SP.Log:Info("Profiles", "Réinitialisé : " .. target) end
    P:_Notify("reset", target)
    return true
end

-------------------------------------------------------------------------------
--  API — EXPORT / IMPORT
-------------------------------------------------------------------------------

function P:Export(name)
    if not _db() then return nil, "AceDB non initialisé" end
    name = name or self:GetCurrentName()

    -- Données brutes du profil
    local raw
    if name == self:GetCurrentName() then
        raw = SP.db
    else
        raw = _db().profiles and _db().profiles[name] or {}
    end

    local envelope = {
        addon         = "SphereNameplates",
        schemaVersion = SCHEMA_VERSION,
        addonVersion  = SP.Version or "?",
        profileName   = name,
        createdAt     = date("%Y-%m-%d"),
        data          = P:_BuildExportData(raw),
    }

    local jsonStr = P:_Serialize(envelope)
    if not jsonStr then return nil, "Erreur de sérialisation" end

    local encoded = EXPORT_PREFIX .. P:_B64Encode(jsonStr)
    if SP.Log then
        SP.Log:Info("Profiles", string.format("Export '%s' : %d chars", name, #encoded))
    end
    return encoded
end

function P:ImportString(str)
    if type(str) ~= "string" then return false, "Chaîne attendue", nil end
    str = str:match("^%s*(.-)%s*$")  -- trim

    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Format non reconnu (préfixe attendu : " .. EXPORT_PREFIX .. ")", nil
    end

    local jsonStr, decErr = P:_B64Decode(str:sub(#EXPORT_PREFIX + 1))
    if not jsonStr then
        return false, "Décodage Base64 échoué : " .. tostring(decErr), nil
    end

    local ok, envelope = P:_Deserialize(jsonStr)
    if not ok then
        return false, "Désérialisation échouée : " .. tostring(envelope), nil
    end

    local validOk, summary = P:Validate(envelope)
    if not validOk then
        return false, "Validation échouée : " .. (summary.error or "?"), nil
    end

    return true, summary, envelope
end

function P:ApplyImport(envelope, targetName, overwrite)
    if not _db() then return false, "AceDB non initialisé" end
    local ok, cleanName = _validateName(targetName)
    if not ok then return false, cleanName end
    targetName = cleanName

    local cleanData = P:Sanitize(envelope.data)

    if overwrite then
        -- Écraser : switcher sur le profil cible, vider, remplir
        local prev = self:GetCurrentName()
        SP._profileBulkOp = true
        pcall(_db().SetProfile,   _db(), targetName)
        pcall(_db().ResetProfile, _db(), nil, true)  -- noCallbacks=true
        SP._profileBulkOp = false
    else
        -- Nouveau profil
        local createOk, createErr = self:Create(targetName)
        if not createOk then return false, createErr end
        -- Create() a déjà switché sur targetName
    end

    -- S'assurer qu'on est sur le profil cible
    if self:GetCurrentName() ~= targetName then
        SP._profileBulkOp = true
        pcall(_db().SetProfile, _db(), targetName)
        SP._profileBulkOp = false
    end

    -- Mettre à jour SP.db AVANT d'écrire : après ResetProfile, AceDB peut avoir
    -- remplacé la table interne ; relier le pointeur d'abord évite d'écrire
    -- dans un objet périmé.
    SP.db = _db().profile
    P:_ApplyDataToCurrentProfile(cleanData)
    SP:EnsureProfileDefaults()
    SP:RefreshAll()

    if SP.Log then
        SP.Log:Info("Profiles", "Import appliqué → '" .. targetName .. "'")
    end
    P:_Notify("imported", targetName)
    return true, targetName
end

-------------------------------------------------------------------------------
--  API — VALIDATION / SANITISATION
-------------------------------------------------------------------------------

function P:Validate(envelope)
    local summary = {
        warnings = 0, unknownKeys = 0, clamped = 0, error = nil,
        profileName = "Import", addonVersion = "?", createdAt = "?",
    }
    if type(envelope) ~= "table" then
        summary.error = "L'enveloppe n'est pas une table"
        return false, summary
    end
    if envelope.addon ~= "SphereNameplates" then
        summary.error = "addon incompatible : " .. tostring(envelope.addon)
        return false, summary
    end
    if type(envelope.schemaVersion) ~= "number" or envelope.schemaVersion < 1 then
        summary.error = "schemaVersion invalide"
        return false, summary
    end
    if envelope.schemaVersion > SCHEMA_VERSION then
        summary.error = string.format(
            "Version de schéma trop récente (%d > %d) — mettez à jour l'addon",
            envelope.schemaVersion, SCHEMA_VERSION)
        return false, summary
    end
    if type(envelope.data) ~= "table" then
        summary.error = "data manquant ou invalide"
        return false, summary
    end

    local defProfile = SP.DEFAULTS and SP.DEFAULTS.profile or {}

    for k, v in pairs(envelope.data) do
        if UNIT_TYPE_SET[k] then
            -- Vérifier les clés de la sous-table unitType
            if type(v) == "table" then
                local defUnit = defProfile[k] or {}
                for k2 in pairs(v) do
                    if defUnit[k2] == nil then
                        summary.unknownKeys = summary.unknownKeys + 1
                        summary.warnings    = summary.warnings    + 1
                    end
                end
            end
        elseif not GLOBAL_EXPORT_SET[k] then
            summary.unknownKeys = summary.unknownKeys + 1
            summary.warnings    = summary.warnings    + 1
        end
    end

    summary.profileName  = type(envelope.profileName)  == "string" and envelope.profileName  or "Import"
    summary.addonVersion = type(envelope.addonVersion)  == "string" and envelope.addonVersion  or "?"
    summary.createdAt    = type(envelope.createdAt)     == "string" and envelope.createdAt     or "?"
    return true, summary
end

function P:Sanitize(data)
    if type(data) ~= "table" then return {} end
    local clean      = {}
    local defProfile = SP.DEFAULTS and SP.DEFAULTS.profile or {}

    -- Clés globales exportables
    for _, k in ipairs(GLOBAL_EXPORT_KEYS) do
        local v = data[k]
        if v ~= nil then
            local def = defProfile[k]
            if def ~= nil and type(v) == type(def) then
                clean[k] = (type(v) == "number") and P:_ClampValue(k, v) or v
            end
        end
    end

    -- Sous-tables unitType
    for _, ut in ipairs(UNIT_TYPES) do
        local src = data[ut]
        if type(src) == "table" then
            clean[ut] = {}
            local defUnit = defProfile[ut] or {}
            for k2, v2 in pairs(src) do
                local def2 = defUnit[k2]
                -- Cas 1 : clé connue (défaut non-nil) — vérifier compatibilité de type
                if def2 ~= nil and type(v2) == type(def2) then
                    if type(v2) == "number" then
                        clean[ut][k2] = P:_ClampValue(k2, v2)
                    elseif type(v2) == "table" then
                        -- Tableaux de couleurs {r,g,b} ou {r,g,b,a}
                        clean[ut][k2] = {}
                        for i = 1, #v2 do
                            local c = v2[i]
                            clean[ut][k2][i] = (type(c) == "number")
                                and math.max(0.0, math.min(1.0, c))
                                or  (type(def2[i]) == "number" and def2[i] or 0)
                        end
                    else
                        clean[ut][k2] = v2
                    end
                -- Cas 2 : clé couleur optionnelle dont le défaut est nil
                -- (nameR/G/B, hpTextR/G/B, hpPercentTextR/G/B, hpAbsoluteTextR/G/B, etc.)
                elseif def2 == nil and type(v2) == "number"
                    and k2:match("[RGBrgb]$") then
                    clean[ut][k2] = math.max(0.0, math.min(1.0, v2))
                end
            end
        end
    end

    return clean
end

-------------------------------------------------------------------------------
--  API — MIGRATION
-------------------------------------------------------------------------------

function P:MigrateIfNeeded()
    if not _db() then return end
    local g = _gbl()
    if not g then return end

    g.profile_meta  = g.profile_meta  or {}
    g.profile_order = g.profile_order or {}

    local rawList = _db():GetProfiles()
    -- S'assurer que le profil actif est inclus
    local curName = self:GetCurrentName()
    local inRaw = {}
    for _, n in ipairs(rawList) do inRaw[n] = true end
    if not inRaw[curName] then
        rawList[#rawList+1] = curName
        inRaw[curName] = true
    end

    if #g.profile_order > 0 then
        -- Déjà migré : vérifier la cohérence (ajouter les orphelins)
        local inOrder = {}
        for _, n in ipairs(g.profile_order) do inOrder[n] = true end
        for _, n in ipairs(rawList) do
            if not inOrder[n] then
                g.profile_order[#g.profile_order+1] = n
                g.profile_meta[n] = g.profile_meta[n] or { createdAt = date("%Y-%m-%d") }
            end
        end
        return
    end

    -- Première fois : construire l'ordre depuis AceDB
    table.sort(rawList, function(a, b)
        if a == DEFAULT_PROFILE then return true end
        if b == DEFAULT_PROFILE then return false end
        return a < b
    end)
    g.profile_order = rawList
    for _, n in ipairs(rawList) do
        g.profile_meta[n] = g.profile_meta[n] or { createdAt = date("%Y-%m-%d") }
    end

    if SP.Log then
        SP.Log:Info("Profiles", "Migration OK — " .. #rawList .. " profil(s) détecté(s)")
    end
end

-------------------------------------------------------------------------------
--  API — INITIALISATION
-------------------------------------------------------------------------------

function P:Init()
    if not _db() then
        if SP.Log then SP.Log:Warn("Profiles", "AceDB indisponible à Init()") end
        return
    end

    -- Construire UNIT_TYPES depuis DEFAULTS (toutes les clés table)
    UNIT_TYPES    = {}
    UNIT_TYPE_SET = {}
    if SP.DEFAULTS and SP.DEFAULTS.profile then
        for k, v in pairs(SP.DEFAULTS.profile) do
            if type(v) == "table" then
                UNIT_TYPES[#UNIT_TYPES+1] = k
                UNIT_TYPE_SET[k] = true
            end
        end
    end

    self:MigrateIfNeeded()

    if SP.Log then
        SP.Log:Info("Profiles",
            string.format("Init OK — actif: '%s', %d profil(s)",
                self:GetCurrentName(), #self:GetList()))
    end
end

-------------------------------------------------------------------------------
--  CALLBACKS
-------------------------------------------------------------------------------

local _callbacks = {}

function P:RegisterCallback(fn)
    if type(fn) == "function" then
        _callbacks[#_callbacks+1] = fn
    end
end

function P:_Notify(event, name)
    for _, fn in ipairs(_callbacks) do
        pcall(fn, event, name)
    end
    if SP.UI and type(SP.UI.OnProfileEvent) == "function" then
        pcall(SP.UI.OnProfileEvent, SP.UI, event, name)
    end
end

-------------------------------------------------------------------------------
--  HELPERS INTERNES — DONNÉES
-------------------------------------------------------------------------------

--- Construit la table d'export depuis les données brutes du profil.
--- Remplit les clés manquantes depuis DEFAULTS.
function P:_BuildExportData(profileData)
    local data       = {}
    local defProfile = SP.DEFAULTS and SP.DEFAULTS.profile or {}

    -- Clés globales
    for _, k in ipairs(GLOBAL_EXPORT_KEYS) do
        local v = (profileData and profileData[k] ~= nil)
            and profileData[k]
            or defProfile[k]
        if v ~= nil then data[k] = v end
    end

    -- Sous-tables unitType : fusionner profil + defaults
    for _, ut in ipairs(UNIT_TYPES) do
        data[ut] = {}
        local defUnit = defProfile[ut] or {}
        -- Defaults en premier
        for k2, v2 in pairs(defUnit) do data[ut][k2] = v2 end
        -- Surcharges du profil
        if profileData and type(profileData[ut]) == "table" then
            for k2, v2 in pairs(profileData[ut]) do
                data[ut][k2] = v2
            end
        end
    end

    return data
end

--- Applique cleanData au profil actif (SP.db).
function P:_ApplyDataToCurrentProfile(cleanData)
    if not SP.db then return end

    for _, k in ipairs(GLOBAL_EXPORT_KEYS) do
        if cleanData[k] ~= nil then SP.db[k] = cleanData[k] end
    end

    for _, ut in ipairs(UNIT_TYPES) do
        if type(cleanData[ut]) == "table" then
            -- Ne jamais réutiliser SP.db[ut] obtenu via __index (ce serait la table
            -- de defaults partagée). Toujours forcer une nouvelle table dans le profil.
            if type(rawget(SP.db, ut)) ~= "table" then
                rawset(SP.db, ut, {})
            end
            for k2, v2 in pairs(cleanData[ut]) do
                SP.db[ut][k2] = v2
            end
        end
    end
end

--- Clamp d'une valeur numérique selon le type de clé.
function P:_ClampValue(key, value)
    if type(value) ~= "number" then return value end
    -- Tailles d'éléments
    if key == "size" then return math.max(8, math.min(256, value)) end
    if key:find("_size") or key:find("FontSize") then
        return math.max(4, math.min(128, value))
    end
    -- Largeurs / épaisseurs
    if key:find("[Ww]idth") or key:find("[Tt]hickness") then
        return math.max(0, math.min(128, value))
    end
    -- Composantes couleur et alphas (clé se terminant en R/G/B/A ou contenant alpha/Alpha)
    if key:match("[RGBArgba]$") or key:find("alpha") or key:find("Alpha") then
        return math.max(0.0, math.min(1.0, value))
    end
    -- Offsets en pixels (bornes larges)
    if key:find("[Oo]ffset") then
        return math.max(-512, math.min(512, value))
    end
    -- Seuils HP (0–100)
    if key:find("threshold") then
        return math.max(0, math.min(100, value))
    end
    -- Vitesses / facteurs d'échelle
    if key:find("[Ss]peed") or key:find("[Ss]cale") then
        return math.max(0.0, math.min(10.0, value))
    end
    return value  -- pas de clamp par défaut
end

-------------------------------------------------------------------------------
--  HELPERS INTERNES — SÉRIALISATION JSON-LIKE
--
--  Sous-ensemble JSON : objects, arrays, strings, numbers, booleans, null.
--  Aucun loadstring — désérialisation par parseur récursif-descendant.
-------------------------------------------------------------------------------

local function _encStr(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"',  '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    return '"' .. s .. '"'
end

local function _serVal(v, depth)
    depth = depth or 0
    local t = type(v)
    if v == nil  then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v then return "0" end  -- NaN guard
        if v == math.floor(v) and math.abs(v) < 1e12 then
            return string.format("%d", v)
        end
        return string.format("%.7g", v)
    end
    if t == "string" then return _encStr(v) end
    if t == "table" then
        if depth >= 5 then return "null" end  -- profondeur max : envelope→data→unitType→colorArray→valeur
        -- Détection array (indices consécutifs depuis 1, aucune clé string)
        local n = #v
        local isArray = (n > 0)
        if isArray then
            for i = 1, n do
                if v[i] == nil then isArray = false; break end
            end
        end
        if isArray then
            local parts = {}
            for i = 1, n do parts[i] = _serVal(v[i], depth + 1) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        -- Object : clés triées pour sortie déterministe
        local keys = {}
        for k in pairs(v) do keys[#keys+1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            local val = v[k]
            if val ~= nil then
                parts[#parts+1] = _encStr(tostring(k)) .. ":" .. _serVal(val, depth + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

function P:_Serialize(t)
    local ok, result = pcall(_serVal, t, 0)
    return ok and result or nil
end

-- Sentinel JSON null (distinct de nil Lua)
local _NULL = {}

function P:_Deserialize(str)
    local pos = 1
    local len = #str

    local function skipWS()
        while pos <= len do
            local b = str:byte(pos)
            if b==32 or b==9 or b==10 or b==13 then pos=pos+1 else break end
        end
    end

    local parseVal  -- forward-declaration (nécessaire pour récursion mutuelle)

    local function parseStr()
        pos = pos + 1   -- saute le "
        local buf = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(buf)
            elseif c == '\\' then
                pos = pos + 1
                local e = str:sub(pos, pos)
                if     e == '"'  then buf[#buf+1] = '"'
                elseif e == '\\' then buf[#buf+1] = '\\'
                elseif e == 'n'  then buf[#buf+1] = '\n'
                elseif e == 'r'  then buf[#buf+1] = '\r'
                elseif e == 't'  then buf[#buf+1] = '\t'
                elseif e == '/'  then buf[#buf+1] = '/'
                else                  buf[#buf+1] = '\\'; buf[#buf+1] = e
                end
            else
                buf[#buf+1] = c
            end
            pos = pos + 1
        end
        error("Chaîne JSON non terminée")
    end

    local function parseObj()
        pos = pos + 1   -- saute {
        local result = {}
        skipWS()
        if str:sub(pos,pos) == '}' then pos=pos+1; return result end
        while pos <= len do
            skipWS()
            if str:sub(pos,pos) ~= '"' then
                error("Clé de chaîne attendue à pos " .. pos)
            end
            local key = parseStr()
            skipWS()
            if str:sub(pos,pos) ~= ':' then
                error("':' attendu à pos " .. pos)
            end
            pos = pos + 1
            local val = parseVal()
            if val ~= _NULL then result[key] = val end
            skipWS()
            local sep = str:sub(pos,pos)
            if     sep == ',' then pos = pos + 1
            elseif sep == '}' then pos = pos + 1; break
            else error("',' ou '}' attendu à pos " .. pos)
            end
        end
        return result
    end

    local function parseArr()
        pos = pos + 1   -- saute [
        local result = {}
        skipWS()
        if str:sub(pos,pos) == ']' then pos=pos+1; return result end
        while pos <= len do
            local val = parseVal()
            result[#result+1] = (val ~= _NULL) and val or false
            skipWS()
            local sep = str:sub(pos,pos)
            if     sep == ',' then pos = pos + 1
            elseif sep == ']' then pos = pos + 1; break
            else error("',' ou ']' attendu à pos " .. pos)
            end
        end
        return result
    end

    parseVal = function()
        skipWS()
        if pos > len then error("Fin de chaîne inattendue") end
        local c = str:sub(pos, pos)
        if c == '"' then
            return parseStr()
        elseif c == '{' then
            return parseObj()
        elseif c == '[' then
            return parseArr()
        elseif str:sub(pos, pos+3) == "true" then
            pos = pos + 4; return true
        elseif str:sub(pos, pos+4) == "false" then
            pos = pos + 5; return false
        elseif str:sub(pos, pos+3) == "null" then
            pos = pos + 4; return _NULL
        else
            -- Nombre (entier ou flottant, optionnellement signé)
            local numStr, npos = str:match("^(-?%d+%.?%d*[eE]?[+%-]?%d*)()", pos)
            if numStr then
                pos = npos
                return tonumber(numStr)
            end
            error("Token JSON invalide '" .. c .. "' à pos " .. pos)
        end
    end

    local ok, result = pcall(parseVal)
    if ok and result == _NULL then result = nil end
    return ok, result
end

-------------------------------------------------------------------------------
--  HELPERS INTERNES — BASE64
--
--  Alphabet standard RFC 4648. Encodage/décodage purs Lua, sans dépendance.
-------------------------------------------------------------------------------

local _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local _B64D = {}
for i = 1, #_B64 do _B64D[_B64:sub(i,i)] = i - 1 end

function P:_B64Encode(str)
    local out = {}
    for i = 1, #str, 3 do
        local b1, b2, b3 = str:byte(i, i+2)
        b2 = b2 or 0
        b3 = b3 or 0
        local v = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v /   4096) % 64
        local c3 = math.floor(v /     64) % 64
        local c4 =             v          % 64
        out[#out+1] = _B64:sub(c1+1, c1+1)
        out[#out+1] = _B64:sub(c2+1, c2+1)
        out[#out+1] = str:byte(i+1) and _B64:sub(c3+1, c3+1) or "="
        out[#out+1] = str:byte(i+2) and _B64:sub(c4+1, c4+1) or "="
    end
    return table.concat(out)
end

function P:_B64Decode(str)
    str = str:gsub("[^%w%+%/%=]", "")  -- strip tout sauf l'alphabet + padding
    if #str % 4 ~= 0 then
        return nil, "Longueur Base64 invalide (" .. #str .. " chars)"
    end
    local out = {}
    for i = 1, #str, 4 do
        local c1 = _B64D[str:sub(i,   i  )]
        local c2 = _B64D[str:sub(i+1, i+1)]
        local c3 = (str:sub(i+2, i+2) ~= "=") and _B64D[str:sub(i+2, i+2)] or nil
        local c4 = (str:sub(i+3, i+3) ~= "=") and _B64D[str:sub(i+3, i+3)] or nil
        if c1 == nil or c2 == nil then
            return nil, "Caractère Base64 invalide à pos " .. i
        end
        out[#out+1] = string.char(c1 * 4 + math.floor(c2 / 16))
        if c3 then
            out[#out+1] = string.char((c2 % 16) * 16 + math.floor(c3 / 4))
        end
        if c4 then
            out[#out+1] = string.char((c3 % 4)  * 64 + c4)
        end
    end
    return table.concat(out)
end
