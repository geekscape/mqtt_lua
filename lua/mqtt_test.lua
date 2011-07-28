#!/usr/bin/lua
-- ------------------------------------------------------------------------- --
-- mqtt_test.lua
-- ~~~~~~~~~~~~~
-- Please do not remove the following notices.
-- Copyright (c) 2011 by Geekscape Pty. Ltd.
-- Documentation: http://http://geekscape.github.com/lua_mqtt_client
-- License: GPLv3 http://geekscape.org/static/aiko_license.html
-- Version: 0.0 2011-07-28
--
-- Description
-- ~~~~~~~~~~~
-- Repetitively publishes MQTT messages on the topic "test/1",
-- until the "quit" message is received on the topic "test/2".
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

print("[mqtt_test v0.0 2011-07-28]")

if (not is_openwrt()) then require("luarocks.require") end
require("lapp")

local args = lapp [[
  Test Lua MQTT client library
  -d,--debug                       Verbose console logging
  -i,--id     (default MQTT test)  MQTT client identifier
  -p,--port   (default 1883)       MQTT server port number
  <host>      (default localhost)  MQTT server hostname
]]

local MQTT = require("mqtt_library")

if (args.debug) then MQTT.Utility.set_debug(true) end

local mqtt_client = MQTT.client.create(args.host, args.port, callback)

mqtt_client:connect(args.id)

mqtt_client:publish("test/1", "*** Lua test A ***")
mqtt_client:subscribe({"test/2"})

local running = true

while (running) do
  mqtt_client:handler()
  mqtt_client:publish("test/1", "*** Lua test B ***")
  socket.sleep(1.0)  -- seconds
end

mqtt_client:unsubscribe({"test/2"})
mqtt_client:destroy()

-- ------------------------------------------------------------------------- --
