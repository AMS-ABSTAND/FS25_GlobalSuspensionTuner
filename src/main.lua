--
-- FS25 Global Suspension Tuner
-- Bootstraps the spec by attaching it to every vehicle type that has either
-- the Suspensions or the Wheels specialization.
--

local modName = g_currentModName or "FS25_GlobalSuspensionTuner"
local modDirectory = g_currentModDirectory or ""

print(string.format("[GlobalSuspensionTuner] main.lua sourced (modName=%s)", tostring(modName)))

source(modDirectory .. "src/Config.lua")
GstConfig.setModDirectory(modDirectory)

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
