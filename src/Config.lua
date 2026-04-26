--
-- GlobalSuspensionTuner / Config
--
-- Reads / writes  <userProfile>/modSettings/FS25_GlobalSuspensionTuner.xml.
-- Values for cab, seat, character torso and wheel suspension can be tuned
-- globally in <defaults>; per-vehicle overrides go into <vehicle> blocks.
-- Loaded vehicles register themselves automatically so they can be edited
-- afterwards.
--
-- Public API:
--   GstConfig.setModDirectory(dir)
--   GstConfig.ensureLoaded()
--   GstConfig.getProfileFor(configFileName) -> profile table
--   GstConfig.flushIfDirty()
--

GstConfig = {}

GstConfig._loaded = false
GstConfig._defaults = nil
GstConfig._vehicles = {}
GstConfig._dirty = false
GstConfig._modDirectory = nil

-- --- Schema --------------------------------------------------------------
--
-- Single source of truth for every attribute the mod understands. The XML
-- reader, writer, fallback table and merge logic all derive from this list.
-- Adding a new attribute means adding a single line here.
--

local NUM, TRIPLE = "num", "triple"

local BLOCKS = {
    {
        tag = "cab",
        attrs = {
            { name = "weight",      type = NUM },
            { name = "minRotation", type = TRIPLE },
            { name = "maxRotation", type = TRIPLE },
            { name = "springX",     type = NUM },
            { name = "damperX",     type = NUM },
        },
    },
    {
        tag = "seat",
        attrs = {
            { name = "weight",         type = NUM },
            { name = "minTranslation", type = TRIPLE },
            { name = "maxTranslation", type = TRIPLE },
            { name = "springY",        type = NUM },
            { name = "damperY",        type = NUM },
        },
    },
    {
        tag = "torso",
        attrs = {
            { name = "weight",      type = NUM },
            { name = "minRotation", type = TRIPLE },
            { name = "maxRotation", type = TRIPLE },
            { name = "springY",     type = NUM },
            { name = "damperY",     type = NUM },
            { name = "springZ",     type = NUM },
            { name = "damperZ",     type = NUM },
        },
    },
    {
        tag = "wheels",
        attrs = {
            { name = "suspTravelScale",  type = NUM },
            { name = "suspTravelMax",    type = NUM },
            { name = "springMultiplier", type = NUM },
            { name = "damperMultiplier", type = NUM },
        },
    },
}

-- --- Built-in fallback defaults -----------------------------------------
--
-- Used when the user file can't be read at all. Also written into the
-- file on first run.
--

local FALLBACK = {
    cab = {
        weight = 800,
        minRotation = { -2.26, 0, 0 },
        maxRotation = {  2.26, 0, 0 },
        springX = 60, damperX = 6,
    },
    seat = {
        weight = 300,
        minTranslation = { 0, -0.30, 0 },
        maxTranslation = { 0,  0.30, 0 },
        springY = 6, damperY = 0.9,
    },
    torso = {
        weight = 160,
        minRotation = { 0, -8, -8 },
        maxRotation = { 0,  8,  8 },
        springY = 5, damperY = 0.7,
        springZ = 5, damperZ = 0.7,
    },
    wheels = {
        suspTravelScale  = 1.5,
        suspTravelMax    = 0.30,
        springMultiplier = 0.3,
        damperMultiplier = 0.3,
    },
}

-- --- Logging / parsing helpers ------------------------------------------

local function clog(fmt, ...)
    print("[GlobalSuspensionTuner/Config] " .. string.format(fmt, ...))
end

local function parseTriple(s)
    if s == nil then return nil end
    local a, b, c = string.match(s, "(%S+)%s+(%S+)%s+(%S+)")
    if a == nil then return nil end
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function fmtNum(v)
    if v == nil then return nil end
    if math.floor(v) == v and math.abs(v) < 1e9 then
        return tostring(math.floor(v))
    end
    return string.format("%.4g", v)
end

local function fmtTriple(t)
    if t == nil then return nil end
    return string.format("%s %s %s",
        fmtNum(t[1]) or "0", fmtNum(t[2]) or "0", fmtNum(t[3]) or "0")
end

local function shortenMatch(configFileName)
    if configFileName == nil then return nil end
    if configFileName:find("^data/") ~= nil then return configFileName end
    local idx = configFileName:find("/mods/")
    if idx ~= nil then return configFileName:sub(idx + 1) end
    return configFileName
end

-- --- Generic block reader / serializer ----------------------------------

local function readBlock(xmlFile, baseKey, attrs)
    local t = {}
    for _, a in ipairs(attrs) do
        local raw = xmlFile:getString(baseKey .. "#" .. a.name)
        if raw ~= nil then
            if a.type == NUM then
                t[a.name] = tonumber(raw)
            elseif a.type == TRIPLE then
                t[a.name] = parseTriple(raw)
            end
        end
    end
    if next(t) == nil then return nil end
    return t
end

local function serializeBlock(t, block, indent)
    if t == nil then return nil end

    local parts = {}
    for _, a in ipairs(block.attrs) do
        local v = t[a.name]
        if v ~= nil then
            local str
            if a.type == NUM then
                str = fmtNum(v)
            elseif a.type == TRIPLE then
                str = fmtTriple(v)
            end
            if str ~= nil then
                parts[#parts + 1] = string.format('%s="%s"', a.name, str)
            end
        end
    end

    if #parts == 0 then return nil end
    return indent .. "<" .. block.tag .. " " .. table.concat(parts, " ") .. "/>"
end

-- --- Default-XML written on first run -----------------------------------
--
-- Initial template only - on first auto-discovery saveAll() rewrites the
-- file in canonical form (with all attributes shown).
--

local DEFAULT_XML = [[<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<globalSuspensionTuner>
    <!--
        FS25 Global Suspension Tuner config

        - <defaults> applies to every vehicle.
        - Every loaded vehicle (vanilla + mod) auto-registers below as a
          <vehicle match="..." enabled="true"/> entry. Edit attributes to
          override per vehicle, set enabled="false" to skip a vehicle.
        - 'match' is a substring search inside the vehicle's configFileName.
          Shorten it to match families (e.g. "fendt/vario1000").

        Units: rotation in degrees, translation in meters.
    -->

    <defaults>
        <cab    weight="800"  minRotation="-2.26 0 0" maxRotation="2.26 0 0" springX="60" damperX="6"/>
        <seat   weight="300"  minTranslation="0 -0.3 0" maxTranslation="0 0.3 0" springY="6" damperY="0.9"/>
        <torso  weight="160"  minRotation="0 -8 -8" maxRotation="0 8 8" springY="5" damperY="0.7" springZ="5" damperZ="0.7"/>
        <wheels suspTravelScale="1.5" suspTravelMax="0.3" springMultiplier="0.3" damperMultiplier="0.3"/>
    </defaults>

</globalSuspensionTuner>
]]

-- --- File paths / write helpers -----------------------------------------

local function getUserConfigPath()
    return getUserProfileAppPath() .. "modSettings/FS25_GlobalSuspensionTuner.xml"
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if f == nil then return false, "open failed" end
    f:write(content)
    f:close()
    return true
end

local function ensureUserConfigExists()
    local path = getUserConfigPath()
    if fileExists(path) then return path end

    local dir = getUserProfileAppPath() .. "modSettings"
    if not fileExists(dir) then createFolder(dir) end

    local ok, err = writeFile(path, DEFAULT_XML)
    if not ok then
        clog("WARN could not write default config (%s)", tostring(err))
        return nil
    end

    clog("created default config at %s", path)
    return path
end

-- --- Public: setModDirectory --------------------------------------------

function GstConfig.setModDirectory(dir)
    GstConfig._modDirectory = dir
end

-- --- Load ----------------------------------------------------------------

local function findBlock(tag)
    for _, b in ipairs(BLOCKS) do
        if b.tag == tag then return b end
    end
    return nil
end

function GstConfig.ensureLoaded()
    if GstConfig._loaded then return end
    GstConfig._loaded = true

    local path = ensureUserConfigExists()
    if path == nil then
        GstConfig._defaults = FALLBACK
        return
    end

    local xmlFile = XMLFile.load("globalSuspensionTuner", path)
    if xmlFile == nil then
        clog("WARN could not load %s - using built-in fallback", path)
        GstConfig._defaults = FALLBACK
        return
    end

    -- Defaults: start from FALLBACK, overlay anything the user has set.
    local defaults = {}
    for _, b in ipairs(BLOCKS) do
        defaults[b.tag] = {}
        for k, v in pairs(FALLBACK[b.tag]) do defaults[b.tag][k] = v end

        local userBlock = readBlock(xmlFile, "globalSuspensionTuner.defaults." .. b.tag, b.attrs)
        if userBlock ~= nil then
            for k, v in pairs(userBlock) do defaults[b.tag][k] = v end
        end
    end
    GstConfig._defaults = defaults

    -- Per-vehicle overrides
    GstConfig._vehicles = {}
    local i = 0
    while true do
        local key = string.format("globalSuspensionTuner.vehicle(%d)", i)
        if not xmlFile:hasProperty(key) then break end

        local entry = {
            match   = xmlFile:getString(key .. "#match"),
            enabled = (xmlFile:getString(key .. "#enabled") or "true"):lower() ~= "false",
        }
        for _, b in ipairs(BLOCKS) do
            entry[b.tag] = readBlock(xmlFile, key .. "." .. b.tag, b.attrs)
        end

        if entry.match ~= nil and entry.match ~= "" then
            table.insert(GstConfig._vehicles, entry)
        else
            clog("WARN vehicle entry #%d has no match attribute - skipped", i)
        end
        i = i + 1
    end

    xmlFile:delete()
    clog("loaded - %d vehicle override(s)", #GstConfig._vehicles)
end

-- --- Save ---------------------------------------------------------------

local HEADER = [[<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<globalSuspensionTuner>
    <!--
        FS25 Global Suspension Tuner config

        - <defaults> applies to every vehicle. Edit attribute values to
          change the global feel.
        - Each loaded vehicle (vanilla + mod) auto-registers as a <vehicle>
          entry below. Add per-vehicle overrides as attributes; missing
          attributes inherit from <defaults>.
          Set enabled="false" to skip a vehicle entirely.
        - The 'match' string is a substring search inside configFileName.
          Shorten it (e.g. "fendt/vario1000") to match several variants -
          first matching entry wins.

        Units: rotation in degrees, translation in meters.
    -->

]]

local FOOTER = "</globalSuspensionTuner>\n"

local function serializeVehicle(entry)
    local rootAttrs = string.format('match="%s" enabled="%s"',
        entry.match,
        (entry.enabled == false) and "false" or "true")

    local children = {}
    for _, b in ipairs(BLOCKS) do
        local line = serializeBlock(entry[b.tag], b, "        ")
        if line ~= nil then children[#children + 1] = line end
    end

    if #children == 0 then
        return "    <vehicle " .. rootAttrs .. "/>"
    end

    local out = { "    <vehicle " .. rootAttrs .. ">" }
    for _, c in ipairs(children) do out[#out + 1] = c end
    out[#out + 1] = "    </vehicle>"
    return table.concat(out, "\n")
end

local function serializeAll()
    local out = { HEADER }

    out[#out + 1] = "    <defaults>"
    for _, b in ipairs(BLOCKS) do
        out[#out + 1] = serializeBlock(GstConfig._defaults[b.tag], b, "        ")
            or ("        <" .. b.tag .. "/>")
    end
    out[#out + 1] = "    </defaults>"
    out[#out + 1] = ""

    if #GstConfig._vehicles > 0 then
        out[#out + 1] = "    <!-- Auto-discovered vehicles - edit attributes below to override per vehicle -->"
        for _, entry in ipairs(GstConfig._vehicles) do
            out[#out + 1] = serializeVehicle(entry)
        end
        out[#out + 1] = ""
    end

    out[#out + 1] = FOOTER
    return table.concat(out, "\n")
end

local function saveNow()
    local ok, err = writeFile(getUserConfigPath(), serializeAll())
    if not ok then
        clog("WARN saveNow failed (%s)", tostring(err))
        return false
    end
    return true
end

function GstConfig.flushIfDirty()
    if not GstConfig._dirty then return end
    if saveNow() then
        GstConfig._dirty = false
    end
end

-- --- Override matching / auto-discovery ---------------------------------

local function findOverride(configFileName)
    if configFileName == nil then return nil end
    for _, entry in ipairs(GstConfig._vehicles) do
        if entry.match ~= nil and entry.match ~= ""
            and string.find(configFileName, entry.match, 1, true)
        then
            return entry
        end
    end
    return nil
end

local function recordNewVehicle(configFileName)
    local match = shortenMatch(configFileName)
    if match == nil or match == "" then return end

    for _, e in ipairs(GstConfig._vehicles) do
        if e.match == match then return end
    end

    table.insert(GstConfig._vehicles, { match = match, enabled = true })
    GstConfig._dirty = true
end

local function mergeBlock(defaultsBlock, overrideBlock)
    if overrideBlock == nil then return defaultsBlock end
    local out = {}
    for k, v in pairs(defaultsBlock) do out[k] = v end
    for k, v in pairs(overrideBlock) do out[k] = v end
    return out
end

function GstConfig.getProfileFor(configFileName)
    GstConfig.ensureLoaded()

    local defaults = GstConfig._defaults or FALLBACK
    local override = findOverride(configFileName)

    if override == nil then
        recordNewVehicle(configFileName)
        GstConfig.flushIfDirty()
    end

    if override ~= nil and override.enabled == false then
        return { enabled = false }
    end

    local profile = { enabled = true }
    for _, b in ipairs(BLOCKS) do
        profile[b.tag] = mergeBlock(defaults[b.tag], override and override[b.tag] or nil)
    end
    profile._matched = override and override.match or nil
    return profile
end
