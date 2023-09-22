local log = require "log"
local utils = require "st.utils"

local capabilities = require "st.capabilities"
local api = require "api"
local json = require "st.json"
local base64 = require "st.base64"
local DEVICE_KEY = "devicekey"

local command_handlers = {}

function command_handlers.switch_on(driver, device, command)
    log.debug(string.format("[%s] calling switch_on", device.device_network_id))
    log.trace("command:", utils.stringify_table(command))
    if command.component == "main" then
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switch", {
            switch = "on"
        })
        device:emit_event(capabilities.switch.switch.on())
    else
        local outlet = tonumber(command.component:match("outlet(%d)"))
        if outlet ~= nil then
            local component = device.profile.components[command.component]
            api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switches", {
                switch = "on",
                outlet = outlet
            })
            device:emit_component_event(component, capabilities.switch.switch.on())
        end
    end
end

function command_handlers.switch_off(driver, device, command)
    log.debug(string.format("[%s] calling switch_off", device.device_network_id))
    log.trace("command:", utils.stringify_table(command))
    if command.component == "main" then
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switch", {
            switch = "off"
        })
        device:emit_event(capabilities.switch.switch.off())
    else
        local outlet = tonumber(command.component:match("outlet(%d)"))
        if outlet ~= nil then
            local component = device.profile.components[command.component]
            api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switches", {
                switch = "off",
                outlet = outlet
            })
            device:emit_component_event(component, capabilities.switch.switch.off())
        end
    end
end
function command_handlers.switchLevel_setLevel(driver, device, command)
    log.debug(string.format("[%s] calling switchLevel_setLevel", device.device_network_id))
    local level = command.args.level
    if level ~= 0 then
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "dimmable", {
            brightness = level
        })
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.switchLevel.level(level))
    else
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switch", {
            switch = "off"
        })
        device:emit_event(capabilities.switch.switch.off())
    end

end
function command_handlers.UIID44_switchLevel_setLevel(driver, device, command)
    log.debug(string.format("[%s] calling UIID44_switchLevel_setLevel", device.device_network_id))
    local level = command.args.level

    if level ~= 0 then
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "dimmable", {
            brightness = level,
            mode = 0,
            switch = "on"
        })
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.switchLevel.level(level))
    else
        api.send(device.device_network_id, device:get_field(DEVICE_KEY), "switch", {
            switch = "off"
        })
        device:emit_event(capabilities.switch.switch.off())
    end

end
return command_handlers
