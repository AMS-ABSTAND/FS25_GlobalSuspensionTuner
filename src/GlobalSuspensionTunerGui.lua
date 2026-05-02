-- GlobalSuspensionTunerGui.lua  v0.3.0.0
-- In-game settings overlay for GlobalSuspensionTuner.
-- Same FS25-style dark panel + orange accent as the SlowSteering GUI.
--
-- Keyboard:
--   Up/Down       navigate settings
--   Left/Right    change selected value
--   Tab / Q / E   cycle tab    (Shift+Tab = previous)
--   P             cycle preset
--   F1            reset selected setting to default (FALLBACK)
--   F5            reset ALL settings to active preset / FALLBACK
--   Enter         save & close
--   Esc / Bksp    cancel & close
--
-- Mouse: tab click, row select, slider drag, < / > chevrons, footer buttons.

GstGui = {}
GstGui.isOpen          = false
GstGui.activeTab       = 1
GstGui.selectedIdx     = 1
GstGui.tempValues      = {}
GstGui.activePreset    = "vanilla"
GstGui.originalSnap    = nil
GstGui.bgOverlay       = nil
GstGui.flashFrames     = 0
GstGui.flashColor      = nil
GstGui.hoverTab        = 0
GstGui.hoverRow        = 0
GstGui.hoverFooter     = 0
GstGui.dragging        = nil
GstGui.mouseX          = 0
GstGui.mouseY          = 0
GstGui._rowRects        = {}
GstGui._tabRects        = {}
GstGui._sliderRects     = {}
GstGui._valueLeftRects  = {}
GstGui._valueRightRects = {}
GstGui._togglePillRects = {}
GstGui._footerRects     = {}

-- =========================================================
-- VALUE STORE  (flat key namespace: "cab.weight", "wheels.springMultiplier" ...)
-- =========================================================
-- We mirror GstConfig._defaults into a flat table while the GUI is open,
-- then write back on save.

local function flatGet(t, dottedKey)
    local a, b = dottedKey:match("([^.]+)%.([^.]+)")
    if a == nil then return t[dottedKey] end
    if t[a] == nil then return nil end
    return t[a][b]
end

local function flatSet(t, dottedKey, value)
    local a, b = dottedKey:match("([^.]+)%.([^.]+)")
    if a == nil then t[dottedKey] = value; return end
    if t[a] == nil then t[a] = {} end
    t[a][b] = value
end

-- =========================================================
-- PRESETS  (whole-defaults snapshots)
-- =========================================================
GstGui.PRESETS = {
    vanilla = {
        cab    = { weight = 100, springX = 200,  damperX = 30  },
        seat   = { weight =  80, springY = 30,   damperY = 5   },
        torso  = { weight =  80, springY = 20,   damperY = 3, springZ = 20, damperZ = 3 },
        wheels = { suspTravelScale = 1.0, suspTravelMax = 0.20, springMultiplier = 1.0, damperMultiplier = 1.0 },
    },
    weich = {
        cab    = { weight = 600, springX = 100, damperX = 10 },
        seat   = { weight = 250, springY = 12,  damperY = 1.5 },
        torso  = { weight = 140, springY = 8,   damperY = 1.0, springZ = 8, damperZ = 1.0 },
        wheels = { suspTravelScale = 1.25, suspTravelMax = 0.25, springMultiplier = 0.55, damperMultiplier = 0.55 },
    },
    sehrWeich = {
        cab    = { weight = 800, springX = 60,  damperX = 6 },
        seat   = { weight = 300, springY = 6,   damperY = 0.9 },
        torso  = { weight = 160, springY = 5,   damperY = 0.7, springZ = 5, damperZ = 0.7 },
        wheels = { suspTravelScale = 1.5, suspTravelMax = 0.30, springMultiplier = 0.30, damperMultiplier = 0.30 },
    },
    extrem = {
        cab    = { weight = 1000, springX = 30, damperX = 4 },
        seat   = { weight = 350,  springY = 4,  damperY = 0.6 },
        torso  = { weight = 180,  springY = 3,  damperY = 0.5, springZ = 3, damperZ = 0.5 },
        wheels = { suspTravelScale = 1.8, suspTravelMax = 0.40, springMultiplier = 0.18, damperMultiplier = 0.18 },
    },
}
GstGui.PRESET_ORDER = { "vanilla", "weich", "sehrWeich", "extrem", "custom" }
GstGui.PRESET_LABELS = {
    vanilla   = "Vanilla",
    weich     = "Weich",
    sehrWeich = "Sehr weich",
    extrem    = "Extrem weich",
    custom    = "Eigen",
}

-- =========================================================
-- TAB & SETTING DEFINITIONS
-- =========================================================
GstGui.TABS = {
    {
        id = "general",
        label = "Allgemein",
        items = {
            { key = "_preset", label = "Profil", type = "preset",
              help = "Voreinstellungen fuer das Federungs-Verhalten. Aenderungen schalten auf 'Eigen'." },
        }
    },
    {
        id = "cab",
        label = "Kabine",
        items = {
            { key = "cab.weight",  label = "Masse",       type = "float", step = 25,   range = { 50,   2000 }, fmt = "%.0f kg",
              help = "Effektive Kabinenmasse. Hoeher = mehr Traegheit, weicher gefuehlt." },
            { key = "cab.springX", label = "Feder X",     type = "float", step = 5,    range = { 1,    300  }, fmt = "%.0f",
              help = "Federsteifigkeit der Kabinen-Aufhaengung um X. Niedriger = weicher." },
            { key = "cab.damperX", label = "Daempfer X",  type = "float", step = 0.5,  range = { 0.1,  30   }, fmt = "%.1f",
              help = "Daempfung der Kabine. Hoeher = weniger Nachschwingen." },
        }
    },
    {
        id = "seat",
        label = "Sitz",
        items = {
            { key = "seat.weight",  label = "Masse",      type = "float", step = 10,   range = { 30,   1000 }, fmt = "%.0f kg",
              help = "Effektive Sitzmasse." },
            { key = "seat.springY", label = "Feder Y",    type = "float", step = 0.5,  range = { 0.5,  150  }, fmt = "%.1f",
              help = "Vertikale Federsteifigkeit des Sitzes. Niedriger = weicher." },
            { key = "seat.damperY", label = "Daempfer Y", type = "float", step = 0.1,  range = { 0.1,  20   }, fmt = "%.1f",
              help = "Vertikale Sitz-Daempfung." },
        }
    },
    {
        id = "torso",
        label = "Torso",
        items = {
            { key = "torso.weight",  label = "Masse",      type = "float", step = 5,    range = { 20,   500 }, fmt = "%.0f kg",
              help = "Effektive Masse des Spielfigur-Torsos." },
            { key = "torso.springY", label = "Feder Y",    type = "float", step = 0.5,  range = { 0.5,  100 }, fmt = "%.1f",
              help = "Federsteifigkeit Torso um Y-Achse (Nicken)." },
            { key = "torso.damperY", label = "Daempfer Y", type = "float", step = 0.1,  range = { 0.1,  20  }, fmt = "%.1f",
              help = "Daempfung Torso Y-Achse." },
            { key = "torso.springZ", label = "Feder Z",    type = "float", step = 0.5,  range = { 0.5,  100 }, fmt = "%.1f",
              help = "Federsteifigkeit Torso um Z-Achse (Wanken)." },
            { key = "torso.damperZ", label = "Daempfer Z", type = "float", step = 0.1,  range = { 0.1,  20  }, fmt = "%.1f",
              help = "Daempfung Torso Z-Achse." },
        }
    },
    {
        id = "wheels",
        label = "Raeder",
        items = {
            { key = "wheels.suspTravelScale",  label = "Federweg-Skala",     type = "float", step = 0.05, range = { 0.5, 3.0 }, fmt = "%.2fx",
              help = "Multiplikator fuer den originalen Federweg jedes Rades." },
            { key = "wheels.suspTravelMax",    label = "Federweg-Max",       type = "float", step = 0.01, range = { 0.05, 0.6 }, fmt = "%.2f m",
              help = "Obergrenze fuer den Federweg in Metern (auch nach Skalierung)." },
            { key = "wheels.springMultiplier", label = "Federsteifigkeit",   type = "float", step = 0.05, range = { 0.05, 2.0 }, fmt = "%.2fx",
              help = "Multiplikator fuer die Rad-Federsteifigkeit. <1 = weicher." },
            { key = "wheels.damperMultiplier", label = "Daempfung",          type = "float", step = 0.05, range = { 0.05, 2.0 }, fmt = "%.2fx",
              help = "Multiplikator fuer die Rad-Daempfung. <1 = weniger Daempfung." },
        }
    },
}

-- =========================================================
-- THEME
-- =========================================================
local C = {
    dim         = { 0.00, 0.00, 0.00, 0.62 },
    panelBg     = { 0.078, 0.090, 0.110, 0.985 },
    panelEdge   = { 0.20,  0.22,  0.26,  1.00  },
    headerBg    = { 0.118, 0.137, 0.169, 1.00  },
    headerLine  = { 1.00,  0.62,  0.06,  1.00  },
    tabBg       = { 0.090, 0.107, 0.130, 1.00  },
    tabActiveBg = { 0.137, 0.165, 0.200, 1.00  },
    tabHover    = { 0.114, 0.137, 0.170, 1.00  },
    tabUnderline= { 1.00,  0.62,  0.06,  1.00  },
    rowBg       = { 0.105, 0.125, 0.150, 0.55  },
    rowSelected = { 0.18,  0.22,  0.27,  1.00  },
    rowHover    = { 0.140, 0.165, 0.198, 1.00  },
    rowAccent   = { 1.00,  0.62,  0.06,  1.00  },
    sliderTrack = { 0.18,  0.20,  0.24,  1.00  },
    sliderFill  = { 1.00,  0.62,  0.06,  1.00  },
    sliderFillD = { 0.55,  0.36,  0.06,  1.00  },
    sliderKnob  = { 1.00,  1.00,  1.00,  1.00  },
    txtPrimary  = { 0.94,  0.95,  0.96,  1.00  },
    txtSecond   = { 0.70,  0.74,  0.78,  1.00  },
    txtMuted    = { 0.50,  0.54,  0.58,  1.00  },
    txtAccent   = { 1.00,  0.74,  0.30,  1.00  },
    txtChanged  = { 1.00,  0.85,  0.30,  1.00  },
    txtOk       = { 0.45,  0.85,  0.55,  1.00  },
    panelInner  = { 0.058, 0.068, 0.082, 1.00  },
    divider     = { 0.18,  0.20,  0.24,  1.00  },
    btnBg       = { 0.12,  0.14,  0.17,  1.00  },
    btnBgHover  = { 0.18,  0.22,  0.27,  1.00  },
    btnSaveBg   = { 0.18,  0.45,  0.20,  1.00  },
    btnSaveBgH  = { 0.25,  0.60,  0.27,  1.00  },
    btnCancelBg = { 0.42,  0.18,  0.18,  1.00  },
    btnCancelBgH= { 0.55,  0.24,  0.24,  1.00  },
}

-- =========================================================
-- LAYOUT
-- =========================================================
local L = {}
local function computeLayout()
    L.dialogX = 0.16
    L.dialogY = 0.10
    L.dialogW = 0.68
    L.dialogH = 0.80
    L.headerH = 0.058
    L.tabH    = 0.044
    L.footerH = 0.060
    L.padX    = 0.020
    L.padY    = 0.014
    L.leftRatio = 0.62
    L.rowH    = 0.052
end
computeLayout()

-- =========================================================
-- HELPERS
-- =========================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pointIn(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function setColor(t)
    setTextColor(t[1], t[2], t[3], t[4])
end

local function currentItems() return GstGui.TABS[GstGui.activeTab].items end
local function currentItem()  return currentItems()[GstGui.selectedIdx] end

local function deepCopyDefaults(d)
    local out = {}
    for k, v in pairs(d) do
        if type(v) == "table" then
            out[k] = {}
            for kk, vv in pairs(v) do out[k][kk] = vv end
        else
            out[k] = v
        end
    end
    return out
end

local function snapshotEqualsPreset(name)
    local p = GstGui.PRESETS[name]
    if p == nil then return false end
    for blockKey, block in pairs(p) do
        for k, v in pairs(block) do
            local cur = flatGet(GstGui.tempValues, blockKey .. "." .. k)
            if cur == nil or math.abs(cur - v) > 1e-4 then
                return false
            end
        end
    end
    return true
end

local function detectPreset()
    for _, name in ipairs(GstGui.PRESET_ORDER) do
        if name ~= "custom" and snapshotEqualsPreset(name) then return name end
    end
    return "custom"
end

local function applyPresetToTemp(name)
    if name == "custom" then GstGui.activePreset = "custom"; return end
    local p = GstGui.PRESETS[name]
    if p == nil then return end
    GstGui.tempValues = deepCopyDefaults(p)
    GstGui.activePreset = name
end

local function getValue(def)
    if def.type == "preset" then return GstGui.activePreset end
    return flatGet(GstGui.tempValues, def.key)
end

local function setValueRaw(def, value)
    flatSet(GstGui.tempValues, def.key, value)
end

local function formatItem(def, val)
    if def.type == "preset" then
        return GstGui.PRESET_LABELS[val] or tostring(val)
    end
    if val == nil then return "-" end
    return string.format(def.fmt, val)
end

local function maybeUnlockCustom(def)
    if def.type == "preset" then return end
    if GstGui.activePreset == "custom" then return end
    if not snapshotEqualsPreset(GstGui.activePreset) then
        GstGui.activePreset = "custom"
    end
end

local function changeValue(def, dir)
    if def.type == "preset" then
        local order = GstGui.PRESET_ORDER
        local idx = 1
        for i, v in ipairs(order) do if v == GstGui.activePreset then idx = i; break end end
        idx = ((idx - 1 + dir) % #order) + 1
        applyPresetToTemp(order[idx])
        GstGui.flashColor  = { 1.00, 0.62, 0.06 }
        GstGui.flashFrames = 12
        return
    end
    local r = def.range
    if r == nil then return end
    local cur = getValue(def) or r[1]
    local v = cur + dir * (def.step or 0.05)
    v = clamp(v, r[1], r[2])
    if def.step and def.step > 0 then
        v = math.floor(v / def.step + 0.5) * def.step
        v = clamp(v, r[1], r[2])
    end
    setValueRaw(def, v)
    maybeUnlockCustom(def)
end

local function setSliderNorm(def, norm)
    local r = def.range
    if r == nil then return end
    norm = clamp(norm, 0, 1)
    local v = r[1] + norm * (r[2] - r[1])
    if def.step and def.step > 0 then
        v = math.floor(v / def.step + 0.5) * def.step
        v = clamp(v, r[1], r[2])
    end
    setValueRaw(def, v)
    maybeUnlockCustom(def)
end

local function resetSelectedToDefault()
    local def = currentItem()
    if def == nil or def.type == "preset" then return end
    -- Use PRESETS.sehrWeich as the canonical default (matches FALLBACK)
    local p = GstGui.PRESETS.sehrWeich
    local a, b = def.key:match("([^.]+)%.([^.]+)")
    if p[a] == nil or p[a][b] == nil then return end
    setValueRaw(def, p[a][b])
    maybeUnlockCustom(def)
    GstGui.flashColor  = { 1.00, 0.62, 0.06 }
    GstGui.flashFrames = 10
end

local function resetAllToProfile()
    local profile = GstGui.activePreset
    if profile == "custom" then profile = "sehrWeich" end
    applyPresetToTemp(profile)
    GstGui.flashColor  = { 1.00, 0.62, 0.06 }
    GstGui.flashFrames = 12
end

-- =========================================================
-- OPEN / CLOSE
-- =========================================================
function GstGui.open()
    if GstGui.isOpen then return end
    computeLayout()
    GstConfig.ensureLoaded()

    -- Snapshot current GstConfig defaults into tempValues
    GstGui.tempValues  = deepCopyDefaults(GstConfig._defaults or {})
    GstGui.originalSnap = deepCopyDefaults(GstConfig._defaults or {})
    GstGui.activePreset = detectPreset()

    GstGui.isOpen      = true
    GstGui.activeTab   = 1
    GstGui.selectedIdx = 1
    GstGui.flashFrames = 0
    GstGui.dragging    = nil

    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true)
    end
end

function GstGui.close(save)
    if not GstGui.isOpen then return end

    if save then
        -- Write back into GstConfig defaults
        GstConfig.ensureLoaded()
        for blockKey, block in pairs(GstGui.tempValues) do
            if GstConfig._defaults[blockKey] == nil then
                GstConfig._defaults[blockKey] = {}
            end
            for k, v in pairs(block) do
                GstConfig._defaults[blockKey][k] = v
            end
        end
        GstConfig._dirty = true
        GstConfig.flushIfDirty()

        -- Retune all loaded vehicles so changes take effect immediately
        if GlobalSuspensionTuner ~= nil and GlobalSuspensionTuner.retuneAll ~= nil then
            GlobalSuspensionTuner.retuneAll()
        end

        if g_currentMission ~= nil then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                "Suspension Tuner: Einstellungen gespeichert")
        end
    end

    GstGui.isOpen = false
    GstGui.dragging = nil

    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
    end
end

-- =========================================================
-- INPUT (keyboard)
-- =========================================================
function GstGui.onKeyEvent(unicode, sym, modifier, isDown)
    if not GstGui.isOpen then return end
    if not isDown then return end

    local items = currentItems()
    local idx   = GstGui.selectedIdx

    if sym == Input.KEY_tab or sym == Input.KEY_e or sym == Input.KEY_q then
        local n = #GstGui.TABS
        local dir = 1
        if sym == Input.KEY_q then
            dir = -1
        elseif Input.MOD_lshift ~= nil and modifier == Input.MOD_lshift then
            dir = -1
        end
        GstGui.activeTab   = ((GstGui.activeTab - 1 + dir) % n) + 1
        GstGui.selectedIdx = 1
        return
    end

    if sym == Input.KEY_up then
        GstGui.selectedIdx = ((idx - 2) % #items) + 1
        return
    elseif sym == Input.KEY_down then
        GstGui.selectedIdx = (idx % #items) + 1
        return
    end

    local def = items[idx]
    if def == nil then return end

    if sym == Input.KEY_left then
        changeValue(def, -1); return
    elseif sym == Input.KEY_right then
        changeValue(def,  1); return
    end

    if sym == Input.KEY_p then
        local order = GstGui.PRESET_ORDER
        local i = 1
        for k, v in ipairs(order) do if v == GstGui.activePreset then i = k end end
        i = (i % #order) + 1
        applyPresetToTemp(order[i])
        GstGui.flashColor  = { 1.00, 0.62, 0.06 }
        GstGui.flashFrames = 12
        return
    end

    if sym == Input.KEY_f1 then resetSelectedToDefault(); return end
    if sym == Input.KEY_f5 then resetAllToProfile();      return end

    if sym == Input.KEY_return or sym == Input.KEY_KP_enter then
        GstGui.close(true)
    elseif sym == Input.KEY_escape or sym == Input.KEY_backspace then
        GstGui.close(false)
    end
end

-- =========================================================
-- INPUT (mouse)
-- =========================================================
function GstGui.onMouseEvent(posX, posY, isDown, isUp, button)
    if not GstGui.isOpen then return end
    GstGui.mouseX = posX
    GstGui.mouseY = posY

    GstGui.hoverTab = 0
    for i, r in ipairs(GstGui._tabRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then GstGui.hoverTab = i; break end
    end
    GstGui.hoverRow = 0
    for i, r in ipairs(GstGui._rowRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then GstGui.hoverRow = i; break end
    end
    GstGui.hoverFooter = 0
    for i, r in ipairs(GstGui._footerRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then GstGui.hoverFooter = i; break end
    end

    if GstGui.dragging ~= nil then
        local def = GstGui.dragging
        local sr  = GstGui._sliderRects[def.key]
        if sr ~= nil then
            local norm = (posX - sr[1]) / sr[3]
            setSliderNorm(def, norm)
        end
        if isUp and button == Input.MOUSE_BUTTON_LEFT then GstGui.dragging = nil end
    end

    if not isDown then return end
    if button ~= Input.MOUSE_BUTTON_LEFT then return end

    if GstGui.hoverTab > 0 then
        GstGui.activeTab   = GstGui.hoverTab
        GstGui.selectedIdx = 1
        return
    end

    if GstGui.hoverFooter > 0 then
        local btn = GstGui.hoverFooter
        if btn == 1 then GstGui.close(true)
        elseif btn == 2 then GstGui.close(false)
        elseif btn == 3 then resetAllToProfile() end
        return
    end

    if GstGui.hoverRow > 0 then
        GstGui.selectedIdx = GstGui.hoverRow
        local def = currentItems()[GstGui.hoverRow]

        if def ~= nil and def.type == "float" then
            local sr = GstGui._sliderRects[def.key]
            if sr ~= nil and pointIn(posX, posY, sr[1], sr[2] - 0.005, sr[3], sr[4] + 0.010) then
                local norm = (posX - sr[1]) / sr[3]
                setSliderNorm(def, norm)
                GstGui.dragging = def
                return
            end
        end

        if def ~= nil then
            local lr = GstGui._valueLeftRects[def.key]
            local rr = GstGui._valueRightRects[def.key]
            if lr ~= nil and pointIn(posX, posY, lr[1], lr[2], lr[3], lr[4]) then
                changeValue(def, -1); return
            end
            if rr ~= nil and pointIn(posX, posY, rr[1], rr[2], rr[3], rr[4]) then
                changeValue(def,  1); return
            end
        end
    end
end

-- =========================================================
-- UPDATE
-- =========================================================
function GstGui.onUpdate(dt)
    if not GstGui.isOpen then return end
    if GstGui.flashFrames > 0 then GstGui.flashFrames = GstGui.flashFrames - 1 end
end

-- =========================================================
-- DRAW HELPERS
-- =========================================================
local function ensureBgOverlay()
    if GstGui.bgOverlay == nil then
        GstGui.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.png")
    end
    return GstGui.bgOverlay
end

local function drawRect(overlay, x, y, w, h, c)
    setOverlayColor(overlay, c[1], c[2], c[3], c[4])
    renderOverlay(overlay, x, y, w, h)
end

local function drawRectRGBA(overlay, x, y, w, h, r, g, b, a)
    setOverlayColor(overlay, r, g, b, a)
    renderOverlay(overlay, x, y, w, h)
end

local function drawOutline(overlay, x, y, w, h, c, t)
    t = t or 0.0012
    drawRect(overlay, x,         y,           w, t, c)
    drawRect(overlay, x,         y + h - t,   w, t, c)
    drawRect(overlay, x,         y,           t, h, c)
    drawRect(overlay, x + w - t, y,           t, h, c)
end

-- =========================================================
-- DRAW: header
-- =========================================================
local function drawHeader(overlay)
    local x, y, w, h = L.dialogX, L.dialogY + L.dialogH - L.headerH, L.dialogW, L.headerH
    drawRect(overlay, x, y, w, h, C.headerBg)
    drawRect(overlay, x, y, w, 0.0025, C.headerLine)

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setColor(C.txtPrimary)
    renderText(x + L.padX, y + h * 0.50 - 0.005, 0.0235, "GLOBAL SUSPENSION TUNER")

    setTextBold(false)
    setColor(C.txtSecond)
    renderText(x + L.padX + 0.255, y + h * 0.50, 0.0135,
        "Globale Federungs-Anpassung fuer alle Fahrzeuge")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setColor(C.txtAccent)
    renderText(x + w - L.padX, y + h * 0.50 - 0.003, 0.0135, "v0.3.0.0")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setColor(C.txtSecond)
    renderText(x + w - L.padX, y + h * 0.50 - 0.022, 0.0115,
        "Profil:  " .. (GstGui.PRESET_LABELS[GstGui.activePreset] or GstGui.activePreset))
end

-- =========================================================
-- DRAW: tabs
-- =========================================================
local function drawTabs(overlay)
    GstGui._tabRects = {}
    local barY = L.dialogY + L.dialogH - L.headerH - L.tabH
    local barX = L.dialogX
    local barW = L.dialogW
    local barH = L.tabH

    drawRect(overlay, barX, barY, barW, barH, C.tabBg)

    local n = #GstGui.TABS
    local tabW = barW / n
    for i, tab in ipairs(GstGui.TABS) do
        local tx = barX + (i - 1) * tabW
        local active = (i == GstGui.activeTab)
        local hover  = (i == GstGui.hoverTab)

        if active then
            drawRect(overlay, tx, barY, tabW, barH, C.tabActiveBg)
            drawRect(overlay, tx, barY, tabW, 0.0028, C.tabUnderline)
        elseif hover then
            drawRect(overlay, tx, barY, tabW, barH, C.tabHover)
        end

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(active)
        if active or hover then setColor(C.txtPrimary) else setColor(C.txtSecond) end
        renderText(tx + tabW * 0.5, barY + barH * 0.34, 0.0165, tab.label)
        GstGui._tabRects[i] = { tx, barY, tabW, barH }
    end
    setTextBold(false)
end

-- =========================================================
-- DRAW: settings list
-- =========================================================
local function drawList(overlay)
    GstGui._rowRects        = {}
    GstGui._sliderRects     = {}
    GstGui._valueLeftRects  = {}
    GstGui._valueRightRects = {}

    local items = currentItems()
    local idx   = GstGui.selectedIdx

    local listX   = L.dialogX
    local listW   = L.dialogW * L.leftRatio
    local listTop = L.dialogY + L.dialogH - L.headerH - L.tabH
    local listBot = L.dialogY + L.footerH
    local listH   = listTop - listBot

    drawRect(overlay, listX, listBot, listW, listH, C.panelInner)

    local rowH = L.rowH
    local startY = listTop - L.padY - rowH
    local labelX = listX + L.padX
    local rowRight = listX + listW - L.padX

    for i, def in ipairs(items) do
        local y = startY - (i - 1) * rowH
        local isSelected = (i == idx)
        local isHover    = (i == GstGui.hoverRow)

        local rrX = listX + 0.005
        local rrY = y - 0.004
        local rrW = listW - 0.010
        local rrH = rowH - 0.006

        if isSelected then
            drawRect(overlay, rrX, rrY, rrW, rrH, C.rowSelected)
            drawRect(overlay, rrX, rrY, 0.004, rrH, C.rowAccent)
        elseif isHover then
            drawRect(overlay, rrX, rrY, rrW, rrH, C.rowHover)
        else
            drawRect(overlay, rrX, rrY, rrW, rrH, C.rowBg)
        end
        GstGui._rowRects[i] = { rrX, rrY, rrW, rrH }

        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(isSelected)
        if isSelected or isHover then setColor(C.txtPrimary) else setColor(C.txtSecond) end
        renderText(labelX + 0.006, y + 0.029, 0.0155, def.label)
        setTextBold(false)

        local val = getValue(def)
        local valStr = formatItem(def, val)

        if def.type == "float" and def.range ~= nil and val ~= nil then
            local sliderX = labelX + 0.006
            local sliderY = y + 0.012
            local sliderW = (rowRight - sliderX) - 0.115
            local sliderH = 0.005
            if sliderW > 0.06 then
                local norm = (val - def.range[1]) / (def.range[2] - def.range[1])
                norm = clamp(norm, 0, 1)
                drawRect(overlay, sliderX, sliderY, sliderW, sliderH, C.sliderTrack)
                local fillCol = isSelected and C.sliderFill or C.sliderFillD
                drawRect(overlay, sliderX, sliderY, sliderW * norm, sliderH, fillCol)
                local knobW = 0.006
                local knobH = sliderH + 0.008
                drawRect(overlay,
                    sliderX + sliderW * norm - knobW * 0.5,
                    sliderY - 0.0015, knobW, knobH, C.sliderKnob)
                GstGui._sliderRects[def.key] = { sliderX, sliderY, sliderW, sliderH }
            end
        end

        local origVal
        if def.type ~= "preset" and GstGui.originalSnap ~= nil then
            origVal = flatGet(GstGui.originalSnap, def.key)
        end
        local isChanged = (origVal ~= nil and val ~= nil and math.abs(val - origVal) > 1e-6)

        setTextAlignment(RenderText.ALIGN_RIGHT)
        if isChanged then setColor(C.txtChanged)
        elseif isSelected then setColor(C.txtAccent)
        else setColor(C.txtOk) end

        local valY = y + 0.029
        renderText(rowRight, valY, 0.0155, valStr)

        local valW = #valStr * 0.0085
        if valW < 0.04 then valW = 0.04 end
        local rightArrowX = rowRight - valW - 0.012
        local leftArrowX  = rowRight - valW - 0.012 - 0.030

        if isSelected then
            setColor(C.txtAccent)
            renderText(rightArrowX + 0.020, valY, 0.018, ">")
            setTextAlignment(RenderText.ALIGN_LEFT)
            renderText(leftArrowX, valY, 0.018, "<")

            local hitW = 0.018
            local hitH = 0.026
            local hitY = y + 0.014
            GstGui._valueLeftRects[def.key]  = { leftArrowX - 0.002,            hitY, hitW, hitH }
            GstGui._valueRightRects[def.key] = { rightArrowX + 0.020 - hitW*0.5, hitY, hitW, hitH }
        end
    end

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- DRAW: right panel (summary + help)
-- =========================================================
local function drawRightPanel(overlay)
    local rx = L.dialogX + L.dialogW * L.leftRatio
    local rw = L.dialogW * (1 - L.leftRatio)
    local rTop = L.dialogY + L.dialogH - L.headerH - L.tabH
    local rBot = L.dialogY + L.footerH

    drawRect(overlay, rx, rBot, rw, rTop - rBot, C.panelInner)
    drawRect(overlay, rx, rBot, 0.0015, rTop - rBot, C.divider)

    local pad = L.padX

    -- Section: snapshot summary
    local hdrY = rTop - L.padY - 0.018
    setTextBold(true)
    setColor(C.txtAccent)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(rx + pad, hdrY, 0.0125, "UEBERSICHT")
    setTextBold(false)

    local lines = {
        { "Kabine",  string.format("%.0f kg / Fed %.0f", flatGet(GstGui.tempValues, "cab.weight") or 0, flatGet(GstGui.tempValues, "cab.springX") or 0) },
        { "Sitz",    string.format("%.0f kg / Fed %.1f", flatGet(GstGui.tempValues, "seat.weight") or 0, flatGet(GstGui.tempValues, "seat.springY") or 0) },
        { "Torso",   string.format("%.0f kg / Fed %.1f", flatGet(GstGui.tempValues, "torso.weight") or 0, flatGet(GstGui.tempValues, "torso.springY") or 0) },
        { "Raeder",  string.format("%.2fx Feder / %.2fx Daempf.",
            flatGet(GstGui.tempValues, "wheels.springMultiplier") or 0,
            flatGet(GstGui.tempValues, "wheels.damperMultiplier") or 0) },
        { "Federweg",string.format("%.2fx (max %.2f m)",
            flatGet(GstGui.tempValues, "wheels.suspTravelScale") or 0,
            flatGet(GstGui.tempValues, "wheels.suspTravelMax")   or 0) },
    }

    local lineY = hdrY - 0.030
    for _, ln in ipairs(lines) do
        setColor(C.txtSecond)
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(rx + pad, lineY, 0.0118, ln[1])
        setColor(C.txtPrimary)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        renderText(rx + rw - pad, lineY, 0.0118, ln[2])
        lineY = lineY - 0.020
    end

    -- Help card pinned to bottom
    local helpCardTop = rBot + 0.150
    local helpCardBot = rBot + 0.012
    drawRect(overlay, rx + 0.001, helpCardBot, rw - 0.002, helpCardTop - helpCardBot, C.panelBg)
    drawRect(overlay, rx + pad, helpCardTop - 0.0014, rw - pad * 2, 0.0014, C.headerLine)

    setColor(C.txtAccent)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(rx + pad, helpCardTop - 0.020, 0.0125, "ERLAEUTERUNG")
    setTextBold(false)

    local def = currentItem()
    if def ~= nil then
        setColor(C.txtPrimary)
        setTextBold(true)
        renderText(rx + pad, helpCardTop - 0.040, 0.0140, def.label)
        setTextBold(false)
        setColor(C.txtSecond)

        local helpText = def.help or ""
        local maxLine = 42
        local cursor = 1
        local ly = helpCardTop - 0.058
        while cursor <= #helpText do
            local stop = math.min(cursor + maxLine - 1, #helpText)
            if stop < #helpText then
                local space = helpText:sub(cursor, stop):match(".*() ")
                if space and space > 10 then stop = cursor + space - 2 end
            end
            renderText(rx + pad, ly, 0.0115, helpText:sub(cursor, stop))
            ly = ly - 0.015
            cursor = stop + 2
            if ly < helpCardBot + 0.008 then break end
        end
    end
end

-- =========================================================
-- DRAW: footer
-- =========================================================
local function drawFooterButton(overlay, idx, x, y, w, h, label, baseCol, hoverCol)
    local hover = (idx == GstGui.hoverFooter)
    drawRect(overlay, x, y, w, h, hover and hoverCol or baseCol)
    drawOutline(overlay, x, y, w, h, C.divider)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setColor(C.txtPrimary)
    renderText(x + w * 0.5, y + h * 0.30, 0.0135, label)
    setTextBold(false)
    GstGui._footerRects[idx] = { x, y, w, h }
end

local function drawFooter(overlay)
    GstGui._footerRects = {}
    local fx = L.dialogX
    local fy = L.dialogY
    local fw = L.dialogW
    local fh = L.footerH

    drawRect(overlay, fx, fy, fw, fh, C.headerBg)
    drawRect(overlay, fx, fy + fh, fw, 0.0018, C.divider)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setColor(C.txtMuted)
    setTextBold(false)
    renderText(fx + L.padX, fy + fh * 0.62, 0.0115,
        "[Tab] Kategorie   [Pfeile] Wert   [P] Profil   [F1] Reset Wert   [F5] Alle")

    local btnH = fh - 0.018
    local btnY = fy + 0.009
    local btnW = 0.110
    local gap  = 0.008
    local saveX   = fx + fw - L.padX - btnW
    local cancelX = saveX - gap - btnW
    local resetX  = cancelX - gap - btnW

    drawFooterButton(overlay, 3, resetX,  btnY, btnW, btnH, "Zuruecksetzen", C.btnBg,       C.btnBgHover)
    drawFooterButton(overlay, 2, cancelX, btnY, btnW, btnH, "Abbrechen",     C.btnCancelBg, C.btnCancelBgH)
    drawFooterButton(overlay, 1, saveX,   btnY, btnW, btnH, "Speichern",     C.btnSaveBg,   C.btnSaveBgH)
end

-- =========================================================
-- DRAW: master
-- =========================================================
function GstGui.onDraw()
    if not GstGui.isOpen then return end
    local overlay = ensureBgOverlay()
    if overlay == nil or overlay == 0 then
        setColor(C.txtPrimary)
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(0.5, 0.5, 0.02, "Suspension Tuner: Overlay nicht verfuegbar")
        return
    end

    drawRect(overlay, 0, 0, 1, 1, C.dim)
    drawRect(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, C.panelBg)
    drawOutline(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, C.panelEdge, 0.0014)

    drawHeader(overlay)
    drawTabs(overlay)
    drawList(overlay)
    drawRightPanel(overlay)
    drawFooter(overlay)

    if GstGui.flashFrames > 0 and GstGui.flashColor ~= nil then
        local a = GstGui.flashFrames / 12 * 0.18
        local c = GstGui.flashColor
        drawRectRGBA(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, c[1], c[2], c[3], a)
    end

    setColor(C.txtPrimary)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function GstGui.destroy()
    if GstGui.bgOverlay ~= nil and GstGui.bgOverlay ~= 0 then
        delete(GstGui.bgOverlay)
        GstGui.bgOverlay = nil
    end
end
