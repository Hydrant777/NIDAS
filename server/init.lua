-- Import section
local event = require("event")
local component = require("component")
local modem = component.modem
local serialization = require("serialization")

local addDroneMachine = require("server.usecases.add-drone-machine")
local getMultiblockStatus = require("server.usecases.get-multiblock-status")
local getPowerStatus = require("server.usecases.get-lsc-status")

local constants = require("configuration.constants")
local portNumber = constants.machineStatusPort
local serverResponseTime = constants.networkResponseTime

local serverData = {}
local knownMachines = {}
local server = {}
local statuses = {multiblocks = {}, power = {}}

--

local function save()
    local file = io.open("/home/NIDAS/settings/serverData", "w")
    file:write(serialization.serialize(serverData))
    file:close()
    file = io.open("/home/NIDAS/settings/machineData", "w")
    file:write(serialization.serialize(statuses))
    file:close()
    file = io.open("/home/NIDAS/settings/knownMachines", "w")
    file:write(serialization.serialize(statuses))
    file:close()
end

local function load()
    local file = io.open("/home/NIDAS/settings/serverData", "r")
    if file then
        serverData = serialization.unserialize(file:read("*a")) or {statuses = statuses}
        statuses = serverData.statuses
        file:close()
    end
    file = io.open("/home/NIDAS/settings/machineData", "r")
    if file then
        statuses = serialization.unserialize(file:read("*a")) or {}
        file:close()
    end
    file = io.open("/home/NIDAS/settings/machine-addresses", "r")
    if file then
        serverData.knownMachines = serialization.unserialize(file:read("*a")) or {}
        file:close()
    end
end
load()

local function updateMachineList(_, address, _)
    local comp = component.proxy(address)
    if comp.type == "waypoint" or comp.type == "gt_machine" or comp.type == "gt_batterybuffer" then
        addDroneMachine(address)
        local file = io.open("/home/NIDAS/settings/machine-addresses", "r")
        if file then
            serverData.knownMachines = serialization.unserialize(file:read("*a")) or {}
            file:close()
        end
    end
end
event.listen("component_added", updateMachineList)

modem.open(portNumber)

local function isMain()
    -- Identifies as main
    local function identifyAsMainServer(_, _, sender, port, _, messageName)
        if port == portNumber and messageName == "are_you_the_main_server" then
            modem.send(sender, portNumber, "I_am_the_main_server")
        end
    end
    event.listen("modem_message", identifyAsMainServer)

    -- Gets other server statuses
    local function updateMachineStatuses(_, _, _, port, _, messageName, arg)
        if port == portNumber and messageName == "local_multiblock_statuses" then
            for address, status in pairs(serialization.unserialize(arg)) do
                statuses.multiblocks[address] = status
            end
        end
    end
    event.listen("modem_message", updateMachineStatuses)
    modem.broadcast(portNumber, "get_status")
end

if serverData.isMain then
    isMain()
elseif serverData.isMain == nil then
    -- Server not configured yet
    -- In case there's no response, server is main
    serverData.isMain = true

    local function detectMainServer(_, _, _, port, _, messageName)
        if port == portNumber and messageName == "I_am_the_main_server" then
            serverData.isMain = false
        end
    end

    event.listen("modem_message", detectMainServer)
    modem.broadcast(portNumber, "are_you_the_main_server")

    -- Ignores response after timeout
    event.timer(
        serverResponseTime,
        function()
            event.ignore("modem_message", detectMainServer)
            if serverData.isMain then
                isMain()
            end
            save()
        end
    )
else
    -- Server is local
    -- Sends it's statuses
    local function sendStatuses(_, _, sender, port, _, messageName)
        if port == portNumber and messageName == "get_status" then
            local updatedStatuses = {}
            for address, status in statuses.multiblocks do
                updatedStatuses[address] = {state = status.state, problems = status.problems}
            end
            modem.send(sender, portNumber, "local_multiblock_statuses", serialization.serialize(updatedStatuses))
        end
    end
    event.listen("modem_message", sendStatuses)
end

local function updatePowerStatus(_, _, _, port, _, messageName, arg)
    if port == portNumber and messageName == "local_power_status" then
        statuses.powerStatus = serialization.unserialize(arg)
    end
end
event.listen("modem_message", updatePowerStatus)

local refresh = nil
local selectedMachine = "None"
local currentConfigWindow = {}
local function changeMachine(machineAddress, data)
    selectedMachine = machineAddress
    local x, y, gui, graphics, renderer, page = table.unpack(data)
    renderer.removeObject(currentConfigWindow)
    refresh(x, y, gui, graphics, renderer, page)
end

function server.configure(x, y, gui, graphics, renderer, page)
    local renderingData = {x, y, gui, graphics, renderer, page}
    graphics.context().gpu.setActiveBuffer(page)
    graphics.text(3, 11, "Machine:")
    local onActivation = {}
    for address, componentType in component.list() do
        if componentType == "gt_machine" then
            if statuses.multiblocks[address] == nil then
                statuses.multiblocks[address] = {}
            end
            local displayName = statuses.multiblocks[address].name or address
            table.insert(
                onActivation,
                {displayName = displayName, value = changeMachine, args = {address, renderingData}}
            )
        end
    end
    local _, ySize = graphics.context().gpu.getBufferSize(page)
    table.insert(
        currentConfigWindow,
        gui.smallButton(x + 10, y + 5, selectedMachine, gui.selectionBox, {x + 15, y + 5, onActivation})
    )
    table.insert(currentConfigWindow, gui.bigButton(x + 2, y + tonumber(ySize) - 4, "Save Configuration", save))
    local attributeChangeList = {
        {name = "Main Server", attribute = "isMain", type = "boolean", defaultValue = false},
        {
            name = "Power Capacitor",
            attribute = "powerAddress",
            type = "component",
            defaultValue = "None",
            componentType = "gt_machine",
            nameTable = statuses.multiblocks
        }
    }
    gui.multiAttributeList(x + 3, y + 1, page, currentConfigWindow, attributeChangeList, serverData)

    if selectedMachine ~= "None" then
        local attributeChangeList = {
            {name = "Machine Name", attribute = "name", type = "string", defaultValue = nil}
        }
        gui.multiAttributeList(
            x + 3,
            y + 7,
            page,
            currentConfigWindow,
            attributeChangeList,
            statuses.multiblocks,
            selectedMachine
        )
    end
    renderer.update()
    return currentConfigWindow

    -- TODO: Code for GUI configuration of server:
    ---- Machine widgets layout?
end
refresh = server.configure

local savingInterval = 500
local savingCounter = savingInterval
function server.update()
    local shouldBroadcastStatuses = false
    local updatedStatuses = {}

    for address, machine in pairs(serverData.knownMachines or {}) do
        local multiblockStatus = getMultiblockStatus(address, machine.name, machine.location)
        statuses.multiblocks[address] = statuses.multiblocks[address] or {}

        if multiblockStatus.state ~= statuses.multiblocks[address].state then
            shouldBroadcastStatuses = shouldBroadcastStatuses or not serverData.isMain
            updatedStatuses[address] = {
                state = multiblockStatus.state,
                problems = multiblockStatus.problems,
                name = machine.name,
                location = machine.location
            }
        end

        statuses.multiblocks[address] = multiblockStatus
    end

    if shouldBroadcastStatuses then
        modem.broadcast(portNumber, "local_multiblock_statuses", serialization.serialize(updatedStatuses))
    end

    if serverData.powerAddress then
        local powerStatus = getPowerStatus(serverData.powerAddress, "Lapotronic Supercapacitor")
        if statuses.powerStatus ~= powerStatus then
            modem.broadcast(portNumber, "local_power_status", serialization.serialize(powerStatus))
        end
        statuses.powerStatus = powerStatus
    else
        statuses.powerStatus = nil
    end
    if savingCounter == savingInterval then
        save()
        savingCounter = 1
    end
    savingCounter = savingCounter + 1
    return statuses
end

return server
