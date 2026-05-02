--
-- FS25 Global Suspension Tuner
-- Bootstraps the spec by attaching it to every vehicle type that has either
-- the Suspensions or the Wheels specialization.
--

local modName = g_currentModName or "FS25_GlobalSuspensionTuner"
local modDirectory = g_currentModDirectory or ""

print(string.format("[GlobalSuspensionTuner] main.lua sourced (modName=%s)", tostring(modName)))

source(modDirectory .. "src/Config.lua")
source(modDirectory .. "src/GlobalSuspensionTunerGui.lua")
GstConfig.setModDirectory(modDirectory)

-- =========================================================
-- GUI listener (global - hotkey Shift+G opens settings)
-- =========================================================
local GstListener = {}

function GstListener:loadMap(name)
    GstConfig.ensureLoaded()
end
function GstListener:deleteMap()
    GstGui.close(false)
    GstGui.destroy()
end
function GstListener:update(dt)     GstGui.onUpdate(dt) end
function GstListener:draw()         GstGui.onDraw() end

function GstListener:keyEvent(unicode, sym, modifier, isDown)
    GstGui.onKeyEvent(unicode, sym, modifier, isDown)
end

function GstListener:mouseEvent(posX, posY, isDown, isUp, button)
    GstGui.onMouseEvent(posX, posY, isDown, isUp, button)
end

addModEventListener(GstListener)

local function attachSpec(typeManager)
    if not g_modIsLoaded[modName] then return end
    if typeManager.typeName ~= "vehicle" then return end

    local fullSpecName = modName .. ".globalSuspensionTuner"
    local attached = 0

    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        local hasSuspensions = Suspensions ~= nil
            and SpecializationUtil.hasSpecialization(Suspensions, typeEntry.specializations)
        local hasWheels = Wheels ~= nil
            and SpecializationUtil.hasSpecialization(Wheels, typeEntry.specializations)

        if hasSuspensions or hasWheels then
            typeManager:addSpecialization(typeName, fullSpecName)
            attached = attached + 1
        end
    end

    print(string.format("[GlobalSuspensionTuner] spec attached to %d vehicle types", attached))
end

TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, attachSpec)
