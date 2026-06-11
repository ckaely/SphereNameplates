-------------------------------------------------------------------------------
--  SphereNameplates - Moi
--
--  Sphere personnelle fixe, hors nameplates. Reutilise Orb/CastBar/Auras avec
--  unit="player" et unitType="PLAYER_SELF".
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.Moi = SP.Moi or {}
local M = SP.Moi

local UNIT = "player"
local UTYPE = "PLAYER_SELF"
local ACTIVE_KEY = "unitframe:player"

local function DB()
    return SP.db or {}
end

local function CFG()
    return SP.GetCfg and SP:GetCfg(UTYPE) or {}
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function IsEditMode()
    return DB().snp_edit_mode == true
end

local POWER_COLORS = {
    [0]  = {0.00, 0.35, 1.00}, -- Mana
    [1]  = {1.00, 0.05, 0.02}, -- Rage
    [2]  = {1.00, 0.54, 0.00}, -- Focus
    [3]  = {1.00, 0.86, 0.05}, -- Energy
    [4]  = {0.35, 0.55, 1.00}, -- Combo points
    [6]  = {0.00, 0.82, 1.00}, -- Runic power
    [7]  = {0.00, 0.82, 0.50}, -- Soul shards
    [11] = {0.60, 0.00, 0.80}, -- Maelstrom
    [13] = {0.58, 0.10, 1.00}, -- Insanity
    [16] = {1.00, 0.65, 0.00}, -- Astral power
    [17] = {0.92, 0.72, 0.18}, -- Holy power
    [18] = {0.30, 0.70, 0.10}, -- Essence
}

local CLASS_POWER_COLORS = {
    COMBO_POINTS = {1.00, 0.82, 0.12},
    HOLY_POWER   = {1.00, 0.90, 0.38},
    CHI          = {0.15, 0.95, 0.68},
    SOUL_SHARDS  = {0.72, 0.25, 1.00},
    ARCANE       = {0.40, 0.65, 1.00},
    ESSENCE      = {0.30, 0.90, 0.35},
    RUNES        = {0.10, 0.85, 1.00},
}

local function PowerColor(ptype)
    local c = POWER_COLORS[tonumber(ptype) or -1] or {0.65, 0.65, 0.65}
    return c[1], c[2], c[3]
end

function M:IsEnabled()
    local db = DB()
    return db.addonEnabled ~= false
       and db.modules_moi_enabled ~= false
       and db.moi_enabled == true
end

function M:EnsureSavedDefaults()
    local db = DB()
    if db.moi_hide_blizzard_migrated ~= 1 then
        db.moi_hide_blizzard_player = true
        db.moi_hide_blizzard_migrated = 1
    end
    -- Migration one-shot : Shadow Circle devient le style de bordure par
    -- défaut des unitframes (anneau de classe + support de l'anneau
    -- ressource). Flag posé seulement quand le profil est disponible.
    if db.moi_shadowcircle_migrated ~= 1 then
        local cfg = SP.db and SP.db.PLAYER_SELF
        if cfg then
            cfg.borderStyle = "shadowcircle"
            db.moi_shadowcircle_migrated = 1
        end
    end
end

function M:ShouldShow()
    if not self:IsEnabled() then return false end
    local mode = DB().moi_display_mode or "always"
    if mode == "combat" then
        return (SP.InCombat == true) or (UnitAffectingCombat and UnitAffectingCombat(UNIT) == true)
    end
    return true
end

function M:EnsureAnchor()
    if self.anchor then return self.anchor end

    local anchor = CreateFrame("Button", "SPMoiAnchor", UIParent)
    anchor:SetFrameStrata("HIGH")
    anchor:SetFrameLevel(20)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor._isSPFrame = true

    anchor:SetScript("OnDragStart", function(f)
        if (DB().moi_locked == true and not IsEditMode()) or IsCombatLocked() then return end
        f:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        M:SaveAnchorPosition(f)
    end)

    local edit = CreateFrame("Frame", nil, anchor)
    edit:SetAllPoints()
    edit:SetFrameLevel(anchor:GetFrameLevel() + 50)
    edit:EnableMouse(false)
    edit.bg = edit:CreateTexture(nil, "BACKGROUND")
    edit.bg:SetAllPoints()
    edit.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    edit.bg:SetVertexColor(0.05, 0.25, 0.22, 0.18)
    edit.label = edit:CreateFontString(nil, "OVERLAY")
    edit.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    edit.label:SetTextColor(0.45, 1.0, 0.78, 1)
    edit.label:SetPoint("TOP", anchor, "TOP", 0, -4)
    edit.label:SetText("Moi")
    edit:Hide()
    anchor.editFrame = edit

    self.anchor = anchor
    return anchor
end

function M:SaveAnchorPosition(f)
    f = f or self.anchor
    if not f then return end
    local ok, cx, cy, ux, uy = pcall(function()
        local acx, acy = f:GetCenter()
        local ucx, ucy = UIParent:GetCenter()
        return acx, acy, ucx, ucy
    end)
    if ok and cx and cy and ux and uy and SP.db then
        local x, y = cx - ux, cy - uy
        if SP.ActionBars and SP.ActionBars.SnapPoint and IsEditMode() then
            x, y = SP.ActionBars:SnapPoint(x, y)
        end
        SP.db.moi_x = math.floor(x + 0.5)
        SP.db.moi_y = math.floor(y + 0.5)
        if SP.ActionBars and SP.ActionBars.Refresh and IsEditMode() then
            pcall(SP.ActionBars.Refresh, SP.ActionBars)
        end
    end
end

function M:ApplyAnchor()
    -- L'anchor est parent du bouton secure (clic cible/menu) : il devient
    -- lui-même protégé. Toute mutation (SetPoint/SetShown/...) en combat est
    -- interdite → différer via _pendingAnchor + PLAYER_REGEN_ENABLED.
    if IsCombatLocked() then
        self._pendingAnchor = true
        return
    end
    local anchor = self:EnsureAnchor()
    local db = DB()
    local cfg = CFG()
    local size = tonumber(cfg.size) or 74

    anchor:ClearAllPoints()
    anchor:SetSize(size, size)
    anchor:SetPoint("CENTER", UIParent, "CENTER", tonumber(db.moi_x) or -280, tonumber(db.moi_y) or -170)
    anchor:SetScale(Clamp(db.moi_scale, 0.5, 2.0))
    anchor:EnableMouse(((db.moi_locked ~= true) or IsEditMode()) and self:IsEnabled())
    anchor:SetShown(self:IsEnabled())
    if anchor.editFrame then
        anchor.editFrame:SetShown(IsEditMode() and self:IsEnabled())
    end
    self:UpdateSecureButton()
end

-- ── Bouton secure : clic gauche = se cibler, clic droit = menu Blizzard ─────
-- SecureUnitButtonTemplate avec togglemenu natif → zéro taint, comportement
-- identique au PlayerFrame Blizzard. Actif hors mode édition; si la sphère est
-- déverrouillée (moi_locked=false), le drag transite par ce bouton et déplace
-- l'anchor (clic sans mouvement = ciblage, clic+mouvement = déplacement).
function M:EnsureSecureButton()
    if self.secureBtn then return self.secureBtn end
    local anchor = self:EnsureAnchor()
    local btn = CreateFrame("Button", "SPMoiSecureButton", anchor, "SecureUnitButtonTemplate")
    btn:SetAllPoints(anchor)
    btn:SetFrameLevel((anchor:GetFrameLevel() or 20) + 30)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("unit", UNIT)
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")
    btn._isSPFrame = true
    -- Drag forwardé vers l'anchor (insecure : n'affecte pas le clic secure)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        local a = M.anchor
        if not a then return end
        if (DB().moi_locked == true and not IsEditMode()) or IsCombatLocked() then return end
        pcall(a.StartMoving, a)
    end)
    btn:SetScript("OnDragStop", function()
        local a = M.anchor
        if not a then return end
        pcall(a.StopMovingOrSizing, a)
        M:SaveAnchorPosition(a)
    end)
    self.secureBtn = btn
    return btn
end

function M:UpdateSecureButton()
    if not self:IsEnabled() then
        if self.secureBtn and not IsCombatLocked() then
            self.secureBtn:Hide()
            self.secureBtn:EnableMouse(false)
        end
        return
    end
    if IsCombatLocked() then
        self._pendingSecureButton = true
        return
    end
    local btn = self:EnsureSecureButton()
    -- En mode édition, le bouton secure s'efface : l'anchor + hitbox édition
    -- reprennent la souris pour le placement.
    local active = not IsEditMode()
    btn:EnableMouse(active)
    btn:SetShown(active)
end

local function BlizzardPlayerFrames()
    local out = {}
    local function add(frame)
        if frame then out[#out + 1] = frame end
    end
    add(PlayerFrame)
    add(PlayerFrameBackground)
    add(PlayerFrameHealthBar)
    add(PlayerFrameManaBar)
    add(PlayerFrameTexture)
    add(PlayerFrameAlternateManaBar)
    add(PlayerFrameGroupIndicator)
    add(PlayerFrame and PlayerFrame.PlayerFrameContainer or nil)
    return out
end

function M:HideBlizzardPlayerFrame(frame)
    if not frame then return end
    frame._snpMoiHidden = true
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    if frame.Hide then pcall(frame.Hide, frame) end
end

function M:RestoreBlizzardPlayerFrame(frame)
    if not frame or not frame._snpMoiHidden then return end
    frame._snpMoiHidden = nil
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
    if frame.Show then pcall(frame.Show, frame) end
end

function M:HookBlizzardPlayerFrame(frame)
    if not frame or frame._snpMoiHooked then return end
    frame._snpMoiHooked = true
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function(f)
            if M:IsEnabled() and DB().moi_hide_blizzard_player ~= false and not IsCombatLocked() then
                M:HideBlizzardPlayerFrame(f)
            end
        end)
    end
end

function M:ApplyBlizzardPlayerFrame()
    self:EnsureSavedDefaults()
    local hide = self:IsEnabled() and DB().moi_hide_blizzard_player ~= false
    if IsCombatLocked() then
        self._pendingBlizzardPlayerFrame = true
        return
    end
    for _, frame in ipairs(BlizzardPlayerFrames()) do
        if frame then
            self:HookBlizzardPlayerFrame(frame)
            if hide then
                self:HideBlizzardPlayerFrame(frame)
            else
                self:RestoreBlizzardPlayerFrame(frame)
            end
        end
    end
end

function M:CreateClassPowerText(data)
    if data.moiClassPowerText or not data.root then return end
    local fs = data.root:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    fs:SetPoint("TOP", data.powerBar or data.orbFrame or data.root, "BOTTOM", 0, -2)
    fs:SetTextColor(1.0, 0.88, 0.35, 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:Hide()
    data.moiClassPowerText = fs
end

local function PlayerClassPowerType()
    local ok, class = pcall(function() return select(2, UnitClass(UNIT)) end)
    if not ok then class = nil end
    local e = Enum and Enum.PowerType
    if not e then return nil end
    if class == "ROGUE" or class == "DRUID" then return e.ComboPoints end
    if class == "PALADIN" then return e.HolyPower end
    if class == "MONK" then return e.Chi end
    if class == "WARLOCK" then return e.SoulShards end
    if class == "MAGE" then return e.ArcaneCharges end
    if class == "EVOKER" then return e.Essence end
    if class == "DEATHKNIGHT" then return e.Runes end
    return nil
end

local function PlayerClassPowerKind()
    local ok, class = pcall(function() return select(2, UnitClass(UNIT)) end)
    if not ok then class = nil end
    if class == "ROGUE" or class == "DRUID" then return "COMBO_POINTS" end
    if class == "PALADIN" then return "HOLY_POWER" end
    if class == "MONK" then return "CHI" end
    if class == "WARLOCK" then return "SOUL_SHARDS" end
    if class == "MAGE" then return "ARCANE" end
    if class == "EVOKER" then return "ESSENCE" end
    if class == "DEATHKNIGHT" then return "RUNES" end
    return nil
end

local function SetFrameClipsChildren(frame, enabled)
    if frame and frame.SetClipsChildren then
        pcall(frame.SetClipsChildren, frame, enabled and true or false)
    end
end

function M:CreateResourceHemisphere(parent, side)
    local full = parent:GetParent() or parent
    local clip = CreateFrame("Frame", nil, parent)
    SetFrameClipsChildren(clip, true)
    local fill = CreateFrame("Frame", nil, clip)
    SetFrameClipsChildren(fill, true)
    local tex = fill:CreateTexture(nil, "OVERLAY", nil, 5)
    tex:SetTexture(SP.SHADOW_CIRCLE_PATH or (SP.MEDIA and (SP.MEDIA .. "shadowcircle")) or "Interface\\Buttons\\UI-ActionButton-Border")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(0.85)
    return { outer = clip, fill = fill, tex = tex, side = side, full = full }
end

function M:EnsureResourceRing(data)
    if not data or not data.root or data.moiResourceRing then return end
    local holder = CreateFrame("Frame", nil, data.root)
    holder:SetFrameLevel((data.root:GetFrameLevel() or 1) + 28)
    holder:SetPoint("CENTER", data.orbFrame or data.root, "CENTER")
    SetFrameClipsChildren(holder, true)
    data.moiResourceRing = {
        holder = holder,
        left = self:CreateResourceHemisphere(holder, "left"),
        right = self:CreateResourceHemisphere(holder, "right"),
        _targetAlpha = 0,
    }
    holder:SetAlpha(0)
    holder:Hide()
end

-- ── Visibilité de l'anneau ressource ────────────────────────────────────────
-- "smart" (défaut) : combat OU ~5s après un lancement de sort.
-- "combat" : combat uniquement. "always" : toujours visible.
local RESOURCE_ACTIVITY_WINDOW = 5.0

function M:MarkResourceActivity()
    self._resourceActivityUntil = (GetTime and GetTime() or 0) + RESOURCE_ACTIVITY_WINDOW
end

function M:IsResourceActive(cfg)
    local mode = (cfg or CFG()).moi_resource_ring_visibility or "smart"
    if mode == "always" then return true end
    local inCombat = (SP.InCombat == true)
        or (UnitAffectingCombat and UnitAffectingCombat(UNIT) == true)
    if inCombat then return true end
    if mode == "smart" then
        local untilT = self._resourceActivityUntil
        return (untilT and GetTime and GetTime() < untilT) == true
    end
    return false
end

function M:LayoutResourceRing(data)
    if not (data and data.moiResourceRing) then return end
    local cfg = CFG()
    local size = (tonumber(data.orbSize) or tonumber(cfg.size) or 74) * Clamp(cfg.moi_resource_ring_scale, 0.80, 1.60)
    local ring = data.moiResourceRing
    ring.holder:SetSize(size, size)
    ring.holder:ClearAllPoints()
    ring.holder:SetPoint("CENTER", data.orbFrame or data.root, "CENTER")
    for _, hemi in ipairs({ring.left, ring.right}) do
        local outer = hemi.outer
        outer:ClearAllPoints()
        outer:SetSize(size * 0.5, size)
        if hemi.side == "left" then
            outer:SetPoint("LEFT", ring.holder, "LEFT")
        else
            outer:SetPoint("RIGHT", ring.holder, "RIGHT")
        end
        hemi.fill:ClearAllPoints()
        hemi.fill:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT")
        hemi.fill:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT")
        hemi.fill:SetSize(size * 0.5, size)
        hemi.tex:ClearAllPoints()
        hemi.tex:SetSize(size, size)
        hemi.tex:SetPoint("CENTER", ring.holder, "CENTER")
    end
end

function M:SetHemisphereValue(hemi, ratio, r, g, b, alpha)
    if not hemi then return end
    ratio = Clamp(ratio, 0, 1)
    alpha = Clamp(alpha, 0, 1)
    local w, h = hemi.outer:GetSize()
    w = tonumber(w) or 1
    h = tonumber(h) or 1
    hemi.fill:SetWidth(w)
    hemi.fill:SetHeight(math.max(1, h * ratio))
    hemi.tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
    hemi.tex:SetAlpha(alpha)
end

function M:GetPrimaryPower()
    local ok, ptype, cur, maxv = pcall(function()
        local pt = UnitPowerType(UNIT)
        return pt, UnitPower(UNIT, pt) or 0, UnitPowerMax(UNIT, pt) or 0
    end)
    if not ok or type(maxv) ~= "number" or maxv <= 0 then return nil end
    return ptype, Clamp((tonumber(cur) or 0) / maxv, 0, 1), cur, maxv
end

function M:GetClassPower()
    local ptype = PlayerClassPowerType()
    if not ptype then return nil end
    local ok, cur, maxv = pcall(function()
        return UnitPower(UNIT, ptype) or 0, UnitPowerMax(UNIT, ptype) or 0
    end)
    if not ok or type(maxv) ~= "number" or maxv <= 0 then return nil end
    local kind = PlayerClassPowerKind()
    return ptype, Clamp((tonumber(cur) or 0) / maxv, 0, 1), cur, maxv, kind
end

function M:UpdateResourceRing()
    local data = self.data
    if not data then return end
    self:EnsureResourceRing(data)
    local ring = data.moiResourceRing
    if not ring then return end
    local cfg = CFG()
    if cfg.moi_resource_ring_enabled == false or cfg.borderStyle ~= "shadowcircle" or not self:ShouldShow() then
        ring._targetAlpha = 0
        ring.holder:SetAlpha(0)
        ring.holder:Hide()
        return
    end

    local ptype, primaryRatio = self:GetPrimaryPower()
    if not ptype then
        ring._targetAlpha = 0
        ring.holder:SetAlpha(0)
        ring.holder:Hide()
        return
    end
    self:LayoutResourceRing(data)
    local pr, pg, pb = PowerColor(ptype)
    local alpha = Clamp(cfg.moi_resource_ring_alpha, 0, 1)
    local minAlpha = Clamp(cfg.moi_resource_ring_min_alpha, 0, 0.80)
    local classType, classRatio, _, classMax, classKind = self:GetClassPower()
    local split = cfg.moi_resource_ring_split ~= false and classType and classMax and classMax > 0

    if split then
        local cr, cg, cb = pr, pg, pb
        local cc = CLASS_POWER_COLORS[classKind or ""]
        if cc then cr, cg, cb = cc[1], cc[2], cc[3] else cr, cg, cb = PowerColor(classType) end
        self:SetHemisphereValue(ring.left, primaryRatio, pr, pg, pb, math.max(minAlpha, alpha))
        self:SetHemisphereValue(ring.right, classRatio or 0, cr, cg, cb, math.max(minAlpha, alpha))
    else
        self:SetHemisphereValue(ring.left, primaryRatio, pr, pg, pb, math.max(minAlpha, alpha))
        self:SetHemisphereValue(ring.right, primaryRatio, pr, pg, pb, math.max(minAlpha, alpha))
    end

    -- Visibilité par fondu : la cible d'alpha est lissée dans TickBehavior.
    ring._targetAlpha = self:IsResourceActive(cfg) and 1 or 0
    if ring._targetAlpha > 0 or (ring.holder:GetAlpha() or 0) > 0.02 then
        ring.holder:Show()
    else
        ring.holder:Hide()
    end
end

function M:UpdateClassPower()
    local data = self.data
    if not data or not data.moiClassPowerText then return end
    local cfg = CFG()
    if cfg.class_power_enabled == false then
        data.moiClassPowerText:Hide()
        return
    end

    local ptype = PlayerClassPowerType()
    if not ptype then
        data.moiClassPowerText:Hide()
        return
    end

    local ok, cur, maxv = pcall(function()
        return UnitPower(UNIT, ptype) or 0, UnitPowerMax(UNIT, ptype) or 0
    end)
    if not ok or type(maxv) ~= "number" or maxv <= 0 then
        data.moiClassPowerText:Hide()
        return
    end

    cur = tonumber(cur) or 0
    if cur <= 0 then
        data.moiClassPowerText:Hide()
        return
    end
    data.moiClassPowerText:SetText(string.format("%d/%d", cur, maxv))
    data.moiClassPowerText:Show()
    self:UpdateResourceRing()
end

function M:EnsureBehaviorGlow(data)
    if not data or not data.root or data.moiBehaviorGlow then return end
    local tex = data.root:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetTexture("Interface\\Cooldown\\ping4")
    tex:SetPoint("CENTER", data.orbFrame or data.root, "CENTER")
    tex:SetBlendMode("ADD")
    tex:SetAlpha(0)
    tex:Hide()
    data.moiBehaviorGlow = tex
end

function M:PulseBehavior(reason, r, g, b)
    local data = self.data
    local cfg = CFG()
    if not (data and data.root and cfg.moi_behavior_glow_enabled ~= false) then return end
    local now = GetTime and GetTime() or 0
    self._behaviorPulseAt = self._behaviorPulseAt or {}
    local cd = Clamp(cfg.moi_behavior_glow_cooldown, 0.20, 10.00)
    if self._behaviorPulseAt[reason] and (now - self._behaviorPulseAt[reason]) < cd then return end
    self._behaviorPulseAt[reason] = now
    self:EnsureBehaviorGlow(data)
    data._moiBehaviorPulse = {
        started = now,
        duration = 1.00,
        r = r or 1, g = g or 1, b = b or 1,
    }
end

function M:TickBehavior(now)
    local data = self.data
    if not data then return end

    -- Fondu de l'anneau ressource (60 FPS) — avant le early-return du pulse
    local ring = data.moiResourceRing
    if ring and ring.holder and ring.holder:IsShown() then
        local target = ring._targetAlpha or 0
        local cur = ring.holder:GetAlpha() or 0
        local diff = target - cur
        if math.abs(diff) > 0.01 then
            ring.holder:SetAlpha(cur + diff * 0.10)
        else
            ring.holder:SetAlpha(target)
            if target == 0 then ring.holder:Hide() end
        end
    end

    local pulse = data._moiBehaviorPulse
    local glow = data.moiBehaviorGlow
    if not (pulse and glow) then return end
    now = now or (GetTime and GetTime()) or 0
    local p = Clamp((now - (pulse.started or now)) / (pulse.duration or 1), 0, 1)
    if p >= 1 then
        glow:SetAlpha(0)
        glow:Hide()
        data._moiBehaviorPulse = nil
        return
    end
    local cfg = CFG()
    local base = tonumber(data.orbSize) or tonumber(cfg.size) or 74
    local maxScale = Clamp(cfg.moi_behavior_glow_size, 1.05, 3.00)
    local size = base * (0.78 + (maxScale - 0.78) * p)
    local alpha = Clamp(cfg.moi_behavior_glow_alpha, 0, 1) * (1 - p) * (0.55 + 0.45 * math.sin(p * math.pi))
    glow:SetSize(size, size)
    glow:SetVertexColor(pulse.r, pulse.g, pulse.b, 1)
    glow:SetAlpha(alpha)
    glow:Show()
end

function M:PlayerHasAggro()
    if UnitThreatSituation then
        local okTarget, targetStatus = pcall(UnitThreatSituation, UNIT, "target")
        if okTarget and targetStatus and targetStatus >= 2 then return true end
        local plates = SP.Plates or {}
        local n = 0
        for _, data in pairs(plates) do
            local unit = data and data.unit
            if unit then
                n = n + 1
                local ok, status = pcall(UnitThreatSituation, UNIT, unit)
                if ok and status and status >= 2 then return true end
                if n >= 40 then break end
            end
        end
    end
    return false
end

function M:EvaluateBehavior()
    local cfg = CFG()
    if cfg.moi_behavior_glow_enabled == false then return end
    local data = self.data
    if not data then return end

    local hp = tonumber(data.targetHP or data.displayHP)
    if hp then
        if cfg.moi_behavior_glow_heal ~= false and self._lastBehaviorHP and hp > self._lastBehaviorHP + 0.025 then
            self:PulseBehavior("heal", 0.18, 1.00, 0.42)
        end
        self._lastBehaviorHP = hp
        local threshold = Clamp((cfg.moi_behavior_lowhp_threshold or 35) / 100, 0.01, 0.99)
        if cfg.moi_behavior_glow_lowhp ~= false and hp <= threshold then
            self:PulseBehavior("lowhp", 1.00, 0.12, 0.08)
        end
    end
    if cfg.moi_behavior_glow_aggro ~= false and self:PlayerHasAggro() then
        self:PulseBehavior("aggro", 1.00, 0.22, 0.04)
    end
end

function M:Destroy()
    local data = self.data
    if data then
        if SP.CastBar and data.castbar then pcall(SP.CastBar.Reset, SP.CastBar, data) end
        if SP.Auras then pcall(SP.Auras.RemoveAll, SP.Auras, data) end
        if data.root then data.root:Hide() end
    end
    SP.UnitFrames[UNIT] = nil
    SP.ActiveOrbData[ACTIVE_KEY] = nil
    self.data = nil
end

function M:EnsureData(live)
    if not self:IsEnabled() then
        self:Destroy()
        self:UpdateSecureButton()   -- masque la zone de clic secure (hors combat)
        return nil
    end

    self:ApplyAnchor()
    local cfg = CFG()
    local liveEdit = live
    if not liveEdit and self._liveEditingUntil and GetTime and GetTime() < self._liveEditingUntil then
        liveEdit = true
    end
    if self.data and self.data.orbSize ~= (cfg.size or 74) then
        if liveEdit then
            return self.data
        end
        self:Destroy()
    end
    if self.data then return self.data end

    local anchor = self:EnsureAnchor()
    local ok, data = pcall(SP.Orb.Create, SP.Orb, UNIT, anchor, UTYPE)
    if not ok or not data then
        if SP.Log then SP.Log:Error("Moi", "Orb.Create failed: " .. tostring(data)) end
        return nil
    end

    data.unit = UNIT
    data.unitType = UTYPE
    data.plate = anchor
    data._isUnitFrame = true
    data._isPlayerSelf = true
    data._packRank = 3
    data._fadeAlpha = 1
    data._nameDistanceAlpha = 1
    data.root._isSPFrame = true
    pcall(data.root.SetIgnoreParentAlpha, data.root, true)

    SP.UnitFrames[UNIT] = data
    SP.ActiveOrbData[ACTIVE_KEY] = data
    self.data = data

    if SP.Auras then
        pcall(SP.Auras.Init, SP.Auras, data)
        pcall(SP.Auras.UpdateUnit, SP.Auras, data, UNIT, nil)
    end
    if SP.CastBar then
        local okCB, cb = pcall(SP.CastBar.Create, SP.CastBar, data)
        if okCB and cb then data.castbar = cb end
    end
    self:CreateClassPowerText(data)
    self:EnsureResourceRing(data)
    self:EnsureBehaviorGlow(data)
    return data
end

function M:UpdateAll(live)
    self:EnsureSavedDefaults()
    local data = self:EnsureData(live)
    self:ApplyBlizzardPlayerFrame()
    if not data then return end

    data._inCombat = (SP.InCombat == true) or (UnitAffectingCombat and UnitAffectingCombat(UNIT) == true)
    pcall(SP.Orb.SoftUpdate, SP.Orb, data, UNIT)
    pcall(SP.UpdateHealth, SP, UNIT, data)
    pcall(SP.Orb.UpdateName, SP.Orb, data, UNIT)
    pcall(SP.Orb.UpdateLevelText, SP.Orb, data, UNIT)
    pcall(SP.Orb.UpdatePower, SP.Orb, data, UNIT)
    if SP.Auras and data.auraIcons then pcall(SP.Auras.UpdateUnit, SP.Auras, data, UNIT, nil) end
    self:UpdateClassPower()
    self:UpdateResourceRing()
    self:EvaluateBehavior()
    self:UpdateVisibility()
end

function M:UpdateVisibility()
    local data = self.data
    if not data or not data.root then return end
    local shown = self:ShouldShow()
    data.root:SetShown(shown)
    -- L'anchor est protégé (ancêtre du bouton secure) : SetShown interdit en
    -- combat. data.root (enfant, non-ancêtre) reste librement manipulable.
    if self.anchor and not IsCombatLocked() then
        self.anchor:SetShown(self:IsEnabled())
    end
    if shown then
        pcall(SP.Orb.ApplySphereVisibility, SP.Orb, data, CFG())
    end
end

function M:TickCast(now)
    local data = self.data
    if data and data.castbar and self:ShouldShow() and SP.CastBar then
        pcall(SP.CastBar.Tick, SP.CastBar, data, now)
    end
end

function M:TickHealth()
    local data = self.data
    if not (data and data.targetHP ~= nil and SP.Orb) then return end
    local cfg = CFG()
    local k = math.min(0.90, (cfg.hp_lerp_speed or 10.0) * 0.018)
    local target = data.targetHP
    local display = data.displayHP or target
    local diff = target - display
    if math.abs(diff) > 0.0005 then
        data.displayHP = display + diff * k
    else
        data.displayHP = target
    end
    pcall(SP.Orb.UpdateFill, SP.Orb, data, data.displayHP)
    self:TickBehavior(GetTime and GetTime() or 0)
end

function M:Poll()
    if not self:IsEnabled() then
        self:Destroy()
        self:ApplyBlizzardPlayerFrame()
        return
    end
    local data = self.data or self:EnsureData()
    if not data then return end
    pcall(SP.UpdateHealth, SP, UNIT, data)
    pcall(SP.Orb.UpdatePower, SP.Orb, data, UNIT)
    pcall(SP.Orb.UpdateLevelText, SP.Orb, data, UNIT)
    if SP.Auras and data.auraIcons then pcall(SP.Auras.UpdateUnit, SP.Auras, data, UNIT, nil) end
    self:UpdateClassPower()
    self:UpdateResourceRing()
    self:EvaluateBehavior()
    self:UpdateVisibility()
end

function M:EnsureEventFrame()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f

    local unitEvents = {
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER_UPDATE",
        "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_AURA",
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_SUCCEEDED",
    }
    for _, ev in ipairs(unitEvents) do
        local ok = pcall(f.RegisterUnitEvent, f, ev, UNIT)
        if not ok then pcall(f.RegisterEvent, f, ev) end
    end
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ALIVE",
        "PLAYER_DEAD",
        "LOSS_OF_CONTROL_ADDED",
        "LOSS_OF_CONTROL_UPDATE",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end

    f:SetScript("OnEvent", function(_, event, unit)
        if event and event:match("^UNIT_") and unit and unit ~= UNIT then return end
        if event == "UNIT_AURA" then
            local data = M.data
            if data and SP.Auras then pcall(SP.Auras.UpdateUnit, SP.Auras, data, UNIT, nil) end
            return
        end
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
            or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            local data = M.data or M:EnsureData()
            if data then
                pcall(SP.Orb.UpdatePower, SP.Orb, data, UNIT)
                M:UpdateClassPower()
                M:UpdateResourceRing()
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then SP.InCombat = true end
        if event == "PLAYER_REGEN_ENABLED" then
            SP.InCombat = false
            if M._pendingBlizzardPlayerFrame then
                M._pendingBlizzardPlayerFrame = nil
                M:ApplyBlizzardPlayerFrame()
            end
            -- Anchor/bouton secure différés pendant le combat : le UpdateAll
            -- en fin de handler les réapplique maintenant que c'est permis.
            M._pendingAnchor = nil
            M._pendingSecureButton = nil
        end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Lancement de sort = fenêtre d'activité de l'anneau ressource (mode smart)
            M:MarkResourceActivity()
        end
        if (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START")
            and CFG().moi_behavior_glow_cast ~= false then
            M:PulseBehavior("cast", 0.25, 0.62, 1.00)
        elseif (event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE")
            and CFG().moi_behavior_glow_cc ~= false then
            M:PulseBehavior("cc", 0.78, 0.35, 1.00)
        end
        M:UpdateAll()
    end)
end

function M:Init()
    self:EnsureSavedDefaults()
    self:EnsureEventFrame()
    self:UpdateAll()
    if C_Timer then
        C_Timer.After(0.30, function() M:ApplyBlizzardPlayerFrame() end)
        C_Timer.After(1.20, function() M:ApplyBlizzardPlayerFrame() end)
    end
end

function M:Refresh(live)
    if live and GetTime then
        self._liveEditingUntil = GetTime() + 0.35
    else
        self._liveEditingUntil = nil
    end
    self:UpdateAll(live)
end
