--
-- GlobalSuspensionTuner specialization
--
-- Step 1: globally rewrites cab + seat + character-torso suspension data
-- after Suspensions:onLoad has populated spec_suspensions.suspensionNodes.
--
-- Step 2: globally softens wheel suspension via WheelPhysics.setSuspensionMultipliers
-- and stretches suspTravel.
--
-- Reference values are taken from FS25_FendtFavorit800_900Series_Physik
-- ("Sehr weich" profile).
--
-- Why this works without an engine call:
--   Suspensions:onUpdate (dataS/scripts/vehicles/specializations/Suspensions.lua)
--   reads suspensionParameters / weight / minRotation / maxRotation /
--   minTranslation / maxTranslation directly from spec.suspensionNodes
--   every physics tick. So mutating those fields takes effect immediately.
--
--   suspensionParameters[i][j] are stored * 1000 by the loader, so we apply
--   the same scale here.
--

GlobalSuspensionTuner = {}

-- --- Step 1 config: cab / seat / torso -----------------------------------

-- All tunable values now live in modSettings/FS25_GlobalSuspensionTuner.xml
-- (auto-created from config_default.xml on first run). The spec asks
-- GstConfig for a per-vehicle profile in onPostLoad.

GlobalSuspensionTuner.DEBUG = true

-- --- Internal helpers ----------------------------------------------------

local DEG_TO_RAD = math.pi / 180

local function ilog(fmt, ...)
    print("[GlobalSuspensionTuner] " .. string.format(fmt, ...))
end

local function dlog(fmt, ...)
    if GlobalSuspensionTuner.DEBUG then
        ilog(fmt, ...)
    end
end

local function deg2rad3(t)
    return { t[1] * DEG_TO_RAD, t[2] * DEG_TO_RAD, t[3] * DEG_TO_RAD }
end

local function getNodeName(nodeId)
    if nodeId == nil or nodeId == 0 then return "" end
    local ok, name = pcall(getName, nodeId)
    if ok and name ~= nil then return name end
    return ""
end

-- Identify cab / seat / torso suspension entries based on the data the
-- vanilla loader places into spec.suspensionNodes.
local function classify(sn)
    if sn.useCharacterTorso == true then
        return "torso"
    end

    local nodeName = getNodeName(sn.node):lower()
    if nodeName == "" then return nil end

    if nodeName:find("seat", 1, true) then
        return "seat"
    end
    if nodeName:find("cabin", 1, true) or nodeName == "cab" or nodeName:find("^cab[_%-]") then
        return "cab"
    end
    return nil
end

local function setParam(sn, axis, pair)
    if sn.suspensionParameters == nil or pair == nil then return end
    local row = sn.suspensionParameters[axis]
    if row == nil then return end
    row[1] = pair[1] * 1000
    row[2] = pair[2] * 1000
end

-- --- Tuning steps --------------------------------------------------------

local function tuneCab(sn, cfg)
    if cfg == nil then return end
    if cfg.weight ~= nil then sn.weight = cfg.weight end
    if sn.isRotational then
        if cfg.minRotation ~= nil then sn.minRotation = deg2rad3(cfg.minRotation) end
        if cfg.maxRotation ~= nil then sn.maxRotation = deg2rad3(cfg.maxRotation) end
    end
    if cfg.springX ~= nil and cfg.damperX ~= nil then
        setParam(sn, 1, { cfg.springX, cfg.damperX })
    end
    dlog("  cab tuned (node=%s weight=%s)", getNodeName(sn.node), tostring(sn.weight))
end

local function tuneSeat(sn, cfg)
    if cfg == nil then return end
    if cfg.weight ~= nil then sn.weight = cfg.weight end
    if not sn.isRotational then
        if cfg.minTranslation ~= nil then
            sn.minTranslation = { cfg.minTranslation[1], cfg.minTranslation[2], cfg.minTranslation[3] }
        end
        if cfg.maxTranslation ~= nil then
            sn.maxTranslation = { cfg.maxTranslation[1], cfg.maxTranslation[2], cfg.maxTranslation[3] }
        end
    end
    if cfg.springY ~= nil and cfg.damperY ~= nil then
        setParam(sn, 2, { cfg.springY, cfg.damperY })
    end
    dlog("  seat tuned (node=%s weight=%s)", getNodeName(sn.node), tostring(sn.weight))
end

local function tuneTorso(sn, cfg)
    if cfg == nil then return end
    if cfg.weight ~= nil then sn.weight = cfg.weight end
    if cfg.minRotation ~= nil then sn.minRotation = deg2rad3(cfg.minRotation) end
    if cfg.maxRotation ~= nil then sn.maxRotation = deg2rad3(cfg.maxRotation) end
    sn.isRotational = true
    if cfg.springY ~= nil and cfg.damperY ~= nil then
        setParam(sn, 2, { cfg.springY, cfg.damperY })
    end
    if cfg.springZ ~= nil and cfg.damperZ ~= nil then
        setParam(sn, 3, { cfg.springZ, cfg.damperZ })
    end
    dlog("  torso tuned (weight=%s)", tostring(sn.weight))
end

local function tuneAllSuspensions(self, profile)
    local spec = self.spec_suspensions
    if spec == nil or not spec.suspensionAvailable or spec.suspensionNodes == nil then
        return 0
    end

    local count = 0
    for _, sn in ipairs(spec.suspensionNodes) do
        local role = classify(sn)
        if role == "cab" then tuneCab(sn, profile.cab); count = count + 1
        elseif role == "seat" then tuneSeat(sn, profile.seat); count = count + 1
        elseif role == "torso" then tuneTorso(sn, profile.torso); count = count + 1
        end
    end
    return count
end

local function tuneAllWheels(self, profile)
    local spec = self.spec_wheels
    if spec == nil or spec.wheels == nil then return 0 end

    local cfg = profile.wheels
    if cfg == nil then return 0 end

    local count = 0

    for _, wheel in ipairs(spec.wheels) do
        local phys = wheel.physics
        if phys ~= nil then
            if cfg.suspTravelScale ~= nil and type(phys.suspTravel) == "number" then
                local newTravel = phys.suspTravel * cfg.suspTravelScale
                if cfg.suspTravelMax ~= nil and newTravel > cfg.suspTravelMax then
                    newTravel = cfg.suspTravelMax
                end
                phys.suspTravel = newTravel
                phys.isPositionDirty = true
            end

            if type(phys.setSuspensionMultipliers) == "function"
                and cfg.springMultiplier ~= nil and cfg.damperMultiplier ~= nil
            then
                phys:setSuspensionMultipliers(cfg.springMultiplier, cfg.damperMultiplier)
            end

            count = count + 1
        end
    end
    return count
end

-- --- Specialization plumbing ---------------------------------------------

function GlobalSuspensionTuner.prerequisitesPresent(specializations)
    -- Either Suspensions or Wheels presence is enough; we noop on what's missing.
    return true
end

function GlobalSuspensionTuner.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", GlobalSuspensionTuner)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", GlobalSuspensionTuner)
end

function GlobalSuspensionTuner:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then return end
    if not isActiveForInputIgnoreSelection then return end
    local entered = self.getIsEntered ~= nil and self:getIsEntered()
    if not entered then return end

    if self._gstActionEvents == nil then self._gstActionEvents = {} end
    self:clearActionEventsTable(self._gstActionEvents)

    if InputAction.GST_OpenSettings == nil then return end
    local _, eventId = self:addActionEvent(self._gstActionEvents,
        InputAction.GST_OpenSettings, self, GlobalSuspensionTuner.onOpenSettings,
        false, true, false, true, nil)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end

function GlobalSuspensionTuner.onOpenSettings(self, actionName, inputValue, callbackState, isAnalog)
    if GstGui ~= nil and GstGui.isOpen then
        GstGui.close(false)
    elseif GstGui ~= nil then
        GstGui.open()
    end
end

function GlobalSuspensionTuner:onPostLoad(savegame)
    if not GlobalSuspensionTuner._loggedFirst then
        GlobalSuspensionTuner._loggedFirst = true
        ilog("first onPostLoad fired - hook is alive")
    end

    local profile = GstConfig.getProfileFor(self.configFileName)
    if not profile.enabled then
        dlog("skip %s (disabled in config)", tostring(self.configFileName))
        return
    end

    local cabSeatCount = tuneAllSuspensions(self, profile)
    local wheelCount = tuneAllWheels(self, profile)

    if cabSeatCount > 0 or wheelCount > 0 then
        local name = self.configFileName or "?"
        local matched = profile._matched and (" [match=" .. profile._matched .. "]") or ""
        ilog("tuned %s%s - cab/seat/torso=%d wheels=%d", tostring(name), matched, cabSeatCount, wheelCount)
    end
end

-- Public: re-apply current GstConfig profile to a single vehicle
function GlobalSuspensionTuner.retuneVehicle(vehicle)
    if vehicle == nil or vehicle.configFileName == nil then return end
    local profile = GstConfig.getProfileFor(vehicle.configFileName)
    if not profile.enabled then return end
    tuneAllSuspensions(vehicle, profile)
    tuneAllWheels(vehicle, profile)
end

-- Public: re-apply settings to every loaded vehicle (called by GUI on save)
function GlobalSuspensionTuner.retuneAll()
    if g_currentMission == nil then return 0 end
    local list = nil
    if g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
        list = g_currentMission.vehicleSystem.vehicles
    elseif g_currentMission.vehicles ~= nil then
        list = g_currentMission.vehicles
    end
    if list == nil then return 0 end

    local n = 0
    for _, v in pairs(list) do
        if v ~= nil and v.configFileName ~= nil then
            GlobalSuspensionTuner.retuneVehicle(v)
            n = n + 1
        end
    end
    ilog("retuneAll touched %d vehicle(s)", n)
    return n
end
