#!/usr/bin/lua
--
-- mqtt_test.lua
-- ~~~~~~~~~~~~~
-- Version: 0.2 2012-06-01
-- ------------------------------------------------------------------------- --
-- Copyright (c) 2011-2012 Geekscape Pty. Ltd.
-- All rights reserved. This program and the accompanying materials
-- are made available under the terms of the Eclipse Public License v1.0
-- which accompanies this distribution, and is available at
-- http://www.eclipse.org/legal/epl-v10.html
--
-- Contributors:
--    Andy Gelme - Initial implementation
-- -------------------------------------------------------------------------- --
--
-- Description
-- ~~~~~~~~~~~
-- Repetitively publishes MQTT messages on the topic_p,
-- until the "quit" message is received on the topic_s.
--
-- References
-- ~~~~~~~~~~
-- Lapp Framework: Lua command line parsing
--   http://lua-users.org/wiki/LappFramework
--
-- ToDo
-- ~~~~
-- - On failure, automatically reconnect to MQTT server.
-- ------------------------------------------------------------------------- --

function callback(
  topic,    -- string
  payload)  -- string

  print("mqtt_test:callback(): " .. topic .. ": " .. payload)

  if (payload == "quit") then running = false end
end

-- ------------------------------------------------------------------------- --

function is_openwrt()
  return(os.getenv("USER") == "root")  -- Assume logged in as "root" on OpenWRT
end

-- ------------------------------------------------------------------------- --

print("[mqtt_test v0.2 2012-06-01]")

if (not is_openwrt()) then require("luarocks.require") end
local lapp = require("pl.lapp")

local args = lapp [[
  Test Lua MQTT client library
  -d,--debug                         Verbose console logging
  -i,--id       (default mqtt_test)  MQTT client identifier
  -p,--port     (default 1883)       MQTT server port number
  -s,--topic_s  (default test/2)     Subscribe topic
  -t,--topic_p  (default test/1)     Publish topic
  <host>        (default localhost)  MQTT server hostname
]]

local MQTT = require("mqtt_library")

if (args.debug) then MQTT.Utility.set_debug(true) end

local mqtt_client = MQTT.client.create(args.host, args.port, callback)

mqtt_client:connect(args.id)

mqtt_client:publish(args.topic_p, "*** Lua test start ***")
mqtt_client:subscribe({ args.topic_s })

local error_message = nil
local running = true

while (error_message == nil and running) do
  error_message = mqtt_client:handler()

  if (error_message == nil) then
    mqtt_client:publish(args.topic_p, "*** Lua test message ***")
    socket.sleep(1.0)  -- seconds
  end
end

if (error_message == nil) then
  mqtt_client:unsubscribe({ args.topic_s })
  mqtt_client:destroy()
else
  print(error_message)
end

-- ------------------------------------------------------------------------- --
