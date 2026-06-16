-------------------------------------------------------------------------------
-- SphereNameplates - ActionBars
--
-- Barres d'actions personnelles configurees depuis Moi > Barres.
-- Les boutons utilisent SecureActionButtonTemplate et ne changent leurs attributs
-- securises que hors combat.
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
if not SP then return end

SP.ActionBars = SP.ActionBars or {}
local M = SP.ActionBars

local NUM_BARS = 8
local MAX_BUTTONS = 12
local SPECIAL_BAR_INDEX = 99
local SPECIAL_SLOT_START = 121
local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_EMPTY_ALPHA = 0.00
local EDIT_PAD = 4
local DEFAULT_GRID_SIZE = 16
local DEFAULT_PRIMARY_PAIR_GAP = 28
local ACTION_BUTTON_MASK = "Interface\\AddOns\\SphereNameplates\\media\\actionbutton-mask-circular"
local SHADOW_CIRCLE_TEX = "Interface\\AddOns\\SphereNameplates\\media\\shadowcircle"
local MIN_SKIN_COOLDOWN = 1.50
local SHADOW_CIRCLE_BAR_SCALE = 3.00
local COOLDOWN_ARC_SEGMENTS = 36

local function DB()
    return SP.db or {}
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function PlayerInCombat()
    if SP.SafeUnitAffectingCombat then
        return SP:SafeUnitAffectingCombat("player")
    end
    if UnitAffectingCombat then
        local ok, inCombat = pcall(UnitAffectingCombat, "player")
        return ok and inCombat == true
    end
    return false
end

local function IsEditMode()
    return DB().snp_edit_mode == true
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Bool(v, fallback)
    if v == nil then return fallback end
    return v == true
end

local function DeepCopyDefaults(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function BarDefaults(index)
    return {
        enabled = index == 1,
        buttons = 12,
        firstSlot = 1 + ((index - 1) * 12),
        followPaging = index == 1,
        orientation = "horizontal", -- horizontal | vertical | grid
        -- Pagination de la barre :
        --   "none"   : slots fixes (firstSlot)
        --   "native" : suit la page native (touche « barre suivante ») + postures
        --   "table"  : map page native 1-6 → page affichée (pagination liée)
        paging = index == 1 and "native" or "none",
        pageBars = {},  -- mode "linked" : barres affichées successivement (par numéro)
        pageOffset = 0, -- repli legacy (décalage de page)
        pageMap = {}, -- [pageNative]=pageAffichee, mode "table" (legacy/avancé)
        columns = 12,
        size = 36,
        spacing = 4,
        scale = 1.0,
        alpha = 1.0,
        inactiveAlpha = 0.25,
        visibility = "always", -- always | combat | nocombat | target | combat_target | mouseover | combatfade | hidden
        x = -220 + ((index - 1) * 18),
        y = -300 - ((index - 1) * 44),
        showEmpty = true,
        emptyAlpha = DEFAULT_EMPTY_ALPHA,
        showHotkey = true,
        showCount = true,
        showMacro = false,
        showCooldown = true,
        clickOnDown = false,
        hoverScale = 1.08,
        buttonSkin = "shadowcircle", -- none | shadowcircle
        skinAlpha = 0.95,
        skinScale = SHADOW_CIRCLE_BAR_SCALE,
        cooldownShade = true,
        cooldownShadeAlpha = 0.62,
        cooldownRingSpin = true,
    }
end

local function SpecialBarDefaults()
    return {
        enabled = true,
        buttons = 12,
        size = 42,
        spacing = 10,
        alpha = 1.0,
        showEmpty = true,
        emptyAlpha = 0.00,
        showHotkey = true,
        showCount = true,
        showMacro = false,
        showCooldown = true,
        clickOnDown = false,
        hoverScale = 1.08,
        buttonSkin = "shadowcircle",
        skinAlpha = 0.95,
        skinScale = SHADOW_CIRCLE_BAR_SCALE,
        cooldownShade = true,
        cooldownShadeAlpha = 0.62,
        cooldownRingSpin = true,
        offsetX = 122,
        offsetY = 42,
    }
end

function M:EnsureDefaults()
    local db = DB()
    if type(db.actionbars) ~= "table" then db.actionbars = {} end
    local root = db.actionbars
    DeepCopyDefaults(root, {
        enabled = false,
        hideBlizzard = true,
        replaceBlizzard = true,
        lock = true,
        selected = 1,
        bars = {},
        special = {},
        editGrid = true,
        editSnap = true,
        editGridSize = DEFAULT_GRID_SIZE,
        primaryPairAnchor = true,
        primaryPairGap = DEFAULT_PRIMARY_PAIR_GAP,
        primaryPairYOffset = 0,
        pageFlash = true,        -- indicateur éphémère "Barre N" au changement de page
        pageFlashDuration = 1.4, -- secondes avant le fondu
        ownBindings = false,     -- (désactivé : casse le cast par raccourci en 12.x — on garde les raccourcis natifs Blizzard)
        castOnDown = true,       -- déclencher au press (réactivité max, anti-latence) via la CVar Blizzard
    })
    if root.replaceBlizzard == nil then root.replaceBlizzard = true end
    if root.hideBlizzard == nil then root.hideBlizzard = true end
    if type(root.bars) ~= "table" then root.bars = {} end
    for i = 1, NUM_BARS do
        if type(root.bars[i]) ~= "table" then root.bars[i] = {} end
        DeepCopyDefaults(root.bars[i], BarDefaults(i))
    end
    if type(root.special) ~= "table" then root.special = {} end
    DeepCopyDefaults(root.special, SpecialBarDefaults())
    if root.precisionLayoutVersion ~= 1 then
        if root.bars[1] and root.bars[1].anchorMode == nil then
            root.bars[1].anchorMode = "moi_left"
        end
        if root.bars[6] and root.bars[6].anchorMode == nil then
            root.bars[6].anchorMode = "moi_right"
        end
        root.precisionLayoutVersion = 1
    end
    if root.pagingDefaultVersion ~= 2 then
        if root.bars[1] and root.bars[1].followPaging == nil then
            root.bars[1].followPaging = true
        end
        for i = 2, NUM_BARS do
            if root.bars[i] then
                root.bars[i].followPaging = false
            end
        end
        root.pagingDefaultVersion = 2
    end
    if root.emptyAlphaDefaultVersion ~= 2 then
        for i = 1, NUM_BARS do
            local cfg = root.bars[i]
            if cfg and (cfg.emptyAlpha == nil or math.abs((tonumber(cfg.emptyAlpha) or 0) - 0.42) < 0.001) then
                cfg.emptyAlpha = DEFAULT_EMPTY_ALPHA
            end
        end
        root.emptyAlphaDefaultVersion = 2
    end
    -- Migration followPaging → paging (champ unifié, pagination par table possible)
    if root.pagingFieldVersion ~= 1 then
        for i = 1, NUM_BARS do
            local cfg = root.bars[i]
            if cfg and cfg.paging == nil then
                cfg.paging = (cfg.followPaging == true) and "native"
                    or (i == 1 and "native" or "none")
            end
            if cfg and type(cfg.pageMap) ~= "table" then cfg.pageMap = {} end
        end
        root.pagingFieldVersion = 1
    end
    -- Réinitialisation de sécurité : la possession des raccourcis (ownBindings)
    -- cassait le cast de la barre principale en 12.x. On la force OFF une fois
    -- pour réparer les profils impactés ; les raccourcis natifs reprennent.
    if root.ownBindingsResetV1 ~= 1 then
        root.ownBindings = false
        root.ownBindingsResetV1 = 1
    end
    return root
end

function M:IsEnabled()
    local root = self:EnsureDefaults()
    return DB().addonEnabled ~= false and root.enabled == true
end

function M:GetBarConfig(index)
    local root = self:EnsureDefaults()
    if index == SPECIAL_BAR_INDEX or index == "special" then
        return root.special
    end
    index = Clamp(index, 1, NUM_BARS)
    return root.bars[index]
end

local function ActionBindingName(slot)
    slot = tonumber(slot) or 0
    if slot >= 1 and slot <= 12 then
        return "ACTIONBUTTON" .. slot
    end
    local idx = ((slot - 1) % 12) + 1
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. idx end
    if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. idx end
    if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. idx end
    if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. idx end
    if slot >= 73 and slot <= 84 then return "CLICK ActionBar7Button" .. idx .. ":LeftButton" end
    if slot >= 85 and slot <= 96 then return "CLICK ActionBar8Button" .. idx .. ":LeftButton" end
    if slot >= 97 and slot <= 108 then return "CLICK ActionBar9Button" .. idx .. ":LeftButton" end
    if slot >= 109 and slot <= 120 then return "CLICK ActionBar10Button" .. idx .. ":LeftButton" end
    return nil
end

local function NativeActionBarPage()
    local page = 1
    if type(GetActionBarPage) == "function" then
        local ok, value = pcall(GetActionBarPage)
        if ok then page = tonumber(value) or 1 end
    elseif type(CURRENT_ACTIONBAR_PAGE) == "number" then
        page = CURRENT_ACTIONBAR_PAGE
    end
    return Clamp(page, 1, 6)
end

local function StaticBarOwnsNativePage(page)
    page = Clamp(page, 1, 6)
    if page <= 1 then return false end
    local root = DB().actionbars
    if type(root) ~= "table" or type(root.bars) ~= "table" then return false end
    local pageStart = ((page - 1) * 12) + 1
    local pageEnd = pageStart + 11
    for i = 2, NUM_BARS do
        local cfg = root.bars[i]
        if cfg and cfg.enabled == true and cfg.followPaging ~= true then
            local count = Clamp(cfg.buttons, 1, MAX_BUTTONS)
            local startSlot = Clamp(cfg.firstSlot, 1, 180)
            local endSlot = startSlot + count - 1
            if startSlot <= pageEnd and endSlot >= pageStart then
                return true
            end
        end
    end
    return false
end

-- Résolution CANONIQUE de la page de la barre principale (bar 1).
-- Utilisée à la fois par le state-driver secure ET par le rendu visuel, pour
-- qu'ils ne divergent JAMAIS (cause du bug "icône page 1 alors qu'on caste
-- une autre page"). Couvre :
--   • bonusbar 1-4 → pages 7-10  (postures guerrier, formes druide, etc.)
--   • bar 2-6      → pages 2-6    (touche "barre d'action suivante")
--   • défaut       → page 1
-- bonusbar:5 + vehicle/override/possess sont gérés par la barre spéciale
-- (bar 1 masquée dans ces états), donc absents ici volontairement.
local function ResolveMainBarPage()
    local bonus = 0
    if GetBonusBarOffset then
        local ok, v = pcall(GetBonusBarOffset)
        if ok then bonus = tonumber(v) or 0 end
    end
    if bonus >= 1 and bonus <= 4 then
        return 6 + bonus
    end
    return NativeActionBarPage()
end

-- Conservé comme alias pour compat ; ne neutralise plus la page (l'ancien
-- StaticBarOwnsNativePage cassait l'affichage au-delà de la page 2).
local function EffectiveNativeActionBarPage()
    return ResolveMainBarPage()
end

local function NativePageDriver()
    return "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
        .. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"
end

-- Nom de la posture/forme active (pages 7-10), pour l'indicateur de barre.
-- Tout en pcall : API de forme variable selon classe/version.
local function CurrentFormName()
    if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
    local okIdx, idx = pcall(GetShapeshiftForm)
    if not okIdx or not idx or idx < 1 then return nil end
    local okInfo, _, _, _, spellID = pcall(GetShapeshiftFormInfo, idx)
    if not okInfo then return nil end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local okName, info = pcall(C_Spell.GetSpellInfo, spellID)
        if okName and type(info) == "table" and info.name then return info.name end
    end
    return nil
end

-- Page native pure (curseur « barre suivante », 1-6), sans bonusbar.
local function ResolveNativePage()
    return NativeActionBarPage()
end

-- Page (1-11) correspondant aux SLOTS d'une barre SphereUI donnée, d'après son
-- firstSlot. Permet de raisonner en « numéro de barre » : afficher la barre 3
-- = afficher ses slots = sa page. Barre N par défaut → page N.
local function BarPageFromIndex(n)
    n = tonumber(n) or 1
    local root = DB().actionbars
    local bcfg = root and root.bars and root.bars[n]
    local fs = (bcfg and tonumber(bcfg.firstSlot)) or (1 + (n - 1) * 12)
    return Clamp(math.floor((fs - 1) / 12) + 1, 1, 11)
end

-- Page « de base » d'une barre (ce qu'elle affiche en page native 1).
local function BarBasePage(cfg, barIndex)
    local fs = tonumber(cfg and cfg.firstSlot) or (1 + ((tonumber(barIndex) or 1) - 1) * 12)
    return Clamp(math.floor((fs - 1) / 12) + 1, 1, 11)
end

-- Liste ordonnée (croissante) des barres « suivantes » choisies pour une barre.
local function BarPageList(cfg)
    local out = {}
    if type(cfg) == "table" and type(cfg.pageBars) == "table" then
        for _, n in ipairs(cfg.pageBars) do
            local v = tonumber(n)
            if v then out[#out + 1] = v end
        end
        table.sort(out)
    end
    return out
end

-- Mode de pagination d'une barre (compat ascendante avec followPaging).
local function BarPagingMode(cfg, barIndex)
    if not cfg then return "none" end
    if cfg.paging then return cfg.paging end
    if cfg.followPaging == true then return "native" end
    return (tonumber(barIndex) == 1) and "native" or "none"
end

local function FollowsNativePaging(cfg, barIndex)
    return BarPagingMode(cfg, barIndex) ~= "none"
end

-- Page AFFICHÉE par une barre, identique côté visuel et côté secure :
--   native : page principale canonique (bonusbar 1-4 → 7-10, bar 2-6 → 2-6)
--   table  : map page native 1-6 → page choisie (pagination LIÉE multi-barres)
--   none   : nil (slots fixes via firstSlot)
local function ResolveBarDisplayPage(cfg, barIndex)
    local mode = BarPagingMode(cfg, barIndex)
    if mode == "native" then
        return ResolveMainBarPage()
    elseif mode == "linked" then
        -- Modèle « barres suivantes » : la barre cycle sur les barres cochées,
        -- dans l'ordre. Page native 1 = sa propre page ; native 2 = 1re barre
        -- cochée ; native 3 = 2e ; etc. Repère par NUMÉRO DE BARRE, pas slot.
        local np = ResolveNativePage()
        local list = BarPageList(cfg)
        if #list > 0 then
            -- Cyclique : le curseur natif (1-6) BOUCLE sur les N+1 états
            -- (propre + N barres). La séquence se limite donc au nombre de
            -- pages définies (pas de défilement dans le vide).
            local states = #list + 1
            local idx = (np - 1) % states   -- 0 = propre, 1..N = barres
            if idx == 0 then return BarBasePage(cfg, barIndex) end
            local target = list[idx]
            if target then return BarPageFromIndex(target) end
            return BarBasePage(cfg, barIndex)
        end
        -- Repli : ancien décalage de pages (compat profils).
        local off = tonumber(cfg.pageOffset) or 0
        return Clamp(np + off, 1, 11)
    elseif mode == "table" then
        local np = ResolveNativePage()
        local map = cfg.pageMap
        local target = map and tonumber(map[np])
        if target then return Clamp(target, 1, 11) end
        local base = map and tonumber(map[1])
        return Clamp(base or np, 1, 11)
    end
    return nil
end

-- Chaîne du state-driver « page » d'une barre (mêmes conditions que le visuel).
local function BarPageDriver(cfg, barIndex)
    local mode = BarPagingMode(cfg, barIndex)
    if mode == "native" then
        return NativePageDriver()
    elseif mode == "linked" then
        local list = BarPageList(cfg)
        local clauses = {}
        if #list > 0 then
            local base = BarBasePage(cfg, barIndex)
            local states = #list + 1
            for np = 2, 6 do
                local idx = (np - 1) % states
                local page = (idx == 0) and base or (BarPageFromIndex(list[idx]) or base)
                clauses[#clauses + 1] = ("[bar:%d] %d"):format(np, page)
            end
            clauses[#clauses + 1] = tostring(base)
        else
            local off = tonumber(cfg.pageOffset) or 0
            for np = 2, 6 do
                clauses[#clauses + 1] = ("[bar:%d] %d"):format(np, Clamp(np + off, 1, 11))
            end
            clauses[#clauses + 1] = tostring(Clamp(1 + off, 1, 11))
        end
        return table.concat(clauses, "; ")
    elseif mode == "table" then
        local map = cfg.pageMap or {}
        local clauses = {}
        for np = 2, 6 do
            local target = tonumber(map[np])
            if target then
                clauses[#clauses + 1] = ("[bar:%d] %d"):format(np, Clamp(target, 1, 11))
            end
        end
        local base = tonumber(map[1]) or 1
        clauses[#clauses + 1] = tostring(Clamp(base, 1, 11))
        return table.concat(clauses, "; ")
    end
    return nil
end

local function IsSpecialBarIndex(barIndex)
    return barIndex == SPECIAL_BAR_INDEX or barIndex == "special"
end

local function SpecialStatePrefix(hidden)
    local state = hidden and "hide" or "show"
    return ("[petbattle] hide; [vehicleui] %s; [overridebar] %s; [possessbar] %s; [bonusbar:5] %s; "):format(state, state, state, state)
end

local function IsSpecialActionState()
    local checks = {
        function() return UnitHasVehicleUI and UnitHasVehicleUI("player") end,
        function() return HasVehicleActionBar and HasVehicleActionBar() end,
        function() return HasOverrideActionBar and HasOverrideActionBar() end,
        function() return HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() end,
        function() return GetBonusBarOffset and GetBonusBarOffset() == 5 end,
        function() return C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar() end,
        function() return C_ActionBar and C_ActionBar.HasOverrideActionBar and C_ActionBar.HasOverrideActionBar() end,
    }
    for _, fn in ipairs(checks) do
        local ok, value = pcall(fn)
        if ok and value then return true end
    end
    return false
end

local function ResolveButtonSlot(cfg, buttonIndex, barIndex)
    buttonIndex = Clamp(buttonIndex, 1, MAX_BUTTONS)
    if IsSpecialBarIndex(barIndex) then
        return SPECIAL_SLOT_START + buttonIndex - 1
    end
    local page = ResolveBarDisplayPage(cfg, barIndex)
    if page then
        return ((page - 1) * 12) + buttonIndex
    end
    return Clamp((tonumber(cfg.firstSlot) or 1) + buttonIndex - 1, 1, 180)
end

-- Famille de commandes de binding native par barre SphereUI. Quand on prend
-- possession des raccourcis, chaque barre « emprunte » les touches assignées à
-- sa famille Blizzard correspondante (bar 1 = ACTIONBUTTON, bar 2 = MultiBar1…).
local BAR_BINDING_FAMILY = {
    [1] = "ACTIONBUTTON",
    [2] = "MULTIACTIONBAR1BUTTON",
    [3] = "MULTIACTIONBAR2BUTTON",
    [4] = "MULTIACTIONBAR3BUTTON",
    [5] = "MULTIACTIONBAR4BUTTON",
    [6] = "MULTIACTIONBAR5BUTTON",
    [7] = "MULTIACTIONBAR6BUTTON",
    [8] = "MULTIACTIONBAR7BUTTON",
}

local function ButtonBindingName(cfg, buttonIndex, slot, barIndex)
    if IsSpecialBarIndex(barIndex) then
        return "ACTIONBUTTON" .. tostring(Clamp(buttonIndex, 1, 12))
    end
    local family = BAR_BINDING_FAMILY[tonumber(barIndex) or 0]
    if family then
        return family .. tostring(Clamp(buttonIndex, 1, 12))
    end
    return ActionBindingName(slot)
end

local function ShortKeyText(binding)
    if not binding then return "" end
    local key = GetBindingKey and GetBindingKey(binding)
    if not key then return "" end
    key = tostring(key):upper()
    key = key:gsub("CTRL%-", "C-"):gsub("SHIFT%-", "S-"):gsub("ALT%-", "A-")
    key = key:gsub("NUMPAD%s*", "")
    key = key:gsub("NUMPAD", "")
    key = key:gsub("PLUS", "+"):gsub("MINUS", "-"):gsub("MULTIPLY", "*"):gsub("DIVIDE", "/"):gsub("DECIMAL", ".")
    key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
    key = key:gsub("BUTTON", "M")
    return key
end

-- BUG-041 : GetActionCooldown retourne des SECRET NUMBERS en Midnight —
-- tonumber(secret) RETOURNE le secret et toute comparaison crash. Toutes les
-- décisions Lua passent en pcall; les valeurs brutes vont à SetCooldown qui
-- les accepte côté C (pattern hpBar).
local function SetCooldownFrame(cd, start, duration, enable, modRate)
    if not cd then return end
    local okOff, isOff = pcall(function()
        return (tonumber(duration) or 0) <= 0 or enable == 0
    end)
    if okOff and isOff then
        pcall(cd.Clear, cd)
        return
    end
    -- Valeurs lisibles OU secrètes : le moteur C trace le swipe lui-même.
    if not pcall(cd.SetCooldown, cd, start, duration, modRate) then
        pcall(cd.SetCooldown, cd, start, duration)
    end
end

local function SetIconInset(btn, pressed)
    if not btn or not btn.icon then return end
    local w = btn:GetWidth() or 36
    local h = btn:GetHeight() or w
    local zoom = btn._visualZoom or 1
    local scale = pressed and 0.94 or 1
    local ox = pressed and 1 or 0
    local oy = pressed and -1 or 0
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("CENTER", btn, "CENTER", ox, oy)
    btn.icon:SetSize(w * zoom * scale, h * zoom * scale)
end

local function SetButtonVisualZoom(btn, zoom)
    if not btn then return end
    btn._visualZoom = Clamp(zoom or 1, 0.75, 1.50)
    SetIconInset(btn, btn._snpPressed == true)
end

-- Enregistrement des clics aligné sur la CVar ActionButtonUseKeyDown.
-- Depuis Dragonflight, la CVar vaut 1 par défaut : le moteur secure déclenche
-- l'action au PRESS. Un bouton enregistré "AnyUp" seul ne déclenche RIEN au
-- clic souris. Pattern Bartender4 : suivre la CVar, ne jamais enregistrer les
-- deux (double déclenchement = canalisations annulées).
local function ApplyClickRegistration(btn, cfg)
    if not btn then return end
    -- Anti-latence : si l'option globale castOnDown est active (défaut), nos
    -- boutons déclenchent au PRESS quelle que soit la CVar Blizzard. Sinon on
    -- suit la CVar ActionButtonUseKeyDown / le réglage par barre clickOnDown.
    local root = DB().actionbars
    local down = (type(root) == "table" and root.castOnDown ~= false)
    if not down then
        down = cfg and cfg.clickOnDown == true
        if not down then
            local ok, useKeyDown = pcall(function()
                return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false
            end)
            down = ok and useKeyDown == true
        end
    end
    btn:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

local function IsActionMoveGesture()
    if IsShiftKeyDown then
        local ok, down = pcall(IsShiftKeyDown)
        if ok and down then return true end
    end
    return false
end

function M:CanMoveAction()
    if InCombat() then return false end
    local root = DB().actionbars
    if root and root.lock == false then return true end
    return IsActionMoveGesture()
end

function M:PickupButtonAction(btn)
    if not (btn and btn._slot and PickupAction and self:CanMoveAction()) then return false end
    local ok = pcall(PickupAction, btn._slot)
    if ok then
        self._dragSourceButton = btn
        self._dragSourceSlot = btn._slot
        return true
    end
    return false
end

function M:PlaceButtonAction(btn)
    if not (btn and btn._slot and PlaceAction and self:CanMoveAction()) then return false end
    local ok = pcall(PlaceAction, btn._slot)
    if ok then
        self:UpdateButton(btn)
        if self._dragSourceButton and self._dragSourceButton ~= btn then
            self:UpdateButton(self._dragSourceButton)
        end
        self._dragSourceButton = nil
        self._dragSourceSlot = nil
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Drag highlight : pendant qu'un sort/objet/macro est sur le curseur, tous les
-- emplacements des barres SNP deviennent visibles : anneau circulaire par slot,
-- nom de barre au-dessus, raccourci clavier affiché même sur slot vide.
-- Vert = slot libre, doré = slot occupé (drop = échange).
-- Purement visuel et insecure : aucun attribut secure n'est touché.
-- Le ghost carré attaché au curseur est dessiné par le moteur C de WoW
-- (PickupAction) et ne peut pas être modifié par un addon — limite Blizzard.
-------------------------------------------------------------------------------
local DRAG_CURSOR_TYPES = {
    spell = true, item = true, macro = true, mount = true,
    petaction = true, flyout = true, battlepet = true, equipmentset = true,
}

function M:EnsureDragHighlight(btn)
    if btn.dragRing then return end
    local ring = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    ring:SetTexture(SP.SHADOW_CIRCLE_PATH or "Interface\\Buttons\\UI-ActionButton-Border")
    ring:SetPoint("CENTER", btn, "CENTER")
    ring:SetBlendMode("ADD")
    ring:Hide()
    btn.dragRing = ring
end

function M:EnsureDragLabel(bar)
    if bar.dragLabel then return end
    local fs = bar:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetTextColor(0.45, 1.0, 0.78, 1)
    fs:SetPoint("BOTTOM", bar, "TOP", 0, 6)
    fs:SetText(bar._index == SPECIAL_BAR_INDEX and "Barre spéciale" or ("Barre " .. tostring(bar._index)))
    fs:Hide()
    bar.dragLabel = fs
end

function M:SetDragHighlights(active)
    active = active and true or false
    if active == (self._dragHighlightActive or false) then return end
    self._dragHighlightActive = active
    if not self.bars then return end
    for index, bar in pairs(self.bars) do
        -- Barre spéciale exclue : contextuelle véhicule, pas une cible de drop
        if index ~= SPECIAL_BAR_INDEX then
            local cfg = self:GetBarConfig(index)
            local barOn = cfg and cfg.enabled == true and bar:IsShown()
            if active and barOn then
                self:EnsureDragLabel(bar)
                bar.dragLabel:Show()
                local ringSize = (tonumber(cfg.size) or 36) * 1.30
                for _, btn in ipairs(bar.buttons or {}) do
                    if btn:IsShown() then
                        self:EnsureDragHighlight(btn)
                        btn.dragRing:SetSize(ringSize, ringSize)
                        local hasAction = false
                        if HasAction and btn._slot then
                            local ok, ha = pcall(function()
                                return HasAction(btn._slot) == true
                            end)
                            hasAction = ok and ha == true
                        end
                        if hasAction then
                            btn.dragRing:SetVertexColor(1.00, 0.82, 0.25, 0.85)
                        else
                            btn.dragRing:SetVertexColor(0.30, 1.00, 0.55, 0.85)
                        end
                        btn.dragRing:Show()
                        btn:SetAlpha(1)
                        -- Jamais de carré : le fond vide reste invisible pendant le drag
                        if btn.bg then btn.bg:SetVertexColor(0.03, 0.025, 0.018, 0) end
                        if btn.hotkey and (btn.hotkey:GetText() or "") == "" then
                            btn.hotkey:SetText(ShortKeyText(btn._bindingName))
                        end
                    end
                end
            else
                if bar.dragLabel then bar.dragLabel:Hide() end
                for _, btn in ipairs(bar.buttons or {}) do
                    if btn.dragRing then btn.dragRing:Hide() end
                    -- UpdateButton restaure alpha/fond/hotkey selon la config
                    self:UpdateButton(btn)
                end
            end
        end
    end
end

function M:UpdateDragHighlightState()
    local cursorType
    if GetCursorInfo then
        local ok, ct = pcall(GetCursorInfo)
        cursorType = ok and ct or nil
    end
    local active = cursorType ~= nil
        and DRAG_CURSOR_TYPES[cursorType] == true
        and not InCombat()
        and self:IsEnabled()
    self:SetDragHighlights(active)
end

function M:ApplyAllClickRegistrations()
    if InCombat() then
        self._pendingRebuild = true
        return
    end
    if not self.bars then return end
    for index, bar in pairs(self.bars) do
        local cfg = self:GetBarConfig(index)
        for _, btn in ipairs(bar.buttons or {}) do
            ApplyClickRegistration(btn, cfg)
        end
    end
end

function M:GetEditGridSize()
    local root = self:EnsureDefaults()
    return Clamp(root.editGridSize or DEFAULT_GRID_SIZE, 4, 96)
end

function M:SnapPoint(x, y)
    local root = self:EnsureDefaults()
    if root.editSnap == false then return x, y end
    local grid = self:GetEditGridSize()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    return math.floor((x / grid) + 0.5) * grid, math.floor((y / grid) + 0.5) * grid
end

function M:EnsureEditGrid()
    if self.editGrid then return self.editGrid end
    local f = CreateFrame("Frame", "SPEditGrid", UIParent)
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(1)
    f:SetAllPoints(UIParent)
    f:EnableMouse(false)
    f.lines = {}
    f:Hide()
    self.editGrid = f
    return f
end

function M:UpdateEditGrid()
    local root = self:EnsureDefaults()
    local f = self:EnsureEditGrid()
    for _, line in ipairs(f.lines or {}) do
        line:Hide()
    end
    if not (IsEditMode() and self:IsEnabled() and root.editGrid ~= false) then
        f:Hide()
        return
    end

    local grid = self:GetEditGridSize()
    local uiW = UIParent and UIParent:GetWidth() or 0
    local uiH = UIParent and UIParent:GetHeight() or 0
    if uiW <= 0 or uiH <= 0 then return end

    f:SetAllPoints(UIParent)
    local poolIndex = 0
    local function acquire()
        poolIndex = poolIndex + 1
        local line = f.lines[poolIndex]
        if not line then
            line = f:CreateTexture(nil, "ARTWORK")
            line:SetTexture(WHITE)
            f.lines[poolIndex] = line
        end
        line:ClearAllPoints()
        line:Show()
        return line
    end

    local halfW, halfH = uiW * 0.5, uiH * 0.5
    local minX = -math.ceil(halfW / grid) * grid
    local maxX = math.ceil(halfW / grid) * grid
    local minY = -math.ceil(halfH / grid) * grid
    local maxY = math.ceil(halfH / grid) * grid

    for x = minX, maxX, grid do
        local major = math.abs(x) < 0.01 or ((math.floor(math.abs(x / grid)) % 4) == 0)
        local line = acquire()
        line:SetPoint("TOP", UIParent, "CENTER", x, halfH)
        line:SetPoint("BOTTOM", UIParent, "CENTER", x, -halfH)
        line:SetWidth(math.abs(x) < 0.01 and 2 or 1)
        if math.abs(x) < 0.01 then
            line:SetVertexColor(1.0, 0.72, 0.18, 0.38)
        elseif major then
            line:SetVertexColor(0.78, 0.58, 0.30, 0.18)
        else
            line:SetVertexColor(0.55, 0.85, 0.95, 0.075)
        end
    end
    for y = minY, maxY, grid do
        local major = math.abs(y) < 0.01 or ((math.floor(math.abs(y / grid)) % 4) == 0)
        local line = acquire()
        line:SetPoint("LEFT", UIParent, "CENTER", -halfW, y)
        line:SetPoint("RIGHT", UIParent, "CENTER", halfW, y)
        line:SetHeight(math.abs(y) < 0.01 and 2 or 1)
        if math.abs(y) < 0.01 then
            line:SetVertexColor(1.0, 0.72, 0.18, 0.38)
        elseif major then
            line:SetVertexColor(0.78, 0.58, 0.30, 0.18)
        else
            line:SetVertexColor(0.55, 0.85, 0.95, 0.075)
        end
    end
    f:Show()
end

function M:HideEditGrid()
    if self.editGrid then self.editGrid:Hide() end
end

local function HideTexture(tex)
    if not tex then return end
    pcall(tex.SetTexture, tex, nil)
    pcall(tex.SetAlpha, tex, 0)
    pcall(tex.Hide, tex)
end

local function StripButtonChrome(btn)
    if not btn then return end
    pcall(btn.SetNormalTexture, btn, nil)
    pcall(btn.SetPushedTexture, btn, nil)
    pcall(btn.SetDisabledTexture, btn, nil)
    pcall(btn.SetHighlightTexture, btn, nil)
    pcall(btn.SetCheckedTexture, btn, nil)
    local tex = btn.GetNormalTexture and btn:GetNormalTexture()
    if tex and tex ~= btn.hover then HideTexture(tex) end
    tex = btn.GetPushedTexture and btn:GetPushedTexture()
    if tex and tex ~= btn.hover then HideTexture(tex) end
    tex = btn.GetDisabledTexture and btn:GetDisabledTexture()
    if tex and tex ~= btn.hover then HideTexture(tex) end
    tex = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if tex and tex ~= btn.hover then HideTexture(tex) end
    tex = btn.GetCheckedTexture and btn:GetCheckedTexture()
    if tex and tex ~= btn.hover then HideTexture(tex) end
end

local function SkinEnabled(cfg)
    return cfg and cfg.buttonSkin == "shadowcircle"
end

local function SetMaskedPoints(mask, owner)
    if not mask or not owner then return end
    pcall(mask.ClearAllPoints, mask)
    pcall(mask.SetAllPoints, mask, owner)
end

local function EnsureButtonSkin(btn)
    if not btn or btn._skinReady then return end
    btn._skinReady = true

    btn.iconMask = btn:CreateMaskTexture()
    pcall(function()
        btn.iconMask:SetTexture(ACTION_BUTTON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        SetMaskedPoints(btn.iconMask, btn.icon)
        btn.icon:AddMaskTexture(btn.iconMask)
    end)

    btn.cooldownShade = btn:CreateTexture(nil, "OVERLAY", nil, -1)
    btn.cooldownShade:SetTexture(WHITE)
    btn.cooldownShade:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", 0, 0)
    btn.cooldownShade:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", 0, 0)
    btn.cooldownShade:SetVertexColor(0, 0, 0, 0)
    btn.cooldownShade:Hide()

    btn.cooldownShadeMask = btn:CreateMaskTexture()
    pcall(function()
        btn.cooldownShadeMask:SetTexture(ACTION_BUTTON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        SetMaskedPoints(btn.cooldownShadeMask, btn.cooldownShade)
        btn.cooldownShade:AddMaskTexture(btn.cooldownShadeMask)
    end)

    btn.skinRing = btn:CreateTexture(nil, "OVERLAY", nil, 4)
    btn.skinRing:SetTexture(SP.SHADOW_CIRCLE_PATH or SHADOW_CIRCLE_TEX)
    btn.skinRing:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.skinRing:SetBlendMode("BLEND")
    btn.skinRing:SetVertexColor(1.0, 0.86, 0.58, 1)
    btn.skinRing:SetAlpha(0)
    btn.skinRing:Hide()

    -- BUG-049 : l'arc de cooldown custom (segments + ticker 0.03s) est SUPPRIMÉ.
    -- Il repeignait 36 segments par bouton à 33 FPS → grosse chute de FPS au
    -- lancement d'un sort en recharge. Le balayage + chiffres NATIFS de la
    -- CooldownFrame (BUG-048) gèrent tout, gratuitement côté C.
end

local function LayoutCooldownArc(btn)
    if not (btn and btn.cooldownArc) then return end
    local size = btn:GetWidth() or 36
    local radius = size * 0.485
    local segLen = math.max(2.0, (2 * math.pi * radius / COOLDOWN_ARC_SEGMENTS) * 0.72)
    local segThick = math.max(1.5, size * 0.055)
    for i, seg in ipairs(btn.cooldownArc) do
        local angle = (math.pi * 0.5) - ((i - 0.5) / COOLDOWN_ARC_SEGMENTS) * 2 * math.pi
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        seg:SetSize(segLen, segThick)
        seg:ClearAllPoints()
        seg:SetPoint("CENTER", btn, "CENTER", x, y)
        seg:SetRotation(-(angle - math.pi * 0.5))
    end
end

local function ClearCooldownArc(btn)
    if not (btn and btn.cooldownArc) then return end
    for _, seg in ipairs(btn.cooldownArc) do
        seg:SetAlpha(0)
        seg:Hide()
    end
end

local function PaintCooldownArc(btn, remainingRatio, cfg)
    if not (btn and btn.cooldownArc and SkinEnabled(cfg)) then
        ClearCooldownArc(btn)
        return
    end
    local lit = math.floor(Clamp(remainingRatio, 0, 1) * COOLDOWN_ARC_SEGMENTS + 0.5)
    local baseAlpha = Clamp(cfg.skinAlpha, 0, 1)
    for i, seg in ipairs(btn.cooldownArc) do
        if i <= lit then
            local k = 0.68 + 0.32 * (i / math.max(1, lit))
            seg:SetVertexColor(1.0, 0.82 * k, 0.26 * k, 1)
            seg:SetAlpha(baseAlpha)
            seg:Show()
        else
            seg:SetAlpha(0)
            seg:Hide()
        end
    end
end

local function ApplyButtonSkin(btn, cfg, hasAction)
    if not btn then return end
    EnsureButtonSkin(btn)
    local enabled = SkinEnabled(cfg)
    local size = btn:GetWidth() or 36
    local scale = SHADOW_CIRCLE_BAR_SCALE
    if btn.skinRing then
        btn.skinRing:SetSize(size * scale, size * scale)
        btn.skinRing:SetShown(enabled and hasAction == true)
        btn.skinRing:SetAlpha((enabled and hasAction) and Clamp(cfg.skinAlpha, 0, 1) or 0)
    end
    if btn.iconMask then
        SetMaskedPoints(btn.iconMask, btn.icon)
    end
    if btn.cooldownShadeMask then
        SetMaskedPoints(btn.cooldownShadeMask, btn.cooldownShade)
    end
    LayoutCooldownArc(btn)
    if not enabled and btn.cooldownShade then
        btn.cooldownShade:SetAlpha(0)
        btn.cooldownShade:Hide()
    end
    if not enabled or hasAction ~= true then
        ClearCooldownArc(btn)
    end
end

function M:ClearCooldownSkin(btn)
    if not btn then return end
    if self.cooldownSkinButtons then self.cooldownSkinButtons[btn] = nil end
    btn._skinCooldownStart = nil
    btn._skinCooldownDuration = nil
    if btn.cdText then
        btn.cdText:SetText("")
        btn.cdText:Hide()
    end
    if btn.cooldownShade then
        btn.cooldownShade:SetAlpha(0)
        btn.cooldownShade:Hide()
    end
    if btn.skinRing then
        btn.skinRing:SetRotation(0)
    end
    ClearCooldownArc(btn)
end

local function FormatCooldownTime(seconds)
    seconds = math.ceil(tonumber(seconds) or 0)
    if seconds <= 0 then return "" end
    if seconds >= 60 then
        return tostring(math.ceil(seconds / 60)) .. "M"
    end
    return tostring(seconds)
end

function M:UpdateCooldownSkin(btn)
    if not btn or not btn._skinCooldownStart or not btn._skinCooldownDuration then
        self:ClearCooldownSkin(btn)
        return
    end
    local cfg = self:GetBarConfig(btn._barIndex)
    if cfg.showCooldown == false then
        self:ClearCooldownSkin(btn)
        return
    end
    local ok, remainingRatio, elapsedRatio, remaining = pcall(function()
        local start = tonumber(btn._skinCooldownStart) or 0
        local duration = tonumber(btn._skinCooldownDuration) or 0
        if duration <= MIN_SKIN_COOLDOWN then return 0, 1, 0 end
        local now = GetTime and GetTime() or 0
        local elapsed = now - start
        local remaining = (start + duration) - now
        if remaining <= 0 then return 0, 1, 0 end
        return Clamp(remaining / duration, 0, 1), Clamp(elapsed / duration, 0, 1), remaining
    end)
    if not ok or remainingRatio <= 0 then
        self:ClearCooldownSkin(btn)
        return
    end
    -- cdText custom DÉSACTIVÉ (BUG-048) : les chiffres natifs de la CooldownFrame
    -- affichent le temps restant. On ne garde que l'ombre/anneau décoratifs.
    if btn.cdText then btn.cdText:Hide() end
    if btn.cooldownShade and SkinEnabled(cfg) and cfg.cooldownShade ~= false then
        btn.cooldownShade:SetVertexColor(0, 0, 0, Clamp(cfg.cooldownShadeAlpha, 0, 1) * remainingRatio)
        btn.cooldownShade:Show()
    elseif btn.cooldownShade then
        btn.cooldownShade:SetAlpha(0)
        btn.cooldownShade:Hide()
    end
    if btn.skinRing and SkinEnabled(cfg) then
        btn.skinRing:SetAlpha(Clamp(cfg.skinAlpha, 0, 1))
        if cfg.cooldownRingSpin ~= false then
            btn.skinRing:SetRotation((elapsedRatio or 0) * math.pi * 2)
        else
            btn.skinRing:SetRotation(0)
        end
    end
    PaintCooldownArc(btn, remainingRatio, cfg)
end

function M:EnsureCooldownSkinTicker()
    if self.cooldownSkinTicker then return end
    local f = CreateFrame("Frame")
    f:Hide()
    f.elapsed = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.elapsed = (frame.elapsed or 0) + (elapsed or 0)
        if frame.elapsed < 0.03 then return end
        frame.elapsed = 0
        local any = false
        for btn in pairs(M.cooldownSkinButtons or {}) do
            if btn and btn:IsShown() then
                any = true
                M:UpdateCooldownSkin(btn)
            else
                M.cooldownSkinButtons[btn] = nil
            end
        end
        if not any then frame:Hide() end
    end)
    self.cooldownSkinTicker = f
end

-- BUG-049 : NO-OP. L'animation de cooldown custom (ticker 0.03s + arc + ombre
-- + rotation) est supprimée pour les FPS. Le cooldown natif (BUG-048) suffit.
-- On s'assure juste qu'aucun bouton ne reste dans le ticker.
function M:RegisterCooldownSkin(btn)
    if btn then self:ClearCooldownSkin(btn) end
    if self.cooldownSkinTicker then self.cooldownSkinTicker:Hide() end
end

function M:CreateButton(bar, barIndex, buttonIndex)
    local name = IsSpecialBarIndex(barIndex)
        and ("SPActionBarSpecialButton%d"):format(buttonIndex)
        or ("SPActionBar%dButton%d"):format(barIndex, buttonIndex)
    local b = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
    StripButtonChrome(b)
    ApplyClickRegistration(b, M:GetBarConfig(barIndex))
    b:RegisterForDrag("LeftButton")
    b:SetAttribute("type", "action")
    b._barIndex = barIndex
    b._buttonIndex = buttonIndex

    -- Masque circulaire pour TOUT le chrome du bouton (fond, hover, press,
    -- glow de relâchement). Sans lui, les slots vides et les feedbacks
    -- apparaissent en CARRÉ alors que les icônes sont rondes.
    b.chromeMask = b:CreateMaskTexture()
    pcall(function()
        b.chromeMask:SetTexture(ACTION_BUTTON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.chromeMask:SetAllPoints(b)
    end)

    -- ARTWORK -1 (sous l'icône) et pas BACKGROUND : en Midnight 12.x,
    -- AddMaskTexture peut être ignoré sur le layer BACKGROUND (cf. WIKI/Orb.lua).
    b.bg = b:CreateTexture(nil, "ARTWORK", nil, -1)
    b.bg:SetAllPoints()
    b.bg:SetTexture(WHITE)
    b.bg:SetVertexColor(0.03, 0.025, 0.018, 0.72)
    pcall(b.bg.AddMaskTexture, b.bg, b.chromeMask)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture(WHITE)
    b.border:SetVertexColor(0, 0, 0, 0)
    b.border:SetAlpha(0)
    pcall(b.border.AddMaskTexture, b.border, b.chromeMask)

    b.hover = b:CreateTexture(nil, "HIGHLIGHT")
    b.hover:SetAllPoints()
    b.hover:SetTexture(WHITE)
    b.hover:SetBlendMode("ADD")
    b.hover:SetVertexColor(1.0, 0.82, 0.25, 0.16)
    pcall(b.hover.AddMaskTexture, b.hover, b.chromeMask)
    b:SetHighlightTexture(b.hover)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    -- BUG-048 : le timer doit TOUJOURS être visible (sinon jeu à l'aveugle).
    -- On laisse la CooldownFrame NATIVE tout faire, comme les barres Blizzard :
    --   • SetDrawSwipe(true)            → balayage radial (assombrissement).
    --   • SetHideCountdownNumbers(false) → chiffres natifs du moteur.
    --   • SetUseCircularEdge(true)       → balayage circulaire (boutons ronds).
    -- Le moteur C gère les valeurs SECRÈTES de GetActionCooldown nativement
    -- (comme les barres Blizzard) → marche pour GCD courts ET cooldowns longs.
    pcall(b.cooldown.SetDrawSwipe, b.cooldown, true)
    pcall(b.cooldown.SetDrawEdge, b.cooldown, true)
    pcall(b.cooldown.SetDrawBling, b.cooldown, false)
    pcall(b.cooldown.SetHideCountdownNumbers, b.cooldown, false)
    pcall(b.cooldown.SetUseCircularEdge, b.cooldown, true)
    pcall(b.cooldown.SetSwipeColor, b.cooldown, 0, 0, 0, 0.55)

    b.cdText = b:CreateFontString(nil, "OVERLAY")
    b.cdText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    b.cdText:SetTextColor(1.0, 0.86, 0.22, 1)
    b.cdText:SetShadowColor(0, 0, 0, 1)
    b.cdText:SetShadowOffset(1, -1)
    b.cdText:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.cdText:Hide()

    b.press = b:CreateTexture(nil, "OVERLAY")
    b.press:SetAllPoints()
    b.press:SetTexture(WHITE)
    b.press:SetVertexColor(0, 0, 0, 0.38)
    b.press:Hide()
    pcall(b.press.AddMaskTexture, b.press, b.chromeMask)

    b.releaseGlow = b:CreateTexture(nil, "OVERLAY")
    b.releaseGlow:SetAllPoints()
    b.releaseGlow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.releaseGlow:SetBlendMode("ADD")
    b.releaseGlow:SetVertexColor(0.40, 1.00, 0.74, 1)
    b.releaseGlow:SetAlpha(0)
    b.releaseGlow:Hide()
    pcall(b.releaseGlow.AddMaskTexture, b.releaseGlow, b.chromeMask)

    b.releaseAnim = b.releaseGlow:CreateAnimationGroup()
    local fade = b.releaseAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.90)
    fade:SetToAlpha(0)
    fade:SetDuration(1.0)
    fade:SetSmoothing("OUT")
    b.releaseAnim:SetScript("OnFinished", function()
        b.releaseGlow:SetAlpha(0)
        b.releaseGlow:Hide()
    end)

    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)

    b.hotkey = b:CreateFontString(nil, "OVERLAY")
    b.hotkey:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    b.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -3)

    b.macro = b:CreateFontString(nil, "OVERLAY")
    b.macro:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    b.macro:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3, 3)
    b.macro:SetJustifyH("LEFT")
    b.macro:SetWidth(44)

    b:SetScript("OnEnter", function(btn)
        StripButtonChrome(btn)
        if btn.hover then btn:SetHighlightTexture(btn.hover) end
        local cfg = M:GetBarConfig(btn._barIndex)
        local parent = btn:GetParent()
        if parent and parent._displayMode == "mouseover" then parent:SetAlpha(cfg.alpha or 1) end
        SetButtonVisualZoom(btn, cfg.hoverScale and cfg.hoverScale ~= 1 and cfg.hoverScale or 1)
        if GameTooltip and btn._slot then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetAction, GameTooltip, btn._slot) then
                GameTooltip:SetText("Action slot " .. tostring(btn._slot), 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(btn)
        StripButtonChrome(btn)
        if btn.hover then btn:SetHighlightTexture(btn.hover) end
        local cfg = M:GetBarConfig(btn._barIndex)
        local parent = btn:GetParent()
        if parent and parent._displayMode == "mouseover" then parent:SetAlpha(cfg.inactiveAlpha or 0.25) end
        SetButtonVisualZoom(btn, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnDragStart", function(btn)
        M:PickupButtonAction(btn)
    end)
    b:SetScript("OnReceiveDrag", function(btn)
        M:PlaceButtonAction(btn)
    end)
    b:SetScript("OnMouseDown", function(btn)
        StripButtonChrome(btn)
        if btn.hover then btn:SetHighlightTexture(btn.hover) end
        M:PressButtonVisual(btn)
    end)
    b:SetScript("OnMouseUp", function(btn, mouseButton)
        StripButtonChrome(btn)
        if btn.hover then btn:SetHighlightTexture(btn.hover) end
        M:ReleaseButtonVisual(btn, true)
        if mouseButton == "RightButton" and IsEditMode() then
            M:ShowEditMenu(btn:GetParent())
            return
        end
        if mouseButton == "RightButton" and btn._slot and CursorHasItem and CursorHasItem() then
            M:PlaceButtonAction(btn)
        end
    end)
    b:SetScript("OnShow", function(btn)
        StripButtonChrome(btn)
        if btn.hover then btn:SetHighlightTexture(btn.hover) end
        M:UpdateButton(btn)
    end)
    StripButtonChrome(b)
    if b.hover then b:SetHighlightTexture(b.hover) end
    return b
end

function M:PressButtonVisual(btn)
    if not btn then return end
    btn._snpPressed = true
    SetIconInset(btn, true)
    if btn.press then
        btn.press:SetAlpha(0.38)
        btn.press:Show()
    end
end

function M:ReleaseButtonVisual(btn, pulse)
    if not btn then return end
    btn._snpPressed = nil
    SetIconInset(btn, false)
    if btn.press then btn.press:Hide() end
    if pulse and btn.releaseGlow and btn.releaseAnim then
        btn.releaseAnim:Stop()
        btn.releaseGlow:SetAlpha(0.90)
        btn.releaseGlow:Show()
        btn.releaseAnim:Play()
    end
end

function M:EnsureBar(index)
    self.bars = self.bars or {}
    if self.bars[index] then return self.bars[index] end
    local frameName = index == SPECIAL_BAR_INDEX and "SPActionBarSpecial" or ("SPActionBar" .. index)
    local bar = CreateFrame("Frame", frameName, UIParent, "SecureHandlerStateTemplate")
    bar._index = index
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar._isSPFrame = true
    bar.buttons = {}
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(f)
        if InCombat() or not IsEditMode() then return end
        pcall(f.StartMoving, f)
    end)
    bar:SetScript("OnDragStop", function(f)
        pcall(f.StopMovingOrSizing, f)
        M:SaveBarPosition(f)
    end)
    bar:SetAttribute("_onstate-visibility", [[
        if newstate == "show" then self:Show() else self:Hide() end
    ]])
    bar:SetAttribute("_onstate-page", [[
        local page = tonumber(newstate) or 1
        self:SetAttribute("nativePage", page)
        local count = tonumber(self:GetAttribute("buttonCount")) or 12
        for i = 1, count do
            local btn = self:GetFrameRef("button" .. i)
            if btn then
                btn:SetAttribute("action", ((page - 1) * 12) + i)
            end
        end
    ]])

    local edit = CreateFrame("Frame", nil, bar)
    edit:SetPoint("TOPLEFT", bar, "TOPLEFT", -EDIT_PAD, EDIT_PAD)
    edit:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", EDIT_PAD, -EDIT_PAD)
    edit:SetFrameLevel(bar:GetFrameLevel() + 40)
    edit:EnableMouse(true)
    edit:RegisterForDrag("LeftButton")
    edit.bg = edit:CreateTexture(nil, "BACKGROUND")
    edit.bg:SetAllPoints()
    edit.bg:SetTexture(WHITE)
    edit.bg:SetVertexColor(0.05, 0.25, 0.22, 0.28)
    edit.lines = {}
    for i = 1, 4 do
        local line = edit:CreateTexture(nil, "OVERLAY")
        line:SetTexture(WHITE)
        line:SetVertexColor(0.22, 1.0, 0.72, 0.72)
        edit.lines[i] = line
    end
    edit.lines[1]:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
    edit.lines[1]:SetPoint("TOPRIGHT", edit, "TOPRIGHT", 0, 0)
    edit.lines[1]:SetHeight(2)
    edit.lines[2]:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0)
    edit.lines[2]:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, 0)
    edit.lines[2]:SetHeight(2)
    edit.lines[3]:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
    edit.lines[3]:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0)
    edit.lines[3]:SetWidth(2)
    edit.lines[4]:SetPoint("TOPRIGHT", edit, "TOPRIGHT", 0, 0)
    edit.lines[4]:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, 0)
    edit.lines[4]:SetWidth(2)
    edit.label = edit:CreateFontString(nil, "OVERLAY")
    edit.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    edit.label:SetTextColor(0.45, 1.0, 0.78, 1)
    edit.label:SetPoint("CENTER")
    edit.label:SetText("Barre " .. index)
    edit:SetScript("OnDragStart", function()
        if InCombat() or not IsEditMode() then return end
        pcall(bar.StartMoving, bar)
    end)
    edit:SetScript("OnDragStop", function()
        pcall(bar.StopMovingOrSizing, bar)
        M:SaveBarPosition(bar)
    end)
    edit:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and IsEditMode() then
            M:ShowEditMenu(bar)
        end
    end)
    edit:Hide()
    bar.editFrame = edit

    self.bars[index] = bar
    return bar
end

function M:GetSpecialAnchor()
    local moi = SP.Moi
    local data = moi and moi.data
    return (data and (data.orbFrame or data.root)) or (moi and moi.anchor) or UIParent
end

function M:GetMoiLayoutCenter()
    local moi = SP.Moi
    local data = moi and moi.data
    local anchor = (data and (data.orbFrame or data.root)) or (moi and moi.anchor)
    if anchor and anchor.GetCenter then
        local ok, ax, ay, ux, uy = pcall(function()
            local cx, cy = anchor:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            return cx, cy, ucx, ucy
        end)
        if ok and ax and ay and ux and uy then
            return ax - ux, ay - uy
        end
    end
    local db = DB()
    return tonumber(db.moi_x) or -280, tonumber(db.moi_y) or -170
end

function M:GetMoiVisualRadius()
    local cfg = SP.GetCfg and SP:GetCfg("PLAYER_SELF") or {}
    local db = DB()
    local size = tonumber(cfg.size) or 74
    local scale = Clamp(db.moi_scale or 1, 0.5, 2.0)
    local borderScale = Clamp(cfg.borderOverlayScale or 1, 0.80, 3.00)
    return (size * 0.5 * math.max(1, borderScale)) * scale
end

function M:GetLinkedBarPosition(index, cfg, width, height)
    local root = self:EnsureDefaults()
    if root.primaryPairAnchor == false or not cfg then return nil end
    local mode = cfg.anchorMode
    if index == 1 and mode == nil then mode = "moi_left" end
    if index == 6 and mode == nil then mode = "moi_right" end
    if mode ~= "moi_left" and mode ~= "moi_right" then return nil end

    local mx, my = self:GetMoiLayoutCenter()
    local barScale = Clamp(cfg.scale or 1, 0.50, 2.0)
    local halfW = (tonumber(width) or 0) * barScale * 0.5
    local gap = Clamp(root.primaryPairGap or DEFAULT_PRIMARY_PAIR_GAP, 0, 240)
    local y = my + (tonumber(root.primaryPairYOffset) or 0)
    local radius = self:GetMoiVisualRadius()
    local x
    if mode == "moi_left" then
        x = mx - radius - gap - halfW
    else
        x = mx + radius + gap + halfW
    end
    return x, y
end

function M:SaveBarPosition(bar)
    if not bar or InCombat() then return end
    if bar._index == SPECIAL_BAR_INDEX then return end
    local root = self:EnsureDefaults()
    local cfg = root.bars[bar._index or 1]
    if not cfg then return end
    if IsEditMode() and (bar._index == 1 or bar._index == 6) then
        cfg.anchorMode = "free"
    end
    local ok, x, y = pcall(function()
        local left, bottom = bar:GetLeft(), bar:GetBottom()
        local width, height = bar:GetWidth(), bar:GetHeight()
        if not left or not bottom or not width or not height then return nil, nil end
        local scale = 1
        if bar.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
            local bs = bar:GetEffectiveScale() or 1
            local us = UIParent:GetEffectiveScale() or 1
            if us > 0 then scale = bs / us end
        end
        local uiW = UIParent and UIParent:GetWidth() or 0
        local uiH = UIParent and UIParent:GetHeight() or 0
        local cx = (left + (width * 0.5)) * scale
        local cy = (bottom + (height * 0.5)) * scale
        return cx - (uiW * 0.5), cy - (uiH * 0.5)
    end)
    if ok and x and y then
        if IsEditMode() then
            x, y = self:SnapPoint(x, y)
        end
        cfg.x = math.floor(x + 0.5)
        cfg.y = math.floor(y + 0.5)
    end
end

function M:ApplyEditMode(bar, cfg)
    local edit = IsEditMode() and self:IsEnabled() and cfg and cfg.enabled == true
    bar:EnableMouse(edit or not self:EnsureDefaults().lock)
    if bar.editFrame then
        bar.editFrame:ClearAllPoints()
        bar.editFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -EDIT_PAD, EDIT_PAD)
        bar.editFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", EDIT_PAD, -EDIT_PAD)
        bar.editFrame:SetShown(edit)
        if edit then
            if bar._index == SPECIAL_BAR_INDEX then
                bar.editFrame.label:SetText("Vehicule")
            else
                bar.editFrame.label:SetText("Barre " .. tostring(bar._index or "?"))
            end
        end
    end
end

local function EditMenuButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 20)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(WHITE)
    b.bg:SetVertexColor(0.16, 0.10, 0.045, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    b.text:SetTextColor(1.0, 0.82, 0.22, 1)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.32, 0.18, 0.06, 0.96) end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(0.16, 0.10, 0.045, 0.92) end)
    return b
end

function M:EditMenuApply(bar, cfg, key, value)
    if not bar or not cfg or InCombat() then return end
    local index = bar._index or 1
    if key == "followPaging" and index ~= 1 then
        value = false
    end
    cfg[key] = value
    if index == SPECIAL_BAR_INDEX then
        self:ApplySpecialLayout()
    else
        self:ApplyLayout(index)
    end
    if index ~= 1 and index ~= SPECIAL_BAR_INDEX and self.bars and self.bars[1] then
        self:ApplyLayout(1)
    end
    local liveBar = self.bars and self.bars[index] or bar
    if self.editMenu and self.editMenu:IsShown() then
        self:ShowEditMenu(liveBar)
    end
end

function M:EnsureEditMenu()
    if self.editMenu then return self.editMenu end
    local f = CreateFrame("Frame", "SPActionBarEditMenu", UIParent, "BackdropTemplate")
    f:SetSize(246, 336)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(650)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not InCombat() then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        frame._snpPositioned = true
    end)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left=3, right=3, top=3, bottom=3},
    })
    f:SetBackdropColor(0.025, 0.018, 0.012, 0.72)
    f:SetBackdropBorderColor(0.85, 0.55, 0.22, 0.78)
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    f.title:SetTextColor(1.0, 0.86, 0.28, 1)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.close = EditMenuButton(f, "x", function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
    f.lock = CreateFrame("Button", nil, f)
    f.lock:SetSize(110, 24)
    f.lock:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    f.lock.bg = f.lock:CreateTexture(nil, "BACKGROUND")
    f.lock.bg:SetAllPoints()
    f.lock.bg:SetTexture(WHITE)
    f.lock.bg:SetVertexColor(0.26, 0.10, 0.035, 0.74)
    f.lock.text = f.lock:CreateFontString(nil, "OVERLAY")
    f.lock.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.lock.text:SetTextColor(1.0, 0.86, 0.28, 1)
    f.lock.text:SetPoint("CENTER")
    f.lock.text:SetText("Verrouiller")
    f.lock:SetScript("OnClick", function()
        if M.SetEditMode then M:SetEditMode(false, true) end
    end)
    -- Bouton « Tableau des barres » : ouvre la config sur la grille.
    f.openTable = CreateFrame("Button", nil, f)
    f.openTable:SetSize(110, 24)
    f.openTable:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.openTable.bg = f.openTable:CreateTexture(nil, "BACKGROUND")
    f.openTable.bg:SetAllPoints()
    f.openTable.bg:SetTexture(WHITE)
    f.openTable.bg:SetVertexColor(0.10, 0.20, 0.30, 0.80)
    f.openTable.text = f.openTable:CreateFontString(nil, "OVERLAY")
    f.openTable.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.openTable.text:SetTextColor(0.55, 0.85, 1.0, 1)
    f.openTable.text:SetPoint("CENTER")
    f.openTable.text:SetText("Tableau")
    f.openTable:SetScript("OnClick", function()
        if SP.UIPlumber and SP.UIPlumber.OpenToBarsTable then
            pcall(SP.UIPlumber.OpenToBarsTable, SP.UIPlumber)
        end
    end)
    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    f.hint:SetTextColor(0.78, 0.70, 0.58, 1)
    f.hint:SetPoint("BOTTOM", f.lock, "TOP", 0, 6)
    f.hint:SetText("Clic droit sur une barre")
    f.rows = {}
    f.rowPool = {}
    self.editMenu = f
    return f
end

function M:PositionEditMenu()
    local f = self:EnsureEditMenu()
    if f._snpPositioned then return f end
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -34, -20)
    f._snpPositioned = true
    return f
end

function M:ShowEditHud()
    if InCombat() then return end
    local f = self:PositionEditMenu()
    f.title:SetText("Edition SNP")
    f._bar = nil
    for _, row in ipairs(f.rowPool or {}) do row:Hide() end
    f.rows = {}
    if f.hint then f.hint:SetText("Grille active - clic droit sur une barre") end
    local root = self:EnsureDefaults()
    local function addHudRow(label, valueText, minusFn, plusFn)
        local idx = #f.rows + 1
        local row = f.rowPool[idx]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetSize(222, 22)
            row:EnableMouse(true)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture(WHITE)
            row.bg:SetVertexColor(0.08, 0.05, 0.025, 0.24)
            row.label = row:CreateFontString(nil, "OVERLAY")
            row.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            row.label:SetTextColor(0.94, 0.82, 0.38, 1)
            row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.value = row:CreateFontString(nil, "OVERLAY")
            row.value:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            row.value:SetTextColor(1, 1, 1, 1)
            row.value:SetPoint("RIGHT", row, "RIGHT", -58, 0)
            row.minus = EditMenuButton(row, "-", nil)
            row.minus:SetPoint("RIGHT", row, "RIGHT", -28, 0)
            row.plus = EditMenuButton(row, "+", nil)
            row.plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            f.rowPool[idx] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36 - (#f.rows * 24))
        row.label:SetText(label)
        row.value:SetText(valueText)
        row.minus:SetScript("OnClick", minusFn)
        row.plus:SetScript("OnClick", plusFn)
        local function onWheel(_, delta)
            if (tonumber(delta) or 0) > 0 then
                if plusFn then plusFn() end
            elseif minusFn then
                minusFn()
            end
        end
        row:SetScript("OnMouseWheel", onWheel)
        if row.EnableMouseWheel then row:EnableMouseWheel(true) end
        row.minus:SetScript("OnMouseWheel", onWheel)
        row.plus:SetScript("OnMouseWheel", onWheel)
        if row.minus.EnableMouseWheel then row.minus:EnableMouseWheel(true) end
        if row.plus.EnableMouseWheel then row.plus:EnableMouseWheel(true) end
        row:SetScript("OnEnter", function(r)
            if r.bg then r.bg:SetVertexColor(0.18, 0.10, 0.04, 0.42) end
        end)
        row:SetScript("OnLeave", function(r)
            if r.bg then r.bg:SetVertexColor(0.08, 0.05, 0.025, 0.24) end
        end)
        row:Show()
        f.rows[idx] = row
    end
    local function refreshHud()
        self:UpdateEditGrid()
        self:Refresh()
        self:ShowEditHud()
    end
    addHudRow("Grille", root.editGrid ~= false and "ON" or "OFF", function()
        root.editGrid = root.editGrid == false
        refreshHud()
    end, function()
        root.editGrid = root.editGrid == false
        refreshHud()
    end)
    addHudRow("Snap", root.editSnap ~= false and "ON" or "OFF", function()
        root.editSnap = root.editSnap == false
        refreshHud()
    end, function()
        root.editSnap = root.editSnap == false
        refreshHud()
    end)
    addHudRow("Pas grille", tostring(self:GetEditGridSize()), function()
        root.editGridSize = Clamp((root.editGridSize or DEFAULT_GRID_SIZE) - 4, 4, 96)
        refreshHud()
    end, function()
        root.editGridSize = Clamp((root.editGridSize or DEFAULT_GRID_SIZE) + 4, 4, 96)
        refreshHud()
    end)
    addHudRow("Barres 1/6", root.primaryPairAnchor ~= false and "AUTO" or "LIBRE", function()
        root.primaryPairAnchor = root.primaryPairAnchor == false
        if root.primaryPairAnchor ~= false then
            if root.bars[1] then root.bars[1].anchorMode = "moi_left" end
            if root.bars[6] then root.bars[6].anchorMode = "moi_right" end
        end
        refreshHud()
    end, function()
        root.primaryPairAnchor = root.primaryPairAnchor == false
        if root.primaryPairAnchor ~= false then
            if root.bars[1] then root.bars[1].anchorMode = "moi_left" end
            if root.bars[6] then root.bars[6].anchorMode = "moi_right" end
        end
        refreshHud()
    end)
    addHudRow("Ecart 1/6", tostring(Clamp(root.primaryPairGap, 0, 240)), function()
        root.primaryPairGap = Clamp((root.primaryPairGap or DEFAULT_PRIMARY_PAIR_GAP) - 4, 0, 240)
        refreshHud()
    end, function()
        root.primaryPairGap = Clamp((root.primaryPairGap or DEFAULT_PRIMARY_PAIR_GAP) + 4, 0, 240)
        refreshHud()
    end)
    f:Show()
end

function M:ShowEditMenu(bar)
    if not bar or not bar._index or InCombat() then return end
    local cfg = self:GetBarConfig(bar._index)
    local f = self:PositionEditMenu()
    f._bar = bar
    for _, row in ipairs(f.rowPool or {}) do row:Hide() end
    f.rows = {}
    f.title:SetText(bar._index == SPECIAL_BAR_INDEX and "Vehicule - edition" or ("Barre " .. tostring(bar._index) .. " - edition"))
    if f.hint then f.hint:SetText("Survole une option + molette") end

    local function addRow(label, valueText, minusFn, plusFn)
        local idx = #f.rows + 1
        local row = f.rowPool[idx]
        if not row then
            row = CreateFrame("Frame", nil, f)
            row:SetSize(222, 22)
            row:EnableMouse(true)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture(WHITE)
            row.bg:SetVertexColor(0.08, 0.05, 0.025, 0.24)
            row.label = row:CreateFontString(nil, "OVERLAY")
            row.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            row.label:SetTextColor(0.94, 0.82, 0.38, 1)
            row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.value = row:CreateFontString(nil, "OVERLAY")
            row.value:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            row.value:SetTextColor(1, 1, 1, 1)
            row.value:SetPoint("RIGHT", row, "RIGHT", -58, 0)
            row.minus = EditMenuButton(row, "-", nil)
            row.minus:SetPoint("RIGHT", row, "RIGHT", -28, 0)
            row.plus = EditMenuButton(row, "+", nil)
            row.plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            f.rowPool[idx] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36 - (#f.rows * 24))
        row.label:SetText(label)
        row.value:SetText(valueText)
        row.minus:SetScript("OnClick", minusFn)
        row.plus:SetScript("OnClick", plusFn)
        local function onWheel(_, delta)
            if (tonumber(delta) or 0) > 0 then
                if plusFn then plusFn() end
            elseif minusFn then
                minusFn()
            end
        end
        row:SetScript("OnMouseWheel", onWheel)
        if row.EnableMouseWheel then row:EnableMouseWheel(true) end
        row.minus:SetScript("OnMouseWheel", onWheel)
        row.plus:SetScript("OnMouseWheel", onWheel)
        if row.minus.EnableMouseWheel then row.minus:EnableMouseWheel(true) end
        if row.plus.EnableMouseWheel then row.plus:EnableMouseWheel(true) end
        row:SetScript("OnEnter", function(r)
            if r.bg then r.bg:SetVertexColor(0.18, 0.10, 0.04, 0.42) end
        end)
        row:SetScript("OnLeave", function(r)
            if r.bg then r.bg:SetVertexColor(0.08, 0.05, 0.025, 0.24) end
        end)
        row:Show()
        f.rows[idx] = row
    end

    local function apply(k, v) self:EditMenuApply(bar, cfg, k, v) end
    local orientation = cfg.orientation or "horizontal"
    addRow("Taille", tostring(Clamp(cfg.size, 20, 72)), function() apply("size", Clamp((cfg.size or 36) - 2, 20, 72)) end, function() apply("size", Clamp((cfg.size or 36) + 2, 20, 72)) end)
    addRow("Boutons", tostring(Clamp(cfg.buttons, 1, MAX_BUTTONS)), function() apply("buttons", Clamp((cfg.buttons or 12) - 1, 1, MAX_BUTTONS)) end, function() apply("buttons", Clamp((cfg.buttons or 12) + 1, 1, MAX_BUTTONS)) end)
    addRow("Colonnes", tostring(Clamp(cfg.columns, 1, MAX_BUTTONS)), function() apply("columns", Clamp((cfg.columns or 6) - 1, 1, MAX_BUTTONS)) end, function() apply("columns", Clamp((cfg.columns or 6) + 1, 1, MAX_BUTTONS)) end)
    addRow("Espacement", tostring(Clamp(cfg.spacing, 0, 16)), function() apply("spacing", Clamp((cfg.spacing or 4) - 1, 0, 16)) end, function() apply("spacing", Clamp((cfg.spacing or 4) + 1, 0, 16)) end)
    addRow("Echelle", string.format("%.2f", Clamp(cfg.scale, 0.5, 2.0)), function() apply("scale", Clamp((cfg.scale or 1) - 0.05, 0.5, 2.0)) end, function() apply("scale", Clamp((cfg.scale or 1) + 0.05, 0.5, 2.0)) end)
    if bar._index == 1 or bar._index == 6 then
        addRow("Ancrage", (cfg.anchorMode == "moi_left" and "Moi gauche") or (cfg.anchorMode == "moi_right" and "Moi droite") or "Libre", function()
            if bar._index == 1 then
                apply("anchorMode", cfg.anchorMode == "moi_left" and "free" or "moi_left")
            else
                apply("anchorMode", cfg.anchorMode == "moi_right" and "free" or "moi_right")
            end
        end, function()
            if bar._index == 1 then
                apply("anchorMode", cfg.anchorMode == "moi_left" and "free" or "moi_left")
            else
                apply("anchorMode", cfg.anchorMode == "moi_right" and "free" or "moi_right")
            end
        end)
    end
    if bar._index == SPECIAL_BAR_INDEX then
        addRow("Ecart horizontal", tostring(Clamp(cfg.offsetX, 70, 260)), function() apply("offsetX", Clamp((cfg.offsetX or 122) - 4, 70, 260)) end, function() apply("offsetX", Clamp((cfg.offsetX or 122) + 4, 70, 260)) end)
        addRow("Ecart vertical", tostring(Clamp(cfg.offsetY, 20, 120)), function() apply("offsetY", Clamp((cfg.offsetY or 42) - 3, 20, 120)) end, function() apply("offsetY", Clamp((cfg.offsetY or 42) + 3, 20, 120)) end)
    end
    addRow("Skin cercle", SkinEnabled(cfg) and "ON" or "OFF", function()
        apply("buttonSkin", SkinEnabled(cfg) and "none" or "shadowcircle")
    end, function()
        apply("buttonSkin", SkinEnabled(cfg) and "none" or "shadowcircle")
    end)
    addRow("Ombre CD", cfg.cooldownShade ~= false and "ON" or "OFF", function()
        apply("cooldownShade", cfg.cooldownShade == false)
    end, function()
        apply("cooldownShade", cfg.cooldownShade == false)
    end)
    addRow("Orientation", orientation, function()
        local nextValue = orientation == "grid" and "vertical" or orientation == "vertical" and "horizontal" or "grid"
        apply("orientation", nextValue)
    end, function()
        local nextValue = orientation == "horizontal" and "vertical" or orientation == "vertical" and "grid" or "horizontal"
        apply("orientation", nextValue)
    end)
    local barIdx = bar._index or 1
    if barIdx == 1 then
        -- Barre principale : suit la touche « barre suivante » de WoW.
        local on = BarPagingMode(cfg, 1) ~= "none"
        addRow("Pagination", on and "Page native" or "Aucune", function()
            apply("paging", on and "none" or "native")
        end, function()
            apply("paging", on and "none" or "native")
        end)
    else
        -- Barres secondaires : liées au curseur natif avec un décalage.
        local mode = BarPagingMode(cfg, barIdx)
        local label = (mode == "linked" and "Liée") or (mode == "native" and "Page native") or "Aucune"
        local function cyclePaging(dir)
            local order = { "none", "linked", "native" }
            local cur = 1
            for k, v in ipairs(order) do if v == mode then cur = k break end end
            cur = cur + dir
            if cur < 1 then cur = #order elseif cur > #order then cur = 1 end
            apply("paging", order[cur])
        end
        addRow("Pagination", label, function() cyclePaging(-1) end, function() cyclePaging(1) end)
        if mode == "linked" then
            addRow("Décalage page", tostring(tonumber(cfg.pageOffset) or 0),
                function() apply("pageOffset", Clamp((cfg.pageOffset or 0) - 1, -10, 10)) end,
                function() apply("pageOffset", Clamp((cfg.pageOffset or 0) + 1, -10, 10)) end)
        end
    end

    f:Show()
end

function M:SetEditMode(enabled, reopenConfig)
    if InCombat() then return end
    local db = DB()
    db.snp_edit_mode = enabled == true
    if db.snp_edit_mode then
        self:UpdateEditGrid()
        if SP.UIPlumber and SP.UIPlumber.Close then
            pcall(SP.UIPlumber.Close, SP.UIPlumber)
        elseif SP.UI and SP.UI.Close then
            pcall(SP.UI.Close, SP.UI)
        end
        self:Refresh()
        if SP.Moi and SP.Moi.Refresh then pcall(SP.Moi.Refresh, SP.Moi) end
        self:ShowEditHud()
    else
        self:HideEditGrid()
        if self.editMenu then self.editMenu:Hide() end
        self:Refresh()
        if SP.Moi and SP.Moi.Refresh then pcall(SP.Moi.Refresh, SP.Moi) end
        if reopenConfig and SP.UIPlumber and SP.UIPlumber.Open then
            pcall(SP.UIPlumber.Open, SP.UIPlumber)
        end
    end
end

function M:VisibilityDriver(mode, hideDuringSpecial)
    local prefix = hideDuringSpecial and SpecialStatePrefix(true) or "[petbattle] hide; "
    if mode == "combat" then
        return prefix .. "[combat] show; hide"
    elseif mode == "nocombat" then
        return prefix .. "[combat] hide; show"
    elseif mode == "target" then
        return prefix .. "[@target,exists] show; hide"
    elseif mode == "combat_target" then
        return prefix .. "[combat] show; [@target,exists] show; hide"
    elseif mode == "hidden" then
        return "hide"
    end
    return prefix .. "show"
end

function M:ApplyVisibility(bar, cfg)
    local mode = cfg.visibility or "always"
    bar._displayMode = mode
    local index = bar._index or 1
    local hideDuringSpecial = index == 1 or index == 6
    if IsEditMode() and self:IsEnabled() and cfg.enabled == true then
        if not InCombat() and UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
        bar:Show()
        bar:SetAlpha(1)
        return
    end
    if InCombat() then
        if mode == "mouseover" then
            bar:SetAlpha(cfg.inactiveAlpha or 0.25)
        elseif mode == "combatfade" then
            bar:SetAlpha(cfg.alpha or 1)
        else
            bar:SetAlpha(cfg.alpha or 1)
        end
        return
    end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
    if RegisterStateDriver then
        pcall(RegisterStateDriver, bar, "visibility", self:VisibilityDriver(mode, hideDuringSpecial))
    elseif mode == "hidden" then
        bar:Hide()
    elseif hideDuringSpecial and IsSpecialActionState() then
        bar:Hide()
    else
        bar:Show()
    end

    if hideDuringSpecial and IsSpecialActionState() then
        bar:Hide()
        return
    end

    local alpha = cfg.alpha or 1
    if mode == "mouseover" then
        bar:SetAlpha(cfg.inactiveAlpha or 0.25)
    elseif mode == "combatfade" and not PlayerInCombat() then
        bar:SetAlpha(cfg.inactiveAlpha or 0.25)
    else
        bar:SetAlpha(alpha)
    end
end

function M:ApplySpecialVisibility(bar, cfg)
    if IsEditMode() and self:IsEnabled() and cfg.enabled == true then
        if not InCombat() and UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
        bar:Show()
        bar:SetAlpha(1)
        return
    end
    if InCombat() then
        bar:SetAlpha(cfg.alpha or 1)
        return
    end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
    if RegisterStateDriver then
        pcall(RegisterStateDriver, bar, "visibility", SpecialStatePrefix(false) .. "hide")
    elseif IsSpecialActionState() then
        bar:Show()
    else
        bar:Hide()
    end
    bar:SetAlpha(cfg.alpha or 1)
    if not IsSpecialActionState() and not IsEditMode() then
        bar:Hide()
    end
end

function M:ApplySpecialLayout()
    if InCombat() then
        self._pendingRebuild = true
        return
    end
    local root = self:EnsureDefaults()
    local cfg = root.special
    local bar = self:EnsureBar(SPECIAL_BAR_INDEX)
    bar._isSpecialActionBar = true
    if bar.editFrame and bar.editFrame.label then
        bar.editFrame.label:SetText("Vehicule")
    end
    if not (root.enabled and cfg and cfg.enabled) then
        if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
        bar:Hide()
        return
    end

    local count = Clamp(cfg.buttons, 1, MAX_BUTTONS)
    local size = Clamp(cfg.size, 24, 72)
    local spacing = Clamp(cfg.spacing, 0, 24)
    local offsetX = Clamp(cfg.offsetX, 70, 260)
    local offsetY = Clamp(cfg.offsetY, 20, 120)
    local groupW = (3 * size) + (2 * spacing)
    local width = (2 * offsetX) + groupW
    local height = (2 * offsetY) + size
    local leftStart = -offsetX - (groupW * 0.5) + (size * 0.5)
    local rightStart = offsetX - (groupW * 0.5) + (size * 0.5)

    bar:SetSize(width, height)
    bar:SetScale(1)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", self:GetSpecialAnchor(), "CENTER", 0, 0)
    bar:SetAttribute("buttonCount", count)
    self:ApplyEditMode(bar, cfg)

    local positions = {
        [1] = {leftStart + 0 * (size + spacing), offsetY},
        [2] = {leftStart + 1 * (size + spacing), offsetY},
        [3] = {leftStart + 2 * (size + spacing), offsetY},
        [4] = {rightStart + 0 * (size + spacing), offsetY},
        [5] = {rightStart + 1 * (size + spacing), offsetY},
        [6] = {rightStart + 2 * (size + spacing), offsetY},
        [7] = {leftStart + 0 * (size + spacing), -offsetY},
        [8] = {leftStart + 1 * (size + spacing), -offsetY},
        [9] = {leftStart + 2 * (size + spacing), -offsetY},
        [10] = {rightStart + 0 * (size + spacing), -offsetY},
        [11] = {rightStart + 1 * (size + spacing), -offsetY},
        [12] = {rightStart + 2 * (size + spacing), -offsetY},
    }

    for i = 1, MAX_BUTTONS do
        local btn = bar.buttons[i]
        if not btn then
            btn = self:CreateButton(bar, SPECIAL_BAR_INDEX, i)
            bar.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetSize(size, size)
        SetButtonVisualZoom(btn, 1)
        local pos = positions[i] or {0, 0}
        btn:SetPoint("CENTER", bar, "CENTER", pos[1], pos[2])
        btn:SetShown(i <= count)
        ApplyClickRegistration(btn, cfg)
        local slot = ResolveButtonSlot(cfg, i, SPECIAL_BAR_INDEX)
        btn._slot = slot
        btn._nativeButtonIndex = i
        btn._bindingName = ButtonBindingName(cfg, i, slot, SPECIAL_BAR_INDEX)
        btn:SetAttribute("action", slot)
        if i <= count then
            pcall(bar.SetFrameRef, bar, "button" .. i, btn)
        end
        self:MapButtonSlot(btn, slot)
        self:MapNativeButton(btn, i)
        self:UpdateButton(btn)
    end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "page") end
    self:ApplySpecialVisibility(bar, cfg)
    self:ApplyEditMode(bar, cfg)
end

function M:ApplyLayout(index)
    if InCombat() then
        self._pendingRebuild = true
        return
    end
    local root = self:EnsureDefaults()
    local cfg = root.bars[index]
    local bar = self:EnsureBar(index)
    -- N'importe quelle barre peut désormais paginer (plus de force-off bar≠1).
    if not (root.enabled and cfg.enabled) then
        if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "visibility") end
        if UnregisterStateDriver then pcall(UnregisterStateDriver, bar, "page") end
        if ClearOverrideBindings then pcall(ClearOverrideBindings, bar) end
        bar:Hide()
        return
    end

    local count = Clamp(cfg.buttons, 1, MAX_BUTTONS)
    local size = Clamp(cfg.size, 20, 72)
    local spacing = Clamp(cfg.spacing, 0, 16)
    local columns = Clamp(cfg.columns, 1, MAX_BUTTONS)
    if cfg.orientation == "horizontal" then columns = count end
    if cfg.orientation == "vertical" then columns = 1 end

    local rows = math.ceil(count / columns)
    local width = (columns * size) + ((columns - 1) * spacing)
    local height = (rows * size) + ((rows - 1) * spacing)

    bar:SetSize(width, height)
    bar:SetScale(Clamp(cfg.scale, 0.50, 2.0))
    bar:ClearAllPoints()
    local linkedX, linkedY = self:GetLinkedBarPosition(index, cfg, width, height)
    bar:SetPoint("CENTER", UIParent, "CENTER", linkedX or tonumber(cfg.x) or 0, linkedY or tonumber(cfg.y) or 0)
    bar:SetAttribute("buttonCount", count)
    self:ApplyEditMode(bar, cfg)

    for i = 1, MAX_BUTTONS do
        local btn = bar.buttons[i]
        if not btn then
            btn = self:CreateButton(bar, index, i)
            bar.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetSize(size, size)
        SetButtonVisualZoom(btn, 1)
        local col = ((i - 1) % columns)
        local row = math.floor((i - 1) / columns)
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (size + spacing), -row * (size + spacing))
        btn:SetShown(i <= count)
        ApplyClickRegistration(btn, cfg)
        local slot = ResolveButtonSlot(cfg, i, index)
        btn._slot = slot
        btn._nativeButtonIndex = FollowsNativePaging(cfg, index) and i or nil
        btn._bindingName = ButtonBindingName(cfg, i, slot, index)
        btn:SetAttribute("action", slot)
        if i <= count then
            pcall(bar.SetFrameRef, bar, "button" .. i, btn)
        end
        self:MapButtonSlot(btn, slot)
        if btn._nativeButtonIndex then self:MapNativeButton(btn, btn._nativeButtonIndex) end
        self:UpdateButton(btn)
    end
    local driver = BarPageDriver(cfg, index)
    if driver and RegisterStateDriver then
        pcall(RegisterStateDriver, bar, "page", driver)
    elseif UnregisterStateDriver then
        pcall(UnregisterStateDriver, bar, "page")
    end
    self:ApplyBarBindings(bar, cfg, index)
    self:ApplyVisibility(bar, cfg)
    self:ApplyEditMode(bar, cfg)
end

-- Prend possession des raccourcis : route les touches assignées à la famille
-- Blizzard de la barre vers NOS boutons secure (clic au press → zéro latence,
-- et la touche caste le slot RÉELLEMENT affiché, pagination liée comprise).
-- Hors combat uniquement (SetOverrideBindingClick est protégé).
function M:ApplyBarBindings(bar, cfg, index)
    if not bar then return end
    if InCombat() then self._pendingRebuild = true return end
    if ClearOverrideBindings then pcall(ClearOverrideBindings, bar) end
    local root = self:EnsureDefaults()
    if root.ownBindings ~= true then return end
    if not (root.enabled and cfg and cfg.enabled) then return end
    if IsSpecialBarIndex(index) then return end
    -- RÈGLE DURE : ne JAMAIS prendre possession des raccourcis de la barre 1.
    -- Ses touches ACTIONBUTTON restent natives (cast fiable + barre véhicule).
    if tonumber(index) == 1 then return end
    local family = BAR_BINDING_FAMILY[tonumber(index) or 0]
    if not family or not (GetBindingKey and SetOverrideBindingClick) then return end
    local count = Clamp(cfg.buttons, 1, MAX_BUTTONS)
    for i = 1, count do
        local btn = bar.buttons[i]
        local name = btn and btn:GetName()
        if name then
            local keys = { GetBindingKey(family .. i) }
            for _, key in ipairs(keys) do
                if key and key ~= "" then
                    pcall(SetOverrideBindingClick, bar, true, key, name, "LeftButton")
                end
            end
        end
    end
end

-- Réapplique la possession des raccourcis sur toutes les barres (UPDATE_BINDINGS).
function M:ApplyAllBindings()
    if InCombat() then self._pendingRebuild = true return end
    if not self.bars then return end
    for index, bar in pairs(self.bars) do
        if not IsSpecialBarIndex(index) then
            self:ApplyBarBindings(bar, self:GetBarConfig(index), index)
        end
    end
end

function M:MapButtonSlot(btn, slot)
    if not btn or not slot then return end
    self.slotButtons = self.slotButtons or {}
    local list = self.slotButtons[slot]
    if not list then
        list = {}
        self.slotButtons[slot] = list
    end
    list[#list + 1] = btn
end

function M:MapNativeButton(btn, buttonIndex)
    if not btn or not buttonIndex then return end
    self.nativeButtons = self.nativeButtons or {}
    local list = self.nativeButtons[buttonIndex]
    if not list then
        list = {}
        self.nativeButtons[buttonIndex] = list
    end
    list[#list + 1] = btn
end

function M:PressSlot(slot)
    local list = self.slotButtons and self.slotButtons[tonumber(slot)]
    if not list then return end
    for _, btn in ipairs(list) do
        if btn:IsShown() then self:PressButtonVisual(btn) end
    end
end

function M:ReleaseSlot(slot)
    local list = self.slotButtons and self.slotButtons[tonumber(slot)]
    if not list then return end
    for _, btn in ipairs(list) do
        if btn:IsShown() then self:ReleaseButtonVisual(btn, true) end
    end
end

function M:PressNativeButton(buttonIndex)
    local list = self.nativeButtons and self.nativeButtons[tonumber(buttonIndex)]
    if not list then return end
    for _, btn in ipairs(list) do
        if btn:IsShown() then self:PressButtonVisual(btn) end
    end
end

function M:ReleaseNativeButton(buttonIndex)
    local list = self.nativeButtons and self.nativeButtons[tonumber(buttonIndex)]
    if not list then return end
    for _, btn in ipairs(list) do
        if btn:IsShown() then self:ReleaseButtonVisual(btn, true) end
    end
end

function M:UpdateButton(btn)
    if not btn or not btn._slot then return end
    StripButtonChrome(btn)
    if btn.hover then btn:SetHighlightTexture(btn.hover) end
    local cfg = self:GetBarConfig(btn._barIndex)
    local slot = ResolveButtonSlot(cfg, btn._buttonIndex or 1, btn._barIndex)
    btn._slot = slot
    btn._bindingName = ButtonBindingName(cfg, btn._buttonIndex or 1, slot, btn._barIndex)
    if not InCombat() then
        pcall(btn.SetAttribute, btn, "action", slot)
    end
    local okHA, rawHA = pcall(function()
        return HasAction and HasAction(slot) == true
    end)
    local hasAction = okHA and rawHA == true
    local emptyAlpha = Clamp(cfg.emptyAlpha, 0, 1)
    if not hasAction and cfg.showEmpty == false then
        ApplyButtonSkin(btn, cfg, false)
        self:ClearCooldownSkin(btn)
        btn:SetAlpha(0)
        return
    end
    btn:SetAlpha(1)

    local texture = GetActionTexture and GetActionTexture(slot)
    if texture then
        btn.icon:SetTexture(texture)
        btn.icon:SetAlpha(1)
    else
        btn.icon:SetTexture(nil)
        btn.icon:SetAlpha(0)
        if btn.cooldown then pcall(btn.cooldown.Clear, btn.cooldown) end
        self:ClearCooldownSkin(btn)
    end
    btn.bg:SetVertexColor(0.03, 0.025, 0.018, hasAction and 0 or emptyAlpha)
    if btn.border then btn.border:SetAlpha(0) end
    ApplyButtonSkin(btn, cfg, hasAction == true)

    -- IsUsableAction peut retourner des secret booleans : les comparaisons
    -- (~= / ==) crashent alors hors pcall. Défaut permissif (utilisable).
    local usable, noMana = true, false
    if IsUsableAction then
        local okU, u, nm = pcall(IsUsableAction, slot)
        if okU then
            local okCmp, us, nom = pcall(function()
                return u ~= false, nm == true
            end)
            if okCmp then usable, noMana = us, nom end
        end
    end
    if noMana then
        btn.icon:SetVertexColor(0.35, 0.45, 1.0, 1)
    elseif usable then
        btn.icon:SetVertexColor(1, 1, 1, 1)
    else
        btn.icon:SetVertexColor(0.42, 0.42, 0.42, 1)
    end

    local okCur, isCur = pcall(function()
        return IsCurrentAction and IsCurrentAction(slot) == true
    end)
    btn._isCurrentAction = (okCur and isCur) or nil
    btn:SetChecked(false)

    if hasAction and GetActionCooldown then
        local ok, start, duration, enable, modRate = pcall(GetActionCooldown, slot)
        if ok then
            if cfg.showCooldown ~= false then
                SetCooldownFrame(btn.cooldown, start, duration, enable, modRate)
            elseif btn.cooldown then
                pcall(btn.cooldown.Clear, btn.cooldown)
            end
            self:RegisterCooldownSkin(btn, start, duration, enable)
        else
            if btn.cooldown then pcall(btn.cooldown.Clear, btn.cooldown) end
            self:ClearCooldownSkin(btn)
        end
    elseif btn.cooldown then
        pcall(btn.cooldown.Clear, btn.cooldown)
        self:ClearCooldownSkin(btn)
    end

    if hasAction and cfg.showCount ~= false and GetActionCount then
        local ok, count = pcall(GetActionCount, slot)
        local okText, text = pcall(function()
            return (ok and count and count > 1) and tostring(count) or ""
        end)
        btn.count:SetText(okText and text or "")
    else
        btn.count:SetText("")
    end

    if hasAction and cfg.showHotkey ~= false then
        btn.hotkey:SetText(ShortKeyText(btn._bindingName))
    else
        btn.hotkey:SetText("")
    end

    if hasAction and cfg.showMacro and GetActionText then
        local ok, text = pcall(GetActionText, slot)
        btn.macro:SetText(ok and text or "")
    else
        btn.macro:SetText("")
    end
end

function M:UpdateAllButtons()
    if not self.bars then return end
    for _, bar in pairs(self.bars) do
        for _, btn in ipairs(bar.buttons or {}) do
            self:UpdateButton(btn)
        end
        local cfg = self:GetBarConfig(bar._index or 1)
        if bar._index == SPECIAL_BAR_INDEX then
            self:ApplySpecialVisibility(bar, cfg)
        else
            self:ApplyVisibility(bar, cfg)
        end
    end
end

local function AddButtonNames(out, prefix, count)
    for i = 1, count do
        out[#out + 1] = prefix .. i
    end
end

function M:GetBlizzardActionFrameNames()
    local names = {
        "MainActionBar", "MainActionBarArtFrame", "MainActionBarButtonContainer",
        "MainMenuBar", "MainMenuBarArtFrame", "MainMenuBarBackpackButton",
        "MainMenuBarPerformanceBarFrame", "MainMenuBarVehicleLeaveButton",
        "ActionBarController", "ActionBarUpButton", "ActionBarDownButton",
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7",
        "MultiBarBottomLeftButtonContainer", "MultiBarBottomRightButtonContainer",
        "MultiBarRightButtonContainer", "MultiBarLeftButtonContainer",
        "StanceBarFrame", "PetActionBarFrame", "PossessActionBar", "PossessBarFrame",
        "OverrideActionBar", "ExtraActionBarFrame", "ZoneAbilityFrame",
        "VehicleMenuBar", "VehicleMenuBarActionButtonFrame", "VehicleSeatIndicator",
        "MicroButtonAndBagsBar", "MicroButtonAndBagsBarExpansionPanel",
        "MicroMenuContainer", "MicroButtonContainer", "BagsBar", "BagsBarExpansionToggle",
        "BagBarExpandToggle", "MainMenuBarBackpackButton", "KeyRingButton",
        "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
        "ReputationWatchBar", "ArtifactWatchBar", "HonorWatchBar",
        "MainMenuExpBar", "MainMenuBarMaxLevelBar", "ExhaustionTick",
        "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
        "AchievementMicroButton", "QuestLogMicroButton", "GuildMicroButton",
        "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
        "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
        "ProfessionMicroButton",
    }
    AddButtonNames(names, "ActionButton", 12)
    AddButtonNames(names, "MultiBarBottomLeftButton", 12)
    AddButtonNames(names, "MultiBarBottomRightButton", 12)
    AddButtonNames(names, "MultiBarRightButton", 12)
    AddButtonNames(names, "MultiBarLeftButton", 12)
    AddButtonNames(names, "MultiBar5Button", 12)
    AddButtonNames(names, "MultiBar6Button", 12)
    AddButtonNames(names, "MultiBar7Button", 12)
    AddButtonNames(names, "StanceButton", 10)
    AddButtonNames(names, "PetActionButton", 10)
    AddButtonNames(names, "PossessButton", 2)
    AddButtonNames(names, "VehicleMenuBarActionButton", 6)
    AddButtonNames(names, "OverrideActionBarButton", 6)
    for i = 0, 4 do
        names[#names + 1] = "CharacterBag" .. i .. "Slot"
    end
    names[#names + 1] = "ReagentBag0Slot"
    names[#names + 1] = "CharacterReagentBag0Slot"
    names[#names + 1] = "MainMenuBarBagButtons"
    return names
end

function M:IsReplacingBlizzard()
    local root = self:EnsureDefaults()
    return root.enabled == true and root.replaceBlizzard ~= false
end

function M:HideBlizzardFrame(frame)
    if not frame then return end
    frame._snpActionBarsHidden = true
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    if frame.Hide and not InCombat() then pcall(frame.Hide, frame) end
end

function M:RestoreBlizzardFrame(frame)
    if not frame or not frame._snpActionBarsHidden then return end
    frame._snpActionBarsHidden = nil
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
    if frame.Show then pcall(frame.Show, frame) end
end

function M:HookBlizzardFrame(frame)
    if not frame or frame._snpActionBarsHooked then return end
    frame._snpActionBarsHooked = true
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function(f)
            if M:IsReplacingBlizzard() then
                M:HideBlizzardFrame(f)
            end
        end)
    end
end

function M:ApplyBlizzardBars()
    local root = self:EnsureDefaults()
    local hide = root.enabled == true and root.replaceBlizzard ~= false
    root.hideBlizzard = hide
    if InCombat() and not hide then
        self._pendingBlizzard = true
        return
    end
    for _, name in ipairs(self:GetBlizzardActionFrameNames()) do
        local frame = _G[name]
        if frame then
            self:HookBlizzardFrame(frame)
            if hide then
                self:HideBlizzardFrame(frame)
            else
                self:RestoreBlizzardFrame(frame)
            end
        end
    end
end

local function MultiBarSlot(barIndex, buttonIndex)
    buttonIndex = tonumber(buttonIndex)
    if not buttonIndex then return nil end
    local barKey = tostring(barIndex or "")
    local stringBases = {
        ActionBar7 = 72,
        ActionBar8 = 84,
        ActionBar9 = 96,
        ActionBar10 = 108,
    }
    if stringBases[barKey] then
        return stringBases[barKey] + buttonIndex
    end
    barIndex = tonumber(barIndex)
    if not barIndex then return nil end
    local bases = {
        [1] = 60,  -- MultiBarBottomLeft
        [2] = 48,  -- MultiBarBottomRight
        [3] = 24,  -- MultiBarRight
        [4] = 36,  -- MultiBarLeft
        [5] = 72,  -- Retail ActionBar7
        [6] = 84,  -- Retail ActionBar8
        [7] = 96,  -- Retail ActionBar9
        [8] = 108, -- Retail ActionBar10
    }
    local base = bases[barIndex]
    if not base then return nil end
    return base + buttonIndex
end

function M:HookKeyFeedback()
    if not hooksecurefunc then return end
    self._keyHooked = self._keyHooked or {}
    local function hook(name, fn)
        if self._keyHooked[name] or type(_G[name]) ~= "function" then return end
        local ok = pcall(hooksecurefunc, name, fn)
        if ok then self._keyHooked[name] = true end
    end

    hook("ActionButtonDown", function(id)
        M:PressNativeButton(tonumber(id))
        M:PressSlot(tonumber(id))
    end)
    hook("ActionButtonUp", function(id)
        M:ReleaseNativeButton(tonumber(id))
        M:ReleaseSlot(tonumber(id))
    end)
    hook("MultiActionButtonDown", function(barIndex, buttonIndex)
        local slot = MultiBarSlot(barIndex, buttonIndex)
        if slot then M:PressSlot(slot) end
    end)
    hook("MultiActionButtonUp", function(barIndex, buttonIndex)
        local slot = MultiBarSlot(barIndex, buttonIndex)
        if slot then M:ReleaseSlot(slot) end
    end)
end

function M:Refresh()
    self:EnsureDefaults()
    self:HookKeyFeedback()
    if InCombat() then
        self._pendingRebuild = true
        return
    end
    self.slotButtons = {}
    self.nativeButtons = {}
    for i = 1, NUM_BARS do
        self:ApplyLayout(i)
    end
    self:ApplySpecialLayout()
    self:UpdateEditGrid()
    self:ApplyBlizzardBars()
    self:CheckPageChange(true)   -- pose la référence de page sans flasher
    if IsEditMode() and self:IsEnabled() then
        self:ShowEditHud()
    elseif self.editMenu then
        self.editMenu:Hide()
    end
end

-- ── Indicateur éphémère de page (« Barre N ») ───────────────────────────────
function M:PageLabel(page)
    page = tonumber(page) or 1
    if page >= 7 then
        local name = CurrentFormName()
        if name and name ~= "" then return name end
        return "Posture " .. (page - 6)
    end
    if page == 1 then return "Barre principale" end
    return "Barre " .. page
end

function M:EnsurePageFlash()
    if self.pageFlashFrame then return self.pageFlashFrame end
    local f = CreateFrame("Frame", "SPActionBarPageFlash", UIParent, "BackdropTemplate")
    f:SetSize(200, 38)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(720)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = {left=3, right=3, top=3, bottom=3},
    })
    f:SetBackdropColor(0.03, 0.025, 0.02, 0.82)
    f:SetBackdropBorderColor(0.55, 0.38, 0.14, 0.9)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    f.text:SetPoint("CENTER")
    f.text:SetTextColor(1.0, 0.84, 0.32, 1)

    f.anim = f:CreateAnimationGroup()
    f.holdAnim = f.anim:CreateAnimation("Alpha")
    f.holdAnim:SetFromAlpha(1); f.holdAnim:SetToAlpha(1)
    f.holdAnim:SetDuration(1.0); f.holdAnim:SetOrder(1)
    local fade = f.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0)
    fade:SetDuration(0.45); fade:SetOrder(2); fade:SetSmoothing("OUT")
    f.anim:SetScript("OnFinished", function() f:Hide() end)
    f:Hide()
    self.pageFlashFrame = f
    return f
end

function M:AnchorPageFlash(f)
    f:ClearAllPoints()
    local moi = SP.Moi and ((SP.Moi.data and SP.Moi.data.root) or SP.Moi.anchor)
    if moi then
        f:SetPoint("BOTTOM", moi, "TOP", 0, 26)
        return
    end
    local bar = self.bars and self.bars[1]
    if bar then
        f:SetPoint("BOTTOM", bar, "TOP", 0, 12)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    end
end

function M:FlashPage(label)
    local root = self:EnsureDefaults()
    if root.pageFlash == false then return end
    local f = self:EnsurePageFlash()
    self:AnchorPageFlash(f)
    f.text:SetText(label or "")
    f:SetWidth(math.max(140, (f.text:GetStringWidth() or 100) + 52))
    local hold = Clamp(root.pageFlashDuration, 0.4, 5.0) - 0.45
    f.holdAnim:SetDuration(math.max(0.1, hold))
    pcall(f.anim.Stop, f.anim)
    f:SetAlpha(1)
    f:Show()
    pcall(f.anim.Play, f.anim)
end

-- Détecte un changement de page de la barre principale et flashe le nom.
-- silent=true : pose la référence sans flasher (init/reload).
function M:CheckPageChange(silent)
    -- Flash si l'addon est actif et qu'au moins une barre activée pagine.
    local paginates = false
    if self:IsEnabled() then
        local root = self:EnsureDefaults()
        for i = 1, NUM_BARS do
            local c = root.bars[i]
            if c and c.enabled == true and BarPagingMode(c, i) ~= "none" then
                paginates = true
                break
            end
        end
    end
    if not paginates then
        self._lastShownPage = nil
        return
    end
    local page = ResolveMainBarPage()
    local prev = self._lastShownPage
    if prev ~= page then
        self._lastShownPage = page
        if not silent and prev ~= nil then
            self:FlashPage(self:PageLabel(page))
        end
    end
end

function M:EnsureEventFrame()
    if self.eventFrame then return end
    local f = CreateFrame("Frame")
    self.eventFrame = f
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED",
        "ACTIONBAR_SLOT_CHANGED",
        "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_USABLE",
        "ACTIONBAR_UPDATE_COOLDOWN",
        "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_OVERRIDE_ACTIONBAR",
        "UPDATE_VEHICLE_ACTIONBAR",
        "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_POSSESS_BAR",
        "UPDATE_EXTRA_ACTIONBAR",
        "PET_BAR_UPDATE",
        "UPDATE_SHAPESHIFT_FORM",
        "UPDATE_SHAPESHIFT_USABLE",
        "UPDATE_MICRO_BUTTONS",
        "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "SPELL_UPDATE_COOLDOWN",
        "UPDATE_BINDINGS",
        "CURSOR_CHANGED",
        "CVAR_UPDATE",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "CURSOR_CHANGED" then
            M:UpdateDragHighlightState()
            return
        end
        if event == "CVAR_UPDATE" then
            if arg1 == "ActionButtonUseKeyDown" then
                M:ApplyAllClickRegistrations()
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            -- Masquer les highlights de drag, puis laisser le flux normal
            -- (UpdateAllButtons + ApplyBlizzardBars) s'exécuter comme avant.
            M:SetDragHighlights(false)
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if M._pendingRebuild then
                M._pendingRebuild = nil
                M:Refresh()
            end
            if M._pendingBlizzard then
                M._pendingBlizzard = nil
                M:ApplyBlizzardBars()
            end
            M:UpdateAllButtons()
            M:ApplyAllBindings()      -- réapplique les raccourcis différés en combat
            M:CheckPageChange(true)   -- resync silencieux après combat
            return
        end
        if event == "UPDATE_BINDINGS" then
            M:UpdateAllButtons()
            M:ApplyAllBindings()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.25, function() M:Refresh() end)
            C_Timer.After(1.00, function() M:ApplyBlizzardBars() end)
            return
        end
        M:UpdateAllButtons()
        M:ApplyBlizzardBars()
        if event == "ACTIONBAR_PAGE_CHANGED"
            or event == "UPDATE_BONUS_ACTIONBAR"
            or event == "UPDATE_SHAPESHIFT_FORM" then
            M:CheckPageChange()
        end
        -- Entrée/sortie d'état spécial : la barre 1 doit rendre/reprendre ses
        -- touches ACTIONBUTTON pour la barre véhicule/monture.
        if event == "UPDATE_VEHICLE_ACTIONBAR"
            or event == "UPDATE_OVERRIDE_ACTIONBAR"
            or event == "UPDATE_POSSESS_BAR"
            or event == "UPDATE_BONUS_ACTIONBAR" then
            M:ApplyAllBindings()
        end
    end)
end

function M:Init()
    self:EnsureDefaults()
    self:EnsureEventFrame()
    -- Réglages CVar hors combat quand nos barres sont actives :
    --   countdownForCooldowns : chiffres de recharge natifs.
    --   ActionButtonUseKeyDown : cast AU PRESS = supprime la latence ressentie
    --     (sans ça, les actions partent au RELÂCHEMENT de la touche → ~0.5s).
    if self:IsEnabled() and not InCombat() then
        pcall(SetCVar, "countdownForCooldowns", "1")
        if DB().actionbars and DB().actionbars.castOnDown ~= false then
            pcall(SetCVar, "ActionButtonUseKeyDown", "1")
        end
    end
    self:Refresh()
end
