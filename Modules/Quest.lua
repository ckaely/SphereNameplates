-------------------------------------------------------------------------------
-- SphereNameplates v6.0 — Modules/Quest.lua
-- Détection des PNJ liés à des quêtes actives
--
-- AMÉLIORATIONS v6.0 :
--   • Icône "!" dorée (questgivernormal) — reconnaissable immédiatement
--   • Nom en bleu (cfg.quest_color_name) — via data.isQuestUnit → UpdateName
--   • Son à l'apparition du PNJ de quête (cfg.quest_sound)
--   • Cache GUID (5s TTL) — évite les appels API répétitifs
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.Quest = {}

-- API quête (accès défensif)
local C_QuestLog_UnitIsRelated = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest

-- États de quête
-- AVAILABLE (2)  : PNJ offre une quête          → "!" doré
-- INCOMPLETE (3) : quête en cours, PNJ concerné → "!" tamisé
-- REWARD (4)     : quête à remettre             → "?" doré
local QUEST_STATE_AVAILABLE  = 2
local QUEST_STATE_INCOMPLETE = 3
local QUEST_STATE_REWARD     = 4

-- Icône "!" (questgivernormal) et "?" (ActiveQuestIcon = quête à rendre)
local QUEST_ICON_EXCLAIM = "Interface\\minimap\\tracking\\questgivernormal.blp"
local QUEST_ICON_TURNIN  = "Interface\\GossipFrame\\ActiveQuestIcon"

-- Son discret de détection quête (pitch de loot léger — non envahissant)
local QUEST_SOUND_ID = SOUNDKIT and SOUNDKIT.IG_QUEST_ITEM_PICKUP or 1363

-- Cache des PNJ déjà vérifiés
local unitQuestCache = {}   -- [unitGUID] = {state=num|bool, expiry=time}
local soundPlayedGuids = {} -- [unitGUID] = true   → son déjà joué pour ce GUID
local CACHE_TTL = 5.0

-------------------------------------------------------------------------------
--  CRÉATION DU WIDGET QUÊTE (icône + compteur de progression)
-------------------------------------------------------------------------------
function SP.Quest:CreateWidget(data)
    local root     = data.root
    local nameText = data.nameText

    -- Icône "!" / "?" (à droite du nom)
    local questIcon = root:CreateTexture(nil, "OVERLAY", nil, 5)
    questIcon:SetSize(16, 16)
    if nameText then
        questIcon:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    else
        questIcon:SetPoint("CENTER", root, "CENTER", 0, 0)
    end
    questIcon:SetTexture(QUEST_ICON_EXCLAIM)
    questIcon:SetVertexColor(1.0, 0.85, 0.0)
    questIcon:SetAlpha(0)
    data.questIcon = questIcon

    -- Texte de progression optionnel (ex: 2/5)
    local questText = root:CreateFontString(nil, "OVERLAY")
    questText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    questText:SetPoint("LEFT", questIcon, "RIGHT", 2, 0)
    questText:SetTextColor(1, 0.85, 0, 1)
    questText:SetShadowColor(0, 0, 0, 1)
    questText:SetShadowOffset(1, -1)
    questText:Hide()
    data.questText = questText
end

-------------------------------------------------------------------------------
--  MISE À JOUR : détection et affichage
-------------------------------------------------------------------------------
function SP.Quest:UpdateUnit(data, unit)
    if not data.questIcon then return end
    local cfg = SP:GetCfg(data.unitType)

    if not cfg.quest_enabled or UnitIsPlayer(unit) then
        data.questIcon:SetAlpha(0)
        if data.questText then data.questText:Hide() end
        data.isQuestUnit = false
        return
    end

    local guid = UnitGUID(unit)
    local now  = GetTime()

    -- Vérifier le cache
    if guid then
        local cached = unitQuestCache[guid]
        if cached and now < cached.expiry then
            self:_Apply(data, unit, cfg, guid, cached.state)
            return
        end
    end

    -- Détection : GetQuestGiverStatus distingue nouvelle/en cours/à rendre
    local questState = false
    local ok1, status = pcall(GetQuestGiverStatus, unit)
    if ok1 and type(status) == "number" then
        if status == QUEST_STATE_AVAILABLE or status == QUEST_STATE_INCOMPLETE
           or status == QUEST_STATE_REWARD then
            questState = status
        end
    end
    -- Fallback : C_QuestLog.UnitIsRelatedToActiveQuest (détecte en cours / à rendre)
    if not questState and C_QuestLog_UnitIsRelated then
        local ok2, result = pcall(C_QuestLog_UnitIsRelated, unit)
        if ok2 and result == true then questState = QUEST_STATE_INCOMPLETE end
    end

    -- Mettre en cache
    if guid then
        unitQuestCache[guid] = { state=questState, expiry=now + CACHE_TTL }
    end

    self:_Apply(data, unit, cfg, guid, questState)
end

-------------------------------------------------------------------------------
--  APPLIQUE L'ÉTAT QUÊTE SUR LA PLAQUE
--  questState : QUEST_STATE_AVAILABLE(2), QUEST_STATE_INCOMPLETE(3),
--               QUEST_STATE_REWARD(4), ou false
-------------------------------------------------------------------------------
function SP.Quest:_Apply(data, unit, cfg, guid, questState)
    data.isQuestUnit = questState ~= false

    if questState then
        if questState == QUEST_STATE_REWARD then
            -- "?" doré : quête à remettre
            data.questIcon:SetTexture(QUEST_ICON_TURNIN)
            data.questIcon:SetVertexColor(1.0, 0.85, 0.0)
            data.questIcon:SetAlpha(1)
        elseif questState == QUEST_STATE_INCOMPLETE then
            -- "!" tamisé : quête en cours, PNJ associé
            data.questIcon:SetTexture(QUEST_ICON_EXCLAIM)
            data.questIcon:SetVertexColor(0.7, 0.7, 0.7)
            data.questIcon:SetAlpha(0.6)
        else
            -- "!" doré : nouvelle quête disponible
            data.questIcon:SetTexture(QUEST_ICON_EXCLAIM)
            data.questIcon:SetVertexColor(1.0, 0.85, 0.0)
            data.questIcon:SetAlpha(1)
        end

        -- Son à la première apparition de ce PNJ de quête
        if cfg.quest_sound and guid and not soundPlayedGuids[guid] then
            soundPlayedGuids[guid] = true
            pcall(PlaySound, QUEST_SOUND_ID, "SFX")
        end

        pcall(SP.Orb.UpdateName, SP.Orb, data, unit)
    else
        data.questIcon:SetAlpha(0)
        if data.questText then data.questText:Hide() end
        if guid then soundPlayedGuids[guid] = nil end
    end
end

-------------------------------------------------------------------------------
--  NETTOYAGE DU CACHE
-------------------------------------------------------------------------------
function SP.Quest:ClearCache()
    wipe(unitQuestCache)
    wipe(soundPlayedGuids)
end

-------------------------------------------------------------------------------
--  MISE À JOUR GLOBALE (après QUEST_ACCEPTED, UNIT_QUEST_LOG_CHANGED)
-------------------------------------------------------------------------------
function SP.Quest:UpdateAll()
    SP.Quest:ClearCache()
    for unit, data in pairs(SP.Plates) do
        SP.Quest:UpdateUnit(data, unit)
    end
end
