-------------------------------------------------------------------------------
--  SphereNameplates · Logs
--
--  Module de journalisation interne horodate, persistance optionnelle,
--  niveaux INFO/WARN/ERROR/PERF/DEBUG, ring buffer a capacite fixe.
--
--  API publique :
--    SP.Log:Info(module, msg)      niveau INFO
--    SP.Log:Warn(module, msg)      niveau WARN
--    SP.Log:Error(module, msg)     niveau ERROR (jamais throttle)
--    SP.Log:Perf(module, msg)      niveau PERF
--    SP.Log:Debug(module, msg)     niveau DEBUG (off par defaut)
--    SP.Log:Clear()                vide le buffer
--    SP.Log:SetEnabled(bool)       activer/desactiver
--    SP.Log:GetEntries(opts)       retourne tableau filtre
--    SP.Log:Count()                nombre d'entrees actuelles
--
--  Throttle : meme (module + 32 premiers chars msg) → 1 entree / 2 s
--  Anti-spam combat : DEBUG bloque si SP.InCombat == true
--  Ring buffer : index modulaire, pas de table.remove (O(1))
-------------------------------------------------------------------------------

local addonName, _ = ...
local SP = _G["SphereNameplates"]
if not SP then return end

SP.Log = SP.Log or {}
local Log = SP.Log

-- ─── Constantes ──────────────────────────────────────────────────────────────
Log.THROTTLE_SAME_MSG = 2.0   -- secondes entre deux entrees identiques
Log.LEVELS = { INFO=1, WARN=2, ERROR=3, PERF=4, DEBUG=5 }
Log.LEVEL_COLORS = {
    INFO  = "|cFF88CCFF",
    WARN  = "|cFFFFCC44",
    ERROR = "|cFFFF4444",
    PERF  = "|cFFFF8800",
    DEBUG = "|cFFAAAAAA",
}

-- ─── État interne ─────────────────────────────────────────────────────────────
Log._entries   = Log._entries  or {}  -- ring buffer
Log._head      = Log._head     or 0   -- prochain index a ecrire (1-based modulo)
Log._count     = Log._count    or 0   -- nombre d'entrees valides
Log._capacity  = 0                    -- defini au premier log (lit la DB)
Log._throttle  = {}                   -- [key] = timestamp derniere emission
Log._enabled   = false                -- mis a jour dynamiquement

-- ─── Helpers DB ───────────────────────────────────────────────────────────────
local function _db()
    return SP.db
end

local function _capacity()
    local db = _db()
    return (db and db.logs_max_entries) or 200
end

local function _levelEnabled(level)
    local db = _db()
    if not db then return level == "ERROR" end
    if level == "INFO"  then return db.logs_level_info  ~= false end
    if level == "WARN"  then return db.logs_level_warn  ~= false end
    if level == "ERROR" then return true end   -- ERROR toujours
    if level == "PERF"  then return db.logs_level_perf  ~= false end
    if level == "DEBUG" then return db.logs_level_debug == true  end
    return false
end

-- ─── IsEnabled ────────────────────────────────────────────────────────────────
function Log:IsEnabled()
    local db = _db()
    return db and db.logs_enabled == true
end

function Log:SetEnabled(bool)
    local db = _db()
    if db then db.logs_enabled = bool == true end
end

-- ─── Ecriture interne ─────────────────────────────────────────────────────────
local function _write(level, module, msg)
    -- Guard global
    if not Log:IsEnabled() then return end
    if not _levelEnabled(level) then return end

    -- Anti-spam combat : DEBUG bloque en combat
    if level == "DEBUG" and SP.InCombat then return end

    -- Throttle (sauf ERROR)
    if level ~= "ERROR" then
        local key  = (module or "?") .. ":" .. tostring(msg):sub(1, 40)
        local now  = GetTime()
        local last = Log._throttle[key]
        if last and (now - last) < Log.THROTTLE_SAME_MSG then return end
        Log._throttle[key] = now
    end

    -- Capacite
    local cap = _capacity()
    if cap ~= Log._capacity then
        -- Capacite changee → resize (simple reinit)
        Log._entries  = {}
        Log._head     = 0
        Log._count    = 0
        Log._capacity = cap
    end
    if cap <= 0 then return end

    -- Ring buffer : ecrire a _head (1-based)
    Log._head = (Log._head % cap) + 1
    Log._entries[Log._head] = {
        t      = GetTime(),
        date   = date("%H:%M:%S"),
        level  = level,
        module = module or "?",
        msg    = tostring(msg),
    }
    if Log._count < cap then Log._count = Log._count + 1 end
end

-- ─── API publique ─────────────────────────────────────────────────────────────
function Log:Info (m, msg) _write("INFO",  m, msg) end
function Log:Warn (m, msg) _write("WARN",  m, msg) end
function Log:Error(m, msg) _write("ERROR", m, msg) end
function Log:Perf (m, msg) _write("PERF",  m, msg) end
function Log:Debug(m, msg) _write("DEBUG", m, msg) end

function Log:Clear()
    Log._entries = {}
    Log._head    = 0
    Log._count   = 0
    Log._throttle= {}
end

function Log:Count()
    return Log._count
end

-- ─── GetEntries — retourne les entrees du plus recent au plus ancien ──────────
-- opts = { level = "WARN", module = "Auras", max = 100 }
function Log:GetEntries(opts)
    opts = opts or {}
    local cap    = _capacity()
    if cap <= 0 or Log._count == 0 then return {} end

    local filterLevel  = opts.level  -- nil = tous
    local filterModule = opts.module -- nil = tous
    local maxOut = opts.max or Log._count
    local out = {}

    -- Parcours du plus recent (head) au plus ancien
    local head = Log._head
    for i = 1, Log._count do
        local idx = ((head - i) % cap) + 1
        local e   = Log._entries[idx]
        if e then
            local ok = true
            if filterLevel  and e.level  ~= filterLevel  then ok = false end
            if filterModule and e.module ~= filterModule then ok = false end
            if ok then
                out[#out + 1] = e
                if #out >= maxOut then break end
            end
        end
    end
    return out
end

-- ─── Intégration SP:Debug → SP.Log ───────────────────────────────────────────
-- Surcharge SP:Debug pour qu'il alimente aussi le ring buffer
local _origDebug = SP.Debug
function SP:Debug(msg)
    -- Comportement original : chat si debugMode
    if SP.db and SP.db.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[SP-DBG]|r " .. tostring(msg))
    end
    -- Nouveau : alimenter le ring buffer Logs
    Log:Debug("Core", msg)
end
