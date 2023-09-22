local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local json = require "st.json"
local utils = require "st.utils"
local base64 = require "st.base64"

local command_handlers = require "command_handlers"
local discovery = require "discovery"

local api = require "api"

local POLLING_TIMER = "update_timer"
local DRIVER_NAME = "ewelink LAN Driver"
local POLLING_COUNTER = "polling_counter"
local DEVICE_KEY = "devicekey"
local BRIDGE_DNI = "ewelink-vhub"

local PROFILES = {
    ["plug"] = "plug",
    ["light"] = "light",
    [1] = "uiid1",
    [6] = "uiid1",
    [44] = "uiid44",
    [138] = "switch1",
    [139] = "switch2",
    [140] = "switch3",
    [141] = "switch4"
}
local CHANNELS = {
    [0] = "outlet0",
    [1] = "outlet1",
    [2] = "outlet2",
    [3] = "outlet3"
}
local function update_device_from_params(device, params)
    if not params then return end
    if params.switch then
        if params.switch == "off" then device:emit_event(capabilities.switch.switch.off()) end
        if params.switch == "on" then device:emit_event(capabilities.switch.switch.on()) end
    end
    if params.switches then
        for idx, channel in ipairs(params.switches) do
            local component = device.profile.components[CHANNELS[channel.outlet]]
            if channel.switch == "off" then
                device:emit_component_event(component, capabilities.switch.switch.off())
            end
            if channel.switch == "on" then
                device:emit_component_event(component, capabilities.switch.switch.on())
            end
        end
    end
    if params.rssi then
        if (device:supports_capability(capabilities.signalStrength, "main")) then
            device:emit_event(capabilities.signalStrength.rssi(params.rssi))
        end
    end
    if params.brightness then
        -- local level = utils.round(params.brightness / 255 * 100)
        device:emit_event(capabilities.switchLevel.level(params.brightness))
    end
end

local function poll(driver, bridge, last_seqs, last_seen)
    log.info(driver.NAME, "Started polling")
    log.trace("last_seqs:", utils.stringify_table(last_seqs))
    log.trace("last_seen:", utils.stringify_table(last_seen))
    local logmdns = bridge.preferences.logmdns or true
    local counter = bridge:get_field(POLLING_COUNTER) or 1
    local records = api.discover(last_seqs, last_seen, counter, logmdns)
    for idx, record in ipairs(records) do
        local deviceid = record.txt.id
        local device = driver:device_by_id(deviceid)
        if device ~= nil then
            local devicekey = device:get_field(DEVICE_KEY)
            local params = api.read_record(record, devicekey, logmdns)
            if params ~= nil then
                device:online()
                update_device_from_params(device, params)
            end
        else
            local metadata = {
                type = "LAN",
                parent_device_id = bridge.id,
                device_network_id = deviceid,
                label = deviceid,
                profile = PROFILES[record.txt.type],
                manufacturer = 'ewelink',
                model = PROFILES[record.txt.type],
                vendor_provided_label = deviceid
            }
            log.info(utils.stringify_table(metadata))
            driver:try_create_device(metadata)
        end
    end
    local offlineThreshold = bridge.preferences.offlineThreshold
    if counter >= offlineThreshold then
        log.info("Started mark offline as polling counter reached offline threshold")
        for _, device in pairs(bridge:get_child_list()) do
            local l = last_seen[device.device_network_id]
            if l == nil or l == 0 then device:offline() end
        end
        counter = 1
        for k in pairs(last_seen) do last_seen[k] = 0 end
    else
        counter = counter + 1
    end
    bridge:set_field(POLLING_COUNTER, counter)
end

local function update_device_from_info(device, online, params)
    if online then
        local params = params
        update_device_from_params(device, params)
    else
        device:offline()
    end
end

local function create_child_devices(driver, bridge, bridge_netinfo)
    local processed_devices = {}
    for _, device in pairs(bridge:get_child_list()) do
        local device_info = bridge_netinfo[device.device_network_id]
        if not device_info then
            log.info("Not found", device.label)
            device:offline()
        else
            log.info("found", device.label)
            processed_devices[device_info.deviceid] = device.id
            local profile = PROFILES[device_info.extra.uiid]
            if profile ~= nil then
                device:try_update_metadata({
                    profile = profile,
                    model = profile,
                    vendor_provided_label = device_info.name
                })
            else
                log.warn("Unknown uiid:", utils.stringify_table(device_info))
                device:try_update_metadata({
                    vendor_provided_label = device_info.name
                })
            end
            update_device_from_info(device, device_info.online, device_info.params)
        end
    end
    for deviceid, device_info in pairs(bridge_netinfo) do
        if not processed_devices[deviceid] then
            log.info("Creating", device_info.name)
            local profile = PROFILES[device_info.extra.uiid]
            if profile == nil then
                log.warn("Unknown uiid:", utils.stringify_table(device_info))
            else
                local metadata = {
                    type = "LAN",
                    parent_device_id = bridge.id,
                    device_network_id = device_info.deviceid,
                    label = device_info.name,
                    profile = profile,
                    manufacturer = device_info.extra.manufacturer .. " (" .. device_info.extra.model .. ")",
                    model = profile
                }
                if device_info.showBrand then
                    metadata.manufacturer = device_info.brandName .. " (" .. device_info.extra.model .. ")"
                end
                log.info(utils.stringify_table(metadata))
                driver.datastore.dni_to_devicekey[device_info.deviceid] = device_info.devicekey
                driver:try_create_device(metadata)
            end
        end
    end

end
local function setup_polling_task(driver, bridge)
    if bridge == nil then
        local bridge_id = driver.datastore.dni_to_id[BRIDGE_DNI]
        bridge = driver:get_device_info(bridge_id)
    end
    local interval = bridge.preferences.pollingInterval
    local timer = bridge:get_field(POLLING_TIMER)
    if timer ~= nil then bridge.thread:cancel_timer(timer) end
    local last_seqs = {}
    local last_seen = {}
    timer = bridge.thread:call_on_schedule(interval, function(d)
        poll(driver, bridge, last_seqs, last_seen)
    end)
    bridge:set_field(POLLING_TIMER, timer)
    bridge.thread:call_with_delay(0, function(d)
        poll(driver, bridge, last_seqs, last_seen)
    end)
end
local function download_bridge_netinfo(driver, device)
    if device.preferences.url == "" then
        log.info("set url in bridge settings to populate initial devices")
        return
    end
    log.info("device.preferences.url=", device.preferences.url)
    local bridge_netinfo = api.download_info(device.preferences.url)
    log.trace("url returned:", utils.stringify_table(bridge_netinfo))
    if not bridge_netinfo then return end
    driver.datastore.bridge_netinfo = bridge_netinfo
    create_child_devices(driver, device, bridge_netinfo)
end
local function device_added(driver, device, event, args)
    log.info(device:pretty_print(), event)
    driver.datastore.dni_to_id[device.device_network_id] = device.id
    device:set_field(DEVICE_KEY, driver.datastore.dni_to_devicekey[device.device_network_id], {
        persist = true
    })
    local device_info = driver.datastore.bridge_netinfo[device.device_network_id]
    if device_info ~= nil then update_device_from_info(device, device_info.online, device_info.params) end
end

local function device_init(driver, device, event, args)
    log.info(device:pretty_print(), event)
end
local function device_infoChanged(driver, device, event, args)
    log.info(device:pretty_print(), event)
    if args.old_st_store.preferences.devicekey ~= device.preferences.devicekey then
        device:set_field(DEVICE_KEY, device.preferences.devicekey, {
            persist = true
        })
        setup_polling_task(driver)
    end
end
local function device_removed(driver, device, event, args)
    log.info("Removing  device", device.device_network_id)
    driver.datastore.dni_to_id[device.device_network_id] = nil
end
local function bridge_refresh(driver, device, command)
    log.debug(device:pretty_print(), "calling bridge refresh")
    driver:call_with_delay(1, function(d)
        download_bridge_netinfo(driver, device)
        setup_polling_task(driver, device)
    end, DRIVER_NAME .. " Download device info")
end

local function bridge_infoChanged(driver, device, event, args)
    log.info(device:pretty_print(), event)
    if args.old_st_store.preferences.url ~= device.preferences.url then
        device.thread:call_with_delay(1, function(d)
            download_bridge_netinfo(driver, device)
        end)
    end
    if args.old_st_store.preferences.pollingInterval ~= device.preferences.pollingInterval then
        setup_polling_task(driver, device)
    end
end
local function bridge_added(driver, device, event, args)
    log.info(device:pretty_print(), event)
    driver.datastore.bridge_netinfo = {}
    driver.datastore.dni_to_id[device.device_network_id] = device.id
end

local function bridge_init(driver, device, event, args)
    log.info(device:pretty_print(), event)
    device:online()
    setup_polling_task(driver, device)
end
local function bridge_removed(driver, device, event, args)
    log.info("Removing  bridge")
    driver.datastore.bridge_netinfo = {}
end
-- create the driver object
local driver = Driver(DRIVER_NAME, {
    discovery = discovery.handle_discovery,
    lifecycle_handlers = {
        added = device_added,
        init = device_init,
        removed = device_removed
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = command_handlers.switch_on,
            [capabilities.switch.commands.off.NAME] = command_handlers.switch_off
        },
        [capabilities.switchLevel.ID] = {
            [capabilities.switchLevel.commands.setLevel.NAME] = command_handlers.switchLevel_setLevel
        }
    },

    sub_drivers = {{
        NAME = "ewelink bridge",
        can_handle = function(opts, driver, device, ...)
            return device.device_network_id == BRIDGE_DNI
        end,
        lifecycle_handlers = {
            added = bridge_added,
            init = bridge_init,
            removed = bridge_removed,
            infoChanged = bridge_infoChanged
        },
        capability_handlers = {
            [capabilities.refresh.ID] = {
                [capabilities.refresh.commands.refresh.NAME] = bridge_refresh
            }
        }
    }, {
        NAME = "generic",
        can_handle = function(opts, driver, device, ...)
            return device.model == "plug" or device.model == "light"
        end,
        lifecycle_handlers = {
            infoChanged = device_infoChanged
        }
    }, {
        NAME = "UIID 44",
        can_handle = function(opts, driver, device, ...)
            return device.model == "uiid44"
        end,
        capability_handlers = {
            [capabilities.switchLevel.ID] = {
                [capabilities.switchLevel.commands.setLevel.NAME] = command_handlers.UIID44_switchLevel_setLevel
            }
        }
    }},
    device_by_id = function(self, deviceid)
        local uuid = self.datastore.dni_to_id[deviceid]
        if uuid == nil then
            return nil
        else
            return self:get_device_info(uuid)
        end
    end
})

if driver.datastore["bridge_netinfo"] == nil then driver.datastore["bridge_netinfo"] = {} end
if driver.datastore["dni_to_id"] == nil then driver.datastore["dni_to_id"] = {} end
if driver.datastore["dni_to_devicekey"] == nil then driver.datastore["dni_to_devicekey"] = {} end

log.info("Starting " .. DRIVER_NAME)
driver:run()
log.warn(DRIVER_NAME .. " exiting")
