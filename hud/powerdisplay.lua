local computer = require("computer")
local colors = require("lib.graphics.colors")
local ar = require("lib.graphics.ar")
local parser = require("lib.utils.parser")
local time = require("lib.utils.time")
local screen = require("lib.utils.screen")
local states = require("server.entities.states")

local powerDisplay = {}

local hudObjects = {}
local energyData = {
    intervalCounter = 1,
    readings = {},
    startTime = 0,
    endTime = 0,
    updateInterval = 500,
    energyPerTick = 0
}

local energyUnit = "EU"

function powerDisplay.changeColor(glasses, backgroundColor, primaryColor, accentColor)
    local graphics = require("lib.graphics.graphics")
    for i = 1, #hudObjects do
        if hudObjects[i].glasses ~= nil then
            if hudObjects[i].glasses.address == glasses then
                if backgroundColor ~= nil then
                    for j = 1, #hudObjects[i].static do
                        hudObjects[i].static[j].setColor(screen.toRGB(backgroundColor))
                    end
                end
                if primaryColor ~= nil then
                    hudObjects[i].dynamic.energyBar.setColor(screen.toRGB(primaryColor))
                    hudObjects[i].dynamic.currentEU.setColor(screen.toRGB(primaryColor))
                end
                if accentColor ~= nil then
                    hudObjects[i].dynamic.maxEU.setColor(screen.toRGB(accentColor))
                    hudObjects[i].dynamic.percentage.setColor(screen.toRGB(accentColor))
                    hudObjects[i].dynamic.filltime.setColor(screen.toRGB(accentColor))
                end
            end
        end
    end
end
--Scales: Small = 1, Normal = 2, Large = 3, Auto = 4x to 10x (Even)
--Glasses is a table of all glasses you want to dispaly the data on, with optional colour data.
--Glass table format {glassProxy, [{resolutionX, resolutionY}], [scale], [borderColor], [primaryColor], [accentColor], [width], [heigth]}
--Only the glass proxy is required, rest have default values.
function powerDisplay.widget(glasses, data)
    if data ~= nil then
    local currentEU = math.floor(data.storedEU)
    local maxEU = math.floor(data.EUCapacity)
    if maxEU < 0 then
        maxEU = math.abs(maxEU)
    end
    local percentage = math.min(currentEU/maxEU, 1.0)
    if percentage >= 0.999 then
        currentEU = maxEU
        percentage = 1.0
    end
    --Update I/O
    if energyData.intervalCounter == 1 then
        energyData.startTime = computer.uptime()
        energyData.readings[1] = currentEU
    end
    if energyData.intervalCounter < energyData.updateInterval then
        energyData.intervalCounter = energyData.intervalCounter + 1
    end
    if energyData.intervalCounter == energyData.updateInterval then
        energyData.endTime = computer.uptime()
        energyData.readings[2] = currentEU

        local ticks = math.ceil((energyData.endTime - energyData.startTime) * 20)
        energyData.energyPerTick = math.floor((energyData.readings[2] - energyData.readings[1])/ticks)
        energyData.intervalCounter = 1
    end
    if #hudObjects < #glasses then
        for i = 1, #glasses do
            if glasses[i][1] == nil then
                error("Must provide glass proxy for energy display.")
            end
            table.insert(hudObjects,  {
                static          = {},
                dynamic         = {},
                glasses         = glasses[i][1],
                resolution      = glasses[i][2] or {2560, 1440},
                scale           = glasses[i][3] or 3,
                borderColor     = glasses[i][4] or colors.darkGray,
                primaryColor    = glasses[i][5] or colors.electricBlue,
                accentColor     = glasses[i][6] or colors.magenta,
                width           = glasses[i][7] or 0,
                heigth          = glasses[i][8] or 29
            })
        end 
    end
    for i = 1, #hudObjects do
        if hudObjects[i].width == 0 then hudObjects[i].width = screen.size(hudObjects[i].resolution, hudObjects[i].scale)[1]/2 - 91 end
        local h = hudObjects[i].heigth
        local w = hudObjects[i].width
        local compact = w < 250
        local x = 0
        local y = screen.size(hudObjects[i].resolution, hudObjects[i].scale)[2] - h
        local hProgress = math.ceil(h * 0.4)
        local energyBarLength = w-4-hProgress
        local hDivisor = 3
        local hIO = h-hProgress-2*hDivisor-1
        if #hudObjects[i].static == 0 and #hudObjects[i].glasses ~= nil then
            local borderColor = hudObjects[i].borderColor
            local primaryColor = hudObjects[i].primaryColor
            local accentColor = hudObjects[i].accentColor
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y}, w, h, borderColor, 0.6))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y-2}, w, 5+hProgress, borderColor, 0.6))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y-4}, w, 2, borderColor, 0.5))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y-6}, w, 2, borderColor, 0.4))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y-8}, w, 2, borderColor, 0.3))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y-10}, w, 2, borderColor, 0.2))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y}, w, hDivisor, borderColor))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y+hDivisor+hProgress}, w, hDivisor, borderColor))
            table.insert(hudObjects[i].static, ar.rectangle(hudObjects[i].glasses, {x, y+h-1}, w, 1, borderColor))
            table.insert(hudObjects[i].static, ar.quad(hudObjects[i].glasses, {x, y+hDivisor}, {x, y+hDivisor+hProgress}, {x+3+hProgress, y+hDivisor+hProgress}, {x+3, y+hDivisor}, borderColor))
            table.insert(hudObjects[i].static, ar.quad(hudObjects[i].glasses, {x+w-1-hProgress, y+hDivisor}, {x+w-1, y+hDivisor+hProgress}, {x+w, y+hDivisor+hProgress}, {x+w, y+hDivisor}, borderColor))
            table.insert(hudObjects[i].static, ar.quad(hudObjects[i].glasses, {x, y+2*hDivisor+hProgress}, {x, y+2*hDivisor+hProgress+hIO}, {x+30+hIO, y+2*hDivisor+hProgress+hIO}, {x+30, y+2*hDivisor+hProgress}, borderColor))
            table.insert(hudObjects[i].static, ar.quad(hudObjects[i].glasses, {x+w-30-hIO, y+2*hDivisor+hProgress}, {x+w-30, y+2*hDivisor+hProgress+hIO}, {x+w, y+2*hDivisor+hProgress+hIO}, {x+w, y+2*hDivisor+hProgress}, borderColor))
            hudObjects[i].dynamic.energyBar = ar.quad(hudObjects[i].glasses, {x+3, y+hDivisor}, {x+3+hProgress, y+hDivisor+hProgress}, {x+3+hProgress, y+hDivisor+hProgress}, {x+3, y+hDivisor}, primaryColor)
            hudObjects[i].dynamic.currentEU = ar.text(hudObjects[i].glasses, "", {x+2, y-9}, primaryColor)
            hudObjects[i].dynamic.maxEU = ar.text(hudObjects[i].glasses, "", {x+w-90, y-9}, accentColor)
            hudObjects[i].dynamic.percentage = ar.text(hudObjects[i].glasses, "", {x+w/2-5, y-9}, accentColor)
            hudObjects[i].dynamic.filltime = ar.text(hudObjects[i].glasses, "Time to empty:", {x+30+hIO, y+2*hDivisor+hProgress+3}, accentColor, 0.7)
            hudObjects[i].dynamic.fillrate = ar.text(hudObjects[i].glasses, "", {x+w/2-10, y+2*hDivisor+hProgress+2}, borderColor)
            hudObjects[i].dynamic.state = ar.text(hudObjects[i].glasses, "", {x+w-95, y+2*hDivisor+hProgress+2}, colors.red)
            if compact then hudObjects[i].dynamic.state.setPosition(x+w/2-15, y+hDivisor+2) end
        end
        hudObjects[i].dynamic.energyBar.setVertex(3, x+3+hProgress+energyBarLength*percentage, y+hDivisor+hProgress)
        hudObjects[i].dynamic.energyBar.setVertex(4, x+3+energyBarLength*percentage, y+hDivisor)
        if compact then
            hudObjects[i].dynamic.currentEU.setText(parser.metricNumber(currentEU).." "..energyUnit)
        else
            hudObjects[i].dynamic.currentEU.setText(parser.splitNumber(currentEU).." "..energyUnit)
        end
        if maxEU > 9000000000000000000 then
            hudObjects[i].dynamic.maxEU.setText("∞ "..energyUnit)
            hudObjects[i].dynamic.maxEU.setPosition(x+w-25, y-9)
        else
            if compact then
                hudObjects[i].dynamic.maxEU.setText(parser.metricNumber(maxEU).." "..energyUnit)
            else
                hudObjects[i].dynamic.maxEU.setText(parser.splitNumber(maxEU).." "..energyUnit)
            end
            hudObjects[i].dynamic.maxEU.setPosition(x+w-30-(4.5*#parser.splitNumber(maxEU)), y-9)
        end
        hudObjects[i].dynamic.percentage.setText(parser.percentage(percentage))
        local hIOString = ""
        if compact then
            hIOString = parser.metricNumber(energyData.energyPerTick)
        else
            hIOString = parser.splitNumber(energyData.energyPerTick)
        end
        hudObjects[i].dynamic.fillrate.setPosition(x+w/2-18-(#hIOString*1.6), y+2*hDivisor+hProgress+2)
        if energyData.energyPerTick >= 0 then
            hudObjects[i].dynamic.fillrate.setText("+"..hIOString.." "..energyUnit.."/t") 
            hudObjects[i].dynamic.fillrate.setColor(screen.toRGB(colors.lime))
        else
            hudObjects[i].dynamic.fillrate.setText(hIOString.." "..energyUnit.."/t")
            hudObjects[i].dynamic.fillrate.setColor(screen.toRGB(colors.red))
        end
        local fillTimeString = ""
        if not compact then
            if energyData.energyPerTick > 0 then
                local fillTime = math.floor((maxEU-currentEU)/(energyData.energyPerTick*20))
                fillTimeString = "Full: " .. time.format(math.abs(fillTime))
            elseif energyData.energyPerTick < 0 then
                local fillTime = math.floor((currentEU)/(energyData.energyPerTick*20))
                fillTimeString = "Empty: " .. time.format(math.abs(fillTime))
            else
                fillTimeString = ""
            end
        end
        if data.state == states.OFF then
            hudObjects[i].dynamic.state.setText("Disabled")
        else
            if data.problems > 0 then
                hudObjects[i].dynamic.state.setText("Maintenance")
            else
                hudObjects[i].dynamic.state.setText("")
            end
        end
        hudObjects[i].dynamic.filltime.setText(fillTimeString)
    end
    end
end

function powerDisplay.remove(glassAddress)
    for i = 1, #hudObjects do
        local hudObject = hudObjects[i]
        local glasses = hudObject.glasses
        if glasses ~= nil then
            if glasses.address == glassAddress then
                for j = 1, #hudObjects[i].static do
                    hudObjects[i].glasses.removeObject(hudObjects[i].static[j].getID())
                end
                for name, value in pairs(hudObjects[i].dynamic) do
                    hudObjects[i].glasses.removeObject(hudObjects[i].dynamic[name].getID())
                end
            end
        end
    end
end

return powerDisplay