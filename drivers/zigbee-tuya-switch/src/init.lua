-- Zigbee Tuya Button
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local log = require "log"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local isAlreadyEmit = false
local remapButtonTbl = {
    ["one"] = "switch1",
    ["two"] = "switch2",
    ["three"] = "switch3",
}

local function getRemapButton(device)
    remapButton = device.preferences.remapButton
    log.info("--------- Moon --------->> remapButton: ", remapButton)

    if remapButton == nil then
        return "main"
    else
        return remapButtonTbl[remapButton]
    end
end

local on_handler = function(driver, device, command)
    log.info("--------- Moon --------->> on_handler - component : ", command.component)

    if command.component == "main" or command.component == getRemapButton(device) then
        device.profile.components["main"]:emit_event(capabilities.switch.switch.on())
        command.component = getRemapButton(device)
    end

    device.profile.components[command.component]:emit_event(capabilities.switch.switch.on())
    isAlreadyEmit = true
    device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
end

local off_handler = function(driver, device, command)
    log.info("--------- Moon --------->> off_handler - component : ", command.component)

    if command.component == "main" or command.component == getRemapButton(device) then
        device.profile.components["main"]:emit_event(capabilities.switch.switch.off())
        command.component = getRemapButton(device)
    end

    -- Note : The logic is the same, but it uses endpoint.
    --local endpoint = device:get_endpoint_for_component_id(command.component)
    --device:emit_event_for_endpoint(endpoint, capabilities.switch.switch.off())
    --device:send(zcl_clusters.OnOff.server.commands.Off(device):to_endpoint(endpoint))
    device.profile.components[command.component]:emit_event(capabilities.switch.switch.off())
    isAlreadyEmit = true
    device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.Off(device))
end

local component_to_endpoint = function(device, component_id)
    log.info("--------- Moon --------->> component_to_endpoint - component_id : ", component_id)
    local ep = component_id:match("switch(%d)")
    return ep and tonumber(ep) or device.fingerprinted_endpoint_id
end

local endpoint_to_component = function(device, ep)
    log.info("--------- Moon --------->> endpoint_to_component - endpoint : ", ep)

    local component_id = string.format("switch%d", ep)

    if getRemapButton(device) == component_id and isAlreadyEmit == false then
        syncComponent(device, "on")
    end

    isAlreadyEmit = false

    if getRemapButton(device) == "main" then
        component_id = "main"
    end

    return component_id
end

function syncComponent(device, reverse)
    local status = device:get_latest_state(getRemapButton(device), "switch", "switch", "off", nil)
    if status == reverse then
        device.profile.components["main"]:emit_event(capabilities.switch.switch.off())
    else
        device.profile.components["main"]:emit_event(capabilities.switch.switch.on())
    end
end

local device_info_changed = function(driver, device, event, args)
    syncComponent(device, "off")
end

local device_init = function(self, device)
    log.info("--------- Moon --------->> device_init")
    device:set_component_to_endpoint_fn(component_to_endpoint) -- get_endpoint_for_component_id
    device:set_endpoint_to_component_fn(endpoint_to_component)
end

local device_added = function(driver, device)
    log.info("--------- Moon --------->> device_added")
    -- Workaround : Should emit or send to enable capabilities UI
    for key, value in pairs(device.profile.components) do
        log.info("--------- Moon --------->> device_added - key : ", key)
        device.profile.components[key]:emit_event(capabilities.switch.switch.on())
        device:send_to_component(key, zcl_clusters.OnOff.server.commands.On(device))
    end
end

local device_driver_switched = function()
    getRemapButton(device)(device)
end

local function configure_device(self, device)
    device:configure()
end

local zigbee_tuya_switch_driver_template = {
    supported_capabilities = {
        capabilities.switch,
        capabilities.refresh
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = on_handler,
            [capabilities.switch.commands.off.NAME] = off_handler
        }
    },
    lifecycle_handlers = {
        infoChanged = device_info_changed,
        init = device_init,
        added = device_added,
        --driverSwitched = device_driver_switched,
        doConfigure = configure_device
    }
}

defaults.register_for_default_handlers(zigbee_tuya_switch_driver_template, zigbee_tuya_switch_driver_template.supported_capabilities)
local zigbee_driver = ZigbeeDriver("zigbee-tuya-switch", zigbee_tuya_switch_driver_template)
--local zigbee_driver = ZigbeeDriver("zigbee-tuya-switch-dev", zigbee_tuya_switch_driver_template)
zigbee_driver:run()