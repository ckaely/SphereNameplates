-------------------------------------------------------------------------------
-- SphereNameplates v7.5 — Core.lua
-- Cycle de vie nameplates + dispatcher d'événements + minimap
--
-- ARCHITECTURE ÉVÉNEMENTS v7.5 (runtime actif) :
--   Santé/power/auras pilotés par le dispatcher global de SpherePlatesEventFrame.
--   Les casts ne sont pas dispatchés ici : chaque nameplate crée son watcher dédié
--   dans Modules/CastBar.lua via RegisterUnitEvent + polling de secours.
--
-- CORRECTIONS v7.2→v7.5 :
--   • RefreshAll() SANS timer → rebuild immédiat, zéro flicker
--   • SetTargetRatio → UpdateFill immédiat au premier attach
--   • root:Show() explicite après toute création d'orbe
--   • OnPlateAdded : retry intelligent si l'unité n'existe pas encore
--   • HardRefreshAll : scan C_NamePlate.GetNamePlates ET retente les unités connues
--   • UnitFrame Blizzard masqué proprement — HookScript permanent
--   • v7.5 : watchers RegisterUnitEvent de castbar consolidés (HP reste global)
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]

local frame = CreateFrame("Frame", "SpherePlatesEventFrame", UIParent)

-- ─────────────────────────────────────────────────────────────────────────────
--  ÉVÉNEMENTS
-- ─────────────────────────────────────────────────────────────────────────────
-- NOTE WoW Midnight 12.0.1 :
--   UNIT_HEALTH_FREQUENT et UNIT_POWER_FREQUENT ont été supprimés.
--   RegisterEvent() sur un event inconnu lève une erreur Lua fatale qui
--   empêche SetScript("OnEvent") d'être atteint → aucune sphère possible.
--   Solution : pcall par event + liste purgée des events retirés.
local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEAVING_WORLD",
    "GROUP_ROSTER_UPDATE",
    -- Nameplates
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    -- Santé (UNIT_HEALTH_FREQUENT supprimé en WoW Midnight 12.0.1)
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    -- Power (UNIT_POWER_FREQUENT supprimé en WoW Midnight 12.0.1)
    "UNIT_POWER_UPDATE",
    "UNIT_DISPLAYPOWER",
    -- Ciblage
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    -- Combat
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    -- Unité
    "UNIT_NAME_UPDATE",          -- données de classe disponibles (joueurs allié/ennemi)
    "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_FACTION",
    "UNIT_LEVEL",
    -- Auras
    "UNIT_AURA",
    -- Sorts : gérés par des watchers RegisterUnitEvent dans CastBar.lua
    -- (NE PAS enregistrer ici — double dispatch inutile + risque de nil)
    -- Divers
    "RAID_TARGET_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "QUEST_REMOVED",
    "QUEST_WATCH_LIST_CHANGED",
    "UNIT_QUEST_LOG_CHANGED",
}
-- Enregistrement défensif : un event inconnu ne tue plus le chargement
for _, ev in ipairs(EVENTS) do
    local ok, err = pcall(frame.RegisterEvent, frame, ev)
    if not ok then
        -- Log silencieux — ne bloque pas les autres events
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFFAA00[SP]|r Event non supporté ignoré : " .. tostring(ev))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ANIMATION (OnUpdate — 4 accumulateurs)
-- ─────────────────────────────────────────────────────────────────────────────
local _animAcc = 0
local _castAcc = 0
local _lerpAcc = 0
local _pollAcc = 0   -- poll HP de secours toutes les 0.5s
local _fadeAcc = 0   -- poll distance fade toutes les 0.25s

frame:SetScript("OnUpdate", function(_, elapsed)
    _animAcc = _animAcc + elapsed
    _castAcc = _castAcc + elapsed
    _lerpAcc = _lerpAcc + elapsed
    _pollAcc = _pollAcc + elapsed
    _fadeAcc = _fadeAcc + elapsed

    -- Glows pulsants cible/focus (30 FPS suffit)
    -- Les rotations DiabolicUI sont gérées nativement par WoW AnimationGroup.
    if _animAcc >= 1/30 then
        local _pt0 = debugprofilestop()
        if not (SP.db and SP.db.modules_orbanim_enabled == false) then
            SP.Orb:AnimTick(_animAcc)
        end
        if SP.Profiler then
            SP.Profiler:Track("AnimTick", debugprofilestop() - _pt0)
            SP.Profiler:TickPanel(GetTime())
        end
        _animAcc = 0
    end

    -- Castbar (60 FPS pour smoothness)
    -- Un seul pcall englobant : élimine ~1200 pcalls/sec à 20 plaques.
    if _castAcc >= 1/60 then
        if not (SP.db and SP.db.modules_castbar_enabled == false) then
            local now = GetTime()
            local _pt0 = debugprofilestop()
            pcall(function()
                for _, data in pairs(SP.Plates) do
                    if data.castbar then
                        SP.CastBar:Tick(data, now)
                    end
                end
                if SP.Moi and SP.Moi.TickCast then
                    SP.Moi:TickCast(now)
                end
            end)
            if SP.Profiler then SP.Profiler:Track("CastBar", debugprofilestop() - _pt0) end
        end
        _castAcc = 0
    end

    -- Lerp HP (60 FPS) : displayHP suit targetHP en douceur
    -- hp_lerp_speed (1–30) → k = speed * 0.018  (8=défaut → k≈0.144 ≈ ancien 0.15)
    if _lerpAcc >= 1/60 then
        if not (SP.db and SP.db.modules_hplerp_enabled == false) then
            local _pt0 = debugprofilestop()
            for _, data in pairs(SP.Plates) do
                if data.targetHP ~= nil then
                    local cfg   = SP:GetCfg(data.unitType)
                    local k     = math.min(0.90, (cfg.hp_lerp_speed or 8.0) * 0.018)
                    local target  = data.targetHP
                    local display = data.displayHP or target
                    local diff    = target - display
                    if math.abs(diff) > 0.0005 then
                        data.displayHP = display + diff * k
                    else
                        data.displayHP = target
                    end
                    SP.Orb:UpdateFill(data, data.displayHP)
                end
            end
            if SP.Moi and SP.Moi.TickHealth then
                pcall(SP.Moi.TickHealth, SP.Moi)
            end
            if SP.Profiler then SP.Profiler:Track("HPLerp", debugprofilestop() - _pt0) end
        end
        _lerpAcc = 0
    end

    -- Distance fade — 4 fois par seconde (pas besoin de 60 FPS)
    -- Note : on stocke _fadeAlpha sur le data plutôt que d'appeler SetAlpha
    -- directement. AnimTick (30 FPS) compose pack alpha + fade alpha en une seule
    -- passe → élimine le conflit "last write wins" entre les deux systèmes.
    if _fadeAcc >= 0.25 then
        if not (SP.db and SP.db.modules_fade_enabled == false) then
            local _pt0 = debugprofilestop()
            for unit, data in pairs(SP.Plates) do
                local cfg = SP:GetCfg(data.unitType)
                if cfg.fade_enabled and data.root then
                    -- UnitDistanceSquared : disponible en WoW Retail mais peut être absent
                    -- Si absent : pas de fade (_fadeAlpha reste à 1.0)
                    local ok, dist = false, nil
                    if type(UnitDistanceSquared) == "function" then
                        ok, dist = pcall(UnitDistanceSquared, unit)
                    end
                    if ok and type(dist) == "number" then
                        local fadeStart = cfg.fade_start or 25
                        local fadeEnd   = cfg.fade_end   or 40
                        local minA      = cfg.fade_min_alpha or 0.55
                        local d = math.sqrt(dist)
                        if d <= fadeStart then
                            data._fadeAlpha = 1.0
                        elseif d >= fadeEnd then
                            data._fadeAlpha = minA
                        else
                            local t = (d - fadeStart) / (fadeEnd - fadeStart)
                            data._fadeAlpha = 1.0 - t * (1.0 - minA)
                        end
                    end
                else
                    data._fadeAlpha = 1.0
                end

                local nameAlpha = data._nameDistanceAlpha
                if nameAlpha == nil then nameAlpha = 1.0 end
                if cfg.name_distance_enabled and data.nameText then
                    local isTarget = SP.SafeUnitIsUnit and SP:SafeUnitIsUnit(unit, "target")
                    if isTarget then
                        nameAlpha = 1.0
                        data._nameDistanceLastDist = nil
                    else
                        local okNameDist, computed = pcall(function()
                            if type(UnitDistanceSquared) ~= "function" then return nil end
                            local dist2 = UnitDistanceSquared(unit)
                            if type(dist2) ~= "number" then return nil end
                            local d = math.sqrt(dist2)
                            data._nameDistanceLastDist = d
                            local mode = cfg.name_distance_mode or "limit"
                            if mode == "fade" then
                                local fullD = tonumber(cfg.name_fade_full) or 2
                                local hideD = tonumber(cfg.name_fade_hidden) or 20
                                if hideD <= fullD then hideD = fullD + 1 end
                                if d <= fullD then return 1.0 end
                                if d >= hideD then return 0.0 end
                                local t = (d - fullD) / (hideD - fullD)
                                return 1.0 - t
                            end
                            local maxD = tonumber(cfg.name_distance_max) or 20
                            return d <= maxD and 1.0 or 0.0
                        end)
                        if okNameDist and type(computed) == "number" then
                            computed = math.max(0, math.min(1, computed))
                            local lerp = 0.45
                            nameAlpha = nameAlpha + (computed - nameAlpha) * lerp
                            if math.abs(nameAlpha - computed) < 0.015 then nameAlpha = computed end
                        end
                    end
                else
                    nameAlpha = 1.0
                end
                if data._nameDistanceAlpha ~= nameAlpha then
                    data._nameDistanceAlpha = nameAlpha
                    if SP.Orb and SP.Orb.ApplyNameDistanceAlpha then
                        pcall(SP.Orb.ApplyNameDistanceAlpha, SP.Orb, data)
                    end
                end
            end
            if SP.Profiler then SP.Profiler:Track("Fade", debugprofilestop() - _pt0) end
        end
        _fadeAcc = 0
    end

    -- Poll HP + aggro + auras + pack-mode toutes les 0.5s
    if _pollAcc >= 0.5 then
        local _pt0 = debugprofilestop()
        local _auras_on = not (SP.db and SP.db.modules_auras_enabled == false)

        -- ── Pack Mode — Solution B : détection densité ────────────────────────
        -- Comptage O(N) des plaques actives. Si >= threshold → mode pack actif.
        -- La priorité visuelle (C) est calculée par plaque :
        --   Rang 3 : cible / focus
        --   Rang 2 : marqué raid / boss / aggro totale (al>=3)
        --   Rang 1 : en combat / aggro partielle
        --   Rang 0 : background mob
        local packEnabled = SP.db and SP.db.pack_mode_enabled
        if packEnabled then
            local plateCount = 0
            for _ in pairs(SP.Plates) do plateCount = plateCount + 1 end
            local threshold = (SP.db and SP.db.pack_threshold) or 6
            local wasPackMode = SP._packMode
            SP._packMode      = (plateCount >= threshold)
            SP._packPlateCount = plateCount

            -- Calcul priorité visuelle par plaque (Solution C)
            for _, data in pairs(SP.Plates) do
                local rank = 0
                if data._isTarget or data._isFocus then
                    rank = 3
                else
                    local al = data._aggroLevel or 0
                    -- Rang 2 : marqué raid, boss, ou aggro totale
                    local hasMark = false
                    if data.unit then
                        local ok, idx = pcall(GetRaidTargetIndex, data.unit)
                        if ok and idx ~= nil and (not canaccessvalue or canaccessvalue(idx)) then
                            idx = tonumber(idx)
                            hasMark = idx and idx > 0
                        end
                    end
                    local isBoss = false
                    if data.unit then
                        local ok, cl = pcall(UnitClassification, data.unit)
                        isBoss = ok and (cl == "worldboss" or cl == "elite" or cl == "rareelite")
                    end
                    if hasMark or isBoss or al >= 3 then
                        rank = 2
                    elseif data._inCombat or al >= 1 then
                        rank = 1
                    end
                end
                data._packRank = rank
            end

            -- PackOrb update (grande sphère de cluster)
            if SP.PackOrb then
                pcall(SP.PackOrb.UpdateClusters, SP.PackOrb)
            end
        else
            SP._packMode      = false
            SP._packPlateCount = 0
            -- Rang neutre quand pack mode désactivé
            for _, data in pairs(SP.Plates) do
                data._packRank = 3  -- full vis quand mode off
            end
            if SP.PackOrb then
                pcall(SP.PackOrb.HideAll, SP.PackOrb)
            end
        end

        for unit, data in pairs(SP.Plates) do
            pcall(SP.UpdateHealth, SP, unit, data)
            -- Update aggro (UnitThreatSituation) — pas d'event spécifique, doit être polled
            if data.unitType == "ENEMY" or data.unitType == "ENEMY_PLAYER" then
                pcall(SP.Orb.UpdateAggro, SP.Orb, data, unit)
            end
            -- Refresh couleur nom si mode progressive (suit displayHP à 0.5s)
            local _ncfg = SP:GetCfg(data.unitType)
            if _ncfg and _ncfg.name_color_mode == "progressive" then
                pcall(SP.Orb.UpdateName, SP.Orb, data, unit)
            end
            -- Refresh couleur fill si mode progressive (NEUTRAL et autres non-joueurs
            -- reçoivent peu de UNIT_HEALTH → la couleur doit être recalculée au poll)
            if _ncfg and _ncfg.fill_color_mode == "progressive" then
                pcall(SP.Orb.UpdateFill, SP.Orb, data, data.displayHP or data.targetHP)
            end
            -- Poll auras : filet de sécurité si UNIT_AURA a été manqué ou pas livré
            if _auras_on and data.auraIcons then
                pcall(SP.Auras.UpdateUnit, SP.Auras, data, unit, nil)
            end
        end
        if SP.Moi and SP.Moi.Poll then
            pcall(SP.Moi.Poll, SP.Moi)
        end
        if SP.Profiler then SP.Profiler:Track("Poll", debugprofilestop() - _pt0) end
        _pollAcc = 0
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  DISPATCHER D'ÉVÉNEMENTS
-- ─────────────────────────────────────────────────────────────────────────────
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    local _spdbgEventT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil

    if event == "ADDON_LOADED" and arg1 == "SphereNameplates" then
        SP:Initialize()

    elseif event == "PLAYER_ENTERING_WORLD" then
        if SP.Initialized then
            -- Pré-peupler le pool d'icônes auras hors combat pour éviter CreateFrame
            -- en InCombatLockdown lors du premier cycle d'auras.
            if SP.Auras and SP.Auras.PrewarmPool then
                pcall(SP.Auras.PrewarmPool, SP.Auras, 160)
            end
            -- Délai minimal pour que WoW charge les nameplates de zone
            if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
            C_Timer.After(0.5, function() SP:HardRefreshAll() end)
            C_Timer.After(1.5, function()
                if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
                SP:HardRefreshAll()
            end)
        end

    elseif event == "PLAYER_LEAVING_WORLD" then
        if SP.Quest then SP.Quest:ClearCache(true) end
        -- Vider le cache GUID classe (les tokens nameplateN changent entre zones)
        if SP._guidClassCache then
            for k in pairs(SP._guidClassCache) do SP._guidClassCache[k] = nil end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if SP.Initialized then
            if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
            C_Timer.After(0.25, function() SP:HardRefreshAll() end)
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        SP:Debug("EVENT NAME_PLATE_UNIT_ADDED → " .. tostring(arg1))
        SP:OnPlateAdded(arg1)
        if SP.Orb and SP.Orb.RefreshAllRaidMarks then
            SP.Orb:RefreshAllRaidMarks(0.05)
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        SP:Debug("EVENT NAME_PLATE_UNIT_REMOVED → " .. tostring(arg1))
        SP:OnPlateRemoved(arg1)

    elseif event == "UNIT_HEALTH"
        or event == "UNIT_MAXHEALTH" then
        SP:Debug(string.format("[HP] %s → %s", event, tostring(arg1)))

        -- Priorité 1 : accès direct par token (arg1 = "nameplate1", etc.)
        local directData = SP.Plates[arg1]
        if directData then
            pcall(SP.UpdateHealth, SP, arg1, directData)
        else
            -- Priorité 2 : UnitIsUnit loop — fallback pour les alias
            for unit, data in pairs(SP.Plates) do
                local ok, same = pcall(UnitIsUnit, unit, arg1)
                if ok and same then
                    pcall(SP.UpdateHealth, SP, unit, data)
                    break
                end
            end
        end

    elseif event == "UNIT_POWER_UPDATE"
        or event == "UNIT_DISPLAYPOWER" then
        local data = SP.Plates[arg1]
        if data then SP.Orb:UpdatePower(data, arg1) end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- WoW restaure parfois les éléments Blizzard au changement de cible.
        -- Re-appliquer le masquage sur toutes les plates actives.
        for unit, data in pairs(SP.Plates) do
            if data.plate then
                SP:HideBlizzardElements(data.plate)
            end
            -- Forcer mise à jour HP de la nouvelle cible
            local ok, same = pcall(UnitIsUnit, unit, "target")
            if ok and same then
                pcall(SP.UpdateHealth, SP, unit, data)
            end
        end
        SP:UpdateAllGlows()
        for unit, data in pairs(SP.Plates) do
            pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg(data.unitType))
            pcall(SP.Orb.UpdateLevelText, SP.Orb, data, unit)
            pcall(SP.Orb.UpdateRaidMark, SP.Orb, data, unit)
        end

    elseif event == "PLAYER_FOCUS_CHANGED" then
        SP:UpdateAllGlows()

    elseif event == "PLAYER_REGEN_DISABLED" then
        SP.InCombat = true
        SP:Debug("ENTER_COMBAT")
        for unit, data in pairs(SP.Plates) do
            local ut = data.unitType
            if ut == "ENEMY" or ut == "ENEMY_PLAYER" then
                SP.Orb:UpdateLevelText(data, unit)
                SP.Orb:UpdateCombat(data, unit)
            end
            pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg(data.unitType))
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        SP.InCombat = false
        SP:Debug("LEAVE_COMBAT")
        if SP.Auras and SP.Auras.PrewarmPool then
            pcall(SP.Auras.PrewarmPool, SP.Auras, 160)
        end
        if SP._pendingNameplateCVars then
            SP._pendingNameplateCVars = nil
            if SP.ApplyNameplateCVars then SP:ApplyNameplateCVars() end
        end
        for unit, data in pairs(SP.Plates) do
            local ut = data.unitType
            if ut == "ENEMY" or ut == "ENEMY_PLAYER" then
                SP.Orb:UpdateLevelText(data, unit)
                SP.Orb:UpdateCombat(data, unit)
            end
            pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg(data.unitType))
        end
        if SP.RaidMarkerMenu and SP.RaidMarkerMenu._pendingAttach and SP.RaidMarkerMenu.RefreshAttachments then
            pcall(SP.RaidMarkerMenu.RefreshAttachments, SP.RaidMarkerMenu)
        end

    elseif event == "UNIT_NAME_UPDATE" then
        -- Données de classe arrivées côté client → résoudre la couleur si encore en attente
        local data = arg1 and SP.Plates[arg1]
        if data and not data._cachedClass then
            local isPlayer = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
            if isPlayer and data.unit then
                pcall(SP.Orb.RefreshUnitColors, SP.Orb, data, data.unit, data._displayRatio or 1)
            end
        end

    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        local data = SP.Plates[arg1]
        if data then SP.Orb:UpdateElite(data, arg1) end

    elseif event == "UNIT_FACTION" then
        if SP.Plates[arg1] then SP:ReclassifyUnit(arg1) end

    elseif event == "UNIT_LEVEL" then
        local data = SP.Plates[arg1]
        if data then SP.Orb:UpdateLevelText(data, arg1) end

    elseif event == "UNIT_AURA" then
        if not (SP.db and SP.db.modules_auras_enabled == false) then
            local data = SP.Plates[arg1]
            if data then SP.Auras:UpdateUnit(data, arg1, arg2) end
        end

    -- UNIT_SPELLCAST_* : gérés par les watchers RegisterUnitEvent de CastBar.lua
    -- (pas de dispatch global ici pour éviter le double traitement)

    elseif event == "RAID_TARGET_UPDATE" then
        if SP.Orb and SP.Orb.RefreshAllRaidMarks then
            SP.Orb:RefreshAllRaidMarks()
            SP.Orb:RefreshAllRaidMarks(0.05)
        end

    elseif event == "QUEST_ACCEPTED" or event == "UNIT_QUEST_LOG_CHANGED"
        or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED"
        or event == "QUEST_WATCH_LIST_CHANGED" then
        C_Timer.After(0.3, function()
            if SP.Quest then SP.Quest:UpdateAll() end
        end)
    end

    if _spdbgEventT0 and SP.SPDebug and SP.SPDebug.TrackEvent then
        pcall(SP.SPDebug.TrackEvent, SP.SPDebug, event, debugprofilestop() - _spdbgEventT0, arg1)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  INITIALISATION
-- ─────────────────────────────────────────────────────────────────────────────
function SP:IsInInstance()
    if not IsInInstance then return false, nil end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if ok then return inInstance == true, instanceType end
    return false, nil
end

function SP:ApplyNameplateCVars()
    if InCombatLockdown and InCombatLockdown() then
        SP._pendingNameplateCVars = true
        return
    end
    local function CV(k, v) pcall(SetCVar, k, v) end
    local db = SP.db or {}
    local inInstance = false
    if SP.IsInInstance then inInstance = SP:IsInInstance() end
    local forceFriendlyInstance = db.behavior_force_friendly_players_instance ~= false

    CV("nameplateShowAll",            "1")
    CV("nameplateShowEnemies",        "1")
    CV("nameplateShowEnemyPlayers",   "1")
    CV("nameplateShowEnemyCastBars",  "1")
    CV("nameplateMaxDistance",        "60")

    if inInstance then
        local showFriendly = forceFriendlyInstance and "1" or "0"
        CV("nameplateShowFriends",         showFriendly)
        CV("nameplateShowFriendlyPlayers", showFriendly)
    else
        CV("nameplateShowFriends",         "1")
        CV("nameplateShowFriendlyPlayers", "1")
    end

    -- ── Pack Mode — Solution A : recalibrage espacement Blizzard pour sphères ──
    -- Les CVars nameplateOverlapH/V sont calibrés pour des barres plates standard.
    -- Les sphères couvrent 2-3× plus de surface → on élargit l'espacement.
    -- Guard : si un addon comme Plater ou KuiNameplates est présent, on laisse
    -- leur CVar manager prendre le relais pour éviter les conflits.
    if db.pack_mode_enabled and db.pack_cvar_adjust ~= false then
        local hasConflict = IsAddOnLoaded and (
            IsAddOnLoaded("Plater") or
            IsAddOnLoaded("KuiNameplates") or
            IsAddOnLoaded("TidyPlates") or
            IsAddOnLoaded("NeatPlates")
        )
        if not hasConflict then
            CV("nameplateOverlapH", tostring(db.pack_cvar_overlap_h or 1.25))
            CV("nameplateOverlapV", tostring(db.pack_cvar_overlap_v or 1.55))
        end
    end
end

function SP:Initialize()
    if SP.Initialized then return end
    SP.Initialized = true

    -- AceDB
    local ok, AceDB = pcall(LibStub, "AceDB-3.0")
    if ok and AceDB then
        local ok2, obj = pcall(AceDB.New, AceDB, "SpherePlatesDB", SP.DEFAULTS, true)
        if ok2 and obj then
            SP.dbObj = obj
            SP.db    = obj.profile
            local function onProfileChange()
                SP.db = SP.dbObj.profile
                if SP.EnsureProfileDefaults then SP:EnsureProfileDefaults() end
                -- SP._profileBulkOp : positionné par ProfileManager lors des
                -- opérations multi-étapes (Rename, Duplicate...) pour éviter
                -- de déclencher N RefreshAll intermédiaires inutiles.
                if not SP._profileBulkOp then SP:RefreshAll() end
                if SP.ActionBars and SP.ActionBars.Refresh then
                    pcall(SP.ActionBars.Refresh, SP.ActionBars)
                end
            end
            pcall(obj.RegisterCallback, obj, "OnProfileChanged", onProfileChange)
            pcall(obj.RegisterCallback, obj, "OnProfileCopied",  onProfileChange)
            pcall(obj.RegisterCallback, obj, "OnProfileReset",   onProfileChange)
        end
    end

    -- Fallback DB si AceDB absent
    if not SP.db then
        SP:Print("|cFFFFAA00AceDB manquant — profil par défaut en mémoire.|r")
        SP.db = {}
        for k, v in pairs(SP.DEFAULTS.profile) do
            if type(v) == "table" then
                SP.db[k] = {}
                for k2, v2 in pairs(v) do SP.db[k][k2] = v2 end
            else
                SP.db[k] = v
            end
        end
    end

    if SP.EnsureProfileDefaults then SP:EnsureProfileDefaults() end

    -- Profils (façade AceDB + export/import)
    if SP.Profiles then SP.Profiles:Init() end

    -- LibSharedMedia
    local ok2, LSM = pcall(LibStub, "LibSharedMedia-3.0")
    if ok2 and LSM then
        local M = SP.MEDIA
        LSM:Register("font", "SP Alte",    M .. "Alte.ttf")
        LSM:Register("font", "SP Dajova",  M .. "Dajova.ttf")
        LSM:Register("font", "SP Rotund",  M .. "rotund.ttf")
        LSM:Register("font", "SP Rotundo", M .. "rotundo.ttf")
        SP.LSM = LSM
    end

    -- UI
    SP.UI:Register()

    -- CVars — active les nameplates ennemis/alliés
    SP:ApplyNameplateCVars()

    -- Icône minimap
    SP:CreateMinimapButton()

    -- Restaurer l'état du panneau perf si ouvert avant reload
    if SP.Profiler and SP.Profiler.RestorePanelState then
        SP.Profiler:RestorePanelState()
    end

    -- Sphere personnelle fixe ("Moi"), hors nameplates.
    if SP.Moi and SP.Moi.Init then
        pcall(SP.Moi.Init, SP.Moi)
    end
    if SP.MoiXP and SP.MoiXP.Init then
        pcall(SP.MoiXP.Init, SP.MoiXP)
    end
    if SP.ActionBars and SP.ActionBars.Init then
        pcall(SP.ActionBars.Init, SP.ActionBars)
    end

    SP:Print("v" .. SP.Version .. " chargé — |cFF00FFFFtapez /snp|r")
    if SP.Log then SP.Log:Info("Core", "Initialize OK v" .. SP.Version) end
    SP._diagPlates = 0   -- compteur diagnostic
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ICÔNE MINIMAP (draggable)
-- ─────────────────────────────────────────────────────────────────────────────
function SP:CreateMinimapButton()
    local btn = CreateFrame("Button", "SPMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local RADIUS = 80
    local _dragging = false

    local function UpdatePos()
        local angle = math.rad((SP.db and SP.db.minimap_angle) or 220)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * RADIUS,
            math.sin(angle) * RADIUS)
    end
    UpdatePos()

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(SP.MEDIA .. "orb-border")
    bg:SetAllPoints(btn)

    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(56, 56)
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -12, 12)

    btn:SetScript("OnDragStart", function() _dragging = true end)
    btn:SetScript("OnDragStop",  function() _dragging = false end)

    frame:HookScript("OnUpdate", function()
        if not _dragging then return end
        if not IsMouseButtonDown("LeftButton") then _dragging = false; return end
        local cx, cy   = Minimap:GetCenter()
        local mx, my   = GetCursorPosition()
        local scale    = UIParent:GetEffectiveScale()
        mx = mx / scale
        my = my / scale
        local angle = math.deg(math.atan2(my - cy, mx - cx))
        if SP.db then SP.db.minimap_angle = angle end
        UpdatePos()
    end)

    btn:SetScript("OnClick", function(_, button)
        if _dragging then _dragging = false; return end
        if button == "LeftButton" then
            SP.UI:Open()
        elseif button == "RightButton" then
            SP:ToggleMinimapDropdown(btn)
        end
    end)

    btn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText(
            "|cFF8B0000Sphere|r|cFFFF7A00Plates|r |cFF888888v" .. SP.Version .. "|r",
            1, 1, 1)
        GameTooltip:AddLine("|cFFAAAAFF• Clic gauche|r : Configuration", 1, 1, 1)
        GameTooltip:AddLine("|cFFAAAAFF• Clic droit|r : Menu commandes", 1, 1, 1)
        GameTooltip:AddLine("|cFFAAAAFF• Drag|r : Repositionner", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    SP.MinimapBtn = btn
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DROPDOWN MINIMAP — Clic droit : menu de toutes les commandes /snp
-- ─────────────────────────────────────────────────────────────────────────────
local _minimapDropdown = nil

local SNP_COMMANDS = {
    { cmd = "",         label = "Configuration",    color = {1.0,0.82,0.0},  desc = "Ouvre la fenetre de reglages" },
    { cmd = "on",       label = "Activer",          color = {0.2,1.0,0.3},   desc = "Active l'addon immediatement" },
    { cmd = "off",      label = "Desactiver",       color = {1.0,0.4,0.3},   desc = "Desactive l'addon" },
    { cmd = "reload",   label = "Recharger",        color = {0.4,0.8,1.0},   desc = "Reconstruit toutes les nameplates" },
    { cmd = "reset",    label = "Reset profil",     color = {1.0,0.6,0.1},   desc = "Reinitialise le profil courant" },
    { cmd = "perf",     label = "Perf Monitor",     color = {0.8,0.5,1.0},   desc = "Panneau de performance par module" },
    { cmd = "status",   label = "Status",           color = {0.6,0.9,1.0},   desc = "Etat de l'addon et statistiques" },
    { cmd = "plates",   label = "Plates actives",   color = {0.8,0.8,0.8},   desc = "Diagnostic des spheres visibles" },
    { cmd = "pack",     label = "Mode densite",     color = {0.55,0.28,0.90},desc = "Diagnostic clustering et Pack Orb" },
    { cmd = "layers",   label = "Layers alpha",     color = {0.6,0.8,0.6},   desc = "Trace alpha de toutes les couches" },
    { cmd = "version",  label = "Version",          color = {0.65,0.65,0.65},desc = "Affiche la version de l'addon" },
    { cmd = "debug",    label = "Debug toggle",     color = {1.0,0.5,0.1},   desc = "Active / desactive le mode debug" },
}

local function _ExecuteSnpCmd(cmd)
    if cmd == "" then
        if SP.UI then SP.UI:Open() end
    else
        local handler = SlashCmdList and SlashCmdList["SPHEREPLATES"]
        if handler then pcall(handler, cmd) end
    end
end

function SP:CreateMinimapDropdown()
    local d = CreateFrame("Frame", "SP_MinimapDropdown", UIParent)
    d:SetFrameStrata("TOOLTIP")
    d:SetFrameLevel(300)
    d:Hide()

    -- Fond sombre avec bordure or
    local bg = d:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetAllPoints(d)
    bg:SetColorTexture(0.04, 0.04, 0.07, 0.96)

    local border = CreateFrame("Frame", nil, d, "BackdropTemplate")
    border:SetAllPoints(d)
    if border.SetBackdrop then
        border:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = {left=3, right=3, top=3, bottom=3},
        })
        border:SetBackdropBorderColor(0.80, 0.60, 0.10, 1.0)
    end

    -- Titre
    local title = d:CreateFontString(nil, "OVERLAY")
    pcall(title.SetFont, title, "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -8)
    title:SetText("|cFF8B0000Sphere|r|cFFFF7A00Plates|r |cFF888888— commandes|r")

    -- Séparateur titre
    local sep = d:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  d, "TOPLEFT",  6, -22)
    sep:SetPoint("TOPRIGHT", d, "TOPRIGHT", -6, -22)
    sep:SetColorTexture(0.7, 0.55, 0.10, 0.55)

    -- Lignes de commandes
    local ROW_H = 26
    local START_Y = -28
    local W = 292

    for i, info in ipairs(SNP_COMMANDS) do
        local row = CreateFrame("Button", nil, d)
        row:SetSize(W - 8, ROW_H)
        row:SetPoint("TOPLEFT", d, "TOPLEFT", 4, START_Y - (i - 1) * ROW_H)

        -- Highlight survol
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 1, 1, 0.07)
        hl:Hide()
        row:SetScript("OnEnter", function() hl:Show() end)
        row:SetScript("OnLeave", function() hl:Hide() end)

        -- Puce colorée
        local dot = row:CreateTexture(nil, "ARTWORK")
        dot:SetSize(5, 5)
        dot:SetPoint("LEFT", row, "LEFT", 6, 0)
        dot:SetColorTexture(info.color[1], info.color[2], info.color[3], 1)

        -- Label commande
        local lbl = row:CreateFontString(nil, "OVERLAY")
        pcall(lbl.SetFont, lbl, "Fonts\\FRIZQT__.TTF", 11, "")
        lbl:SetPoint("LEFT", dot, "RIGHT", 6, 1)
        lbl:SetWidth(108)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(info.label)
        lbl:SetTextColor(info.color[1], info.color[2], info.color[3], 1)

        -- Description
        local dsc = row:CreateFontString(nil, "OVERLAY")
        pcall(dsc.SetFont, dsc, "Fonts\\FRIZQT__.TTF", 10, "")
        dsc:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        dsc:SetWidth(148)
        dsc:SetJustifyH("LEFT")
        dsc:SetText(info.desc)
        dsc:SetTextColor(0.68, 0.62, 0.52, 1)

        -- Clic : exécuter la commande et fermer
        local cmdStr = info.cmd
        row:SetScript("OnClick", function()
            d:Hide()
            _ExecuteSnpCmd(cmdStr)
        end)
    end

    -- Séparateur bas
    local sep2 = d:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT",  d, "BOTTOMLEFT",  6, 6)
    sep2:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -6, 6)
    sep2:SetColorTexture(0.7, 0.55, 0.10, 0.30)

    -- Taille finale du frame
    local totalH = math.abs(START_Y) + (#SNP_COMMANDS * ROW_H) + 12
    d:SetSize(W, totalH)

    -- Fermeture au clic en dehors (frame transparent couvrant UIParent)
    local trap = CreateFrame("Frame", nil, UIParent)
    trap:SetAllPoints(UIParent)
    trap:SetFrameStrata("HIGH")
    trap:SetFrameLevel(1)
    trap:Hide()
    trap:SetScript("OnMouseDown", function()
        d:Hide()
        trap:Hide()
    end)
    d._trap = trap

    _minimapDropdown = d
    return d
end

function SP:ToggleMinimapDropdown(anchor)
    if not _minimapDropdown then
        self:CreateMinimapDropdown()
    end
    local d = _minimapDropdown
    if d:IsShown() then
        d:Hide()
        if d._trap then d._trap:Hide() end
    else
        d:ClearAllPoints()
        -- Positionner au-dessus du bouton, légèrement décalé vers la droite
        d:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", -260, 6)
        d:Show()
        if d._trap then d._trap:Show() end
    end
end

function SP:ToggleAddon()
    if not SP.db then return end
    SP.db.addonEnabled = not (SP.db.addonEnabled ~= false)
    if SP.db.addonEnabled then
        SP:Print("Activé.")
        SP:HardRefreshAll()
    else
        SP:Print("Désactivé.")
        SP._isRefreshing = true
        for unit in pairs(SP.Plates) do SP:OnPlateRemoved(unit) end
        SP._isRefreshing = false
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  AJOUT D'UNE PLAQUE (NAME_PLATE_UNIT_ADDED)
-- ─────────────────────────────────────────────────────────────────────────────
function SP:OnPlateAdded(unit)
    local _spdbgT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil
    if SP.SPDebug then SP.SPDebug:Count("Core.OnPlateAdded", "events", 1) end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFF4444[SP]|r C_NamePlate absent — orbes impossibles")
        return
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then
        SP:Debug("PLATE_ADDED " .. unit .. " → frame introuvable, ignoré")
        return
    end

    if SP.db and SP.db.addonEnabled == false then return end

    -- Déterminer le type d'unité (sans dépendre de UnitExists —
    -- UnitReaction fonctionne même si UnitExists = false en WoW Midnight)
    local unitType = SP:GetUnitType(unit)
    if not unitType then
        -- Dernière chance : réessai unique après 120ms
        SP._retryCount = (SP._retryCount or 0) + 1
        if SP._retryCount <= 40 then   -- max 40 retries au total
            C_Timer.After(0.12, function()
                if C_NamePlate.GetNamePlateForUnit(unit) then
                    SP:OnPlateAdded(unit)
                end
            end)
        end
        return
    end
    SP._retryCount = 0

    if unitType == "FRIENDLY_PLAYER" and SP.IsInInstance and SP:IsInInstance()
       and SP.db and SP.db.behavior_force_friendly_players_instance == false then
        SP:HideBlizzardElements(plate)
        return
    end

    local cfg = SP:GetCfg(unitType)

    -- Nettoyer une ancienne sphère sur ce token
    if SP.Plates[unit] then
        SP._isRefreshing = true
        SP:OnPlateRemoved(unit)
        SP._isRefreshing = false
    end

    -- Essayer de récupérer depuis le pool
    local data = SP.Orb:Acquire(unitType, plate, cfg)
    local ok = true
    if not data then
        -- Création protégée par pcall — TOUTES les erreurs sont loguées (max 10)
        SP._orbErrCount = (SP._orbErrCount or 0)
        ok, data = pcall(SP.Orb.Create, SP.Orb, unit, plate, unitType)
    end

    if not ok or not data then
        if SP._orbErrCount < 10 then
            SP._orbErrCount = SP._orbErrCount + 1
            local msg = ok and "Orb.Create a retourne nil"
                             or tostring(data)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFFF4444[SphereNameplates]|r Orbe "..unit.." échoué : "..msg)
        end
        return
    end

    -- Assurer la visibilité du root
    if data.root then
        data.root:Show()
        -- Forcer le strata HIGH pour être au-dessus des nameplates Blizzard
        pcall(data.root.SetFrameStrata, data.root, "HIGH")
        -- Marquer comme frame SP — HideBlizzardElements ne le cachera pas
        data.root._isSPFrame = true
        -- V3 Codex fix: ignorer l'alpha de la nameplate Blizzard parent (qui peut
        -- moduler la visibilité selon distance/visibilité, créant un assombrissement
        -- non maîtrisé). Configurable via cfg.ignore_parent_alpha (default true).
        local cfg = SP:GetCfg(unitType) or {}
        if cfg.ignore_parent_alpha ~= false then
            pcall(data.root.SetIgnoreParentAlpha, data.root, true)
        end
    end

    -- Enregistrement IMMÉDIAT dans SP.Plates avant tout hook ou event
    -- (ordre strict : Create → assign SP.Plates → HideBlizzardElements)
    data.unit            = unit
    data.targetHP        = nil   -- sera rempli par UpdateHealth
    data.displayHP       = nil   -- sera rempli par UpdateHealth (premier = direct)
    SP.Plates[unit]      = data
    SP.ActiveUnits[unit] = unitType
    SP.ActiveOrbData[unit] = data
    pcall(SP.Orb.RefreshUnitColors, SP.Orb, data, unit, 1)
    if SP.PlayerContextMenu and SP.PlayerContextMenu.Attach then
        pcall(SP.PlayerContextMenu.Attach, SP.PlayerContextMenu, data, unit)
    end
    if SP.RaidMarkerMenu and SP.RaidMarkerMenu.Attach then
        pcall(SP.RaidMarkerMenu.Attach, SP.RaidMarkerMenu, data, unit)
    end

    -- Masquer les barres Blizzard — APRÈS enregistrement dans SP.Plates
    -- pour que tout event déclenché par les hooks trouve la plate déjà connue
    SP:HideBlizzardElements(plate)

    -- ── Retry cascade pour la résolution de classe joueur ───────────────────
    -- Problème : UnitClass(unit) retourne nil pendant 0.1–2s après NAME_PLATE_UNIT_ADDED
    -- (chargement asynchrone des unités en entrée de zone).
    -- Pour les alliés à 100% HP, UNIT_HEALTH ne déclenche pas de UpdateFill → la
    -- couleur de classe n'est jamais corrigée automatiquement sans ces retries.
    -- Fix A (SafeUnitClass amélioré) + Fix C (AnimTick) couvrent l'ongoing,
    -- ces retries couvrent les 6 premières secondes avec 3 tentatives.
    --
    -- Le retry à 0.5s masque aussi les éléments Blizzard (restauration WoW Midnight).
    local function _classRetry(delay, isFirst)
        C_Timer.After(delay, function()
            local d2 = SP.Plates[unit]
            if not d2 then return end
            -- Masquage Blizzard uniquement au premier retry (0.5s)
            if isFirst and d2.plate then SP:HideBlizzardElements(d2.plate) end
            -- Si la classe est déjà résolue (par Fix C ou un event), inutile de continuer
            if d2._cachedClass then return end
            local isPlayer = (d2.unitType == "ENEMY_PLAYER" or d2.unitType == "FRIENDLY_PLAYER")
            if not isPlayer or not d2.unit then return end
            -- RefreshUnitColors appelle SafeUnitClass (Fix A : classID → GetClassInfo)
            -- puis UpdateFill si la classe est résolue.
            pcall(SP.Orb.RefreshUnitColors, SP.Orb, d2, d2.unit, d2._displayRatio or 1)
        end)
    end
    _classRetry(0.5, true)   -- premier retry : masquage Blizzard + classe
    _classRetry(2.0, false)  -- deuxième retry : zone lente
    _classRetry(6.0, false)  -- troisième retry : instance / chargement long

    -- Diagnostic visible : message pour les 5 premières sphères créées
    SP._diagPlates = (SP._diagPlates or 0) + 1
    if SP._diagPlates <= 5 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cFF00FF88[SP]|r Orbe #%d créé — %s [%s] FL=%s",
            SP._diagPlates, unit, unitType,
            tostring(data.root and data.root:GetFrameLevel())))
    end

    -- Initialiser les modules
    pcall(SP.Auras.Init,       SP.Auras, data)
    pcall(SP.Auras.UpdateUnit, SP.Auras, data, unit, nil)

    -- CastBar : capturer le retour pour garantir data.castbar après Create()
    do
        local ok_cb, cb_result = pcall(SP.CastBar.Create, SP.CastBar, data)
        if ok_cb and cb_result then
            data.castbar = cb_result  -- double-sécurité : Create() l'assigne déjà
        elseif not ok_cb then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cFFFF4444[SP]|r CastBar.Create ERREUR %s : %s",
                unit, tostring(cb_result)))
        end
    end

    if SP.Quest then
        pcall(SP.Quest.CreateWidget, SP.Quest, data)
        pcall(SP.Quest.UpdateUnit,   SP.Quest, data, unit)
    end

    -- Mise à jour initiale complète
    -- Une frame recyclee depuis le pool garde ses regions, mais pas forcement
    -- les derniers reglages live (alphas FX, ombres, bordure, visibilite).
    pcall(SP.Orb.SoftUpdate, SP.Orb, data, unit)

    pcall(SP.UpdateHealth,      SP, unit, data)
    pcall(SP.Orb.UpdateName,    SP.Orb, data, unit)
    pcall(SP.Orb.UpdateLevelText, SP.Orb, data, unit)
    pcall(SP.Orb.UpdateElite,   SP.Orb, data, unit)
    pcall(SP.Orb.UpdateCombat,  SP.Orb, data, unit)
    pcall(SP.Orb.UpdatePower,   SP.Orb, data, unit)
    pcall(SP.Orb.UpdateRaidMark,SP.Orb, data, unit)
    pcall(SP.Orb.SetTargetGlow, SP.Orb, data, SP:SafeUnitIsUnit(unit, "target"))
    pcall(SP.Orb.SetFocusGlow,  SP.Orb, data, SP:SafeUnitIsUnit(unit, "focus"))
    pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, cfg)

    -- Cast en cours au moment de l'ajout
    local ok1, cname = pcall(UnitCastingInfo, unit)
    if ok1 and cname then
        pcall(SP.CastBar.StartCast, SP.CastBar, data, unit, false)
    else
        local ok2, chname = pcall(UnitChannelInfo, unit)
        if ok2 and chname then
            pcall(SP.CastBar.StartCast, SP.CastBar, data, unit, true)
        end
    end

    -- iLvL : queue inspection si joueur niveau max, hors cache
    if SP.Inspect and SP.Inspect.Queue then
        pcall(SP.Inspect.Queue, SP.Inspect, unit)
    end

    SP:Debug(string.format("PLATE_OK %s [%s]", unit, unitType))
    if _spdbgT0 and SP.SPDebug then
        SP.SPDebug:Track("Core.OnPlateAdded", debugprofilestop() - _spdbgT0, { plates = SP.SPDebug:CountPlates() })
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SUPPRESSION D'UNE PLAQUE (NAME_PLATE_UNIT_REMOVED)
-- ─────────────────────────────────────────────────────────────────────────────
function SP:OnPlateRemoved(unit)
    local _spdbgT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil
    if SP.SPDebug then SP.SPDebug:Count("Core.OnPlateRemoved", "events", 1) end
    local data = SP.Plates[unit]
    if data then
        if SP.PlayerContextMenu and SP.PlayerContextMenu.Detach then
            pcall(SP.PlayerContextMenu.Detach, SP.PlayerContextMenu, data, unit)
        end
        if SP.RaidMarkerMenu and SP.RaidMarkerMenu.Detach then
            pcall(SP.RaidMarkerMenu.Detach, SP.RaidMarkerMenu, data, unit)
        end
        pcall(SP.Auras.RemoveAll, SP.Auras, data)
        -- Masquer explicitement les frames castbar AVANT Reset() (sécurité)
        if data.castbar then
            local cb = data.castbar
            -- Désenregistrer le watcher avant tout (v9.0)
            if cb.watcher then
                pcall(cb.watcher.UnregisterAllEvents, cb.watcher)
                cb.watcher = nil
            end
            if cb.cd       then pcall(cb.cd.Hide,            cb.cd)               end
            if cb.glowTex  then pcall(cb.glowTex.SetAlpha,   cb.glowTex,  0)      end
            if cb.headTex  then pcall(cb.headTex.SetAlpha,   cb.headTex,  0)      end
            if cb.trailTex then pcall(cb.trailTex.SetAlpha,  cb.trailTex, 0)      end
            if cb.flashTex then pcall(cb.flashTex.SetAlpha,  cb.flashTex, 0)      end
        end
        if SP.CastBar then pcall(SP.CastBar.Reset, SP.CastBar, data) end
        if data.root then
            pcall(data.root.Hide, data.root)
            -- Empêcher que le root traine en mémoire graphique
            pcall(data.root.ClearAllPoints, data.root)
        end
        -- Restaurer l'UnitFrame Blizzard UNIQUEMENT si pas en refresh
        if not SP._isRefreshing then
            if data.plate and data.plate.UnitFrame then
                pcall(data.plate.UnitFrame.SetAlpha, data.plate.UnitFrame, 1)
            end
        end
    end
    SP.Plates[unit]      = nil
    SP.ActiveUnits[unit] = nil
    SP.ActiveOrbData[unit] = nil
    
    -- Retourner au pool
    if data then
        pcall(SP.Orb.Release, SP.Orb, data)
    end
    if _spdbgT0 and SP.SPDebug then
        SP.SPDebug:Track("Core.OnPlateRemoved", debugprofilestop() - _spdbgT0, { plates = SP.SPDebug:CountPlates() })
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MASQUER LES ÉLÉMENTS BLIZZARD
--  Appelé depuis OnPlateAdded. SetAlpha(0) sur le UnitFrame entier +
--  sur chaque sous-élément connu pour résister aux mises à jour WoW.
--  HookScript("OnShow") empêche WoW de les restaurer au changement de cible.
--  ⚠️  On ne casse pas l'interactivité : EnableMouse reste intact.
-- ─────────────────────────────────────────────────────────────────────────────
function SP:HideBlizzardElements(plate)
    if not plate then return end

    -- ── Helper : masquer un frame/region et accrocher son OnShow ─────────────
    local function safeHide(f)
        if not f then return end
        -- Ne jamais cacher nos propres frames SP
        if f._isSPFrame then return end
        if type(f.SetAlpha) == "function" then
            pcall(f.SetAlpha, f, 0)
        end
        -- Hook OnShow permanent : WoW Midnight restaure parfois des éléments
        -- lors d'un changement de cible ou d'état de combat.
        if not f._spHooked and type(f.HookScript) == "function" then
            f._spHooked = true
            pcall(f.HookScript, f, "OnShow", function(e)
                if not e._isSPFrame then pcall(e.SetAlpha, e, 0) end
            end)
        end
    end

    -- ── Récursion sur tous les enfants (frames + regions) ────────────────────
    -- Profondeur max 3 niveaux : plate → UnitFrame → sous-éléments → textures
    --
    -- RÈGLE CRITIQUE : si un enfant a _isSPFrame = true, c'est notre root frame
    -- (ou un descendant marqué). On NE le cache PAS et on NE récurse PAS dedans.
    -- Sans cette garde, hideChildren(root, 1) s'appelle et cache orbFrame, hpBar,
    -- overlayOrbFrame, etc. → tout devient invisible malgré les orbes créés.
    local function hideChildren(parent, depth)
        if depth > 5 then return end
        -- Frames enfants
        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if ok and children then
            for _, child in ipairs(children) do
                if not child._isSPFrame then
                    -- Frame Blizzard → cacher + hook + récurser dedans
                    safeHide(child)
                    hideChildren(child, depth + 1)
                end
                -- Frame SP (_isSPFrame = true) → ignoré complètement
                -- (ni safeHide ni hideChildren — ses enfants sont tous SP aussi)
            end
        end
        -- Regions (textures, fontstrings) directement sur ce frame
        local ok2, regions = pcall(function() return {parent:GetRegions()} end)
        if ok2 and regions then
            for _, r in ipairs(regions) do
                if r and type(r.SetAlpha) == "function" then
                    pcall(r.SetAlpha, r, 0)
                end
            end
        end
    end

    hideChildren(plate, 0)
end

function SP:ReclassifyUnit(unit)
    local old = SP.ActiveUnits[unit]
    local new = SP:GetUnitType(unit)
    if new == old then return end
    SP:Debug("RECLASSIFY " .. unit .. " : " .. tostring(old) .. " → " .. tostring(new))
    SP._isRefreshing = true
    SP:OnPlateRemoved(unit)
    SP._isRefreshing = false
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit) then
        SP:OnPlateAdded(unit)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  REFRESH INTELLIGENT — SANS TIMER (v7.2)
--
--  Principe :
--   1. Soft-update si taille inchangée → zéro flicker, instantané
--   2. Hard-rebuild si taille change → supprimer + recréer IMMÉDIATEMENT
--      (la plate WoW est toujours là, pas besoin d'attendre)
-- ─────────────────────────────────────────────────────────────────────────────
function SP:RefreshAll()
    local _spdbgT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil
    if SP.SPDebug then SP.SPDebug:Count("Core.RefreshAll", "refreshes", 1) end
    local toRebuild = {}

    for unit, data in pairs(SP.Plates) do
        local cfg = SP:GetCfg(data.unitType)
        if (cfg.size or 64) ~= data.orbSize then
            toRebuild[unit] = true
        else
            -- Invalider le cache couleur fill pour forcer un recalcul complet.
            -- Sans ça, un changement de cfg.fillR ne serait visible qu'au prochain
            -- event HP (ou poll 0.5s) si le cache _lastFillR est encore valide.
            data._lastFillR = nil
            data._lastFillG = nil
            data._lastFillB = nil
            -- Soft-update immédiat sans toucher aux frames
            pcall(SP.Orb.SoftUpdate, SP.Orb, data, unit)
        end
    end

    -- Rebuild pour les changements de taille — SANS timer
    if next(toRebuild) then
        SP._isRefreshing = true

        -- Supprimer les orbes concernés (les plates WoW restent intactes)
        for unit in pairs(toRebuild) do
            SP:OnPlateRemoved(unit)
        end

        -- Reconstruire immédiatement (la plate frame est toujours là)
        -- Note: UnitExists() est peu fiable pour les tokens nameplate en WoW Midnight
        for unit in pairs(toRebuild) do
            if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
                local plate = C_NamePlate.GetNamePlateForUnit(unit)
                if plate then
                    SP:OnPlateAdded(unit)
                end
            end
        end

        SP._isRefreshing = false
    end

    if SP.Preview then SP.Preview:Refresh() end
    if _spdbgT0 and SP.SPDebug then
        SP.SPDebug:Track("Core.RefreshAll", debugprofilestop() - _spdbgT0, { refresh = true, plates = SP.SPDebug:CountPlates() })
    end
end

-- Rebuild total (changement de zone, /sp reload)
function SP:HardRefreshAll()
    local _spdbgT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil
    if SP.SPDebug then SP.SPDebug:Count("Core.HardRefreshAll", "refreshes", 1) end
    SP:Debug("HardRefreshAll")

    -- Reset pack mode pour éviter des plaques bloquées dans un état réduit
    SP._packMode       = false
    SP._packPlateCount = 0
    if SP.PackOrb then pcall(SP.PackOrb.HideAll, SP.PackOrb) end

    -- Snapshot des unités connues
    local snap = {}
    for unit in pairs(SP.Plates) do snap[unit] = true end

    SP._isRefreshing = true
    for unit in pairs(snap) do SP:OnPlateRemoved(unit) end
    SP._isRefreshing = false

    -- Délai pour laisser WoW recréer les nameplates après changement de zone
    C_Timer.After(0.15, function()
        if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
        local plates = C_NamePlate.GetNamePlates(false)
        if not plates then return end
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken
            -- UnitExists() peu fiable pour les tokens nameplate en WoW Midnight
            -- On se fie à GetNamePlates() pour la liste valide
            if unit then
                SP:OnPlateAdded(unit)
            end
        end
        -- Retenter les unités connues absent de GetNamePlates
        for unit in pairs(snap) do
            if not SP.Plates[unit] then
                -- Vérifier la plate frame directement plutôt qu'UnitExists
                local okp, plate2 = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                if okp and plate2 then
                    SP:OnPlateAdded(unit)
                end
            end
        end
    end)
    if _spdbgT0 and SP.SPDebug then
        SP.SPDebug:Track("Core.HardRefreshAll", debugprofilestop() - _spdbgT0, { refresh = true, plates = SP.SPDebug:CountPlates() })
    end
end

-- Force-update d'une sphère spécifique (sans changer de cible)
function SP:ForceUpdate(unit)
    local data = SP.Plates[unit]
    if not data then return end
    SP:UpdateHealth(unit, data)
    SP.Orb:UpdateName(data, unit)
    SP.Orb:UpdateLevelText(data, unit)
    SP.Orb:UpdateElite(data, unit)
    SP.Orb:UpdateCombat(data, unit)
    SP.Orb:UpdatePower(data, unit)
    SP.Orb:UpdateRaidMark(data, unit)
    SP.Auras:UpdateUnit(data, unit, nil)
    SP.Orb:ApplySphereVisibility(data, SP:GetCfg(data.unitType))
    SP:Debug("ForceUpdate → " .. unit)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SANTÉ — UpdateHealth
--  WoW Midnight 12.x : UnitHealth/UnitHealthMax sont "secret number tainted".
--  Toute arithmétique Lua crashe. SetValue/SetMinMaxValues (C API) ACCEPTENT
--  les valeurs taintées — le moteur C calcule le ratio en interne.
--  → passe directement les tainted values au StatusBar data.hpBar.
--  → OnSizeChanged (Orb.lua Create) tente d'extraire un ratio clean pour
--    lerp + effets visuels si h est non-tainté.
-- ─────────────────────────────────────────────────────────────────────────────
function SP:UpdateHealth(unit, data)
    local _spdbgT0 = (SP.SPDebug and debugprofilestop and debugprofilestop()) or nil
    data = data or SP.Plates[unit]
    if not data or not unit or not data.hpBar then return end

    -- ── 1. Driver HP visuel — passer par UnitHealthPercent quand possible ─────
    -- En Midnight, le couple UnitHealth/UnitHealthMax peut ne pas piloter notre
    -- StatusBar custom malgré le pcall. UnitHealthPercent + ScaleTo100 donne une
    -- valeur C-side directement compatible avec une barre 0..100, sans division Lua.
    local visualDriven = false
    data._hpDriver = "none"
    local okPct = pcall(function()
        if type(UnitHealthPercent) ~= "function" then return end
        if not (CurveConstants and CurveConstants.ScaleTo100) then return end
        local immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
        data.hpBar:SetMinMaxValues(0, 100, immediate)
        data.hpBar:SetValue(UnitHealthPercent(unit, false, CurveConstants.ScaleTo100), immediate)
        data._hpDriver = "UnitHealthPercent.ScaleTo100"
        visualDriven = true
    end)

    if not okPct or not visualDriven then
        -- Fallback historique : accepte parfois les secret numbers en C-side.
        local okRaw = pcall(function()
            local immediate = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
            data.hpBar:SetMinMaxValues(0, UnitHealthMax(unit), immediate)
            data.hpBar:SetValue(UnitHealth(unit), immediate)
            data._hpDriver = "UnitHealth.raw"
        end)
        if not okRaw then data._hpDriver = "failed" end
    end

    -- ── 2. Ratio propre — pour les effets visuels (couleur fill, glow lowHP) ───
    -- Tentative GetHPRatio (scratch StatusBar + SetFormattedText escape).
    local ok, ratio = pcall(SP.GetHPRatio, SP, unit)

    if ok and type(ratio) == "number" then
        if data.targetHP == nil then
            -- Premier appel : affichage direct sans lerp (évite le fondu au noir)
            data.targetHP  = ratio
            data.displayHP = ratio
            pcall(SP.Orb.UpdateFill, SP.Orb, data, ratio)
        else
            -- Appels suivants : le lerp OnUpdate (60 FPS) gère l'interpolation
            data.targetHP = ratio
        end
    else
        local cfg = data.unitType and SP:GetCfg(data.unitType)
        if cfg and cfg.fill_color_mode == "progressive" then
            pcall(SP.Orb.UpdateFill, SP.Orb, data, data.displayHP or data.targetHP)
        end
    end

    pcall(SP.Orb.UpdateLevelText, SP.Orb, data, unit)
    if _spdbgT0 and SP.SPDebug then
        SP.SPDebug:Track("Core.UpdateHealth", debugprofilestop() - _spdbgT0)
    end
    SP:Debug("UpdateHealth " .. tostring(unit) .. " → hpBar updated, ratio=" .. tostring(ok and ratio or "err"))
end

-- ─────────────────────────────────────────────────────────────────────────────
--  GLOWS CIBLE / FOCUS
-- ─────────────────────────────────────────────────────────────────────────────
function SP:UpdateAllGlows()
    for unit, data in pairs(SP.Plates) do
        SP.Orb:SetTargetGlow(data, SP:SafeUnitIsUnit(unit, "target"))
        SP.Orb:SetFocusGlow(data,  SP:SafeUnitIsUnit(unit, "focus"))
        pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, SP:GetCfg(data.unitType))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  COMMANDES SLASH
-- ─────────────────────────────────────────────────────────────────────────────
-- /snp et /sp tous les deux enregistrés (évite conflits potentiels)
SLASH_SPHEREPLATES1 = "/snp"
SLASH_SPHEREPLATES2 = "/sphereplates"
SLASH_SPHEREPLATES3 = "/sp"
SlashCmdList["SPHEREPLATES"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    -- ── Profils ──────────────────────────────────────────────────────────────
    if cmd == "profils" or cmd == "profiles" then
        if not SP.Profiles then SP:Print("Module Profiles non chargé."); return end
        local list    = SP.Profiles:GetList()
        local current = SP.Profiles:GetCurrentName()
        SP:Print("=== Profils (" .. #list .. ") ===")
        for _, n in ipairs(list) do
            local mark = (n == current) and " |cFF00FF00[actif]|r" or ""
            SP:Print("  • " .. n .. mark)
        end

    elseif cmd:sub(1, 7) == "profil " then
        if not SP.Profiles then SP:Print("Module Profiles non chargé."); return end
        local name = strtrim(cmd:sub(8))
        if #name == 0 then SP:Print("Usage: /snp profil <nom>"); return end
        -- Correspondance insensible à la casse
        local list = SP.Profiles:GetList()
        local match = nil
        for _, n in ipairs(list) do
            if n:lower() == name:lower() then match = n; break end
        end
        if not match then
            SP:Print("|cFFFF4444Profil introuvable : " .. name .. "|r")
        else
            local ok, err = SP.Profiles:Load(match)
            if ok then
                SP:Print("Profil chargé : |cFF00FF00" .. match .. "|r")
            else
                SP:Print("|cFFFF4444Erreur : " .. tostring(err) .. "|r")
            end
        end

    -- ── Perf ─────────────────────────────────────────────────────────────────
    elseif cmd == "perf" then
        if SP.SPDebug then SP.SPDebug:Open("overview")
        elseif SP.Profiler then SP.Profiler:TogglePanel() end

    elseif cmd == "logs" then
        if SP.SPDebug then SP.SPDebug:Open("logs"); return end
        -- Dump rapide des derniers logs dans le chat
        if not (SP.Log and SP.Log:IsEnabled()) then
            SP:Print("|cFFFFAA00Logs désactivés. Activer dans /snp > Modules.|r")
        else
            local entries = SP.Log:GetEntries({max=20})
            if #entries == 0 then
                SP:Print("Aucun log enregistré.")
            else
                SP:Print("=== Derniers logs SphereNameplates ===")
                local COLS = SP.Log.LEVEL_COLORS or {}
                for i = #entries, 1, -1 do
                    local e = entries[i]
                    local col = COLS[e.level] or "|cFFFFFFFF"
                    SP:Print(string.format("[%s] %s%s|r [%s] %s",
                        e.date or "??:??:??", col, e.level or "?", e.module or "?", e.msg or ""))
                end
            end
        end

    elseif cmd == "spdebug" or cmd == "debugui" then
        if SP.SPDebug then SP.SPDebug:Open("overview") end

    elseif cmd == "uilab" or cmd == "psuilab" then
        if SP.UIPlumber and SP.UIPlumber.ToggleUILab then
            local ok, err = pcall(SP.UIPlumber.ToggleUILab, SP.UIPlumber)
            if not ok then SP:Print("PSUI Lab erreur: " .. tostring(err)) end
        else
            SP:Print("PSUI Lab indisponible.")
        end

    elseif cmd == "reset" then
        if SP.dbObj then SP.dbObj:ResetProfile() end
        SP:Print("Profil réinitialisé.")

    elseif cmd == "reload" then
        SP:HardRefreshAll()
        SP:Print("Rechargé.")

    elseif cmd == "version" then
        SP:Print("v" .. SP.Version)

    elseif cmd == "preview" then
        if SP.Preview then SP.Preview:Open() end

    elseif cmd == "debug" or cmd == "debug on" then
        if SP.db then SP.db.debugMode = (cmd == "debug on") and true or (not SP.db.debugMode) end
        SP:Print("Debug : " .. ((SP.db and SP.db.debugMode) and "|cFF00CCFFon|r" or "off"))

    elseif cmd == "debug off" then
        if SP.db then SP.db.debugMode = false end
        SP:Print("Debug off.")

    elseif cmd == "plates" then
        local count = 0
        for unit, data in pairs(SP.Plates) do
            count = count + 1
            local hp   = data.targetHP  or 0
            local disp = data.displayHP or 0
            SP:Print(string.format("%s [%s] HP=%.0f%% disp=%.0f%% size=%s",
                unit, data.unitType or "?",
                hp * 100, disp * 100, tostring(data.orbSize)))
        end
        SP:Print("Total : " .. count .. " sphère(s)")

    elseif cmd == "layers" then
        -- Diagnostic Codex : trace alpha/effective alpha de toutes les couches
        SP:Print("=== /snp layers : trace des couches visuelles ===")
        local n = 0
        for unit, data in pairs(SP.Plates) do
            n = n + 1
            local cfg = SP:GetCfg(data.unitType) or {}
            SP:Print(string.format("--- %s [%s] ---", unit, data.unitType or "?"))
            SP:Print(string.format("  fade=%s  start=%s  end=%s  min=%s",
                tostring(cfg.fade_enabled), tostring(cfg.fade_start),
                tostring(cfg.fade_end), tostring(cfg.fade_min_alpha)))
            SP:Print(string.format("  nameDistance=%s mode=%s alpha=%.2f pack=%.2f dist=%s max=%s full=%s hidden=%s",
                tostring(cfg.name_distance_enabled),
                tostring(cfg.name_distance_mode),
                tonumber(data._nameDistanceAlpha) or 1,
                tonumber(data._packNameAlpha) or 1,
                data._nameDistanceLastDist and string.format("%.1f", data._nameDistanceLastDist) or "n/a",
                tostring(cfg.name_distance_max),
                tostring(cfg.name_fade_full),
                tostring(cfg.name_fade_hidden)))
            local rA = data.root and data.root:GetAlpha() or "nil"
            local rE = data.root and data.root.GetEffectiveAlpha and data.root:GetEffectiveAlpha() or "n/a"
            local pA = data.plate and data.plate:GetAlpha() or "nil"
            local pE = data.plate and data.plate.GetEffectiveAlpha and data.plate:GetEffectiveAlpha() or "n/a"
            SP:Print(string.format("  root α=%.2f  effA=%.2f  | plate α=%.2f  effA=%.2f",
                tonumber(rA) or 0, tonumber(rE) or 0, tonumber(pA) or 0, tonumber(pE) or 0))
            SP:Print(string.format("  bg α=%s  R=%s G=%s B=%s",
                tostring(cfg.bgAlpha), tostring(cfg.bgR), tostring(cfg.bgG), tostring(cfg.bgB)))
            SP:Print(string.format("  emptyClear=%s  emptyShade=%s shadeA=%s",
                tostring(cfg.orb_empty_clear_enabled ~= false),
                tostring(cfg.orb_empty_shade_enabled ~= false),
                tostring(cfg.orb_empty_shade_alpha)))
            SP:Print("  hpDriver=" .. tostring(data._hpDriver or "nil"))
            if data.hpBar then
                local okBar, minv, maxv = pcall(data.hpBar.GetMinMaxValues, data.hpBar)
                local okVal, val = pcall(data.hpBar.GetValue, data.hpBar)
                SP:Print("  hpBar min=" .. tostring(okBar and minv or "err") ..
                    " max=" .. tostring(okBar and maxv or "err") ..
                    " value=" .. tostring(okVal and val or "err"))
            end
            SP:Print(string.format("  shadow α=%s  shadow2 α=%s (enabled=%s)",
                tostring(cfg.orb_shadow_alpha), tostring(cfg.orb_shadow2_alpha), tostring(cfg.orb_shadow2_enabled)))
            if data.bgTex      then SP:Print("  bgTex.α="      .. tostring(data.bgTex:GetAlpha())) end
            if data.hpEffectMask then
                SP:Print("  hpEffectMask h=" .. tostring(data.hpEffectMask:GetHeight()))
            end
            if data.hpFxClipFrame then
                SP:Print("  hpFxClip h=" .. tostring(data.hpFxClipFrame:GetHeight()) ..
                    " shown=" .. tostring(data.hpFxClipFrame:IsShown()))
            end
            if data.emptyShadeTex then
                SP:Print(string.format("  emptyShade shown=%s frameA=%s texA=%s h=%s fl=%s",
                    tostring(data.emptyShadeFrame and data.emptyShadeFrame:IsShown()),
                    tostring(data.emptyShadeFrame and data.emptyShadeFrame:GetAlpha()),
                    tostring(data.emptyShadeTex:GetAlpha()),
                    tostring(data.emptyShadeTex:GetHeight()),
                    tostring(data.emptyShadeFrame and data.emptyShadeFrame:GetFrameLevel() or "nil")))
            end
            if data.shadowTex  then SP:Print("  shadowTex.α="  .. tostring(data.shadowTex:GetAlpha())) end
            if data.shadowTex2 then SP:Print("  shadowTex2.α=" .. tostring(data.shadowTex2:GetAlpha())) end
            if data.singleGlow then SP:Print("  singleGlow.α=" .. tostring(data.singleGlow:GetAlpha())) end
            if data.castbar and data.castbar.cd then
                SP:Print("  castbar.cd α=" .. tostring(data.castbar.cd:GetAlpha()))
            end
            local circ = data._cb_circ
            if circ then
                local v8Shown = 0
                if circ.v8Segments then
                    for _, seg in ipairs(circ.v8Segments) do
                        if seg.fill and seg.fill:GetAlpha() > 0 then v8Shown = v8Shown + 1 end
                    end
                end
                SP:Print(string.format("  cb_circ preset=%s  v8=%s/%s  owRing=%s  owGlow=%s  techRing=%s  techGlow=%s",
                    tostring(circ.preset),
                    tostring(v8Shown),
                    tostring(circ.v8Count or "nil"),
                    circ.owRing and tostring(circ.owRing:GetAlpha()) or "nil",
                    circ.owGlow and tostring(circ.owGlow:GetAlpha()) or "nil",
                    circ.techRing and tostring(circ.techRing:GetAlpha()) or "nil",
                    circ.techGlow and tostring(circ.techGlow:GetAlpha()) or "nil"))
            end
            SP:Print(string.format("  ignore_parent_alpha=%s", tostring(cfg.ignore_parent_alpha)))
        end
        if n == 0 then SP:Print("Aucune plate active.") end

    elseif cmd == "layerlab" or cmd == "lab" then
        if SP.Orb and SP.Orb.ToggleLayerLab then
            local ok, err = pcall(SP.Orb.ToggleLayerLab, SP.Orb)
            if not ok then SP:Print("LayerLab erreur: " .. tostring(err)) end
        else
            SP:Print("LayerLab indisponible: Orb non charge.")
        end

    elseif cmd == "colors" then
        -- Diagnostic classe/couleur de chaque plate active (contexte clean → SafeUnitClass fiable)
        SP:Print("=== /snp colors : diagnostic couleur classe ===")
        local n = 0
        for unit, data in pairs(SP.Plates) do
            n = n + 1
            local cfg = SP:GetCfg(data.unitType) or {}
            local uname = "?"
            pcall(function() uname = UnitName(unit) or "?" end)
            SP:Print(string.format("--- %s [%s] %s ---", unit, data.unitType or "?", uname))
            -- Classe cached
            SP:Print(string.format("  _cachedClass=%s", tostring(data._cachedClass)))
            -- SafeUnitClass live (contexte propre ici)
            local isPlayer = (data.unitType == "ENEMY_PLAYER" or data.unitType == "FRIENDLY_PLAYER")
            local liveCls = nil
            pcall(function()
                local okP, ip = true, SP.SafeUnitIsPlayer and SP:SafeUnitIsPlayer(unit) or false
                local okC, _, c = pcall(UnitClass, unit)
                SP:Print(string.format("  UnitIsPlayer=%s/%s  UnitClass=%s", tostring(okP), tostring(ip), tostring(c)))
                if okP and ip and okC and c then liveCls = c end
            end)
            SP:Print(string.format("  isPlayer(unitType)=%s  LiveClass=%s", tostring(isPlayer), tostring(liveCls)))
            -- Couleur fill actuelle (lue depuis fillTex, ResolveFillColor est local à Orb.lua)
            local fr, fg, fb = 0, 0, 0
            if data.fillTex then
                pcall(function() fr, fg, fb = data.fillTex:GetVertexColor() end)
            end
            -- fill_color_mode et saturation
            SP:Print(string.format("  fill_color_mode=%s  fill_saturation=%.2f",
                tostring(cfg.fill_color_mode), tonumber(cfg.fill_saturation) or 1))
            -- Vertex color actuel de fillTex
            if data.fillTex then
                local r, g, b = 0, 0, 0
                pcall(function() r, g, b = data.fillTex:GetVertexColor() end)
                SP:Print(string.format("  fillTex.vertex=(%.2f,%.2f,%.2f)", r, g, b))
            end
            if data.galaxy1 then
                local r, g, b = 0, 0, 0
                pcall(function() r, g, b = data.galaxy1:GetVertexColor() end)
                SP:Print(string.format("  galaxy1.vertex=(%.2f,%.2f,%.2f)", r, g, b))
            end
        end
        if n == 0 then SP:Print("Aucune plate active.") end

    elseif cmd == "pack" then
        -- Diagnostic pack mode : état courant, clusters, ranks par plate
        local db = SP.db or {}
        SP:Print("=== /snp pack : diagnostic mode densité ===")
        SP:Print(string.format("  Activé=%s  packMode=%s  plates=%d  seuil=%d",
            tostring(db.pack_mode_enabled),
            tostring(SP._packMode),
            SP._packPlateCount or 0,
            db.pack_threshold or 6))
        for unit, data in pairs(SP.Plates) do
            local uname = "?"
            pcall(function() uname = UnitName(unit) or "?" end)
            SP:Print(string.format("  %s [%s] %s  rank=%d  scale=%.2f  alpha=%.2f  fadeA=%.2f",
                unit, data.unitType or "?", uname,
                data._packRank or 3,
                data._packScale or 1.0,
                data._packAlpha or 1.0,
                data._fadeAlpha or 1.0))
        end
        -- Pack Orb debug
        if SP.PackOrb then
            pcall(SP.PackOrb.DebugPrint, SP.PackOrb)
        end

    elseif cmd == "enable" or cmd == "on" then
        if SP.db then SP.db.addonEnabled = true end
        SP._orbErrCount = 0
        SP:HardRefreshAll()
        SP:Print("|cFF00FF00Addon activé de force.|r")

    elseif cmd == "disable" or cmd == "off" then
        if SP.db then SP.db.addonEnabled = false end
        SP._isRefreshing = true
        for unit in pairs(SP.Plates) do SP:OnPlateRemoved(unit) end
        SP._isRefreshing = false
        SP:Print("Addon désactivé.")

    elseif cmd == "status" then
        SP:Print("=== SphereNameplates Status ===")
        SP:Print("Initialized : " .. tostring(SP.Initialized))
        SP:Print("db ok : " .. tostring(SP.db ~= nil))
        SP:Print("addonEnabled : " .. tostring(SP.db and SP.db.addonEnabled))
        SP:Print("Plates actives : " .. (function()
            local n = 0; for _ in pairs(SP.Plates) do n=n+1 end; return n
        end)())
        SP:Print("Erreurs orbe : " .. tostring(SP._orbErrCount or 0))
        -- Tester création basique de frame
        local ok, err = pcall(function()
            local f = CreateFrame("Frame", nil, UIParent)
            f:SetSize(10,10)
            local t = f:CreateTexture()
            t:SetAllPoints(f)
            -- Tester MaskTexture
            local m = f:CreateMaskTexture()
            m:SetAllPoints(f)
            -- Tester AnimationGroup sur texture
            local ag = t:CreateAnimationGroup()
            ag:Stop()
            f:Hide()
        end)
        SP:Print("API test : " .. (ok and "|cFF00FF00OK|r" or "|cFFFF4444ÉCHEC : " .. tostring(err) .. "|r"))
        -- Test config ENEMY
        local cfg = SP:GetCfg("ENEMY")
        SP:Print("ENEMY cfg : enabled=" .. tostring(cfg.enabled) .. " size=" .. tostring(cfg.size))
        -- Test GetNamePlates
        if C_NamePlate and C_NamePlate.GetNamePlates then
            local plates = C_NamePlate.GetNamePlates(false)
            SP:Print("NamePlates WoW : " .. tostring(plates and #plates or "nil"))
        else
            SP:Print("|cFFFF4444C_NamePlate.GetNamePlates : ABSENT|r")
        end

    elseif cmd == "auras" then
        -- ── DIAGNOSTIC AURAS — INVENTAIRE API + SCAN BRUT ────────────────────
        -- But : confirmer QUELLES fonctions existent en runtime et ce qu'elles retournent.
        -- Aucun filtrage. Aucune transformation. Données brutes uniquement.
        SP:Print("=== AURAS DIAGNOSTIC ===")

        -- ── 1. Existence des APIs au niveau global ────────────────────────────
        local ua = _G["C_UnitAuras"]
        SP:Print("C_UnitAuras type   = " .. type(ua))
        if type(ua) == "table" then
            SP:Print("  .GetAuraSlots          = " .. type(ua.GetAuraSlots))
            SP:Print("  .GetAuraDataBySlot     = " .. type(ua.GetAuraDataBySlot))
            SP:Print("  .GetAuraDataByAuraInstanceID = " .. type(ua.GetAuraDataByAuraInstanceID))
            SP:Print("  .GetUnitAuras          = " .. type(ua.GetUnitAuras))
        end
        SP:Print("UnitAura (global)  = " .. type(_G["UnitAura"]))
        SP:Print("UnitDebuff (global)= " .. type(_G["UnitDebuff"]))
        SP:Print("UnitBuff   (global)= " .. type(_G["UnitBuff"]))

        -- ── 2. Scan brut sur chaque unité active ──────────────────────────────
        local count = 0
        for unit, data in pairs(SP.Plates) do
            count = count + 1
            SP:Print(string.format("--- unit=%s [%s] ---", unit, tostring(data.unitType)))

            -- Test GetAuraSlots
            if type(ua) == "table" and type(ua.GetAuraSlots) == "function" then
                -- Essai 1 : HARMFUL|INCLUDE_NAME_PLATE_ONLY
                local ok1, r1 = pcall(function()
                    return {ua.GetAuraSlots(unit, "HARMFUL|INCLUDE_NAME_PLATE_ONLY")}
                end)
                SP:Print("  GetAuraSlots HARMFUL|NP_ONLY : ok=" .. tostring(ok1)
                    .. " nrets=" .. (ok1 and tostring(#r1) or "err:"..tostring(r1)))
                if ok1 and r1 and #r1 > 0 then
                    SP:Print("    continuationToken=" .. tostring(r1[1])
                        .. " slots[2..n]=" .. tostring(#r1 - 1))
                end

                -- Essai 2 : HARMFUL seul
                local ok2, r2 = pcall(function()
                    return {ua.GetAuraSlots(unit, "HARMFUL")}
                end)
                SP:Print("  GetAuraSlots HARMFUL : ok=" .. tostring(ok2)
                    .. " nrets=" .. (ok2 and tostring(#r2) or "err:"..tostring(r2)))
                if ok2 and r2 and #r2 > 1 then
                    SP:Print("    continuationToken=" .. tostring(r2[1])
                        .. " slots=" .. tostring(#r2 - 1))
                    -- Lire la première aura brute sans toucher aux valeurs taintées
                    local slot1 = r2[2]
                    SP:Print("    premier slot=" .. tostring(slot1))
                    if slot1 and type(ua.GetAuraDataBySlot) == "function" then
                        local ok3, aura = pcall(ua.GetAuraDataBySlot, unit, slot1)
                        SP:Print("    GetAuraDataBySlot ok=" .. tostring(ok3))
                        if ok3 and type(aura) == "table" then
                            -- Lister les clés sans accéder aux valeurs taintées
                            local keys = {}
                            for k in pairs(aura) do keys[#keys+1] = tostring(k) end
                            SP:Print("    aura keys=" .. table.concat(keys, ","))
                            -- Champs non-taintés : name (string), icon (number/string)
                            local ok_n, nm = pcall(function() return tostring(aura.name) end)
                            local ok_i, ic = pcall(function() return tostring(aura.icon) end)
                            local ok_d, dn = pcall(function() return tostring(aura.dispelName) end)
                            SP:Print("    name=" .. (ok_n and nm or "TAINTED")
                                .. " icon=" .. (ok_i and ic or "TAINTED")
                                .. " dispelName=" .. (ok_d and dn or "TAINTED"))
                        elseif not ok3 then
                            SP:Print("    GetAuraDataBySlot ERREUR: " .. tostring(aura))
                        else
                            SP:Print("    aura=nil")
                        end
                    end
                end

                -- Essai 3 : HARMFUL|PLAYER
                local ok4, r4 = pcall(function()
                    return {ua.GetAuraSlots(unit, "HARMFUL|PLAYER")}
                end)
                SP:Print("  GetAuraSlots HARMFUL|PLAYER : ok=" .. tostring(ok4)
                    .. " nrets=" .. (ok4 and tostring(#r4) or "err:"..tostring(r4)))
                if ok4 and r4 then
                    SP:Print("    slots=" .. tostring(math.max(0, #r4 - 1)))
                end

            else
                SP:Print("  GetAuraSlots : NON DISPONIBLE")
            end

            -- Test GetUnitAuras (fallback)
            if type(ua) == "table" and type(ua.GetUnitAuras) == "function" then
                local ok5, r5 = pcall(ua.GetUnitAuras, unit, "HARMFUL", nil)
                SP:Print("  GetUnitAuras HARMFUL : ok=" .. tostring(ok5)
                    .. " type=" .. type(r5)
                    .. " count=" .. (type(r5) == "table" and tostring(#r5) or "n/a"))
            else
                SP:Print("  GetUnitAuras : NON DISPONIBLE")
            end

            if SP.Auras and type(SP.Auras.FetchAuras) == "function" then
                local function safeField(aura, key)
                    local ok, value = pcall(function() return aura[key] end)
                    if not ok or value == nil then return "nil" end
                    local okText, text = pcall(function() return tostring(value) end)
                    return okText and text or "TAINTED"
                end

                local okFetch, fetched = pcall(SP.Auras.FetchAuras, unit, "HARMFUL")
                SP:Print("  FetchAuras HARMFUL merged : ok=" .. tostring(okFetch)
                    .. " count=" .. (okFetch and type(fetched) == "table" and tostring(#fetched) or "n/a"))
                if okFetch and type(fetched) == "table" then
                    for i = 1, math.min(5, #fetched) do
                        local aura = fetched[i]
                        SP:Print("    #" .. i
                            .. " spellId=" .. safeField(aura, "spellId")
                            .. " dispel=" .. safeField(aura, "dispelName")
                            .. " source=" .. safeField(aura, "sourceUnit")
                            .. " player=" .. safeField(aura, "isFromPlayerOrPlayerPet")
                            .. " dur=" .. safeField(aura, "duration"))
                    end
                end
            end

            -- Test UnitDebuff legacy
            if type(_G["UnitDebuff"]) == "function" then
                local ok6, nm = pcall(_G["UnitDebuff"], unit, 1)
                SP:Print("  UnitDebuff(1) : ok=" .. tostring(ok6) .. " name=" .. tostring(nm))
            else
                SP:Print("  UnitDebuff : NON DISPONIBLE")
            end

            -- État interne : combien d'icônes sont actuellement affichées
            SP:Print("  auraIcons actives = " .. tostring(data.auraIcons and #data.auraIcons or "nil"))
            if data.segmentSlots then
                local shown = 0
                for _, slot in ipairs(data.segmentSlots) do
                    if slot.frame and slot.frame:IsShown() then shown = shown + 1 end
                end
                SP:Print("  segments visibles = " .. tostring(shown) .. "/5"
                    .. " ringCount=" .. tostring(data._ringAuraCount or 0))
            end

            if count >= 3 then
                SP:Print("(limité à 3 unités — approche-toi de plus)")
                break
            end
        end
        if count == 0 then
            SP:Print("|cFFFFAA00Aucune unité active — approche d'une cible d'abord.|r")
        end
        SP:Print("=== FIN DIAGNOSTIC AURAS ===")

    elseif cmd == "casttest" then
        -- Lance un arc de test de 5s sur TOUTES les sphères actives
        -- Commande : /snp casttest
        -- Utile pour valider le rendu sans avoir besoin d'un vrai sort
        local count = 0
        for unit, data in pairs(SP.Plates) do
            local ok, result = pcall(SP.CastBar.TestCast, SP.CastBar, data, 5.0)
            if ok and result then count = count + 1 end
        end
        if count == 0 then
            SP:Print("|cFFFFAA00Aucune sphère active. Approche d'une cible d'abord.|r")
        else
            SP:Print(string.format(
                "|cFF00FFFFTest CastBar lancé sur |cFFFFFF00%d|r orbe(s) — durée 5s.", count))
        end

    elseif cmd == "casttest_v8" then
        -- Test isolé du rendu CastBar V8 segments, sans modifier le profil.
        local count = 0
        for unit, data in pairs(SP.Plates) do
            data._forceCastbarV8 = true
            if data.castbar and not (data._cb_circ and data._cb_circ.v8Segments) then
                pcall(SP.CastBar.Reset, SP.CastBar, data)
                data.castbar    = nil
                data._cb_circ   = nil
                data._cb_sprite = nil
                data._cb_ccb    = nil
            end
            local ok, result = pcall(SP.CastBar.TestCast, SP.CastBar, data, 5.0)
            data._forceCastbarV8 = nil
            if ok and result then count = count + 1 end
        end
        if count == 0 then
            SP:Print("|cFFFFAA00Aucune sphère active. Approche d'une cible d'abord.|r")
        else
            SP:Print(string.format(
                "|cFF00FFFFTest CastBar V8 segments lancé sur |cFFFFFF00%d|r orbe(s) — durée 5s.", count))
        end

    elseif cmd:sub(1, 7) == "update " then
        local unit = cmd:sub(8)
        SP:ForceUpdate(unit)

    elseif cmd == "raidmark" then
        SP:Print("=== RAID MARKERS ===")
        local db = SP.db or {}
        local function markerText(token)
            if not token or not GetRaidTargetIndex then return "nil" end
            local ok, value = pcall(GetRaidTargetIndex, token)
            if not ok then return "err" end
            if value == nil then return "nil" end
            if canaccessvalue and not canaccessvalue(value) then return "secret" end
            return tostring(tonumber(value) or value)
        end
        SP:Print("enabled=" .. tostring(db.raidmark_global_enabled ~= false)
            .. " custom=" .. tostring(db.raidmark_custom_enabled ~= false)
            .. " pack=" .. tostring(db.raidmark_pack or "sign_mark")
            .. " position=" .. tostring(db.raidmark_position_mode or "sphere"))
        local count = 0
        for unit, data in pairs(SP.Plates or {}) do
            count = count + 1
            local okExists, exists = pcall(UnitExists, unit)
            local okName, uname = pcall(UnitName, unit)
            local okGUID, guid = pcall(UnitGUID, unit)
            local mark = markerText(unit)
            local alias = ""
            if UnitIsUnit then
                for _, token in ipairs({"target", "mouseover", "focus"}) do
                    local okSame, same = pcall(UnitIsUnit, unit, token)
                    if okSame and same then
                        alias = alias .. " " .. token .. "=" .. markerText(token)
                    end
                end
            end
            local dbg = data and data._raidMarkDebug or {}
            local shown = data and data.raidIconFrame and data.raidIconFrame:IsShown()
            SP:Print(tostring(unit)
                .. " type=" .. tostring(data and data.unitType or "?")
                .. " exists=" .. tostring(okExists and exists or "err")
                .. " name=" .. tostring(okName and uname or "?")
                .. " guid=" .. tostring(okGUID and guid or "?")
                .. " mark=" .. tostring(mark)
                .. alias
                .. " shown=" .. tostring(shown)
                .. " reason=" .. tostring(dbg.reason)
                .. " source=" .. tostring(dbg.source)
                .. " token=" .. tostring(dbg.token)
                .. " tex=" .. tostring(dbg.tex)
                .. " resolved=" .. tostring(dbg.mark))
            if count >= 8 then
                SP:Print("(limite a 8 unites)")
                break
            end
        end
        if count == 0 then SP:Print("Aucune nameplate active.") end
        SP:Print("=== FIN RAID MARKERS ===")

    elseif cmd == "hpcolor" then
        SP:Print("=== HP COLOR ===")
        local count = 0
        local function fmtColor(r, g, b, a)
            local ok, s = pcall(function()
                return string.format("%.2f/%.2f/%.2f/%.2f", r or 0, g or 0, b or 0, a or 0)
            end)
            return ok and s or "secret/blocked"
        end
        for unit, data in pairs(SP.Plates) do
            count = count + 1
            local cfg = SP:GetCfg(data.unitType) or {}
            local kind = (cfg.hpFormat == "absolute") and "absolute" or "percent"
            local mode
            local fr, fg, fb, fa
            if kind == "absolute" then
                mode = cfg.hp_absolute_color_mode or "fixed"
                fr, fg, fb, fa = cfg.hpAbsoluteTextR or cfg.hpTextR or 1, cfg.hpAbsoluteTextG or cfg.hpTextG or 1, cfg.hpAbsoluteTextB or cfg.hpTextB or 1, cfg.hpAbsoluteTextA or 1
            else
                mode = cfg.hp_percent_color_mode
                if mode == nil then mode = cfg.hp_color_dynamic and "dynamic" or "fixed" end
                fr, fg, fb, fa = cfg.hpPercentTextR or cfg.hpTextR or 1, cfg.hpPercentTextG or cfg.hpTextG or 1, cfg.hpPercentTextB or cfg.hpTextB or 1, cfg.hpPercentTextA or 1
            end
            local r, g, b, a, source, reason = SP:GetHPTextColor(data, unit, kind)
            local pr, pg, pb, pa, pSource, pReason = SP:GetHPTextColor(data, unit, "percent")
            local ar, ag, ab, aa, aSource, aReason = SP:GetHPTextColor(data, unit, "absolute")
            local liveColor = "nil"
            local liveSubColor = "nil"
            pcall(function()
                if data.levelText and data.levelText.GetTextColor then
                    local lr, lg, lb, la = data.levelText:GetTextColor()
                    liveColor = fmtColor(lr, lg, lb, la)
                end
                if data.hpSubText and data.hpSubText.GetTextColor then
                    local sr, sg, sb, sa = data.hpSubText:GetTextColor()
                    liveSubColor = fmtColor(sr, sg, sb, sa)
                end
            end)
            SP:Print(string.format(
                "%s [%s] fmt=%s kind=%s mode=%s source=%s reason=%s",
                unit,
                tostring(data.unitType),
                tostring(cfg.hpFormat),
                kind,
                tostring(mode),
                tostring(source),
                tostring(reason)))
            SP:Print("  fixed=" .. fmtColor(fr, fg, fb, fa) .. " final=" .. fmtColor(r, g, b, a) .. " live=" .. liveColor)
            SP:Print("  percent=" .. tostring(pSource) .. "/" .. tostring(pReason) .. " " .. fmtColor(pr, pg, pb, pa)
                .. " | absolute=" .. tostring(aSource) .. "/" .. tostring(aReason) .. " " .. fmtColor(ar, ag, ab, aa)
                .. " | hpSubLive=" .. liveSubColor)
        end
        if SP._hpColorTrace then
            local t = SP._hpColorTrace
            SP:Print("  trace hpcolor=" ..
                " unit=" .. tostring(t.unit) ..
                " type=" .. tostring(t.unitType) ..
                " kind=" .. tostring(t.kind) ..
                " mode=" .. tostring(t.mode) ..
                " source=" .. tostring(t.source) ..
                " reason=" .. tostring(t.reason) ..
                " setTextColor=" .. tostring(t.setTextColor) ..
                " err=" .. tostring(t.error))
        end
        if count == 0 then SP:Print("Aucune plate active.") end

    elseif cmd == "hptest" then
        -- Diagnostic complet de l'extraction HP sur toutes les plates actives
        SP:Print("=== HP TEST ===")
        local count = 0
        for unit, data in pairs(SP.Plates) do
            count = count + 1

            -- Test StatusBar scratch
            local barOK, barRatio = false, nil
            if _G["SPHPScratchBar"] then
                local bar = _G["SPHPScratchBar"]
                local ok1 = pcall(function()
                    bar:SetMinMaxValues(0, UnitHealthMax(unit))
                    bar:SetValue(UnitHealth(unit))
                end)
                if ok1 then
                    local ok2, ratio = pcall(function()
                        local w = bar:GetWidth()
                        local tex = bar:GetStatusBarTexture()
                        if not (w and w > 0 and tex) then return nil end
                        return tex:GetWidth() / w  -- peut crash sur taint → pcall attrape
                    end)
                    if ok2 and type(ratio) == "number" then
                        barRatio = ratio
                        barOK = true
                    end
                end
            end

            -- Test UnitHealthPercent (valeur tainted → escape via SetFormattedText)
            local pctOK, pctStr = false, "nil"
            local ok2, v2 = pcall(UnitHealthPercent, unit)
            if ok2 then
                local safePct = SP.UntaintNum and SP:UntaintNum(v2) or nil
                if safePct ~= nil then
                    pctOK = true
                    pctStr = string.format("%.1f", safePct)
                else
                    pctStr = "tainted"
                end
            end

            -- Test GetHPRatio complet
            local fullRatio = SP:GetHPRatio(unit)
            local cfg = SP:GetCfg(data.unitType)
            local pctMode = cfg and cfg.hp_percent_color_mode
            if pctMode == nil and cfg and cfg.hp_color_dynamic == true then pctMode = "dynamic" end
            local pctDynamic = (pctMode == "dynamic")
            local absDynamic = cfg and (cfg.hp_absolute_color_mode == "dynamic")

            -- barRatio et fullRatio sont déjà nettoyés (clean Lua numbers ou nil)
            local barPctStr  = barRatio  and string.format("%.0f", barRatio  * 100) or "nil"
            local ratioPctStr= fullRatio and string.format("%.0f", fullRatio * 100) or "nil"
            local tgtStr     = data.targetHP  and string.format("%.0f", data.targetHP  * 100) or "nil"
            local dispStr    = data.displayHP and string.format("%.0f", data.displayHP * 100) or "nil"
            local colorStr = "nil"
            pcall(function()
                if data.levelText and data.levelText.GetTextColor then
                    local r, g, b, a = data.levelText:GetTextColor()
                    colorStr = string.format("%.2f/%.2f/%.2f/%.2f", r or 0, g or 0, b or 0, a or 0)
                end
            end)

            SP:Print(string.format(
                "%s | bar=%s(%s%%) | pct=%s(%s) | ratio=%s%% | tgt=%s%% disp=%s%%",
                unit,
                tostring(barOK), barPctStr,
                tostring(pctOK), pctStr,
                ratioPctStr,
                tgtStr, dispStr))
            SP:Print(string.format(
                "  cfg=%s hpFormat=%s percentMode=%s legacyDynamic=%s pctDynamic=%s absMode=%s absDynamic=%s",
                tostring(data.unitType),
                tostring(cfg and cfg.hpFormat),
                tostring(pctMode),
                tostring(cfg and cfg.hp_color_dynamic),
                tostring(pctDynamic),
                tostring(cfg and cfg.hp_absolute_color_mode),
                tostring(absDynamic)))
            local levelTextValue = "nil"
            local hpSubTextValue = "nil"
            pcall(function()
                if data.levelText and data.levelText.GetText then
                    levelTextValue = tostring(data.levelText:GetText())
                end
            end)
            pcall(function()
                if data.hpSubText and data.hpSubText.GetText then
                    hpSubTextValue = tostring(data.hpSubText:GetText())
                end
            end)
            SP:Print(string.format(
                "  text='%s' hpSub='%s' levelShown=%s hpSubShown=%s showHP=%s hpUnder=%s",
                levelTextValue,
                hpSubTextValue,
                tostring(data.levelText and data.levelText:IsShown()),
                tostring(data.hpSubText and data.hpSubText:IsShown()),
                tostring(cfg and cfg.showHPAlsoInOrb),
                tostring(cfg and cfg.show_hp_under_maxlvl)))
            SP:Print("  levelText color=" .. colorStr)
        end
        if count == 0 then SP:Print("Aucune plate active.") end

    else
        SP.UI:Open()
    end
end
