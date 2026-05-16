-------------------------------------------------------------------------------
--  SphereNameplates · PerformanceMonitor
--
--  Upgrade du Profiler minimal existant.
--  Mesure par module : appels/s, avg ms, pic ms (fenetre 30s), total.
--  Cout propre negligeable : debugprofilestop() ~0.001ms, guard enabled.
--
--  API :
--    SP.Profiler:Track(module, elapsed_ms)   enregistre un appel mesure
--    SP.Profiler:GetStats(module)            retourne la table stats du module
--    SP.Profiler:GetAllStats()               retourne tous les modules actifs
--    SP.Profiler:ResetStats()                remise a zero
--    SP.Profiler:ShowPanel()                 affiche le panneau /snp perf
--    SP.Profiler:HidePanel()                 cache le panneau
--    SP.Profiler:TogglePanel()               toggle
--    SP.Profiler:TickPanel(now)              rafraichit le panneau (appelee par Core)
--
--  Compat ascendante :
--    SP.Profiler:Start(key)  / Stop(key)  / Report()  conserves
-------------------------------------------------------------------------------

local addonName, _ = ...
local SP = _G["SphereNameplates"]
if not SP then return end

SP.Profiler = SP.Profiler or {}
local P = SP.Profiler

P.stats   = P.stats   or {}
P.enabled = false            -- mis a jour dans Core par la DB

-- Fenetre de reset du pic (secondes)
P.PEAK_WINDOW = 30.0

-- ─── IsEnabled ────────────────────────────────────────────────────────────────
function P:IsEnabled()
    return SP.db and SP.db.perf_enabled == true
end

-- ─── Track(module, elapsed_ms) ────────────────────────────────────────────────
-- elapsed_ms = debugprofilestop() delta, deja calcule par l'appelant
function P:Track(module, elapsed_ms)
    if not self:IsEnabled() then return end
    local now = GetTime()
    local s = self.stats[module]
    if not s then
        s = {
            calls          = 0,
            total_ms       = 0,
            avg_ms         = 0,
            peak_ms        = 0,
            peak_reset_t   = now,
            last_sec_t     = now,
            last_sec_calls = 0,
            calls_per_sec  = 0,
        }
        self.stats[module] = s
    end

    s.calls    = s.calls + 1
    s.total_ms = s.total_ms + elapsed_ms

    -- EMA avg (alpha = 0.05 → lissage fort)
    s.avg_ms = s.avg_ms * 0.95 + elapsed_ms * 0.05

    -- Pic — reset toutes les PEAK_WINDOW secondes
    if (now - s.peak_reset_t) >= self.PEAK_WINDOW then
        s.peak_ms      = elapsed_ms
        s.peak_reset_t = now
    elseif elapsed_ms > s.peak_ms then
        s.peak_ms = elapsed_ms
    end

    -- Appels par seconde (fenetre 1s glissante)
    if (now - s.last_sec_t) >= 1.0 then
        s.calls_per_sec  = s.last_sec_calls
        s.last_sec_calls = 0
        s.last_sec_t     = now
    end
    s.last_sec_calls = s.last_sec_calls + 1

    -- Log PERF si pic depasse seuil
    if SP.Log and elapsed_ms > 0 then
        local seuil = (SP.db and SP.db.perf_seuil_ms) or 5.0
        if elapsed_ms > seuil then
            SP.Log:Perf(module, string.format("%.2fms (seuil %.1fms)", elapsed_ms, seuil))
        end
    end
end

-- ─── GetStats ─────────────────────────────────────────────────────────────────
function P:GetStats(module)
    return self.stats[module]
end

function P:GetAllStats()
    return self.stats
end

function P:ResetStats()
    self.stats = {}
end

-- ─── Compat ascendante Start/Stop/Report ──────────────────────────────────────
function P:Start(key)
    if not self:IsEnabled() then return end
    self.stats[key] = self.stats[key] or {}
    self.stats[key]._t0    = debugprofilestop()
    self.stats[key].calls  = (self.stats[key].calls or 0)
end

function P:Stop(key)
    if not self:IsEnabled() or not (self.stats[key] and self.stats[key]._t0) then return end
    local diff = debugprofilestop() - self.stats[key]._t0
    self:Track(key, diff)
end

function P:Report()
    SP:Print("=== SphereNameplates Profiler ===")
    for k, v in pairs(self.stats) do
        if (v.calls or 0) > 0 then
            SP:Print(string.format("  %-20s avg=%.3fms  pic=%.3fms  appels=%d  /s=%d",
                k,
                v.avg_ms   or 0,
                v.peak_ms  or 0,
                v.calls    or 0,
                v.calls_per_sec or 0))
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PANNEAU /snp perf
--  Frame draggable, rafraichi toutes les 1s, fond semi-transparent
--  Fermeture par bouton [×]. Visible seulement si perf_panel_visible=true.
-- ─────────────────────────────────────────────────────────────────────────────
local _panel = nil
local _panelAcc = 0

local function _buildPanel()
    if _panel then return end

    local f = CreateFrame("Frame", "SPPerfPanel", UIParent, "BackdropTemplate")
    f:SetSize(380, 260)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    -- Fond
    pcall(function()
        f:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left=3, right=3, top=3, bottom=3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
        f:SetBackdropBorderColor(0.5, 0.5, 0.7, 0.8)
    end)

    -- Titre
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    title:SetText("|cFFFF8800Sphere|cFFFFFFFFPlates|r — |cFF88CCFFPerf Monitor|r")
    f.title = title

    -- Bouton fermer
    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    local closeTex = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTex:SetText("|cFFFF4444[×]|r")
    closeTex:SetAllPoints(close)
    close:SetScript("OnClick", function()
        if SP.db then SP.db.perf_panel_visible = false end
        f:Hide()
    end)
    close:EnableMouse(true)

    -- Séparateur
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    sep:SetSize(360, 2)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -22)

    -- Contenu texte
    local body = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
    body:SetSize(364, 220)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(2)
    body:SetText("Chargement...")
    f.body = body

    f:Hide()
    _panel = f
end

local function _countPlates()
    local n = 0
    if SP.Plates then for _ in pairs(SP.Plates) do n = n + 1 end end
    return n
end

local function _fmtLine(module, s)
    local marker = ""
    local seuil  = (SP.db and SP.db.perf_seuil_ms) or 5.0
    if (s.peak_ms or 0) > seuil then marker = "|cFFFF4444!|r" end
    return string.format(
        "|cFFFFFF88%-18s|r  %4d/s  avg|cFF88FF88%6.3f|rms  pic|cFFFF8800%6.3f|r%s",
        module,
        s.calls_per_sec or 0,
        s.avg_ms  or 0,
        s.peak_ms or 0,
        marker)
end

function P:TickPanel(now)
    if not _panel or not _panel:IsShown() then return end
    _panelAcc = _panelAcc + (now - (P._lastPanelTick or now))
    P._lastPanelTick = now
    if _panelAcc < 1.0 then return end
    _panelAcc = 0

    -- En-tête
    local fps    = GetFramerate and math.floor(GetFramerate() + 0.5) or "?"
    local plates = _countPlates()
    local combat = SP.InCombat and "|cFFFF4444OUI|r" or "|cFF44FF44non|r"
    local logOn  = (SP.Log and SP.Log:IsEnabled()) and "|cFF44FF44on|r" or "off"
    local lines  = {
        string.format("|cFFFF8800FPS:|r %s  |cFFFF8800Plates:|r %d  |cFFFF8800Combat:|r %s  |cFFFF8800Logs:|r %s",
            tostring(fps), plates, combat, logOn),
        "|cFF555577" .. string.rep("─", 54) .. "|r",
        string.format("|cFF888888%-18s  %6s  %9s  %9s|r",
            "Module", "app/s", "avg ms", "pic ms"),
        "|cFF555577" .. string.rep("─", 54) .. "|r",
    }

    -- Trier les modules par avg décroissant
    local sorted = {}
    for k, v in pairs(self.stats) do
        sorted[#sorted + 1] = { name = k, s = v }
    end
    table.sort(sorted, function(a, b)
        return (a.s.avg_ms or 0) > (b.s.avg_ms or 0)
    end)

    if #sorted == 0 then
        lines[#lines + 1] = "|cFF888888(aucune mesure — activer PerformanceMonitor)|r"
    else
        for _, entry in ipairs(sorted) do
            lines[#lines + 1] = _fmtLine(entry.name, entry.s)
        end
    end

    -- Section Inspect
    lines[#lines + 1] = "|cFF555577" .. string.rep("─", 54) .. "|r"
    if SP.Inspect then
        local q = SP.Inspect.queue and #SP.Inspect.queue or 0
        local c = 0
        if SP.Inspect.cache then for _ in pairs(SP.Inspect.cache) do c = c + 1 end end
        lines[#lines + 1] = string.format(
            "|cFF888888Inspect: queue=%d  cache=%d  pending=%s|r",
            q, c, tostring(SP.Inspect.pending and "oui" or "non"))
    end

    _panel.body:SetText(table.concat(lines, "\n"))
end

function P:ShowPanel()
    _buildPanel()
    if _panel then
        _panel:Show()
        if SP.db then SP.db.perf_panel_visible = true end
        P._lastPanelTick = GetTime()
        _panelAcc = 0
    end
end

function P:HidePanel()
    if _panel then
        _panel:Hide()
        if SP.db then SP.db.perf_panel_visible = false end
    end
end

function P:TogglePanel()
    if _panel and _panel:IsShown() then
        self:HidePanel()
    else
        self:ShowPanel()
    end
end

-- Restaurer l'etat du panneau apres chargement DB
function P:RestorePanelState()
    if SP.db and SP.db.perf_panel_visible then
        self:ShowPanel()
    end
end
