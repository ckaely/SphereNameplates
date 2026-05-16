-------------------------------------------------------------------------------
-- SphereNameplates v9.2 — Modules/CastBar.lua
--
-- ARCHITECTURE :
--   Chaque nameplate reçoit un "watcher" frame dédié (RegisterUnitEvent).
--   Un polling 0.2s sert de filet de sécurité si les events ne reçoivent pas.
--
-- MODES :
--   "classic"  (défaut) — Pill bar moderne sous l'orbe + icône du sort
--   "circular"           — Arc Cooldown autour de l'orbe + icône flottante
--
-- ÉVÉNEMENTS (par watcher, RegisterUnitEvent) :
--   UNIT_SPELLCAST_START / STOP / INTERRUPTED / FAILED
--   UNIT_SPELLCAST_CHANNEL_START / STOP / UPDATE
--   PLAYER_ENTERING_WORLD → re-query état actuel
-------------------------------------------------------------------------------

local SP = _G["SphereNameplates"]
SP.CastBar = {}

local math_max   = math.max
local math_min   = math.min
local math_sin   = math.sin
local math_cos   = math.cos
local math_pi    = math.pi
local math_abs   = math.abs
local math_floor = math.floor
local math_sqrt  = math.sqrt
local GetTime    = GetTime

-- ─── Palette ─────────────────────────────────────────────────────────────────
local COLOR_CAST    = {r=1.00, g=0.65, b=0.00}  -- OR       interruptible
local COLOR_CONTROL = {r=0.72, g=0.18, b=1.00}  -- VIOLET   non-interruptible joueur
local COLOR_IMMUNE  = {r=0.88, g=0.10, b=0.08}  -- ROUGE    immune/boss
local COLOR_CHANNEL = {r=0.10, g=0.55, b=0.95}  -- BLEU     channel
local COLOR_FINISH  = {r=0.30, g=1.00, b=0.30}  -- VERT     succès
local COLOR_BROKEN  = {r=0.95, g=0.20, b=0.20}  -- ROUGE    interruption

-- ─── Helpers couleur ────────────────────────────────────────────────────────
local function _arr2rgba(t, fr, fg, fb, fa)
    if type(t) == "table" then
        if t.r then return t.r, t.g, t.b, (t.a or fa or 1) end
        return (t[1] or fr or 1), (t[2] or fg or 1), (t[3] or fb or 1), (t[4] or fa or 1)
    end
    return (fr or 1), (fg or 1), (fb or 1), (fa or 1)
end

local function _rgb(t, def)
    local r, g, b = _arr2rgba(t, def and def.r, def and def.g, def and def.b, 1)
    return { r = r, g = g, b = b }
end

local function _ResolveClassColor(unit)
    if not unit then return nil end
    local ok, _, classFile = pcall(UnitClass, unit)
    if not ok or not classFile then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return { r = c.r, g = c.g, b = c.b } end
    return nil
end

local LOCK_TEX = "Interface\\PetBattles\\PetBattle-LockIcon"
local WHITE    = "Interface\\Buttons\\WHITE8x8"
local MASK_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NATIVE_RING = "Interface\\Buttons\\UI-AutoCastableOverlay"
local SHADOW_CIRCLE_TEX = "Interface\\AddOns\\SphereNameplates\\media\\shadowcircle"

-- ─── Sprite sheet castbar (mode "sprite") ────────────────────────────────────
local CASTBAR_SPRITE_SHEET = "Interface\\AddOns\\SphereNameplates\\media\\castbar_mage\\castbar_mage_sheet.png"
local SPRITE_COLS  = 9
local SPRITE_ROWS  = 8
local SPRITE_TOTAL = 72

-- ─── Textures circulaires GARANTIES radiales / fade-to-transparent ──────────
-- Le PNG SP.MEDIA/orb_glow était un carré opaque qui rendait des rectangles
-- visibles à chaque utilisation BLEND/ADD. Remplacé partout par Interface\Cooldown\ping4
-- (disque WoW natif fade-to-transparent, version-stable).
local RADIAL_GLOW    = "Interface\\Cooldown\\ping4"

-- Assets Quafe (preset "Overwatch Ring CCB" — Quafe_Overwatch doit être installé)
local OW_HUD_RING    = "Interface\\AddOns\\Quafe_Overwatch\\Media\\HUD_Ring"
local OW_BAR_RING    = "Interface\\AddOns\\Quafe_Overwatch\\Media\\Bar_Ring"
local OW_HUD_BAR5    = "Interface\\AddOns\\Quafe_Overwatch\\Media\\HUD_Bar5"
local OW_HUD_BAR5_GLOW = "Interface\\AddOns\\Quafe_Overwatch\\Media\\HUD_Bar5_Glow"
local OW_PLAYER_BD1  = "Interface\\AddOns\\Quafe_Overwatch\\Media\\Player_Bd1"
local OW_MINIMAP_MASK = "Interface\\AddOns\\Quafe_Overwatch\\Media\\MinimapMask"

local function _HasQuafe()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Quafe_Overwatch")
        return ok and loaded
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, "Quafe_Overwatch")
        return ok and loaded
    end
    return false
end

-- Événements cast à enregistrer par watcher
local CAST_UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
}

local function SafeNotNil(v)
    local ok, result = pcall(function()
        return v ~= nil
    end)
    return ok and result or false
end

-- Récupère l'icône d'un sort (spellID ou nom)
local function GetSpellIcon(spellID)
    if not SafeNotNil(spellID) then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and SafeNotNil(t) then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, spellID)
        if ok and SafeNotNil(t) then return t end
    end
    return nil
end

local function SafeBool(v, fallback)
    local ok, result = pcall(function()
        return v and true or false
    end)
    if ok then return result end
    return fallback
end

local function SafeText(v, fallback, maxLen)
    local ok, text = pcall(function()
        local s = tostring(v)
        if maxLen and #s > maxLen then
            return s:sub(1, maxLen - 2) .. ".."
        end
        return s
    end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return fallback or ""
end

local function TrySafeText(v, maxLen)
    local ok, text = pcall(function()
        local s = tostring(v)
        if maxLen and #s > maxLen then
            return s:sub(1, maxLen - 2) .. ".."
        end
        return s
    end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

local function _SetFontText(fontString, value, fallback)
    if not fontString then return false end
    if SafeNotNil(value) then
        local ok = pcall(fontString.SetText, fontString, value)
        if ok then return true end
    end
    if fallback ~= nil then
        return pcall(fontString.SetText, fontString, fallback)
    end
    return false
end

local function _SpellNameFromID(spellId, maxLen)
    if not SafeNotNil(spellId) or not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" then
        return TrySafeText(info.name, maxLen)
    end
    return nil
end

local function _SpellNameValueFromID(spellId)
    if not SafeNotNil(spellId) or not (C_Spell and C_Spell.GetSpellInfo) then return nil, nil, "no_spell_id" end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" and SafeNotNil(info.name) then
        return info.name, TrySafeText(info.name, 26), "spell_info"
    end
    return nil, nil, ok and "spell_info_empty" or "spell_info_error"
end

local function _ResolveCastDisplayValue(name, spellId, isChannel)
    -- Midnight: les noms de sort peuvent etre des secret strings. Ils peuvent
    -- etre affiches par SetText, mais pas convertis/tronques en Lua. On garde
    -- donc une valeur brute pour l'affichage et une valeur debug separee.
    local fallback = isChannel and "Canalisation" or "Incantation"
    local raw, safe, source = _SpellNameValueFromID(spellId)
    if SafeNotNil(raw) then
        return raw, safe or fallback, source
    end
    if SafeNotNil(name) then
        return name, TrySafeText(name, 26) or fallback, "unit_info"
    end
    return fallback, fallback, "fallback"
end

local function _PreferSpellID(primary, fallback)
    if SafeNotNil(primary) then return primary end
    if SafeNotNil(fallback) then return fallback end
    return nil
end

local function _EventCastArgs(...)
    local castGUID, spellId = ...
    return castGUID, spellId
end

local function _CastGUIDMatches(cb, castGUID)
    if not cb then return true end
    if not SafeNotNil(castGUID) or not SafeNotNil(cb.castGUID) then return true end
    local ok, same = pcall(function()
        return cb.castGUID == castGUID
    end)
    return ok and same
end

-------------------------------------------------------------------------------
--  _ClassifyCast — couleur selon le type de sort, config et classe
--    isPlayer + cfg.castbar_color_by_class → RAID_CLASS_COLORS
--    sinon : couleurs cfg ou fallback hardcodé
-------------------------------------------------------------------------------
local function _ClassifyCast(unit, notInt, isChannel, cfg)
    cfg = cfg or {}
    local isPlayer = false
    pcall(function() isPlayer = UnitIsPlayer(unit) and true or false end)

    -- non-interruptible + non-joueur → immune (boss)
    if notInt and not isPlayer then
        return _rgb(cfg.castbar_color_immune, COLOR_IMMUNE), true
    end

    -- channel
    if isChannel then
        if isPlayer and cfg.castbar_color_by_class then
            local cc = _ResolveClassColor(unit)
            if cc then return cc, false end
        end
        return _rgb(cfg.castbar_color_channel, COLOR_CHANNEL), false
    end

    -- cast non-interruptible joueur
    if notInt then
        if isPlayer and cfg.castbar_color_by_class then
            local cc = _ResolveClassColor(unit)
            if cc then return cc, false end
        end
        return _rgb(cfg.castbar_color_nonint, COLOR_CONTROL), false
    end

    -- cast interruptible (défaut)
    if isPlayer and cfg.castbar_color_by_class then
        local cc = _ResolveClassColor(unit)
        if cc then return cc, false end
    end
    return _rgb(cfg.castbar_color_cast, COLOR_CAST), false
end

local function _ClampInt(value, fallback, minValue, maxValue)
    local n = tonumber(value) or fallback
    n = math_floor(n + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

local function _V8Count(value)
    return _ClampInt(value, 12, 3, 24)
end

local function _DottedCount(value)
    return _ClampInt(value, 18, 6, 36)
end

local function _ResetDotted(circ, hideTrack)
    if not (circ and circ.dottedSegments) then return end
    local trackAlpha = (not hideTrack) and circ.dottedShowTrack and 0.20 or 0
    for i = 1, #circ.dottedSegments do
        local dot = circ.dottedSegments[i]
        if dot.track then dot.track:SetAlpha(trackAlpha) end
        if dot.fill  then dot.fill:SetAlpha(0) end
        if dot.glow  then dot.glow:SetAlpha(0) end
    end
end

local function _ColorDotted(circ, color)
    if not (circ and circ.dottedSegments and color) then return end
    for i = 1, #circ.dottedSegments do
        local dot = circ.dottedSegments[i]
        if dot.fill then dot.fill:SetVertexColor(color.r, color.g, color.b, 1) end
        if dot.glow then dot.glow:SetVertexColor(color.r, color.g, color.b, 1) end
    end
end

local function _UpdateDotted(circ, progress, color, channeling, now)
    if not (circ and circ.dottedSegments) then return end
    local v = progress or 0
    if channeling then v = 1.0 - v end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end

    local count = circ.dottedCount or #circ.dottedSegments
    local raw = v * count
    local full = math_floor(raw)
    local partial = raw - full
    if v >= 1 then
        full = count
        partial = 0
    end
    local current = math_min(count, full + 1)
    local baseAlpha = circ.dottedAlpha or 0.95
    local glowAlpha = circ.dottedGlow and (0.18 + 0.14 * (math_sin((now or GetTime()) * 8.0) * 0.5 + 0.5)) or 0

    for i = 1, count do
        local dot = circ.dottedSegments[i]
        if dot.fill then
            dot.fill:SetVertexColor(color.r, color.g, color.b, 1)
            if i <= full then
                dot.fill:SetAlpha(baseAlpha)
            elseif i == current and partial > 0 then
                dot.fill:SetAlpha((0.18 + partial * 0.82) * baseAlpha)
            else
                dot.fill:SetAlpha(0)
            end
        end
        if dot.glow then
            if i == current and partial > 0 then
                dot.glow:SetVertexColor(color.r, color.g, color.b, 1)
                dot.glow:SetAlpha(glowAlpha)
            else
                dot.glow:SetAlpha(0)
            end
        end
    end
end

local function _V8ResetSegments(circ, hideTrack)
    if not (circ and circ.v8Segments) then return end
    local trackAlpha = (not hideTrack) and circ.v8ShowTrack and 0.26 or 0
    for i = 1, #circ.v8Segments do
        local seg = circ.v8Segments[i]
        if seg.backdrop then seg.backdrop:SetAlpha(trackAlpha) end
        if seg.border   then seg.border:SetAlpha(trackAlpha * 0.75) end
        if seg.fill     then seg.fill:SetAlpha(0) end
        if seg.glow     then seg.glow:SetAlpha(0) end
    end
end

local function _V8ColorSegments(circ, color)
    if not (circ and circ.v8Segments and color) then return end
    for i = 1, #circ.v8Segments do
        local seg = circ.v8Segments[i]
        if seg.fill then
            seg.fill:SetVertexColor(color.r, color.g, color.b, 1)
        end
        if seg.glow then
            seg.glow:SetVertexColor(color.r, color.g, color.b, 1)
        end
        if seg.border then
            seg.border:SetVertexColor(color.r * 0.55, color.g * 0.55, color.b * 0.55, 1)
        end
    end
end

-- ─── Sprite castbar update ───────────────────────────────────────────────────
local function _UpdateSprite(sprite, progress, color, channeling)
    if not (sprite and sprite.tex) then return end
    local v = channeling and (1.0 - (progress or 0)) or (progress or 0)
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    -- Clip to last valid frame (frame 71 = 100%)
    local frameIdx = math_min(SPRITE_TOTAL - 1, math_floor(v * SPRITE_TOTAL))
    local col = frameIdx % SPRITE_COLS
    local row = math_floor(frameIdx / SPRITE_COLS)
    sprite.tex:SetTexCoord(
        col / SPRITE_COLS,
        (col + 1) / SPRITE_COLS,
        row / SPRITE_ROWS,
        (row + 1) / SPRITE_ROWS
    )
    if color then
        sprite.tex:SetVertexColor(color.r, color.g, color.b, sprite.alpha or 0.90)
    end
end

local function _V8UpdateSegments(circ, progress, color, channeling, now)
    if not (circ and circ.v8Segments) then return end
    local v = progress or 0
    if channeling then v = 1.0 - v end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end

    local count = circ.v8Count or #circ.v8Segments
    local raw = v * count
    local full = math_floor(raw)
    local partial = raw - full
    if v >= 1 then
        full = count
        partial = 0
    end
    local current = math_min(count, full + 1)
    local pulse = 0.55 + 0.35 * (math_sin((now or GetTime()) * 8.0) * 0.5 + 0.5)

    for i = 1, count do
        local seg = circ.v8Segments[i]
        if seg.fill then
            seg.fill:SetVertexColor(color.r, color.g, color.b, 1)
            if i <= full then
                seg.fill:SetAlpha(0.92)
            elseif i == current and partial > 0 then
                seg.fill:SetAlpha(0.22 + partial * 0.70)
            else
                seg.fill:SetAlpha(0)
            end
        end
        if seg.glow then
            if i == current and partial > 0 then
                seg.glow:SetVertexColor(color.r, color.g, color.b, 1)
                seg.glow:SetAlpha((circ.v8GlowAlpha or 0.26) * pulse)
            else
                seg.glow:SetAlpha(0)
            end
        end
    end
end

local function _CastBarTexture(cfg)
    if SP.GetCastBarTexturePath then
        return SP:GetCastBarTexturePath(cfg and cfg.castbar_texture)
    end
    return WHITE
end

local function _FontPath(name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and name then
        local ok, path = pcall(LSM.Fetch, LSM, "font", name)
        if ok and path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function _ColorFromCfg(cfg, prefix, dr, dg, db, da)
    cfg = cfg or {}
    return cfg[prefix .. "R"] or dr, cfg[prefix .. "G"] or dg, cfg[prefix .. "B"] or db, cfg[prefix .. "A"] or da or 1
end

local function _SetShadowCircleTexture(tex)
    if not tex then return end
    local ok = pcall(tex.SetTexture, tex, SHADOW_CIRCLE_TEX)
    if (not ok) or (tex.GetTexture and not tex:GetTexture()) then
        tex:SetTexture(RADIAL_GLOW)
    end
end

local function _Lerp(a, b, t)
    return a + (b - a) * t
end

local function _CollapseColor(cfg, progress, interrupted)
    cfg = cfg or {}
    if interrupted then
        local c = _rgb(cfg.castbar_color_broken, COLOR_BROKEN)
        return c.r, c.g, c.b, cfg.castbar_collapse_alpha or 0.92
    end
    if (cfg.castbar_collapse_color_mode or "dynamic") == "fixed" then
        return _ColorFromCfg(cfg, "castbar_collapse_fixed", 1.0, 0.25, 0.85, cfg.castbar_collapse_alpha or 0.92)
    end

    local p = progress or 0
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    local a = cfg.castbar_collapse_alpha or 0.92
    local r1, g1, b1 = 1.00, 0.18, 0.78 -- rose
    local r2, g2, b2 = 0.62, 0.18, 1.00 -- violet
    local r3, g3, b3 = 0.12, 0.55, 1.00 -- bleu
    local r4, g4, b4 = 0.18, 1.00, 0.42 -- vert

    if p < 0.333 then
        local t = p / 0.333
        return _Lerp(r1, r2, t), _Lerp(g1, g2, t), _Lerp(b1, b2, t), a
    elseif p < 0.666 then
        local t = (p - 0.333) / 0.333
        return _Lerp(r2, r3, t), _Lerp(g2, g3, t), _Lerp(b2, b3, t), a
    end
    local t = (p - 0.666) / 0.334
    return _Lerp(r3, r4, t), _Lerp(g3, g4, t), _Lerp(b3, b4, t), a
end

local function _ResetCollapse(circ)
    if not (circ and circ.collapseTex) then return end
    circ.collapseTex:SetAlpha(0)
    circ.collapseTex:Hide()
    circ.collapseInterruptStart = nil
    circ.collapseProgress = 0
end

local function _UpdateCollapse(circ, progress, cfg, now, interrupted)
    if not (circ and circ.collapseTex) then return end
    cfg = cfg or {}
    local p = progress or 0
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    circ.collapseProgress = p

    local startScale = tonumber(cfg.castbar_collapse_start_scale) or 1.75
    local endScale = tonumber(cfg.castbar_collapse_end_scale) or 0.72
    if startScale < endScale then startScale, endScale = endScale, startScale end
    local scale = _Lerp(startScale, endScale, p)
    local size = (circ.collapseBaseSize or 64) * scale
    circ.collapseTex:SetSize(size, size)

    local r, g, b, a = _CollapseColor(cfg, p, interrupted)
    if interrupted then
        local blink = 0.35 + 0.55 * (math_sin((now or GetTime()) * 34.0) * 0.5 + 0.5)
        a = (cfg.castbar_collapse_alpha or 0.92) * blink
    end
    circ.collapseTex:SetVertexColor(r, g, b, a)
    circ.collapseTex:SetAlpha(a)
    circ.collapseTex:Show()
end

local function _SaturateRGB(r, g, b, saturation)
    saturation = tonumber(saturation) or 1
    if saturation < 0 then saturation = 0 elseif saturation > 2 then saturation = 2 end
    local l = (r + g + b) / 3
    r = l + (r - l) * saturation
    g = l + (g - l) * saturation
    b = l + (b - l) * saturation
    return math_max(0, math_min(1, r)),
           math_max(0, math_min(1, g)),
           math_max(0, math_min(1, b))
end

local function _CollapseGlowColor(cfg, castColor, interrupted, progress)
    cfg = cfg or {}
    if interrupted then
        local c = _rgb(cfg.castbar_color_broken, COLOR_BROKEN)
        return c.r, c.g, c.b, cfg.castbar_collapse_glow_alpha or 0.85
    end
    local mode = cfg.castbar_collapse_glow_color_mode or "cast"
    if mode == "custom" then
        return _ColorFromCfg(cfg, "castbar_collapse_glow", 0.30, 1.00, 0.45, cfg.castbar_collapse_glow_alpha or 0.85)
    elseif mode == "progressive" then
        local p = progress or 0
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local sr = tonumber(cfg.castbar_collapse_glow_startR) or 1.00
        local sg = tonumber(cfg.castbar_collapse_glow_startG) or 0.22
        local sb = tonumber(cfg.castbar_collapse_glow_startB) or 0.78
        local er = tonumber(cfg.castbar_collapse_glow_endR) or 0.22
        local eg = tonumber(cfg.castbar_collapse_glow_endG) or 1.00
        local eb = tonumber(cfg.castbar_collapse_glow_endB) or 0.62
        local r = _Lerp(sr, er, p)
        local g = _Lerp(sg, eg, p)
        local b = _Lerp(sb, eb, p)
        r, g, b = _SaturateRGB(r, g, b, cfg.castbar_collapse_glow_saturation)
        return r, g, b, cfg.castbar_collapse_glow_alpha or 0.85
    end
    castColor = castColor or COLOR_CAST
    return castColor.r or COLOR_CAST.r, castColor.g or COLOR_CAST.g, castColor.b or COLOR_CAST.b, cfg.castbar_collapse_glow_alpha or 0.85
end

local function _CollapseGlowShape(cfg)
    local shape = (cfg and cfg.castbar_collapse_glow_shape) or "soft"
    if shape == "thin_arcane" then
        return 0.78, 0.58, 0.09, 0.18, false
    elseif shape == "double" then
        return 1.00, 0.95, 0.18, 0.34, false
    elseif shape == "performance" then
        return 0.86, 0.75, 0.00, 0.00, true
    end
    return 1.00, 1.00, 0.16, 0.46, false
end

local function _ResetCollapseGlow(circ)
    if not (circ and circ.collapseGlow) then return end
    local glow = circ.collapseGlow
    if glow.halo then glow.halo:SetAlpha(0); glow.halo:Hide() end
    if glow.ring then glow.ring:SetAlpha(0); glow.ring:Hide() end
    if glow.ringDots then
        -- Compat avec une ancienne tentative visuelle : les dots creaient
        -- les cercles parasites visibles autour du Collapse Glow.
        for i = 1, #glow.ringDots do
            glow.ringDots[i]:SetAlpha(0)
            glow.ringDots[i]:Hide()
        end
    end
    if glow.core then glow.core:SetAlpha(0); glow.core:Hide() end
    if glow.frame then glow.frame:Hide() end
    circ.collapseGlowInterruptStart = nil
    circ.collapseGlowProgress = 0
end

local function _UpdateCollapseGlow(circ, progress, cfg, now, interrupted, castColor)
    if not (circ and circ.collapseGlow) then return end
    cfg = cfg or {}
    local glow = circ.collapseGlow
    local p = progress or 0
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    circ.collapseGlowProgress = p

    local startScale = tonumber(cfg.castbar_collapse_glow_start_scale) or 1.65
    local endScale = tonumber(cfg.castbar_collapse_glow_end_scale) or 0.45
    if startScale < endScale then startScale, endScale = endScale, startScale end
    local scale = _Lerp(startScale, endScale, p)
    local baseSize = glow.baseSize or 64
    local ringSize = math_max(8, baseSize * scale)
    local thick = tonumber(cfg.castbar_collapse_glow_thickness) or 1.0
    if thick < 0.25 then thick = 0.25 elseif thick > 2.5 then thick = 2.5 end

    local sizeMul, thickMul, coreAlphaMul, haloAlphaMul, hideCore = _CollapseGlowShape(cfg)
    thick = thick * thickMul
    local haloSize = (ringSize + math_max(8, 18 * thick)) * sizeMul
    if glow.frame then
        glow.frame:SetSize(haloSize, haloSize)
        glow.frame:Show()
    end
    if glow.halo then glow.halo:SetSize(haloSize, haloSize) end
    if glow.ring then glow.ring:SetSize(ringSize, ringSize) end
    if glow.core then glow.core:SetSize(math_max(6, ringSize * 0.42), math_max(6, ringSize * 0.42)) end

    local r, g, b, alpha = _CollapseGlowColor(cfg, castColor, interrupted, p)
    local intensity = tonumber(cfg.castbar_collapse_glow_intensity) or 1.0
    if intensity < 0 then intensity = 0 elseif intensity > 2 then intensity = 2 end
    alpha = math_min(1, alpha * intensity)
    local pulse = 1
    if cfg.castbar_collapse_glow_pulse ~= false then
        pulse = 0.82 + 0.18 * (math_sin((now or GetTime()) * 6.5) * 0.5 + 0.5)
    end
    if interrupted then
        pulse = 0.25 + 0.75 * (math_sin((now or GetTime()) * 34.0) * 0.5 + 0.5)
    end

    if glow.halo then
        glow.halo:SetVertexColor(r, g, b, 1)
        glow.halo:SetAlpha(alpha * haloAlphaMul * pulse)
        glow.halo:Show()
    end
    if glow.ring then
        glow.ring:SetVertexColor(r, g, b, 1)
        glow.ring:SetAlpha(0)
        glow.ring:Hide()
    end
    if glow.ringDots then
        for i = 1, #glow.ringDots do
            glow.ringDots[i]:SetAlpha(0)
            glow.ringDots[i]:Hide()
        end
    end
    if glow.core then
        glow.core:SetVertexColor(r, g, b, 1)
        if hideCore then
            glow.core:SetAlpha(0)
            glow.core:Hide()
        else
            glow.core:SetAlpha(alpha * coreAlphaMul * pulse)
            glow.core:Show()
        end
    end
end

local function _RestoreNameReplacement(data)
    local cb = data and data.castbar
    if not (cb and cb._nameReplaceActive) then return end
    cb._nameReplaceActive = false
    cb._nameReplaceText = nil
    cb._nameReplaceSafeText = nil
    cb._nameReplaceNext = nil
    if data.nameText then
        if data.unit and SP.Orb and SP.Orb.UpdateName then
            pcall(SP.Orb.UpdateName, SP.Orb, data, data.unit)
        elseif data._previewName then
            data.nameText:SetText(data._previewName)
            data.nameText:Show()
        elseif SP.Orb and SP.Orb.UpdateName then
            pcall(SP.Orb.UpdateName, SP.Orb, data, nil)
        end
    end
end

local function _ApplyNameReplacement(data, text, cfg, now, safeText)
    local cb = data and data.castbar
    if not (cb and data.nameText) then return end
    cfg = cfg or {}
    if cfg.castbar_text_mode ~= "replace_name" or cfg.castbar_showName == false then
        _RestoreNameReplacement(data)
        return
    end
    cb._nameReplaceActive = true
    if SafeNotNil(text) then
        cb._nameReplaceText = text
    else
        cb._nameReplaceText = ""
    end
    cb._nameReplaceSafeText = safeText or TrySafeText(text, 26) or ""
    cb._nameReplaceNext = (now or GetTime()) + 0.20
    _SetFontText(data.nameText, cb._nameReplaceText, cb._nameReplaceSafeText)
    data.nameText:Show()
end

local function _MaintainNameReplacement(data, cfg, now)
    local cb = data and data.castbar
    if not (cb and cb._nameReplaceActive) then return end
    if not SafeNotNil(cb._nameReplaceText) then return end
    if not data.nameText then return end
    cfg = cfg or {}
    if cfg.castbar_text_mode ~= "replace_name" or cfg.castbar_showName == false or not cb.active then
        _RestoreNameReplacement(data)
        return
    end
    if (cb._nameReplaceNext or 0) <= (now or GetTime()) then
        cb._nameReplaceNext = (now or GetTime()) + 0.20
        _SetFontText(data.nameText, cb._nameReplaceText, cb._nameReplaceSafeText or "")
        data.nameText:Show()
    end
end

local function _CreateInterruptMark(data, rootFL)
    local root = data and data.root
    if not root then return nil end
    local frame = CreateFrame("Frame", nil, root)
    frame:SetSize(48, 48)
    frame:SetPoint("CENTER", data.orb or root, "CENTER", 0, 0)
    frame:SetFrameLevel((rootFL or (root:GetFrameLevel() or 10)) + 12)
    pcall(frame.SetFrameStrata, frame, "HIGH")
    frame:Hide()

    local parts = {}
    for i = 1, 4 do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(WHITE)
        tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        tex:Hide()
        parts[i] = tex
    end
    return { frame = frame, parts = parts, start = 0, duration = 0, alpha = 0 }
end

local function _ResetInterruptMark(cb)
    local mark = cb and cb.interruptMark
    if not mark then return end
    mark.active = false
    mark.start = 0
    if mark.parts then
        for i = 1, #mark.parts do
            mark.parts[i]:SetAlpha(0)
            mark.parts[i]:Hide()
        end
    end
    if mark.frame then mark.frame:Hide() end
end

local function _SetMarkPart(mark, idx, w, h, rot, r, g, b, alpha)
    local tex = mark and mark.parts and mark.parts[idx]
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", mark.frame, "CENTER", 0, 0)
    tex:SetSize(w, h)
    pcall(tex.SetRotation, tex, rot or 0)
    tex:SetVertexColor(r, g, b, alpha)
    tex:SetAlpha(alpha)
    tex:Show()
end

local function _ShowInterruptMark(data, cfg, color)
    local cb = data and data.castbar
    local mark = cb and cb.interruptMark
    if not mark or not mark.frame then return end
    cfg = cfg or {}
    if cfg.castbar_interrupt_mark_enabled == false then _ResetInterruptMark(cb); return end
    local shape = cfg.castbar_interrupt_mark_shape or "x"
    if shape == "none" then _ResetInterruptMark(cb); return end

    local size = tonumber(cfg.castbar_interrupt_mark_size) or 18
    if size < 6 then size = 6 elseif size > 42 then size = 42 end
    local alpha = tonumber(cfg.castbar_interrupt_mark_alpha) or 0.92
    if alpha < 0.05 then alpha = 0.05 elseif alpha > 1 then alpha = 1 end
    local duration = tonumber(cfg.castbar_interrupt_mark_duration) or 0.42
    if duration < 0.05 then duration = 0.05 elseif duration > 1.5 then duration = 1.5 end

    local r, g, b
    if cfg.castbar_interrupt_mark_custom_color then
        r = tonumber(cfg.castbar_interrupt_markR) or 0.95
        g = tonumber(cfg.castbar_interrupt_markG) or 0.20
        b = tonumber(cfg.castbar_interrupt_markB) or 0.20
    else
        local c = color or _rgb(cfg.castbar_color_broken, COLOR_BROKEN)
        r, g, b = c.r or COLOR_BROKEN.r, c.g or COLOR_BROKEN.g, c.b or COLOR_BROKEN.b
    end

    _ResetInterruptMark(cb)
    mark.frame:SetSize(size * 2.4, size * 2.4)
    mark.frame:Show()
    mark.active = true
    mark.start = GetTime()
    mark.duration = duration
    mark.alpha = alpha

    local barW = math_max(2, size * 0.22)
    if shape == "cross" then
        _SetMarkPart(mark, 1, barW, size * 1.45, 0, r, g, b, alpha)
        _SetMarkPart(mark, 2, size * 1.45, barW, 0, r, g, b, alpha)
    elseif shape == "slash" then
        _SetMarkPart(mark, 1, barW, size * 1.65, -math_pi / 4, r, g, b, alpha)
    elseif shape == "square" then
        _SetMarkPart(mark, 1, size, size, 0, r, g, b, alpha * 0.72)
    elseif shape == "diamond" then
        _SetMarkPart(mark, 1, size, size, math_pi / 4, r, g, b, alpha * 0.72)
    elseif shape == "rune" then
        _SetMarkPart(mark, 1, barW, size * 1.35, 0, r, g, b, alpha)
        _SetMarkPart(mark, 2, size * 0.72, barW, -math_pi / 5, r, g, b, alpha)
        _SetMarkPart(mark, 3, size * 0.72, barW, math_pi / 5, r, g, b, alpha)
    else -- x
        _SetMarkPart(mark, 1, barW, size * 1.65, math_pi / 4, r, g, b, alpha)
        _SetMarkPart(mark, 2, barW, size * 1.65, -math_pi / 4, r, g, b, alpha)
    end
end

local function _TickInterruptMark(cb, now)
    local mark = cb and cb.interruptMark
    if not (mark and mark.active and mark.frame) then return end
    local elapsed = (now or GetTime()) - (mark.start or 0)
    local duration = mark.duration or 0.42
    if elapsed >= duration then
        _ResetInterruptMark(cb)
        return
    end
    local a = (mark.alpha or 0.9) * (1 - (elapsed / duration))
    if mark.parts then
        for i = 1, #mark.parts do
            if mark.parts[i]:IsShown() then mark.parts[i]:SetAlpha(a) end
        end
    end
end

local function _RuntimeCastStillExists(data, cb)
    if not (data and cb and data.unit) then return true end
    local found = false
    local okCast = pcall(function()
        local n = UnitCastingInfo(data.unit)
        if SafeNotNil(n) then found = true end
    end)
    local okChannel = pcall(function()
        local n = UnitChannelInfo(data.unit)
        if SafeNotNil(n) then found = true end
    end)
    if not okCast and not okChannel then return true end
    return found
end

local function _PlaceCastText(data, castName, castTime, lockTex, cfg, size, thick)
    if not castName then return end
    local anchor = data.orb or data.root
    local pos = cfg.castbar_text_position or "bottom"
    local x = cfg.castbar_text_offset_x or 0
    local y = cfg.castbar_text_offset_y or 0
    local sameIcon = cfg.castbar_show_icon ~= false and (cfg.castbar_icon_position or "top") == pos
    local bump = sameIcon and math_max(10, math_floor(size * 0.18)) or 0
    local gap = math_max(8, thick + 5)

    castName:ClearAllPoints()
    if pos == "center" then
        castName:SetPoint("CENTER", anchor, "CENTER", x, y + (sameIcon and -bump or 0))
    elseif pos == "top" then
        castName:SetPoint("BOTTOM", anchor, "TOP", x, gap + y + bump)
    elseif pos == "left" then
        castName:SetPoint("RIGHT", anchor, "LEFT", -gap + x - bump, y)
    elseif pos == "right" then
        castName:SetPoint("LEFT", anchor, "RIGHT", gap + x + bump, y)
    else
        castName:SetPoint("TOP", anchor, "BOTTOM", x, -gap + y - bump)
    end

    castName:SetWidth(size * 3.2)
    castName:SetJustifyH("CENTER")
    if castTime then
        castTime:ClearAllPoints()
        castTime:SetJustifyH("CENTER")
        castTime:SetPoint("TOP", castName, "BOTTOM", 0, -1)
    end
    if lockTex then
        lockTex:ClearAllPoints()
        lockTex:SetPoint("RIGHT", castName, "LEFT", -3, 0)
    end
end

function SP.CastBar:_CreateV8Segments(data, anchor, arcSize, thick, offX, offY, rootFL, cfg)
    local root = data.root
    if not root then return nil end
    cfg = cfg or {}

    local smoothMode = cfg.castbar_mode == "circular"
    local count = smoothMode and 64 or _V8Count(cfg.castbar_v8_count)
    local segmentMode = cfg.castbar_mode == "segments"
    local showTrack = (not segmentMode) and (not smoothMode) and cfg.castbar_show_track ~= false
    local frame = CreateFrame("Frame", nil, root)
    frame:SetSize(arcSize + 12, arcSize + 12)
    frame:SetPoint("CENTER", anchor or root, "CENTER", offX or 0, offY or 0)
    frame:SetFrameLevel(rootFL + 3)
    pcall(frame.SetFrameStrata, frame, "HIGH")

    local ringRadius = math_max(8, arcSize * 0.5 - math_max(2, thick * (smoothMode and 0.26 or 0.32)))
    local segmentLen = math_max(5, (2 * math_pi * ringRadius / count) * (smoothMode and 0.92 or 0.58))
    local segmentThick = math_max(2, math_min(smoothMode and 4 or 5, thick * (smoothMode and 0.22 or 0.30)))
    local borderPad = segmentMode and 0.8 or 1.2
    local fillTexture = _CastBarTexture(cfg)
    local segments = {}

    for i = 1, count do
        local angle = (math_pi * 0.5) - ((i - 1) / count) * 2 * math_pi
        local x = math_cos(angle) * ringRadius
        local y = math_sin(angle) * ringRadius
        local rotation = -(angle - math_pi * 0.5)

        local border = frame:CreateTexture(nil, "BACKGROUND")
        border:SetTexture(WHITE)
        border:SetSize(segmentLen + borderPad * 2, segmentThick + borderPad * 2)
        border:SetPoint("CENTER", frame, "CENTER", x, y)
        border:SetRotation(rotation)
        border:SetVertexColor(0.30, 0.24, 0.16, 1)
        border:SetAlpha(showTrack and 0.18 or 0)

        local backdrop = frame:CreateTexture(nil, "BORDER")
        backdrop:SetTexture(WHITE)
        backdrop:SetSize(segmentLen, segmentThick)
        backdrop:SetPoint("CENTER", frame, "CENTER", x, y)
        backdrop:SetRotation(rotation)
        backdrop:SetVertexColor(0.02, 0.02, 0.025, 1)
        backdrop:SetAlpha(showTrack and 0.22 or 0)

        local fill = frame:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(fillTexture)
        fill:SetSize(segmentLen, segmentThick)
        fill:SetPoint("CENTER", frame, "CENTER", x, y)
        fill:SetRotation(rotation)
        fill:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1)
        fill:SetAlpha(0)

        local glow = frame:CreateTexture(nil, "OVERLAY")
        glow:SetTexture(RADIAL_GLOW)
        glow:SetSize(segmentLen + 10, segmentLen + 10)
        glow:SetPoint("CENTER", frame, "CENTER", x, y)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1)
        glow:SetAlpha(0)

        segments[i] = {
            border = border,
            backdrop = backdrop,
            fill = fill,
            glow = glow,
        }
    end

    return {
        frame = frame,
        segments = segments,
        count = count,
        showTrack = showTrack,
        glowAlpha = math_min(0.34, 0.12 + 0.08 * (cfg.castbar_glow_intensity or 1.0)),
        smooth = smoothMode,
    }
end

function SP.CastBar:_CreateDottedSegments(data, anchor, arcSize, thick, offX, offY, rootFL, cfg)
    local root = data.root
    if not root then return nil end
    cfg = cfg or {}

    local count = _DottedCount(cfg.castbar_dotted_count)
    local dotSize = math_max(2, math_min(12, tonumber(cfg.castbar_dotted_size) or 5))
    local radius = math_max(8, arcSize * 0.5 - math_max(1, thick * 0.12) + (tonumber(cfg.castbar_dotted_radius) or 0))
    local frame = CreateFrame("Frame", nil, root)
    frame:SetSize(radius * 2 + dotSize * 4, radius * 2 + dotSize * 4)
    frame:SetPoint("CENTER", anchor or root, "CENTER", offX or 0, offY or 0)
    frame:SetFrameLevel(rootFL + 3)
    pcall(frame.SetFrameStrata, frame, "HIGH")

    local showTrack = cfg.castbar_show_track ~= false
    local dots = {}
    for i = 1, count do
        local angle = (math_pi * 0.5) - ((i - 1) / count) * 2 * math_pi
        local x = math_cos(angle) * radius
        local y = math_sin(angle) * radius

        local track = frame:CreateTexture(nil, "BACKGROUND")
        track:SetTexture(RADIAL_GLOW)
        track:SetSize(dotSize * 2.1, dotSize * 2.1)
        track:SetPoint("CENTER", frame, "CENTER", x, y)
        track:SetBlendMode("ADD")
        track:SetVertexColor(0.18, 0.16, 0.12, 1)
        track:SetAlpha(showTrack and 0.20 or 0)

        local fill = frame:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(RADIAL_GLOW)
        fill:SetSize(dotSize * 2.0, dotSize * 2.0)
        fill:SetPoint("CENTER", frame, "CENTER", x, y)
        fill:SetBlendMode("ADD")
        fill:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1)
        fill:SetAlpha(0)

        local glow
        if cfg.castbar_dotted_glow ~= false then
            glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetTexture(RADIAL_GLOW)
            glow:SetSize(dotSize * 4.0, dotSize * 4.0)
            glow:SetPoint("CENTER", frame, "CENTER", x, y)
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1)
            glow:SetAlpha(0)
        end

        dots[i] = { track = track, fill = fill, glow = glow }
    end

    return {
        frame = frame,
        segments = dots,
        count = count,
        dotSize = dotSize,
        radius = radius,
        showTrack = showTrack,
        alpha = math_max(0.1, math_min(1, tonumber(cfg.castbar_dotted_alpha) or 0.95)),
        glow = cfg.castbar_dotted_glow ~= false,
    }
end

function SP.CastBar:_CreateCollapseRing(data, anchor, arcSize, thick, offX, offY, rootFL, cfg)
    local root = data.root
    if not root then return nil end
    cfg = cfg or {}

    local frame = CreateFrame("Frame", nil, root)
    local baseSize = arcSize + math_max(8, thick * 1.4)
    frame:SetSize(baseSize * 2.0, baseSize * 2.0)
    frame:SetPoint("CENTER", anchor or root, "CENTER", offX or 0, offY or 0)
    frame:SetFrameLevel(rootFL + 4)
    pcall(frame.SetFrameStrata, frame, "HIGH")

    local tex = frame:CreateTexture(nil, "OVERLAY")
    _SetShadowCircleTexture(tex)
    tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    tex:SetBlendMode("BLEND")
    tex:SetVertexColor(1, 0.25, 0.85, 0)
    tex:SetAlpha(0)
    tex:Hide()

    return {
        frame = frame,
        tex = tex,
        baseSize = baseSize,
    }
end

function SP.CastBar:_CreateCollapseGlowRing(data, anchor, arcSize, thick, offX, offY, rootFL, cfg)
    local root = data.root
    if not root then return nil end
    cfg = cfg or {}

    local baseSize = arcSize + math_max(8, thick * 1.6)
    local frame = CreateFrame("Frame", nil, root)
    frame:SetSize(baseSize * 2.0, baseSize * 2.0)
    frame:SetPoint("CENTER", anchor or root, "CENTER", offX or 0, offY or 0)
    frame:SetFrameLevel(rootFL + 5)
    pcall(frame.SetFrameStrata, frame, "HIGH")
    frame:Hide()

    local halo = frame:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture(RADIAL_GLOW)
    halo:SetPoint("CENTER", frame, "CENTER", 0, 0)
    halo:SetBlendMode("ADD")
    halo:SetAlpha(0)
    halo:Hide()

    local core = frame:CreateTexture(nil, "OVERLAY")
    core:SetTexture(RADIAL_GLOW)
    core:SetPoint("CENTER", frame, "CENTER", 0, 0)
    core:SetBlendMode("ADD")
    core:SetAlpha(0)
    core:Hide()

    return {
        frame = frame,
        halo = halo,
        core = core,
        baseSize = baseSize,
    }
end

-------------------------------------------------------------------------------
--  _ApplyCast — applique l'état de cast
--  Signature étendue : + iconTex (optionnel)
-------------------------------------------------------------------------------
function SP.CastBar:_ApplyCast(data, name, startMS, endMS, notInt, isChannel, iconTex, spellId, castGUID)
    local cb = data.castbar
    if not cb then return end
    local safeNotInt = SafeBool(notInt, false)
    local safeIsChannel = SafeBool(isChannel, false)

    local now = GetTime()
    local safeSMS = SP:UntaintNum(startMS) or (now * 1000)
    local safeEMS = SP:UntaintNum(endMS)   or (safeSMS + 3000)
    local startSec = safeSMS / 1000
    local endSec   = safeEMS / 1000
    local duration = endSec - startSec

    if duration < 0.1 or duration > 600 or math_abs(startSec - now) > 120 then
        startSec = now
        duration = math_max(0.5, duration > 0 and duration or 3.0)
        endSec   = startSec + duration
    end

    local displayName, safeName, nameSource = _ResolveCastDisplayValue(name, spellId, safeIsChannel)
    SP:Debug(string.format("[CastBar] \"%s\" %.2fs %s src=%s", safeName, duration, safeIsChannel and "[CH]" or "[CAST]", nameSource or "?"))
    local unit = data.unit or ""
    local cfg = SP:GetCfg(data.unitType) or {}
    local clr, isImmune = _ClassifyCast(unit, safeNotInt, safeIsChannel, cfg)

    cb.active        = true
    cb.channeling    = safeIsChannel
    cb.startTime     = startSec
    cb.endTime       = endSec
    cb.duration      = duration
    cb.interruptible = not safeNotInt
    cb.isImmune      = isImmune
    cb.flashStart    = 0
    cb.color         = clr
    cb.spellId       = spellId
    cb.castGUID      = castGUID
    cb.castDisplayName = safeName
    cb.castDisplayText = displayName
    cb.castDisplaySource = nameSource
    cb._activePollTimer = 0
    cb._activePollLast = now
    cb._runtimeMissingSince = nil
    cb._runtimeMissingCount = 0
    _ResetInterruptMark(cb)

    -- ── Icône du sort ──────────────────────────────────────────────────────────
    if cb.iconTex then
        local tex, hasTex = nil, false
        pcall(function()
            if iconTex ~= nil then
                tex = iconTex
                hasTex = true
            end
        end)
        if not hasTex and safeName ~= "" then
            -- Dernier recours : cherche via le nom (peut échouer → nil = icône cachée)
            if C_Spell and C_Spell.GetSpellIDForAura then
                local ok2, id = pcall(C_Spell.GetSpellIDForAura, safeName)
                if ok2 and id then
                    tex = GetSpellIcon(id)
                    hasTex = SafeNotNil(tex)
                end
            end
        end
        if hasTex then
            local okTex = pcall(cb.iconTex.SetTexture, cb.iconTex, tex)
            cb.iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if cb.iconFrame then cb.iconFrame:SetAlpha(okTex and 1 or 0) end
        else
            if cb.iconFrame then cb.iconFrame:SetAlpha(0) end
        end
    end

    -- ── Mode circulaire ─────────────────────────────────────────────────────
    local circ = data._cb_circ
    local isComets = circ and circ.channel_style == "comets" and safeIsChannel
    local isRadar  = circ and circ.channel_style == "radar"  and safeIsChannel
    local isPulse  = circ and circ.channel_style == "pulse"  and safeIsChannel

    if cb.cd then
        cb.cd:SetSwipeColor(clr.r, clr.g, clr.b, 1.0)
        cb.cd:SetReverse(not safeIsChannel)
        cb.cd:SetCooldown(startSec, duration)
        pcall(cb.cd.SetFrameStrata, cb.cd, "HIGH")
        if circ and (circ.v8Segments or circ.dottedSegments or circ.collapseTex or circ.collapseGlow) then
            cb.cd:SetAlpha(0)
            cb.cd:Hide()
        elseif isComets or isRadar then
            cb.cd:SetAlpha(0.20)  -- effets channel remplacent l'arc
            cb.cd:Show()
        else
            cb.cd:SetAlpha(1)
            cb.cd:Show()
        end
    end
    if circ and circ.trackCD then
        circ.trackCD:SetAlpha(0.28)
        circ.trackCD:Show()
    end

    -- Twin mode : 2è cooldown miroir (flip horizontal de la swipe texture)
    if circ and circ.cd2 then
        if (not safeIsChannel) and circ.cast_style == "twin" then
            circ.cd2:SetSwipeColor(clr.r, clr.g, clr.b, 1.0)
            circ.cd2:SetReverse(true)
            circ.cd2:SetCooldown(startSec, duration)
            pcall(function()
                local sw = circ.cd2.GetSwipeTexture and circ.cd2:GetSwipeTexture()
                if sw then sw:SetTexCoord(1, 0, 0, 1) end
            end)
            pcall(circ.cd2.SetFrameStrata, circ.cd2, "HIGH")
            circ.cd2:SetAlpha(0.85)
            circ.cd2:Show()
        else
            circ.cd2:Hide()
        end
    end

    if cb.glowTex then
        cb.glowTex:SetVertexColor(clr.r, clr.g, clr.b)
        local gI = (circ and circ.glow_intensity) or 1.0
        cb.glowTex:SetAlpha((isImmune and 0.16 or 0.10) * gI)
    end
    cb.glowPhase = 0
    if cb.headTex  then cb.headTex:SetVertexColor(clr.r, clr.g, clr.b)  ; cb.headTex:SetAlpha(0)  end
    if cb.trailTex then cb.trailTex:SetVertexColor(clr.r, clr.g, clr.b) ; cb.trailTex:SetAlpha(0) end

    if circ then
        if circ.v8Segments then
            _V8ResetSegments(circ)
            _V8ColorSegments(circ, clr)
        end
        if circ.dottedSegments then
            _ResetDotted(circ)
            _ColorDotted(circ, clr)
        end
        if circ.collapseTex then
            _ResetCollapse(circ)
            _UpdateCollapse(circ, 0, cfg, now, false)
        end
        if circ.collapseGlow then
            _ResetCollapseGlow(circ)
            _UpdateCollapseGlow(circ, 0, cfg, now, false, clr)
        end
        if circ.trail then
            for i = 1, #circ.trail do
                circ.trail[i]:SetVertexColor(clr.r, clr.g, clr.b)
                circ.trail[i]:SetAlpha(0)
            end
        end
        if circ.pin12 then
            circ.pin12:SetVertexColor(clr.r, clr.g, clr.b)
            circ.pin12:SetAlpha(0.50)
        end
        if circ.ticks then
            for i = 1, #circ.ticks do
                local isMajor = ((i - 1) % 6) == 0
                circ.ticks[i]:SetVertexColor(1, 1, 1, isMajor and 0.35 or 0.18)
            end
        end
        if circ.segMarks then
            for i = 1, #circ.segMarks do
                circ.segMarks[i]:SetVertexColor(0, 0, 0, 0.85)
            end
        end
        if circ.comets then
            for i = 1, #circ.comets do
                circ.comets[i]:SetVertexColor(clr.r, clr.g, clr.b)
                circ.comets[i]:SetAlpha(safeIsChannel and 0.85 or 0)
            end
        end
        if circ.radarTrail then
            for i = 1, #circ.radarTrail do
                circ.radarTrail[i]:SetVertexColor(clr.r, clr.g, clr.b)
                circ.radarTrail[i]:SetAlpha(0)
            end
        end
        if circ.pulseRing then
            circ.pulseRing:SetVertexColor(clr.r, clr.g, clr.b)
            circ.pulseRing:SetAlpha(safeIsChannel and 0.30 or 0)
        end
        if circ.completeRing then circ.completeRing:SetAlpha(0) end
        if circ.kickShards then
            for i = 1, #circ.kickShards do circ.kickShards[i]:SetAlpha(0) end
        end
        if circ.icoBorder then
            circ.icoBorder:SetVertexColor(clr.r, clr.g, clr.b)
            circ.icoBorder:SetAlpha(0.55)
        end
        -- V5 : bordure UI-AutoCastableOverlay colorée révélée pendant le cast
        if circ.v5Border then
            circ.v5Border:SetVertexColor(clr.r, clr.g, clr.b)
            circ.v5Border:SetAlpha(0)
        end
        -- Preset Overwatch : track fond reste neutre, glow ext suit la couleur
        if circ.owGlow then
            circ.owGlow:SetVertexColor(clr.r, clr.g, clr.b)
            circ.owGlow:SetAlpha(0.45)
        end
    end
    cb._completeFlashed = false
    cb._kickFXStart = nil

    -- ── Mode sprite ────────────────────────────────────────────────────────
    local spr = data._cb_sprite
    if spr then
        _UpdateSprite(spr, 0, clr, safeIsChannel)
        spr.frame:Show()
    end

    -- ── Mode CCB ───────────────────────────────────────────────────────────
    if data._cb_ccb then
        local notInt = not cb.interruptible
        SP.CCB:Apply(data, safeIsChannel, isImmune, notInt)
    end

    -- ── Mode classique (pill bar) ──────────────────────────────────────────
    if cb.barFill then
        -- Dégradé de gauche (sombre) vers droite (couleur vive)
        pcall(function()
            cb.barFill:SetGradientAlpha("HORIZONTAL",
                clr.r * 0.55, clr.g * 0.55, clr.b * 0.55, 1.0,
                clr.r,        clr.g,        clr.b,        1.0)
        end)
        cb.barFill:SetWidth(safeIsChannel and (cb.barW or 1) or 1)
    end
    if cb.barGlowL then
        cb.barGlowL:SetVertexColor(clr.r, clr.g, clr.b)
    end
    if cb.barBorderTop then
        cb.barBorderTop:SetVertexColor(clr.r * 0.7, clr.g * 0.7, clr.b * 0.7)
        cb.barBorderBot:SetVertexColor(clr.r * 0.7, clr.g * 0.7, clr.b * 0.7)
    end

    -- Verrou
    cb.lockTex:SetAlpha(safeNotInt and 0.75 or 0)

    -- ── Mode classique : afficher barFrame avec visibilité forcée ────────────
    if cb.barFrame then
        pcall(cb.barFrame.SetFrameStrata, cb.barFrame, "HIGH")   -- forcer rendu au-dessus
        cb.barFrame:SetAlpha(1)
        cb.barFrame:Show()
    end

    -- Textes
    local cfg = SP:GetCfg(data.unitType) or {}
    if cfg.castbar_showName ~= false then
        local dn = displayName
        local safeDn = safeName
        -- WoW Midnight : `name` peut être un secret string tainté. `#dn` et `dn:sub`
        -- crashent → on protège via pcall + on évite l'arithmétique sur le secret.
        local okT, trunc = pcall(function()
            if type(dn) == "string" and #dn > 26 then return dn:sub(1, 24) .. "…" end
            return dn
        end)
        if okT and SafeNotNil(trunc) then dn = trunc end
        if isImmune then
            cb.castName:SetTextColor(1.0, 0.45, 0.45, 1)
        elseif not safeNotInt then
            cb.castName:SetTextColor(1.0, 0.88, 0.45, 1)
        else
            cb.castName:SetTextColor(0.88, 0.62, 1.0, 1)
        end
        if cfg.castbar_text_mode == "replace_name" then
            _ApplyNameReplacement(data, dn, cfg, now, safeDn)
            cb.castName:Hide()
        else
            _RestoreNameReplacement(data)
            _SetFontText(cb.castName, dn, safeDn)
            cb.castName:Show()
        end
    else
        _RestoreNameReplacement(data)
        cb.castName:Hide()
    end
    if cfg.castbar_showTime ~= false then
        cb.castTime:SetText(string.format("%.1fs", duration))
        cb.castTime:Show()
    end
    cb.flashTex:SetAlpha(0)

    -- ── Mode focus : masquer HP/ilvl/castTime pendant le cast ─────────────────
    if cfg.castbar_focus_mode then
        if data.levelText then data.levelText:Hide() end
        if data.hpSubText then data.hpSubText:Hide() end
        if cb.castTime    then cb.castTime:Hide()    end
        cb._focusModeActive = true
    end
end

function SP.CastBar:_RefreshCastTiming(data, startMS, endMS, notInt, isChannel)
    local cb = data and data.castbar
    if not (cb and cb.active) then return false end

    local now = GetTime()
    local safeSMS = SP:UntaintNum(startMS)
    local safeEMS = SP:UntaintNum(endMS)
    if not (safeSMS and safeEMS) then return false end

    local startSec = safeSMS / 1000
    local endSec = safeEMS / 1000
    local duration = endSec - startSec
    if duration < 0.1 or duration > 600 or math_abs(startSec - now) > 120 then
        return false
    end

    local safeIsChannel = SafeBool(isChannel, cb.channeling)
    local safeNotInt = SafeBool(notInt, not cb.interruptible)
    local cfg = SP:GetCfg(data.unitType) or {}
    local clr, isImmune = _ClassifyCast(data.unit or "", safeNotInt, safeIsChannel, cfg)

    cb.channeling = safeIsChannel
    cb.startTime = startSec
    cb.endTime = endSec
    cb.duration = duration
    cb.interruptible = not safeNotInt
    cb.isImmune = isImmune
    cb.color = clr

    if cb.cd then
        cb.cd:SetSwipeColor(clr.r, clr.g, clr.b, 1.0)
        cb.cd:SetReverse(not safeIsChannel)
        cb.cd:SetCooldown(startSec, duration)
        if data._cb_circ and (data._cb_circ.v8Segments or data._cb_circ.dottedSegments or data._cb_circ.collapseTex or data._cb_circ.collapseGlow) then
            cb.cd:SetAlpha(0)
            cb.cd:Hide()
        end
    end
    local circ = data._cb_circ
    if circ and circ.cd2 and (not safeIsChannel) and circ.cast_style == "twin" then
        circ.cd2:SetSwipeColor(clr.r, clr.g, clr.b, 1.0)
        circ.cd2:SetReverse(true)
        circ.cd2:SetCooldown(startSec, duration)
    end
    if cb.castTime and cfg.castbar_showTime ~= false then
        cb.castTime:SetText(string.format("%.1fs", math_max(0, endSec - now)))
        cb.castTime:Show()
    end
    return true
end

-------------------------------------------------------------------------------
--  CREATE
-------------------------------------------------------------------------------
function SP.CastBar:Create(data)
    -- Guard : si un castbar existe déjà (orbe recyclé depuis le pool), ne pas
    -- recréer de frames — retourner l'existant directement.
    if data.castbar then return data.castbar end
    local cfg = SP:GetCfg(data.unitType)
    if not cfg.castbar_enabled then return end

    local root   = data.root
    local SIZE   = math_max(16, data.orbSize or 64)
    local thick  = math_max(10, cfg.castbar_arc_thickness or 14)
    local offX   = cfg.castbar_offset_x or 0
    local offY   = cfg.castbar_offset_y or 0
    local mode   = data._forceCastbarV8 and "segments" or (SP.NormalizeCastbarMode and SP:NormalizeCastbarMode(cfg.castbar_mode) or (cfg.castbar_mode or "classic"))

    local arcSize  = SIZE + thick * 2
    local rootFL   = root:GetFrameLevel() or 10
    local nameFS   = cfg.castbar_nameFontSize or 10

    local cd, glowFrame, glowTex, headTex, trailTex
    local barFrame, barFill, barW, barGlowL, barBorderTop, barBorderBot
    local iconFrame, iconTex
    local arcRadius = arcSize * 0.5 - thick * 0.5

    --------------------------------------------------------------------------
    --  Flash commun
    --------------------------------------------------------------------------
    local flashTex = root:CreateTexture(nil, "OVERLAY", nil, 7)
    flashTex:SetTexture(RADIAL_GLOW)
    if data.orb then
        flashTex:SetPoint("TOPLEFT",     data.orb, "TOPLEFT",     -10,  10)
        flashTex:SetPoint("BOTTOMRIGHT", data.orb, "BOTTOMRIGHT",  10, -10)
    end
    flashTex:SetBlendMode("ADD")
    flashTex:SetAlpha(0)

    --------------------------------------------------------------------------
    --  Texte nom du sort (commun)
    --------------------------------------------------------------------------
    local castName = root:CreateFontString(nil, "OVERLAY")
    castName:SetFont(_FontPath(cfg.castbar_text_font), nameFS, "OUTLINE")
    castName:SetJustifyH("CENTER")
    castName:SetWidth(SIZE * 2.8)
    castName:SetTextColor(_ColorFromCfg(cfg, "castbar_text_color", 1.0, 0.88, 0.45, 1))
    castName:SetShadowColor(0, 0, 0, 1)
    castName:SetShadowOffset(1, -1)
    castName:Hide()

    --------------------------------------------------------------------------
    --  Texte temps (commun)
    --------------------------------------------------------------------------
    local castTime = root:CreateFontString(nil, "OVERLAY")
    castTime:SetFont(_FontPath(cfg.castbar_text_font), math_max(7, nameFS - 2), "OUTLINE")
    castTime:SetJustifyH("RIGHT")
    castTime:SetTextColor(0.82, 0.82, 0.82, 0.9)
    castTime:SetShadowColor(0, 0, 0, 1)
    castTime:SetShadowOffset(1, -1)
    castTime:Hide()

    --------------------------------------------------------------------------
    --  Verrou
    --------------------------------------------------------------------------
    local lockTex = root:CreateTexture(nil, "OVERLAY", nil, 4)
    lockTex:SetTexture(LOCK_TEX)
    lockTex:SetSize(9, 9)
    lockTex:SetAlpha(0)
    local interruptMark = _CreateInterruptMark(data, rootFL)

    -- ── BRANCHE SELON LE MODE ───────────────────────────────────────────────

    if mode == "circular" or mode == "segments" or mode == "dotted" or mode == "collapse" or mode == "collapse_glow" then
        -----------------------------------------------------------------------
        --  MODE CIRCULAIRE CCB — couches frame-level :
        --   rootFL+1  trackCD (fond)  + glowFrame (halo modéré)
        --   rootFL+2  cd principal (progression) + cd2 (twin mode)
        --   rootFL+3  bevels, ticks, segMarks, pin12
        --   rootFL+4  trail x3, headTex, comets/radarTrail
        --   rootFL+5  pulseRing, completeRing, kickShards
        --   rootFL+6  iconFrame
        -----------------------------------------------------------------------
        local cstyle  = cfg.castbar_cast_style    or "smooth"
        local chstyle = cfg.castbar_channel_style or "swipe"
        local glowI   = cfg.castbar_glow_intensity or 1.0
        local segN    = cfg.castbar_segments_count or 20
        local cdAnchor = data.orb or root
        local segmentMode = mode == "segments"
        local smoothCircular = mode == "circular"
        local dottedMode = mode == "dotted"
        local collapseMode = mode == "collapse"
        local collapseGlowMode = mode == "collapse_glow"
        local v8Enabled = smoothCircular or segmentMode or dottedMode or collapseMode or collapseGlowMode or (cfg.castbar_v8_segments == true) or (data._forceCastbarV8 == true)

        --  ── 1) Track de fond — preset "overwatch" via assets Quafe ───────
        --     Si preset = "overwatch" ET Quafe_Overwatch installé : utilise
        --     HUD_Ring (texture annulaire fade-to-transparent) comme fond.
        --     Sinon: rien (CooldownFrame swipe est déjà ronde par construction).
        local trackCD = nil
        local owRing, owGlow = nil, nil
        local preset = cfg.castbar_preset or "minimal"
        if (not v8Enabled) and preset == "overwatch" and _HasQuafe() then
            local owFrame = CreateFrame("Frame", nil, root)
            owFrame:SetSize(arcSize, arcSize)
            owFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            owFrame:SetFrameLevel(rootFL + 1)
            owRing = owFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            owRing:SetTexture(OW_HUD_RING)
            owRing:SetAllPoints(owFrame)
            owRing:SetBlendMode("BLEND")
            local tr, tg, tb, ta = _arr2rgba(cfg.castbar_color_track, 0.18, 0.18, 0.22, 0.55)
            owRing:SetVertexColor(tr, tg, tb, ta)
            local glowFrameOW = CreateFrame("Frame", nil, root)
            local gSize = arcSize + math_max(4, math_floor(8 * (cfg.castbar_glow_intensity or 1.0)))
            glowFrameOW:SetSize(gSize, gSize)
            glowFrameOW:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            glowFrameOW:SetFrameLevel(rootFL + 1)
            owGlow = glowFrameOW:CreateTexture(nil, "BACKGROUND", nil, -2)
            owGlow:SetTexture(OW_HUD_BAR5_GLOW)
            owGlow:SetAllPoints(glowFrameOW)
            owGlow:SetBlendMode("ADD")
            owGlow:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
            owGlow:SetAlpha(0)
        end

        --  ── 1.5) Track de fond V7 — UI-AutoCastableOverlay ADD (pas BLEND)
        --     V5 utilisait BLEND avec vertex sombre → carré noir visible si la
        --     texture native n'est pas radialement transparente. V7 corrige :
        --     ADD mode + vertex SOMBRE négatif = soustraction subtile sans carré.
        --     Si toujours moche, le `v5_show_track` peut le désactiver.
        local v5Track = nil
        if (not v8Enabled) and cfg.castbar_show_track ~= false then
            local v5TrackFrame = CreateFrame("Frame", nil, root)
            v5TrackFrame:SetSize(arcSize + 4, arcSize + 4)
            v5TrackFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            v5TrackFrame:SetFrameLevel(rootFL + 1)
            v5Track = v5TrackFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
            v5Track:SetTexture(NATIVE_RING)
            v5Track:SetAllPoints(v5TrackFrame)
            -- ADD avec vertex faible = halo subtil sans rectangle visible
            v5Track:SetBlendMode("ADD")
            v5Track:SetVertexColor(0.45, 0.45, 0.55, 1.0)
            v5Track:SetAlpha(0.30)
        end

        --  ── 2) Cooldown principal — swipe FORCÉ rond (anti-carré 12.x) ────
        local okCD
        okCD, cd = pcall(CreateFrame, "Cooldown", nil, root, "CooldownFrameTemplate")
        if not (okCD and cd) then cd = CreateFrame("Cooldown", nil, root) end
        cd:SetSize(arcSize, arcSize)
        cd:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
        cd:SetFrameLevel(rootFL + 2)
        pcall(cd.SetFrameStrata, cd, "HIGH")
        cd:SetDrawSwipe(true)
        cd:SetDrawEdge(false)
        pcall(function() cd:SetDrawBling(false) end)
        pcall(function() cd:SetHideCountdownNumbers(true) end)
        -- Ne pas forcer ping4 comme texture de swipe: en CooldownFrame 12.x,
        -- cette texture rend un carre noir autour de la progression.
        pcall(function() cd:SetUseCircularEdge(true) end)
        cd:SetReverse(true)
        cd:SetSwipeColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 0.85)
        cd:SetAlpha(v8Enabled and 0 or 1)
        cd:Hide()

        pcall(function()
            if data.orb then data.orb:SetFrameLevel(cd:GetFrameLevel() + 8) end
        end)

        --  ── 2.5) Bordure V5 — anneau UI-AutoCastableOverlay coloré net ────
        --     Au-dessus de la swipe, donne une vraie "gueule" d'anneau coloré.
        local v5Border
        if not v8Enabled then
            local v5BorderFrame = CreateFrame("Frame", nil, root)
            v5BorderFrame:SetSize(arcSize + 4, arcSize + 4)
            v5BorderFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            v5BorderFrame:SetFrameLevel(rootFL + 4)
            v5Border = v5BorderFrame:CreateTexture(nil, "OVERLAY", nil, 1)
            v5Border:SetTexture(NATIVE_RING)
            v5Border:SetAllPoints(v5BorderFrame)
            v5Border:SetBlendMode("ADD")
            v5Border:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
            v5Border:SetAlpha(0)  -- ring decoratif inactif: la progression vient du CooldownFrame
        end

        --  ── 2.6) V6 Spark — point lumineux net qui suit la progression ──
        --     Texture ping4 (radial natif) à la position courante du swipe.
        --     Calcul trig dans Tick : angle = progress * 2π, position sur le rayon.
        local v6Spark
        if not v8Enabled then
            v6Spark = root:CreateTexture(nil, "OVERLAY", nil, 5)
            v6Spark:SetTexture(RADIAL_GLOW)
            v6Spark:SetSize(thick * 0.9, thick * 0.9)
            v6Spark:SetPoint("CENTER", cdAnchor, "CENTER", 0, arcRadius)
            v6Spark:SetBlendMode("ADD")
            v6Spark:SetVertexColor(1.0, 1.0, 1.0)  -- blanc, mixe avec couleur cast
            v6Spark:SetAlpha(0)
        end

        --  ── 3) Twin mode : 2è cooldown miroir ──────────────────────────────
        local cd2
        if (not v8Enabled) and cstyle == "twin" then
            local okC2, c2 = pcall(CreateFrame, "Cooldown", nil, root, "CooldownFrameTemplate")
            if okC2 and c2 then
                cd2 = c2
                cd2:SetSize(arcSize, arcSize)
                cd2:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
                cd2:SetFrameLevel(rootFL + 2)
                pcall(cd2.SetFrameStrata, cd2, "HIGH")
                cd2:SetDrawSwipe(true)
                cd2:SetDrawEdge(false)
                pcall(function() cd2:SetDrawBling(false) end)
                pcall(function() cd2:SetHideCountdownNumbers(true) end)
                cd2:SetReverse(true)
                cd2:Hide()
            end
        end

        --  ── 4) Glow externe — DÉSACTIVÉ (texture orb_glow non-radiale)
        --     L'asset SP.MEDIA/orb_glow est un PNG carré avec gradient ; en
        --     ADD avec vertex tinté il rendait un rectangle bleuté visible
        --     derrière l'orbe. À remplacer par une vraie texture radiale fade
        --     (Quafe HUD_Bar5_Glow.tga par ex.) en V2.
        glowFrame = nil
        glowTex   = nil

        --  ── 5) Bevels — DÉSACTIVÉS : orb_glow se rend comme rectangle noir
        --     en BLEND avec vertex color sombre, ce qui crée un carré opaque
        --     autour de l'orbe. À refaire avec une vraie texture annulaire si
        --     un asset rond fade-to-transparent existe. Pour l'instant : skip.
        local bevelOut, bevelIn = nil, nil

        --  ── 6) Trail (3 textures décroissantes) + head ────────────────────
        local headSize = math_max(5, thick - 3)
        local trail = {}
        if not v8Enabled then
            for i = 1, 3 do
                local tx = root:CreateTexture(nil, "OVERLAY", nil, 5)
                tx:SetTexture(RADIAL_GLOW)
                local sc = 1.1 + 0.35 * i
                tx:SetSize(headSize * sc, headSize * sc)
                tx:SetPoint("CENTER", cd, "CENTER", 0, arcRadius)
                tx:SetBlendMode("ADD")
                tx:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
                tx:SetAlpha(0)
                trail[i] = tx
            end
            trailTex = trail[1]

            headTex = root:CreateTexture(nil, "OVERLAY", nil, 6)
            headTex:SetTexture(RADIAL_GLOW)
            headTex:SetSize(headSize * 1.5, headSize * 1.5)
            headTex:SetPoint("CENTER", cd, "CENTER", 0, arcRadius)
            headTex:SetBlendMode("ADD")
            headTex:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
            headTex:SetAlpha(0)
        end

        --  ── 7) Indicateur 12h (point de départ) ───────────────────────────
        local pin12
        if (not v8Enabled) and cfg.castbar_show_pin12 ~= false then
            pin12 = root:CreateTexture(nil, "OVERLAY", nil, 6)
            pin12:SetTexture(RADIAL_GLOW)
            pin12:SetSize(thick * 0.7, thick * 0.7)
            pin12:SetPoint("CENTER", cd, "CENTER", 0, arcRadius)
            pin12:SetBlendMode("ADD")
            pin12:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
            pin12:SetAlpha(0)
        end

        --  ── 8) Ticks gradués (24, optionnels) ─────────────────────────────
        local ticks
        if (not v8Enabled) and cfg.castbar_show_ticks then
            ticks = {}
            local tF = CreateFrame("Frame", nil, root)
            tF:SetAllPoints(cd)
            tF:SetFrameLevel(rootFL + 3)
            local innerR = arcRadius - thick * 0.5 + 1
            for i = 0, 23 do
                local ang = (i / 24) * 2 * math_pi
                local isMajor = (i % 6) == 0
                local isMinor = (i % 2) == 0
                local len = isMajor and (thick * 0.4) or (isMinor and thick * 0.22 or thick * 0.12)
                local tw  = isMajor and 1.5 or (isMinor and 1.0 or 0.6)
                local tk  = tF:CreateTexture(nil, "OVERLAY")
                tk:SetTexture(WHITE)
                tk:SetSize(tw, len)
                local cx = math_sin(ang) * (innerR + len * 0.5)
                local cy = math_cos(ang) * (innerR + len * 0.5)
                tk:SetPoint("CENTER", tF, "CENTER", cx, cy)
                tk:SetRotation(-ang)
                tk:SetVertexColor(1, 1, 1, isMajor and 0.55 or (isMinor and 0.32 or 0.18))
                ticks[i + 1] = tk
            end
        end

        --  ── 9) Segments — DÉSACTIVÉ V7 (créait l'effet "porc-épic")
        --     N traits noirs WHITE radiaux autour de l'orbe = pics visibles.
        --     Mode segments à refaire avec une vraie texture annulaire dashed.
        local segMarks = nil

        --  ── 10) Channel : comets / radar / pulse ──────────────────────────
        local comets, radarTrail, pulseRing
        if (not v8Enabled) and chstyle == "comets" then
            comets = {}
            for i = 1, 3 do
                local tx = root:CreateTexture(nil, "OVERLAY", nil, 5)
                tx:SetTexture(RADIAL_GLOW)
                tx:SetSize(thick * 1.4, thick * 1.4)
                tx:SetPoint("CENTER", cd, "CENTER", 0, arcRadius)
                tx:SetBlendMode("ADD")
                tx:SetAlpha(0)
                comets[i] = tx
            end
        elseif (not v8Enabled) and chstyle == "radar" then
            radarTrail = {}
            for i = 1, 8 do
                local tx = root:CreateTexture(nil, "OVERLAY", nil, 5)
                tx:SetTexture(RADIAL_GLOW)
                tx:SetSize(thick * 1.2, thick * 1.2)
                tx:SetPoint("CENTER", cd, "CENTER", 0, arcRadius)
                tx:SetBlendMode("ADD")
                tx:SetAlpha(0)
                radarTrail[i] = tx
            end
        elseif (not v8Enabled) and chstyle == "pulse" then
            local pF = CreateFrame("Frame", nil, root)
            pF:SetSize(arcSize + 6, arcSize + 6)
            pF:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            pF:SetFrameLevel(rootFL + 5)
            pulseRing = pF:CreateTexture(nil, "OVERLAY")
            pulseRing:SetTexture(RADIAL_GLOW)
            pulseRing:SetAllPoints(pF)
            pulseRing:SetBlendMode("ADD")
            pulseRing:SetAlpha(0)
        end

        --  ── 11) Anneau de complétion (flash 100%) ─────────────────────────
        local completeRing
        if cfg.castbar_complete_flash ~= false then
            local crF = CreateFrame("Frame", nil, root)
            crF:SetSize(arcSize + 4, arcSize + 4)
            crF:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
            crF:SetFrameLevel(rootFL + 5)
            completeRing = crF:CreateTexture(nil, "OVERLAY")
            completeRing:SetTexture(NATIVE_RING)
            completeRing:SetAllPoints(crF)
            completeRing:SetBlendMode("ADD")
            completeRing:SetVertexColor(1, 1, 1)
            completeRing:SetAlpha(0)
        end

        --  ── 12) Kick FX — DÉSACTIVÉ V7 (créait l'effet "porc-épic" visible)
        --     Les 10 shards WHITE étaient parfois mal nettoyés et restaient
        --     visibles comme des pics radiaux. Effet d'interruption à refaire
        --     proprement via flash global v5Border en rouge plutôt que shards.
        local kickShards = nil

        --  ── 12.5) V8 : segments radiaux fins, sans Cooldown swipe visible ──
        local v8, dotted, collapse, collapseGlow = nil, nil, nil, nil
        if dottedMode then
            dotted = self:_CreateDottedSegments(data, cdAnchor, arcSize, thick, offX, offY, rootFL, cfg)
            if dotted then
                cd:SetAlpha(0)
                cd:Hide()
            end
        elseif collapseMode then
            collapse = self:_CreateCollapseRing(data, cdAnchor, arcSize, thick, offX, offY, rootFL, cfg)
            if collapse then
                cd:SetAlpha(0)
                cd:Hide()
            end
        elseif collapseGlowMode then
            collapseGlow = self:_CreateCollapseGlowRing(data, cdAnchor, arcSize, thick, offX, offY, rootFL, cfg)
            if collapseGlow then
                cd:SetAlpha(0)
                cd:Hide()
            end
        elseif v8Enabled then
            v8 = self:_CreateV8Segments(data, cdAnchor, arcSize, thick, offX, offY, rootFL, cfg)
            if v8 then
                cd:SetAlpha(0)
                cd:Hide()
            end
        end

        --  ── 13) Icône du sort — position configurable ─────────────────────
        local icoSz = math_max(14, math_floor(SIZE * (cfg.castbar_icon_size or 0.42)))
        iconFrame = CreateFrame("Frame", nil, root)
        iconFrame:SetSize(icoSz, icoSz)
        -- rootFL+3 = sous overlayOrbFrame (root+4) qui contient gloss/glassTex/glossTex
        iconFrame:SetFrameLevel(rootFL + 3)
        if data.orb then
            local pos = cfg.castbar_icon_position or "top"
            local iox = (cfg.castbar_icon_offset_x or 0)
            local ioy = (cfg.castbar_icon_offset_y or 0)
            iconFrame:ClearAllPoints()
            if pos == "center" then
                iconFrame:SetPoint("CENTER", data.orb, "CENTER", iox, ioy)
            elseif pos == "bottomright" then
                iconFrame:SetPoint("BOTTOMRIGHT", data.orb, "BOTTOMRIGHT", icoSz * 0.25 + iox, -icoSz * 0.25 + ioy)
            elseif pos == "left" then
                iconFrame:SetPoint("RIGHT", data.orb, "LEFT", -thick * 0.5 - 4 + iox, ioy)
            elseif pos == "right" then
                iconFrame:SetPoint("LEFT", data.orb, "RIGHT", thick * 0.5 + 4 + iox, ioy)
            else  -- top
                iconFrame:SetPoint("BOTTOM", data.orb, "TOP", iox, thick * 0.35 + 4 + ioy)
            end
        end
        iconFrame:SetAlpha(0)

        -- Pas de fond : l'icône native suffit. Mask circulaire si dispo.
        local icoMask = iconFrame:CreateMaskTexture()
        pcall(icoMask.SetTexture, icoMask, MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icoMask:SetAllPoints(iconFrame)

        iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(iconFrame)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pcall(iconTex.AddMaskTexture, iconTex, icoMask)

        -- Bordure circulaire colorée discrète autour de l'icône (couleur cast)
        local icoBorder = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        icoBorder:SetTexture(RADIAL_GLOW)
        icoBorder:SetSize(icoSz + 6, icoSz + 6)
        icoBorder:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        icoBorder:SetBlendMode("ADD")
        icoBorder:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
        icoBorder:SetAlpha(0.0)

        --  ── 14) Textes ─────────────────────────────────────────────────────
        _PlaceCastText(data, castName, castTime, lockTex, cfg, SIZE, thick)

        --  ── 15) Stash références circulaires ──────────────────────────────
        data._cb_circ = {
            preset        = preset,
            v5Track       = v5Track,
            v5Border      = v5Border,
            v6Spark       = v6Spark,
            owRing        = owRing,
            owGlow        = owGlow,
            trackCD       = trackCD,
            cd2           = cd2,
            bevelOut      = bevelOut,
            bevelIn       = bevelIn,
            trail         = trail,
            pin12         = pin12,
            ticks         = ticks,
            segMarks      = segMarks,
            comets        = comets,
            radarTrail    = radarTrail,
            pulseRing     = pulseRing,
            completeRing  = completeRing,
            kickShards    = kickShards,
            icoBorder     = icoBorder,
            v8Segments    = v8 and v8.segments or nil,
            v8Count       = v8 and v8.count or nil,
            v8Frame       = v8 and v8.frame or nil,
            v8ShowTrack   = v8 and v8.showTrack or false,
            v8GlowAlpha   = v8 and v8.glowAlpha or 0.26,
            dottedSegments = dotted and dotted.segments or nil,
            dottedCount    = dotted and dotted.count or nil,
            dottedFrame    = dotted and dotted.frame or nil,
            dottedSize     = dotted and dotted.dotSize or nil,
            dottedRadius   = dotted and dotted.radius or nil,
            dottedShowTrack = dotted and dotted.showTrack or false,
            dottedAlpha    = dotted and dotted.alpha or 0.95,
            dottedGlow     = dotted and dotted.glow or false,
            collapseTex    = collapse and collapse.tex or nil,
            collapseFrame  = collapse and collapse.frame or nil,
            collapseBaseSize = collapse and collapse.baseSize or nil,
            collapseMode   = cfg.castbar_collapse_color_mode or "dynamic",
            collapseStartScale = cfg.castbar_collapse_start_scale or 1.75,
            collapseEndScale = cfg.castbar_collapse_end_scale or 0.72,
            collapseGlow   = collapseGlow,
            collapseGlowShape = cfg.castbar_collapse_glow_shape or "soft",
            collapseGlowColorMode = cfg.castbar_collapse_glow_color_mode or "cast",
            collapseGlowStartScale = cfg.castbar_collapse_glow_start_scale or 1.65,
            collapseGlowEndScale = cfg.castbar_collapse_glow_end_scale or 0.45,
            v8_enabled    = v8Enabled,
            cast_style    = cstyle,
            channel_style = chstyle,
            glow_intensity = glowI,
            segments_count = segN,
            arcRadius     = arcRadius,
        }

    elseif mode == "sprite" then
        -----------------------------------------------------------------------
        --  MODE SPRITE — Anneau animé via sprite sheet 9×8 = 72 frames
        --
        --  Le sprite sheet (castbar_mage_sheet.png, 1152×1024) contient 72 tuiles
        --  128×128 en niveaux de gris.  SetVertexColor() applique la couleur cast.
        --  BlendMode ADD donne l'effet lumineux naturel sur l'orbe.
        --
        --  Couches : rootFL+3 sprite, rootFL+6 icône.
        -----------------------------------------------------------------------
        local cdAnchor = data.orb or root
        local SCOLS, SROWS = SPRITE_COLS, SPRITE_ROWS

        -- ── Sprite frame ─────────────────────────────────────────────────────
        -- Hiérarchie Orb.lua : root+2 orbFrame, root+4 overlayOrbFrame,
        -- root+8 borderOverlayFrame, root+9 nameFrame/ccFrame.
        -- → Sprite à root+10 (au-dessus de tout), orb élevé à root+11
        --   (ses textures masquées circulairement laissent le ring visible).
        -- Le ring dans le sprite source est à r≈90% du frame. On scale le frame
        -- à SIZE*2.2 pour que le ring apparaisse clairement autour de l'orbe.
        local spSize = math_max(arcSize, math_floor(SIZE * 2.2))
        local spFrame = CreateFrame("Frame", nil, root)
        spFrame:SetSize(spSize, spSize)
        spFrame:SetPoint("CENTER", cdAnchor, "CENTER", offX, offY)
        spFrame:SetFrameLevel(rootFL + 10)
        pcall(spFrame.SetFrameStrata, spFrame, "HIGH")
        spFrame:Hide()

        local spTex = spFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        spTex:SetAllPoints(spFrame)
        spTex:SetTexture(CASTBAR_SPRITE_SHEET)
        spTex:SetBlendMode("ADD")
        spTex:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 0.90)
        -- Frame initiale (frame 0 = inner glow uniquement, pas d'arc)
        spTex:SetTexCoord(0, 1/SCOLS, 0, 1/SROWS)

        data._cb_sprite = {
            frame = spFrame,
            tex   = spTex,
            cols  = SCOLS,
            rows  = SROWS,
            total = SPRITE_TOTAL,
            alpha = 0.90,
        }

        -- Elever l'orbe au-dessus du sprite (root+11 > root+10)
        -- Les textures de l'orbe sont masquées circulairement → ring visible autour
        pcall(function()
            if data.orb then data.orb:SetFrameLevel(rootFL + 11) end
        end)

        -- ── Icône du sort (flottante, même style que circular) ───────────────
        local icoSz = math_max(14, math_floor(SIZE * (cfg.castbar_icon_size or 0.42)))
        iconFrame = CreateFrame("Frame", nil, root)
        iconFrame:SetSize(icoSz, icoSz)
        iconFrame:SetFrameLevel(rootFL + 12)  -- au-dessus de l'orbe élevé (root+11)
        if data.orb then
            local pos = cfg.castbar_icon_position or "top"
            local iox = (cfg.castbar_icon_offset_x or 0)
            local ioy = (cfg.castbar_icon_offset_y or 0)
            iconFrame:ClearAllPoints()
            if pos == "center" then
                iconFrame:SetPoint("CENTER", data.orb, "CENTER", iox, ioy)
            elseif pos == "bottomright" then
                iconFrame:SetPoint("BOTTOMRIGHT", data.orb, "BOTTOMRIGHT", icoSz * 0.25 + iox, -icoSz * 0.25 + ioy)
            elseif pos == "left" then
                iconFrame:SetPoint("RIGHT", data.orb, "LEFT", -thick * 0.5 - 4 + iox, ioy)
            elseif pos == "right" then
                iconFrame:SetPoint("LEFT", data.orb, "RIGHT", thick * 0.5 + 4 + iox, ioy)
            else  -- top
                iconFrame:SetPoint("BOTTOM", data.orb, "TOP", iox, thick * 0.35 + 4 + ioy)
            end
        end
        iconFrame:SetAlpha(0)

        local icoMask = iconFrame:CreateMaskTexture()
        pcall(icoMask.SetTexture, icoMask, MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icoMask:SetAllPoints(iconFrame)

        iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(iconFrame)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pcall(iconTex.AddMaskTexture, iconTex, icoMask)

        -- Bordure colorée discrète autour de l'icône
        local icoBorder = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        icoBorder:SetTexture(RADIAL_GLOW)
        icoBorder:SetSize(icoSz + 6, icoSz + 6)
        icoBorder:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        icoBorder:SetBlendMode("ADD")
        icoBorder:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
        icoBorder:SetAlpha(0.0)

        lockTex:SetSize(9, 9)

    elseif mode == "ccb" then
        -----------------------------------------------------------------------
        --  MODE CCB — Circular Castbar Library (Holy/Medium, per-frame PNG)
        --
        --  Tout le travail est délégué à SP.CCB (CastBarCCB.lua).
        --  Ici on crée l'icône flottante et on ajuste le frame-level de l'orbe.
        --
        --  Couches frame-level :
        --   rootFL+10 : mainFrame CCB (Composite + Glow/Highlight/Runes)
        --   rootFL+11 : flashFrame / orbe élevé / iconFrame du sort
        --   rootFL+12 : intFrame (overlay interruption, au-dessus de l'icône)
        --   rootFL+13 : nameFrame (nom, jamais masqué par le CCB)
        -----------------------------------------------------------------------
        SP.CCB:Create(data, cfg, rootFL, SIZE)

        -- ── Icône du sort (même style que circular/sprite) ──────────────────
        local icoSz = math_max(14, math_floor(SIZE * (cfg.castbar_icon_size or 0.42)))
        iconFrame = CreateFrame("Frame", nil, root)
        iconFrame:SetSize(icoSz, icoSz)
        iconFrame:SetFrameLevel(rootFL + 11)  -- même niveau que l'orbe/flash ; intFrame est à +12
        if data.orb then
            local pos = cfg.castbar_icon_position or "top"
            local iox = (cfg.castbar_icon_offset_x or 0)
            local ioy = (cfg.castbar_icon_offset_y or 0)
            iconFrame:ClearAllPoints()
            if pos == "center" then
                iconFrame:SetPoint("CENTER", data.orb, "CENTER", iox, ioy)
            elseif pos == "bottomright" then
                iconFrame:SetPoint("BOTTOMRIGHT", data.orb, "BOTTOMRIGHT", icoSz * 0.25 + iox, -icoSz * 0.25 + ioy)
            elseif pos == "left" then
                iconFrame:SetPoint("RIGHT", data.orb, "LEFT", -thick * 0.5 - 4 + iox, ioy)
            elseif pos == "right" then
                iconFrame:SetPoint("LEFT", data.orb, "RIGHT", thick * 0.5 + 4 + iox, ioy)
            else  -- top
                iconFrame:SetPoint("BOTTOM", data.orb, "TOP", iox, thick * 0.35 + 4 + ioy)
            end
        end
        iconFrame:SetAlpha(0)

        local icoMask2 = iconFrame:CreateMaskTexture()
        pcall(icoMask2.SetTexture, icoMask2, MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icoMask2:SetAllPoints(iconFrame)

        iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(iconFrame)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pcall(iconTex.AddMaskTexture, iconTex, icoMask2)

        local icoBorderCCB = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        icoBorderCCB:SetTexture(RADIAL_GLOW)
        icoBorderCCB:SetSize(icoSz + 6, icoSz + 6)
        icoBorderCCB:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        icoBorderCCB:SetBlendMode("ADD")
        icoBorderCCB:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
        icoBorderCCB:SetAlpha(0.0)

        lockTex:SetSize(9, 9)

    else
        -----------------------------------------------------------------------
        --  MODE CLASSIQUE — Pill bar moderne sous l'orbe
        --
        --  Layout :
        --   [ICO] [████████░░░░░░░░] SPELL NAME    1.5s
        --
        --  Dimensions :
        --   barH      = height du fill
        --   icoSz     = taille icône (carré)
        --   gap       = espacement icône / barre
        --   barW      = largeur de la zone fill seule
        --   totalW    = icoSz + gap + barW
        -----------------------------------------------------------------------
        local barH  = math_max(6, math_min(36, tonumber(cfg.castbar_classic_height) or math.floor(SIZE * 0.18)))
        local icoSz = barH + 4           -- icône légèrement plus haute
        local gap   = 4
        barW        = math_max(40, math_min(320, tonumber(cfg.castbar_classic_width) or arcSize))
        local totalW = icoSz + gap + barW

        -- Position Y : sous l'orbe, gap = thick pixels
        local barOffY = -(SIZE * 0.5 + thick + barH * 0.5 + offY)

        barFrame = CreateFrame("Frame", nil, root)
        barFrame:SetSize(totalW, icoSz)
        -- Ancré sur data.orb si disponible — point de référence fiable pour le placement
        local barAnchor = data.orb or root
        barFrame:SetPoint("CENTER", barAnchor, "CENTER", offX, barOffY)
        barFrame:SetFrameLevel(rootFL + 5)  -- au-dessus des overlays orbe (root+4)
        barFrame:SetAlpha(1)
        barFrame:SetScale(math_max(0.5, math_min(2.0, tonumber(cfg.castbar_classic_scale) or 1)))
        pcall(barFrame.SetFrameStrata, barFrame, "HIGH")
        barFrame:Hide()

        -- ── Icône du sort (gauche) ────────────────────────────────────────
        iconFrame = CreateFrame("Frame", nil, barFrame)
        iconFrame:SetSize(icoSz, icoSz)
        iconFrame:SetPoint("LEFT", barFrame, "LEFT", 0, 0)
        iconFrame:SetFrameLevel(rootFL + 2)
        iconFrame:SetAlpha(0)

        local icoBg = iconFrame:CreateTexture(nil, "BACKGROUND")
        icoBg:SetTexture(WHITE)
        icoBg:SetAllPoints(iconFrame)
        icoBg:SetVertexColor(0.04, 0.04, 0.09, 0.92)

        local icoMask = iconFrame:CreateMaskTexture()
        icoMask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icoMask:SetAllPoints(iconFrame)
        icoBg:AddMaskTexture(icoMask)

        iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        iconTex:AddMaskTexture(icoMask)

        -- Fin de barre colorée très fine (bordure icône)
        local icoBorder = iconFrame:CreateTexture(nil, "OVERLAY")
        icoBorder:SetTexture(WHITE)
        icoBorder:SetAllPoints(iconFrame)
        icoBorder:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 0.55)
        icoBorder:AddMaskTexture(icoMask)

        -- ── Zone barre (à droite de l'icône) ─────────────────────────────
        local barZone = CreateFrame("Frame", nil, barFrame)
        barZone:SetSize(barW, barH)
        barZone:SetPoint("LEFT", iconFrame, "RIGHT", gap, 0)
        barZone:SetFrameLevel(rootFL + 1)

        -- Fond sombre de la barre
        local barBg = barZone:CreateTexture(nil, "BACKGROUND")
        barBg:SetTexture(WHITE)
        barBg:SetAllPoints(barZone)
        barBg:SetVertexColor(_ColorFromCfg(cfg, "castbar_classic_bg", 0.04, 0.04, 0.07, 0.88))

        -- Bordures haut/bas (1 pixel)
        barBorderTop = barZone:CreateTexture(nil, "OVERLAY", nil, 1)
        barBorderTop:SetTexture(WHITE)
        barBorderTop:SetPoint("TOPLEFT",  barZone, "TOPLEFT",  0, 0)
        barBorderTop:SetPoint("TOPRIGHT", barZone, "TOPRIGHT", 0, 0)
        barBorderTop:SetHeight(1)
        local br, bg, bb = _ColorFromCfg(cfg, "castbar_classic_border", COLOR_CAST.r * 0.7, COLOR_CAST.g * 0.7, COLOR_CAST.b * 0.7, 0.7)
        local borderAlpha = cfg.castbar_classic_border ~= false and 0.7 or 0
        barBorderTop:SetVertexColor(br, bg, bb, borderAlpha)

        barBorderBot = barZone:CreateTexture(nil, "OVERLAY", nil, 1)
        barBorderBot:SetTexture(WHITE)
        barBorderBot:SetPoint("BOTTOMLEFT",  barZone, "BOTTOMLEFT",  0, 0)
        barBorderBot:SetPoint("BOTTOMRIGHT", barZone, "BOTTOMRIGHT", 0, 0)
        barBorderBot:SetHeight(1)
        barBorderBot:SetVertexColor(br, bg, bb, borderAlpha)

        -- Fill coloré (ARTWORK, ancré LEFT, largeur dynamique)
        barFill = barZone:CreateTexture(nil, "ARTWORK")
        barFill:SetTexture(_CastBarTexture(cfg))
        barFill:SetPoint("LEFT", barZone, "LEFT", 0, 0)
        barFill:SetHeight(barH)
        barFill:SetWidth(barW)
        pcall(function()
            local fr, fg, fb = _ColorFromCfg(cfg, "castbar_classic_fill", COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1)
            barFill:SetGradientAlpha("HORIZONTAL",
                fr * 0.55, fg * 0.55, fb * 0.55, 1.0,
                fr,        fg,        fb,        1.0)
        end)

        -- Glow sur le bord droit du fill (suit la progression)
        barGlowL = barZone:CreateTexture(nil, "OVERLAY", nil, 2)
        barGlowL:SetTexture(RADIAL_GLOW)
        barGlowL:SetSize(barH * 2.2, barH * 2.2)
        barGlowL:SetPoint("LEFT", barZone, "LEFT", 0, 0)  -- repositionné dans Tick
        barGlowL:SetBlendMode("ADD")
        barGlowL:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
        barGlowL:SetAlpha(0)

        -- Shinmer / gloss léger sur le dessus du fill
        local barShimmer = barZone:CreateTexture(nil, "OVERLAY", nil, 3)
        barShimmer:SetTexture(WHITE)
        barShimmer:SetPoint("TOPLEFT",  barZone, "TOPLEFT",  0, 0)
        barShimmer:SetPoint("TOPRIGHT", barZone, "TOPRIGHT", 0, 0)
        barShimmer:SetHeight(math_max(2, math.floor(barH * 0.35)))
        barShimmer:SetVertexColor(1, 1, 1, 0.09)

        lockTex:SetSize(8, 8)
    end

    _PlaceCastText(data, castName, castTime, lockTex, cfg, SIZE, thick)

    --------------------------------------------------------------------------
    --  Table d'état
    --------------------------------------------------------------------------
    data.castbar = {
        -- Circulaire
        cd            = cd,
        headTex       = headTex,
        trailTex      = trailTex,
        glowFrame     = glowFrame,
        glowTex       = glowTex,
        -- Classique
        barFrame      = barFrame,
        barFill       = barFill,
        barW          = barW,
        barGlowL      = barGlowL,
        barBorderTop  = barBorderTop,
        barBorderBot  = barBorderBot,
        barTexture     = cfg.castbar_texture or "white",
        classicWidth   = cfg.castbar_classic_width or 120,
        classicHeight  = cfg.castbar_classic_height or 12,
        classicScale   = cfg.castbar_classic_scale or 1,
        textPosition   = cfg.castbar_text_position or "bottom",
        textOffsetX    = cfg.castbar_text_offset_x or 0,
        textOffsetY    = cfg.castbar_text_offset_y or 0,
        textFont       = cfg.castbar_text_font,
        textFontSize   = nameFS,
        -- Commun
        iconFrame     = iconFrame,
        iconTex       = iconTex,
        flashTex      = flashTex,
        castName      = castName,
        castTime      = castTime,
        lockTex       = lockTex,
        interruptMark = interruptMark,
        arcSize       = arcSize,
        arcRadius     = arcRadius,
        active        = false,
        channeling    = false,
        startTime     = 0,
        endTime       = 0,
        duration      = 0,
        interruptible = true,
        isImmune      = false,
        flashStart    = 0,
        glowPhase     = 0,
        color         = COLOR_CAST,
        watcher       = nil,
        _createdMode  = mode,   -- mode utilisé à la création (pour détecter changement via SoftUpdate)
    }

    --------------------------------------------------------------------------
    --  Watcher RegisterUnitEvent
    --------------------------------------------------------------------------
    local unitToken = data.unit
    if unitToken then
        local watcherParent = UIParent
        if data.plate and data.plate.UnitFrame then
            watcherParent = data.plate.UnitFrame
        elseif data.plate then
            watcherParent = data.plate
        end

        local watcher = CreateFrame("Frame", nil, watcherParent)
        watcher:SetSize(1, 1)

        watcher:SetScript("OnEvent", function(self, event, evUnit, ...)
            local d = data
            if not d or not d.castbar then return end

            -- Accepte les events du token nameplate ET du token "player"
            -- (la plaque du joueur reçoit les events cast sous "player", pas "nameplateN")
            local function isOurUnit(u)
                if u == unitToken then return true end
                if u == "player" then
                    local ok2, same = pcall(UnitIsUnit, unitToken, "player")
                    return ok2 and same
                end
                return false
            end

            local eventCastGUID, eventSpellId = _EventCastArgs(...)

            if event == "UNIT_SPELLCAST_START" then
                if not isOurUnit(evUnit) then return end
                local name, _, _, sMS, eMS, _, _, notInt, spellId = UnitCastingInfo(evUnit)
                spellId = _PreferSpellID(eventSpellId, spellId)
                if not SafeNotNil(name) then
                    if SafeNotNil(spellId) and C_Spell and C_Spell.GetSpellInfo then
                        local okSI, si = pcall(C_Spell.GetSpellInfo, spellId)
                        if okSI and type(si) == "table" and SafeNotNil(si.name) then
                            local now2 = GetTime()
                            local okCastMs, castMs = pcall(function()
                                local ms = tonumber(si.castTime)
                                if ms and ms > 0 then return ms end
                                return 3000
                            end)
                            castMs = okCastMs and castMs or 3000
                            name  = si.name
                            sMS   = now2 * 1000
                            eMS   = sMS + castMs
                            notInt = false
                        end
                    end
                end
                if SafeNotNil(name) or SafeNotNil(spellId) then
                    local ico = GetSpellIcon(spellId)
                    SP.CastBar:_ApplyCast(d, name, sMS, eMS, notInt, false, ico, spellId, eventCastGUID)
                end

            elseif event == "UNIT_SPELLCAST_DELAYED" then
                if not isOurUnit(evUnit) then return end
                if not _CastGUIDMatches(d.castbar, eventCastGUID) then return end
                local _, _, _, sMS, eMS, _, _, notInt = UnitCastingInfo(evUnit)
                SP.CastBar:_RefreshCastTiming(d, sMS, eMS, notInt, false)

            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                if not isOurUnit(evUnit) then return end
                local name, _, _, sMS, eMS, _, notInt, spellId = UnitChannelInfo(evUnit)
                spellId = _PreferSpellID(eventSpellId, spellId)
                if not SafeNotNil(name) then
                    if SafeNotNil(spellId) and C_Spell and C_Spell.GetSpellInfo then
                        local okSI, si = pcall(C_Spell.GetSpellInfo, spellId)
                        if okSI and type(si) == "table" and SafeNotNil(si.name) then
                            local now2 = GetTime()
                            local okCastMs, castMs = pcall(function()
                                local ms = tonumber(si.castTime)
                                if ms and ms > 0 then return ms end
                                return 3000
                            end)
                            castMs = okCastMs and castMs or 3000
                            name  = si.name
                            sMS   = now2 * 1000
                            eMS   = sMS + castMs
                            notInt = false
                        end
                    end
                end
                if SafeNotNil(name) or SafeNotNil(spellId) then
                    local ico = GetSpellIcon(spellId)
                    SP.CastBar:_ApplyCast(d, name, sMS, eMS, notInt, true, ico, spellId, eventCastGUID)
                end

            elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
                if not isOurUnit(evUnit) then return end
                if not _CastGUIDMatches(d.castbar, eventCastGUID) then return end
                local _, _, _, sMS, eMS, _, notInt = UnitChannelInfo(evUnit)
                SP.CastBar:_RefreshCastTiming(d, sMS, eMS, notInt, true)

            elseif event == "UNIT_SPELLCAST_STOP"
                or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                if not isOurUnit(evUnit) then return end
                if not _CastGUIDMatches(d.castbar, eventCastGUID) then return end
                SP.CastBar:StopCast(d, false)

            elseif event == "UNIT_SPELLCAST_INTERRUPTED"
                or event == "UNIT_SPELLCAST_FAILED" then
                if not isOurUnit(evUnit) then return end
                if not _CastGUIDMatches(d.castbar, eventCastGUID) then return end
                SP.CastBar:StopCast(d, true)

            elseif event == "PLAYER_ENTERING_WORLD" then
                if not unitToken then return end
                local n1, _, _, s1, e1, _, _, ni1, sp1 = UnitCastingInfo(unitToken)
                if SafeNotNil(n1) then
                    SP.CastBar:_ApplyCast(d, n1, s1, e1, ni1, false, GetSpellIcon(sp1), sp1)
                    return
                end
                local n2, _, _, s2, e2, _, ni2, sp2 = UnitChannelInfo(unitToken)
                if SafeNotNil(n2) then
                    SP.CastBar:_ApplyCast(d, n2, s2, e2, ni2, true, GetSpellIcon(sp2), sp2)
                    return
                end
                SP.CastBar:StopCast(d, false)
            end
        end)

        pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
        -- Vérifie si ce token correspond au joueur → enregistre aussi pour "player"
        -- (UNIT_SPELLCAST_START pour le joueur fire avec unit="player", pas "nameplateN")
        local isPlayerUnit = false
        pcall(function() isPlayerUnit = UnitIsUnit(unitToken, "player") end)
        for _, ev in ipairs(CAST_UNIT_EVENTS) do
            local ok, err = pcall(watcher.RegisterUnitEvent, watcher, ev, unitToken)
            if not ok then
                SP:Debug(string.format("[CastBar] RegisterUnitEvent échoué (%s %s): %s", ev, tostring(unitToken), tostring(err)))
                pcall(watcher.RegisterEvent, watcher, ev)
            end
            -- Pour la plaque du joueur : aussi "player" car les events cast du joueur
            -- utilisent toujours ce token, jamais le token nameplate
            if isPlayerUnit then
                pcall(watcher.RegisterUnitEvent, watcher, ev, "player")
            end
        end

        data.castbar.watcher = watcher
        SP:Debug(string.format("[CastBar] watcher créé pour %s [%s]", tostring(unitToken), tostring(data.unitType or "?")))
    end

    return data.castbar
end

-------------------------------------------------------------------------------
--  StartCast — cast déjà en cours lors de l'apparition de la plaque
-------------------------------------------------------------------------------
function SP.CastBar:StartCast(data, unit, isChannel)
    local cb = data.castbar
    if not cb then
        SP:Debug("[CastBar] StartCast NIL castbar " .. tostring(unit))
        return
    end

    local name, _, _, sMS, eMS, _, notInt, spellId
    if isChannel then
        name, _, _, sMS, eMS, _, notInt, spellId = UnitChannelInfo(unit)
    else
        name, _, _, sMS, eMS, _, _, notInt, spellId = UnitCastingInfo(unit)
    end

    if not SafeNotNil(name) and not isChannel then
        name, _, _, sMS, eMS, _, notInt, spellId = UnitChannelInfo(unit)
        isChannel = SafeNotNil(name) and true or false
    end

    if not SafeNotNil(name) then
        SP:Debug(string.format("[CastBar] StartCast nil pour %s %s", tostring(unit), isChannel and "[CH]" or "[CAST]"))
        return
    end

    SP.CastBar:_ApplyCast(data, name, sMS, eMS, notInt, isChannel, GetSpellIcon(spellId), spellId)
end

-------------------------------------------------------------------------------
--  StopCast
-------------------------------------------------------------------------------
function SP.CastBar:StopCast(data, interrupted)
    local cb = data.castbar
    if not cb then return end
    _RestoreNameReplacement(data)
    if not cb.active then return end
    cb.active     = false
    cb.channeling = false
    cb._completeFlashed = false
    cb.castGUID = nil
    cb.spellId = nil
    cb.castDisplayName = nil
    cb.castDisplayText = nil
    cb.castDisplaySource = nil
    cb._activePollTimer = 0
    cb._activePollLast = nil
    cb._runtimeMissingSince = nil
    cb._runtimeMissingCount = 0

    if cb.cd        then cb.cd:SetCooldown(0, 0) ; cb.cd:Hide() end
    if cb.headTex   then cb.headTex:SetAlpha(0)  end
    if cb.trailTex  then cb.trailTex:SetAlpha(0) end
    if cb.barFrame  then cb.barFrame:Hide()      end
    if cb.iconFrame then cb.iconFrame:SetAlpha(0) end
    if cb.barGlowL  then cb.barGlowL:SetAlpha(0) end

    -- ── Mode focus : restaurer HP/ilvl/castTime après fin du cast ─────────────
    if cb._focusModeActive then
        cb._focusModeActive = false
        -- levelText/hpSubText : SoftUpdate recalculera la visibilité correcte
        -- On se contente de re-montrer si la config le demandait
        local rcfg = SP:GetCfg(data.unitType) or {}
        if rcfg.showLevelOrHP and data.levelText then data.levelText:Show() end
        -- hpSubText : géré par SoftUpdate, pas besoin de forcer Show()
        -- castTime : simplement masquer (cast terminé, durée n'a plus de sens)
        if cb.castTime then cb.castTime:Hide() end
    end
    -- Sprite mode
    local spr = data._cb_sprite
    if spr then spr.frame:Hide() end
    -- CCB mode
    if data._cb_ccb then SP.CCB:Stop(data, interrupted) end

    -- Cleanup circular extras
    local circ = data._cb_circ
    if circ then
        if circ.trackCD    then circ.trackCD:Hide() end
        if circ.cd2        then circ.cd2:Hide() end
        if circ.trail      then for i = 1, #circ.trail do circ.trail[i]:SetAlpha(0) end end
        if circ.comets     then for i = 1, #circ.comets do circ.comets[i]:SetAlpha(0) end end
        if circ.radarTrail then for i = 1, #circ.radarTrail do circ.radarTrail[i]:SetAlpha(0) end end
        if circ.pulseRing  then circ.pulseRing:SetAlpha(0) end
        if circ.pin12      then circ.pin12:SetAlpha(0) end
        if circ.icoBorder  then circ.icoBorder:SetAlpha(0) end
        if circ.v5Border   then circ.v5Border:SetAlpha(0) end
        if circ.v6Spark    then circ.v6Spark:SetAlpha(0) end
        if circ.owGlow     then circ.owGlow:SetAlpha(0) end
        if circ.v8Segments then _V8ResetSegments(circ, false) end
        if circ.dottedSegments then _ResetDotted(circ, false) end
        if circ.collapseTex then
            local ccfg = SP:GetCfg(data.unitType) or {}
            if interrupted and ccfg.castbar_collapse_interrupt_flash ~= false then
                circ.collapseInterruptStart = GetTime()
                _UpdateCollapse(circ, circ.collapseProgress or 0, ccfg, circ.collapseInterruptStart, true)
            else
                _ResetCollapse(circ)
            end
        end
        if circ.collapseGlow then
            local gcfg = SP:GetCfg(data.unitType) or {}
            if interrupted and gcfg.castbar_collapse_glow_interrupt_flash ~= false then
                circ.collapseGlowInterruptStart = GetTime()
                _UpdateCollapseGlow(circ, circ.collapseGlowProgress or 0, gcfg, circ.collapseGlowInterruptStart, true, cb.color or COLOR_CAST)
            else
                _ResetCollapseGlow(circ)
            end
        end
        -- v5Track / owRing restent visibles (track de fond constant)
    end

    cb.lockTex:SetAlpha(0)

    local cfg = SP:GetCfg(data.unitType) or {}
    local cBroken = _rgb(cfg.castbar_color_broken, COLOR_BROKEN)
    local cFinish = _rgb(cfg.castbar_color_finish, COLOR_FINISH)
    if interrupted then
        cb.flashTex:SetVertexColor(cBroken.r, cBroken.g, cBroken.b)
        _ShowInterruptMark(data, cfg, cBroken)
    else
        cb.flashTex:SetVertexColor(cFinish.r, cFinish.g, cFinish.b)
        _ResetInterruptMark(cb)
    end
    local suppressFlash = circ and circ.collapseTex and (
        (interrupted and cfg.castbar_collapse_interrupt_flash ~= false)
        or ((not interrupted) and cfg.castbar_collapse_complete_flash == false)
    )
    if not suppressFlash and circ and circ.collapseGlow then
        suppressFlash = (interrupted and cfg.castbar_collapse_glow_interrupt_flash ~= false)
            or ((not interrupted) and cfg.castbar_collapse_glow_complete_flash == false)
    end
    cb.flashTex:SetAlpha(suppressFlash and 0 or 0.80)
    cb.flashStart = GetTime()

    -- Kick FX (shards rouges) sur interrupt
    if interrupted and circ and circ.kickShards then
        for i = 1, #circ.kickShards do
            circ.kickShards[i]:SetVertexColor(cBroken.r, cBroken.g, cBroken.b, 1)
            circ.kickShards[i]:SetAlpha(0.95)
        end
        cb._kickFXStart = GetTime()
    end

    -- Anneau de complétion sur succès anticipé
    if (not interrupted) and circ and circ.completeRing and cb.duration > 0.2
        and not (circ.collapseTex and cfg.castbar_collapse_complete_flash == false)
        and not (circ.collapseGlow and cfg.castbar_collapse_glow_complete_flash == false) then
        circ.completeRing:SetVertexColor(cFinish.r, cFinish.g, cFinish.b)
        circ.completeRing:SetAlpha(0.80)
    end
end

-------------------------------------------------------------------------------
--  TestCast
-------------------------------------------------------------------------------
function SP.CastBar:TestCast(data, duration)
    if not data.castbar then
        local ok = pcall(SP.CastBar.Create, SP.CastBar, data)
        if not (ok and data.castbar) then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFFF4444[SP-CB]|r TestCast: Create échoué " .. tostring(data.unit))
            return false
        end
    end
    local cb  = data.castbar
    local dur = duration or 5.0
    local now = GetTime()

    cb.active        = true
    cb.channeling    = false
    cb.startTime     = now
    cb.endTime       = now + dur
    cb.duration      = dur
    cb.interruptible = true
    cb.isImmune      = false
    cb.color         = COLOR_CAST
    cb.flashStart    = 0
    cb.glowPhase     = 0

    if cb.cd then
        cb.cd:SetSwipeColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1.0)
        cb.cd:SetReverse(true)
        cb.cd:SetCooldown(now, dur)
        if data._cb_circ and (data._cb_circ.v8Segments or data._cb_circ.dottedSegments or data._cb_circ.collapseTex or data._cb_circ.collapseGlow) then
            cb.cd:SetAlpha(0)
            cb.cd:Hide()
        else
            cb.cd:SetAlpha(1)
            cb.cd:Show()
        end
    end
    if data._cb_circ and data._cb_circ.v8Segments then
        _V8ResetSegments(data._cb_circ)
        _V8ColorSegments(data._cb_circ, COLOR_CAST)
    end
    if data._cb_circ and data._cb_circ.dottedSegments then
        _ResetDotted(data._cb_circ)
        _ColorDotted(data._cb_circ, COLOR_CAST)
    end
    if data._cb_circ and data._cb_circ.collapseTex then
        _ResetCollapse(data._cb_circ)
        _UpdateCollapse(data._cb_circ, 0, SP:GetCfg(data.unitType) or {}, now, false)
    end
    if data._cb_circ and data._cb_circ.collapseGlow then
        _ResetCollapseGlow(data._cb_circ)
        _UpdateCollapseGlow(data._cb_circ, 0, SP:GetCfg(data.unitType) or {}, now, false, COLOR_CAST)
    end
    if cb.glowTex then
        cb.glowTex:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b)
        cb.glowTex:SetAlpha(0.35)
    end
    if cb.barFill then
        pcall(function()
            cb.barFill:SetGradientAlpha("HORIZONTAL",
                COLOR_CAST.r * 0.55, COLOR_CAST.g * 0.55, COLOR_CAST.b * 0.55, 1.0,
                COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b, 1.0)
        end)
        cb.barFill:SetWidth(1)
    end
    if cb.barBorderTop then
        cb.barBorderTop:SetVertexColor(COLOR_CAST.r * 0.7, COLOR_CAST.g * 0.7, COLOR_CAST.b * 0.7, 0.7)
        cb.barBorderBot:SetVertexColor(COLOR_CAST.r * 0.7, COLOR_CAST.g * 0.7, COLOR_CAST.b * 0.7, 0.7)
    end
    if cb.barGlowL then cb.barGlowL:SetVertexColor(COLOR_CAST.r, COLOR_CAST.g, COLOR_CAST.b) end
    if cb.barFrame then cb.barFrame:Show() end
    if cb.iconFrame then
        -- Icône de test : sort de feu générique
        if cb.iconTex then pcall(cb.iconTex.SetTexture, cb.iconTex, 135821) end
        cb.iconFrame:SetAlpha(1)
    end

    local tcfg = SP:GetCfg(data.unitType) or {}
    if tcfg.castbar_text_mode == "replace_name" and tcfg.castbar_showName ~= false then
        _ApplyNameReplacement(data, "[ TEST CAST ]", tcfg, now)
        cb.castName:Hide()
    else
        _RestoreNameReplacement(data)
        cb.castName:SetText("[ TEST CAST ]")
        cb.castName:SetTextColor(1, 0.88, 0.45, 1)
        cb.castName:Show()
    end
    cb.castTime:SetText(string.format("%.1fs", dur))
    cb.castTime:Show()
    cb.flashTex:SetAlpha(0)
    cb.lockTex:SetAlpha(0)
    SP:Debug(string.format("[CastBar] TestCast %s arc=%d", tostring(data.unit or "preview"), cb.arcSize))
    return true
end

-------------------------------------------------------------------------------
--  TestChannel
-------------------------------------------------------------------------------
function SP.CastBar:TestChannel(data, duration)
    if not data.castbar then
        local ok = pcall(SP.CastBar.Create, SP.CastBar, data)
        if not (ok and data.castbar) then return false end
    end
    local cb  = data.castbar
    local dur = duration or 5.0
    local now = GetTime()

    cb.active        = true
    cb.channeling    = true
    cb.startTime     = now
    cb.endTime       = now + dur
    cb.duration      = dur
    cb.interruptible = true
    cb.isImmune      = false
    cb.color         = COLOR_CHANNEL
    cb.flashStart    = 0
    cb.glowPhase     = 0

    if cb.cd then
        cb.cd:SetSwipeColor(COLOR_CHANNEL.r, COLOR_CHANNEL.g, COLOR_CHANNEL.b, 1.0)
        cb.cd:SetReverse(false)
        cb.cd:SetCooldown(now, dur)
        if data._cb_circ and (data._cb_circ.v8Segments or data._cb_circ.dottedSegments or data._cb_circ.collapseTex or data._cb_circ.collapseGlow) then
            cb.cd:SetAlpha(0)
            cb.cd:Hide()
        else
            cb.cd:SetAlpha(1)
            cb.cd:Show()
        end
    end
    if data._cb_circ and data._cb_circ.v8Segments then
        _V8ResetSegments(data._cb_circ)
        _V8ColorSegments(data._cb_circ, COLOR_CHANNEL)
    end
    if data._cb_circ and data._cb_circ.dottedSegments then
        _ResetDotted(data._cb_circ)
        _ColorDotted(data._cb_circ, COLOR_CHANNEL)
    end
    if data._cb_circ and data._cb_circ.collapseTex then
        _ResetCollapse(data._cb_circ)
        _UpdateCollapse(data._cb_circ, 0, SP:GetCfg(data.unitType) or {}, now, false)
    end
    if data._cb_circ and data._cb_circ.collapseGlow then
        _ResetCollapseGlow(data._cb_circ)
        _UpdateCollapseGlow(data._cb_circ, 0, SP:GetCfg(data.unitType) or {}, now, false, COLOR_CHANNEL)
    end
    if cb.glowTex then
        cb.glowTex:SetVertexColor(COLOR_CHANNEL.r, COLOR_CHANNEL.g, COLOR_CHANNEL.b)
        cb.glowTex:SetAlpha(0.28)
    end
    if cb.barFill then
        pcall(function()
            cb.barFill:SetGradientAlpha("HORIZONTAL",
                COLOR_CHANNEL.r * 0.55, COLOR_CHANNEL.g * 0.55, COLOR_CHANNEL.b * 0.55, 1.0,
                COLOR_CHANNEL.r, COLOR_CHANNEL.g, COLOR_CHANNEL.b, 1.0)
        end)
        cb.barFill:SetWidth(cb.barW or 1)
    end
    if cb.barBorderTop then
        cb.barBorderTop:SetVertexColor(COLOR_CHANNEL.r * 0.7, COLOR_CHANNEL.g * 0.7, COLOR_CHANNEL.b * 0.7, 0.7)
        cb.barBorderBot:SetVertexColor(COLOR_CHANNEL.r * 0.7, COLOR_CHANNEL.g * 0.7, COLOR_CHANNEL.b * 0.7, 0.7)
    end
    if cb.barGlowL then cb.barGlowL:SetVertexColor(COLOR_CHANNEL.r, COLOR_CHANNEL.g, COLOR_CHANNEL.b) end
    if cb.barFrame then cb.barFrame:Show() end
    if cb.iconFrame then
        if cb.iconTex then pcall(cb.iconTex.SetTexture, cb.iconTex, 135821) end
        cb.iconFrame:SetAlpha(1)
    end

    local tcfg = SP:GetCfg(data.unitType) or {}
    if tcfg.castbar_text_mode == "replace_name" and tcfg.castbar_showName ~= false then
        _ApplyNameReplacement(data, "[ CANAL TEST ]", tcfg, now)
        cb.castName:Hide()
    else
        _RestoreNameReplacement(data)
        cb.castName:SetText("[ CANAL TEST ]")
        cb.castName:SetTextColor(COLOR_CHANNEL.r, COLOR_CHANNEL.g, COLOR_CHANNEL.b, 1)
        cb.castName:Show()
    end
    cb.castTime:SetText(string.format("%.1fs", dur))
    cb.castTime:Show()
    cb.flashTex:SetAlpha(0)
    cb.lockTex:SetAlpha(0)
    return true
end

-------------------------------------------------------------------------------
--  Tick (~60 FPS)
-------------------------------------------------------------------------------
function SP.CastBar:Tick(data, now)
    local cb = data.castbar
    if not cb then return end

    -- Flash fin/interruption
    if cb.flashStart > 0 then
        local a = math_max(0, 0.80 - (now - cb.flashStart) * 2.0)
        cb.flashTex:SetAlpha(a)
        if a <= 0 then cb.flashStart = 0 end
    end
    _TickInterruptMark(cb, now)

    -- Kick FX shards : explosion radiale + fade-out 0.6s
    local circ_t = data._cb_circ
    if cb._kickFXStart and circ_t and circ_t.kickShards and cb.cd then
        local kT = now - cb._kickFXStart
        if kT < 0.6 then
            local a = math_max(0, 0.95 - kT * 1.6)
            local pushOff = kT * 18
            local r = cb.arcRadius
            for i = 1, #circ_t.kickShards do
                local ang = (i / #circ_t.kickShards) * 2 * math_pi
                local px = math_sin(ang) * (r + pushOff + 4)
                local py = math_cos(ang) * (r + pushOff + 4)
                circ_t.kickShards[i]:ClearAllPoints()
                circ_t.kickShards[i]:SetPoint("CENTER", cb.cd, "CENTER", px, py)
                circ_t.kickShards[i]:SetAlpha(a)
            end
        else
            for i = 1, #circ_t.kickShards do circ_t.kickShards[i]:SetAlpha(0) end
            cb._kickFXStart = nil
        end
    end

    -- Complete ring fade-out hors progression (cas StopCast naturel)
    if circ_t and circ_t.completeRing and (not cb.active) then
        local a = circ_t.completeRing:GetAlpha()
        if a > 0 then circ_t.completeRing:SetAlpha(math_max(0, a - 0.04)) end
    end
    if circ_t and circ_t.collapseTex and circ_t.collapseInterruptStart and (not cb.active) then
        local cfg = SP:GetCfg(data.unitType) or {}
        local elapsed = now - circ_t.collapseInterruptStart
        if elapsed < 0.45 then
            _UpdateCollapse(circ_t, circ_t.collapseProgress or 0, cfg, now, true)
        else
            _ResetCollapse(circ_t)
        end
    end

    if circ_t and circ_t.collapseGlow and circ_t.collapseGlowInterruptStart and (not cb.active) then
        local cfg = SP:GetCfg(data.unitType) or {}
        local elapsed = now - circ_t.collapseGlowInterruptStart
        if elapsed < 0.45 then
            _UpdateCollapseGlow(circ_t, circ_t.collapseGlowProgress or 0, cfg, now, true, cb.color or COLOR_CAST)
        else
            _ResetCollapseGlow(circ_t)
        end
    end

    if not cb.active then
        _RestoreNameReplacement(data)
        -- Polling fallback (0.20 s) — filet de sécurité si RegisterUnitEvent ne livre pas
        local dt = now - (cb._pollLast or now)
        cb._pollLast  = now
        cb._pollTimer = (cb._pollTimer or 0) + dt
        if cb._pollTimer >= 0.20 then
            cb._pollTimer = 0
            local unit = data.unit
            if unit then
                local found = false
                pcall(function()
                    local n, _, _, sMS, eMS, _, _, notInt, spID = UnitCastingInfo(unit)
                    if SafeNotNil(n) then
                        found = true
                        SP.CastBar:_ApplyCast(data, n, sMS, eMS, notInt, false, GetSpellIcon(spID), spID)
                    end
                end)
                if not found then
                    pcall(function()
                        local n, _, _, sMS, eMS, _, notInt, spID = UnitChannelInfo(unit)
                        if SafeNotNil(n) then
                            SP.CastBar:_ApplyCast(data, n, sMS, eMS, notInt, true, GetSpellIcon(spID), spID)
                        end
                    end)
                end
            end
        end

        -- Fade out glow circulaire
        if cb.glowTex then
            local gA = cb.glowTex:GetAlpha()
            if gA > 0 then cb.glowTex:SetAlpha(math_max(0, gA - 0.025)) end
            if gA <= 0 and cb.flashStart == 0 then
                cb.castName:Hide()
                cb.castTime:Hide()
            end
        else
            if cb.flashStart == 0 then
                cb.castName:Hide()
                cb.castTime:Hide()
            end
        end
        -- CCB : continuer le fade flash/interrupt même cast inactif
        if data._cb_ccb then
            local ccb_i = data._cb_ccb
            if ccb_i.flashStart > 0 or ccb_i.intStart > 0 then
                SP.CCB:Tick(data, 0, false, now)
            end
        end
        return
    end

    -- Temps restant
    local cfg = SP:GetCfg(data.unitType) or {}
    _MaintainNameReplacement(data, cfg, now)
    if cfg and cfg.castbar_interrupt_fallback ~= false and data.unit then
        cb._activePollTimer = (cb._activePollTimer or 0) + (now - (cb._activePollLast or now))
        cb._activePollLast = now
        if cb._activePollTimer >= 0.10 then
            cb._activePollTimer = 0
            if not _RuntimeCastStillExists(data, cb) then
                cb._runtimeMissingCount = (cb._runtimeMissingCount or 0) + 1
                cb._runtimeMissingSince = cb._runtimeMissingSince or now
                local grace = tonumber(cfg.castbar_interrupt_fallback_grace) or 0.12
                if grace < 0.02 then grace = 0.02 elseif grace > 0.35 then grace = 0.35 end
                local stableMissing = cb._runtimeMissingCount >= 3 and (now - cb._runtimeMissingSince) >= 0.25
                if stableMissing and now < ((cb.endTime or now) - grace) then
                    -- A missing runtime cast is not proof of an interrupt in Midnight.
                    -- Stop cleanly, but reserve the red interrupt visuals for explicit
                    -- INTERRUPTED/FAILED events to avoid false red crosses on normal casts.
                    SP.CastBar:StopCast(data, false)
                    return
                end
            else
                cb._runtimeMissingSince = nil
                cb._runtimeMissingCount = 0
            end
        end
    end
    if cfg.castbar_showTime ~= false then
        cb.castTime:SetText(string.format("%.1fs", math_max(0, cb.endTime - now)))
        cb.castTime:Show()
    end

    local progress = math_min(1.0, (now - cb.startTime) / cb.duration)

    -- ── Mode sprite ─────────────────────────────────────────────────────────
    local spr = data._cb_sprite
    if spr then
        _UpdateSprite(spr, progress, cb.color or COLOR_CAST, cb.channeling)
    end

    -- ── Mode CCB ────────────────────────────────────────────────────────────
    if data._cb_ccb then
        SP.CCB:Tick(data, progress, cb.channeling, now)
    end

    -- ── Circulaire : head + trail multi-segments ────────────────────────────
    local circ = data._cb_circ
    if circ and circ.v8Segments then
        _V8UpdateSegments(circ, progress, cb.color or COLOR_CAST, cb.channeling, now)
    end
    if circ and circ.dottedSegments then
        _UpdateDotted(circ, progress, cb.color or COLOR_CAST, cb.channeling, now)
    end
    if circ and circ.collapseTex then
        local collapseProgress = cb.channeling and (1.0 - progress) or progress
        _UpdateCollapse(circ, collapseProgress, cfg, now, false)
    end
    if circ and circ.collapseGlow then
        _UpdateCollapseGlow(circ, progress, cfg, now, false, cb.color or COLOR_CAST)
    end
    if cb.cd and cb.headTex and progress >= 0 and not cb.channeling then
        local r   = cb.arcRadius
        local ang = 2 * math_pi * progress
        local hx  = r * math_sin(ang)
        local hy  = r * math_cos(ang)
        cb.headTex:ClearAllPoints()
        cb.headTex:SetPoint("CENTER", cb.cd, "CENTER", hx, hy)
        cb.headTex:SetAlpha(0.85)

        if circ and circ.trail then
            local delays = { 0.030, 0.060, 0.090 }
            local alphas = { 0.55, 0.32, 0.16 }
            for i = 1, #circ.trail do
                local ta = 2 * math_pi * math_max(0, progress - (delays[i] or 0.05))
                circ.trail[i]:ClearAllPoints()
                circ.trail[i]:SetPoint("CENTER", cb.cd, "CENTER", r * math_sin(ta), r * math_cos(ta))
                circ.trail[i]:SetAlpha(alphas[i] or 0.2)
            end
        end

        if circ and circ.ticks then
            local cI = #circ.ticks
            for i = 1, cI do
                local tProg = (i - 1) / cI
                if tProg <= progress then
                    circ.ticks[i]:SetVertexColor(cb.color.r, cb.color.g, cb.color.b, 0.95)
                end
            end
        end

        if circ and circ.segMarks and circ.cast_style == "segments" then
            local sN = #circ.segMarks
            for i = 1, sN do
                local sProg = (i - 1) / sN
                if sProg > progress then
                    circ.segMarks[i]:SetVertexColor(0, 0, 0, 0.95)
                else
                    circ.segMarks[i]:SetVertexColor(0, 0, 0, 0.50)
                end
            end
        end
    elseif cb.headTex then
        cb.headTex:SetAlpha(0)
        if cb.trailTex then cb.trailTex:SetAlpha(0) end
        if circ and circ.trail then for i = 1, #circ.trail do circ.trail[i]:SetAlpha(0) end end
    end

    -- ── Channel comets ──────────────────────────────────────────────────────
    if cb.channeling and circ and circ.comets and circ.channel_style == "comets" then
        local r = cb.arcRadius
        local cycle = 2.5
        local nC = #circ.comets
        for i = 1, nC do
            local off = (i - 1) / nC
            local phase = ((now / cycle) + off) % 1
            local ang = 2 * math_pi * phase
            circ.comets[i]:ClearAllPoints()
            circ.comets[i]:SetPoint("CENTER", cb.cd, "CENTER", r * math_sin(ang), r * math_cos(ang))
            circ.comets[i]:SetAlpha(0.85)
        end
    end

    -- ── Channel radar ───────────────────────────────────────────────────────
    if cb.channeling and circ and circ.radarTrail and circ.channel_style == "radar" then
        local r = cb.arcRadius
        local cycle = 2.0
        local headPhase = (now / cycle) % 1
        local nT = #circ.radarTrail
        for i = 1, nT do
            local back = (i - 1) * 0.025
            local p = (headPhase - back) % 1
            local ang = 2 * math_pi * p
            circ.radarTrail[i]:ClearAllPoints()
            circ.radarTrail[i]:SetPoint("CENTER", cb.cd, "CENTER", r * math_sin(ang), r * math_cos(ang))
            circ.radarTrail[i]:SetAlpha((1 - (i - 1) / nT) * 0.85)
        end
    end

    -- ── Channel pulse ───────────────────────────────────────────────────────
    if cb.channeling and circ and circ.pulseRing and circ.channel_style == "pulse" then
        local pulse = 0.18 + 0.30 * (math_sin(now * 4.5) * 0.5 + 0.5)
        circ.pulseRing:SetAlpha(pulse)
    end

    -- ── V6 : Spark qui suit la progression (point lumineux net) ─────────────
    if cb.active and circ and circ.v6Spark and cb.cd then
        local r = cb.arcRadius or 30
        local v = progress
        if cb.channeling then v = 1.0 - progress end
        local ang = 2 * math_pi * v - (math_pi * 0.5)  -- démarre en haut (12h)
        local sx = r * math_cos(ang)
        local sy = -r * math_sin(ang)  -- WoW Y inversé
        circ.v6Spark:ClearAllPoints()
        circ.v6Spark:SetPoint("CENTER", cb.cd, "CENTER", sx, sy)
        local sparkPulse = 0.65 + 0.30 * (math_sin(now * 8.0) * 0.5 + 0.5)
        circ.v6Spark:SetAlpha(sparkPulse)
    end

    -- ── V6 : Pulse subtil de la bordure colorée pendant le cast ─────────────
    if cb.active and circ and circ.v5Border then
        circ.v5Border:SetAlpha(0)
    end

    -- ── Complete flash 100% ─────────────────────────────────────────────────
    if circ and circ.completeRing and not cb.channeling
        and not (circ.collapseTex and cfg.castbar_collapse_complete_flash == false)
        and not (circ.collapseGlow and cfg.castbar_collapse_glow_complete_flash == false) then
        if progress >= 0.999 and not cb._completeFlashed then
            cb._completeFlashed = true
            local fc = _rgb((SP:GetCfg(data.unitType) or {}).castbar_color_finish, COLOR_FINISH)
            circ.completeRing:SetVertexColor(fc.r, fc.g, fc.b)
            circ.completeRing:SetAlpha(0.85)
        elseif cb._completeFlashed then
            local a = circ.completeRing:GetAlpha()
            circ.completeRing:SetAlpha(math_max(0, a - 0.04))
        end
    end

    -- ── Classique : largeur fill + glow edge ────────────────────────────────
    if cb.barFill and cb.barW and cb.barW > 0 then
        local barProgress = cb.channeling and (1.0 - progress) or progress
        local fillW = math_max(1, cb.barW * math_max(0, barProgress))
        cb.barFill:SetWidth(fillW)

        -- Glow sur le bord droit du fill (ou bord gauche pour canal)
        if cb.barGlowL then
            local pulse = 0.28 + 0.18 * math_abs(math_sin(now * 3.5))
            cb.barGlowL:ClearAllPoints()
            if cb.channeling then
                cb.barGlowL:SetPoint("CENTER", cb.barFill, "LEFT", 0, 0)
            else
                cb.barGlowL:SetPoint("CENTER", cb.barFill, "RIGHT", 0, 0)
            end
            cb.barGlowL:SetAlpha(fillW > 2 and pulse or 0)
        end
    end

    -- ── Glow circulaire pulsant — amplitudes réduites ──────────────────────
    if cb.glowTex then
        if cb.isImmune then
            cb.glowPhase = cb.glowPhase + 0.11
            cb.glowTex:SetAlpha(0.14 + ((math_sin(cb.glowPhase * math_pi) + 1) * 0.5) * 0.10)
        elseif not cb.interruptible then
            cb.glowPhase = cb.glowPhase + 0.08
            cb.glowTex:SetAlpha(0.10 + ((math_sin(cb.glowPhase * math_pi) + 1) * 0.5) * 0.08)
        else
            cb.glowPhase = cb.glowPhase + 0.06
            cb.glowTex:SetAlpha(0.06 + ((math_sin(cb.glowPhase * math_pi) + 1) * 0.5) * 0.06)
        end
    end

    -- Auto-stop
    if now > cb.endTime + 0.30 then
        SP.CastBar:StopCast(data, false)
    end
end

-------------------------------------------------------------------------------
--  Reset — nettoyage complet
-------------------------------------------------------------------------------
function SP.CastBar:Reset(data)
    local cb = data.castbar
    if not cb then return end
    _RestoreNameReplacement(data)

    if cb.watcher then
        pcall(cb.watcher.UnregisterAllEvents, cb.watcher)
        cb.watcher = nil
    end

    cb.active     = false
    cb.channeling = false
    cb.flashStart = 0
    cb.glowPhase  = 0

    -- Focus mode : restaurer levelText si on reset en urgence
    if cb._focusModeActive then
        cb._focusModeActive = false
        local rcfg = SP:GetCfg(data.unitType) or {}
        if rcfg.showLevelOrHP and data.levelText then data.levelText:Show() end
    end

    if cb.cd        then cb.cd:SetCooldown(0, 0); cb.cd:Hide()    end
    if cb.headTex   then cb.headTex:SetAlpha(0)                    end
    if cb.trailTex  then cb.trailTex:SetAlpha(0)                   end
    if cb.glowTex   then cb.glowTex:SetAlpha(0)                    end
    if cb.barFrame  then cb.barFrame:Hide()                         end
    if cb.iconFrame then cb.iconFrame:SetAlpha(0)                   end
    if cb.barGlowL  then cb.barGlowL:SetAlpha(0)                   end
    if cb.flashTex  then cb.flashTex:SetAlpha(0)                   end
    if cb.castName  then cb.castName:Hide()                         end
    if cb.castTime  then cb.castTime:Hide()                         end
    if cb.lockTex   then cb.lockTex:SetAlpha(0)                     end
    _ResetInterruptMark(cb)
    cb._runtimeMissingSince = nil
    cb._runtimeMissingCount = 0
    -- Sprite mode
    local spr = data._cb_sprite
    if spr then spr.frame:Hide() end
    -- CCB mode
    if data._cb_ccb then SP.CCB:Reset(data) end

    local circ = data._cb_circ
    if circ then
        if circ.trackCD      then circ.trackCD:Hide()               end
        if circ.cd2          then circ.cd2:Hide()                    end
        if circ.trail        then for i=1,#circ.trail        do circ.trail[i]:SetAlpha(0)        end end
        if circ.comets       then for i=1,#circ.comets       do circ.comets[i]:SetAlpha(0)       end end
        if circ.radarTrail   then for i=1,#circ.radarTrail   do circ.radarTrail[i]:SetAlpha(0)   end end
        if circ.pulseRing    then circ.pulseRing:SetAlpha(0)                                       end
        if circ.completeRing then circ.completeRing:SetAlpha(0)                                    end
        if circ.kickShards   then for i=1,#circ.kickShards   do circ.kickShards[i]:SetAlpha(0)   end end
        if circ.bevelOut     then circ.bevelOut:SetAlpha(0)                                        end
        if circ.bevelIn      then circ.bevelIn:SetAlpha(0)                                         end
        if circ.pin12        then circ.pin12:SetAlpha(0)                                           end
        if circ.icoBorder    then circ.icoBorder:SetAlpha(0)                                       end
        if circ.v5Border     then circ.v5Border:SetAlpha(0)                                        end
        if circ.v5Track      then circ.v5Track:SetAlpha(0)                                         end
        if circ.v6Spark      then circ.v6Spark:SetAlpha(0)                                         end
        if circ.owGlow       then circ.owGlow:SetAlpha(0)                                          end
        if circ.v8Segments   then _V8ResetSegments(circ, true)                                    end
        if circ.dottedSegments then _ResetDotted(circ, true)                                      end
        if circ.collapseTex  then _ResetCollapse(circ)                                             end
        if circ.collapseGlow then _ResetCollapseGlow(circ)                                         end
        -- owRing reste visible (track de fond constant en preset overwatch)
    end
    cb._kickFXStart = nil
    cb._completeFlashed = false
    cb.castGUID = nil
    cb.spellId = nil
    cb.castDisplayName = nil
    cb.castDisplayText = nil
    cb.castDisplaySource = nil
    cb._activePollTimer = 0
    cb._activePollLast = nil
end
