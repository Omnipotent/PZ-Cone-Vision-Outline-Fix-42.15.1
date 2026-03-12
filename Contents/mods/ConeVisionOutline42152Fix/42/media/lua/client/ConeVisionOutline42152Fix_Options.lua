-- Mod options for Cone Vision Outline (42.15.2 Fix) (Settings -> Mods).
-- Color and intensity (alpha) for cone outline (zombies/animals in vision cone).
local MODULE_ID = "ConeVisionOutline42152Fix"

ConeVisionOutline42152FixOptions = ConeVisionOutline42152FixOptions or {}
ConeVisionOutline42152FixOptions.ConeOutlineColor = { r = 1, g = 1, b = 1 }  -- RGB from color picker
ConeVisionOutline42152FixOptions.ConeOutlineAlpha = 0.3  -- intensity 0..1 from slider
ConeVisionOutline42152FixOptions.ScaleOutlineByLight = false  -- scale outline alpha by square light level
ConeVisionOutline42152FixOptions.VehicleOutlineAlwaysOn = false  -- in vehicle: show outlines without holding RMB

local PZOptions

local function applyOptions()
    if not PZAPI or not PZAPI.ModOptions then return end
    local options = PZAPI.ModOptions:getOptions(MODULE_ID)
    if options then
        local optColor = options:getOption("ConeOutlineColor")
        if optColor then
            ConeVisionOutline42152FixOptions.ConeOutlineColor = optColor:getValue()
        end
        local optAlpha = options:getOption("ConeOutlineAlpha")
        if optAlpha then
            ConeVisionOutline42152FixOptions.ConeOutlineAlpha = optAlpha:getValue()
        end
        local optScaleLight = options:getOption("ScaleOutlineByLight")
        if optScaleLight then
            ConeVisionOutline42152FixOptions.ScaleOutlineByLight = optScaleLight:getValue()
        end
        local optVehicleAlways = options:getOption("VehicleOutlineAlwaysOn")
        if optVehicleAlways then
            ConeVisionOutline42152FixOptions.VehicleOutlineAlwaysOn = optVehicleAlways:getValue()
        end
    end
end

local function initConfig()
    if not PZAPI or not PZAPI.ModOptions then return end
    PZOptions = PZAPI.ModOptions:create(MODULE_ID, getText("UI_CVO_Options_Title"))

    local p = ConeVisionOutline42152FixOptions.ConeOutlineColor
    PZOptions:addColorPicker(
        "ConeOutlineColor",
        getText("UI_CVO_Options_ConeOutlineColor"),
        p.r or 1, p.g or 1, p.b or 1, 1,
        getText("UI_CVO_Options_ConeOutlineColor_Tooltip")
    )
    PZOptions:addSlider(
        "ConeOutlineAlpha",
        getText("UI_CVO_Options_ConeOutlineAlpha"),
        0, 1, 0.05,
        ConeVisionOutline42152FixOptions.ConeOutlineAlpha,
        getText("UI_CVO_Options_ConeOutlineAlpha_Tooltip")
    )
    PZOptions:addTickBox(
        "ScaleOutlineByLight",
        getText("UI_CVO_Options_ScaleOutlineByLight"),
        ConeVisionOutline42152FixOptions.ScaleOutlineByLight,
        getText("UI_CVO_Options_ScaleOutlineByLight_Tooltip")
    )
    PZOptions:addTickBox(
        "VehicleOutlineAlwaysOn",
        getText("UI_CVO_Options_VehicleOutlineAlwaysOn"),
        ConeVisionOutline42152FixOptions.VehicleOutlineAlwaysOn,
        getText("UI_CVO_Options_VehicleOutlineAlwaysOn_Tooltip")
    )

    PZOptions.apply = function()
        applyOptions()
    end
end

initConfig()

Events.OnMainMenuEnter.Add(function()
    applyOptions()
end)

Events.OnGameStart.Add(function()
    applyOptions()
end)

return ConeVisionOutline42152FixOptions
