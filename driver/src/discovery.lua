local log = require "log"
local discovery = {}

function discovery.handle_discovery(driver, _, should_continue)
    log.info("Starting ewelink discovery")
    local known = {}
    for _, device in ipairs(driver:get_devices()) do known[device.device_network_id] = device end
    if known["ewelink-vhub"] == nil then
        driver:try_create_device({
            type = "LAN",
            device_network_id = "ewelink-vhub",
            label = "ewelink virtual hub",
            profile = "sonoff-bridge.v1",
            vendor_provided_label = nil
        })
    end
end

return discovery
