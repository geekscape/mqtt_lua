#!/usr/bin/lua
-- ------------------------------------------------------------------------- --
-- example_01.lua
-- ~~~~~~~~~~~~~~
-- Please do not remove the following notices.
-- Copyright (c) 2011-2012 by Geekscape Pty. Ltd.
-- Documentation: http://http://geekscape.github.com/mqtt_lua
-- License: AGPLv3 http://geekscape.org/static/aiko_license.html
-- Version: 0.1
--
-- Description
-- ~~~~~~~~~~~
-- Subscribe to a topic on one MQTT server and publish all received messages
-- to a topic on another MQTT server.
--
-- ToDo
-- ~~~~
-- - On failure, automatically reconnect to MQTT server(s).
-- ------------------------------------------------------------------------- --

function callback(
  topic,    -- string
  message)  -- string

  print("Topic: " .. topic .. ", message: '" .. message .. "'")

  mqtt_client2:publish(args.topic2, message)
end

-- ------------------------------------------------------------------------- --

function is_openwrt()
  return(os.getenv("USER") == "root")  -- Assume logged in as "root" on OpenWRT
end

-- ------------------------------------------------------------------------- --

if (not is_openwrt()) then require("luarocks.require") end
require("lapp")

args = lapp [[
  Subscribe to topic1 and publish all messages on topic2
  -g,--host1   (default localhost)   Subscribe MQTT server hostname
  -h,--host2   (default localhost)   Publish MQTT server hostname
  -i,--id      (default example_01)  MQTT client identifier
  -p,--port1   (default 1883)        Subscribe MQTT server port number
  -q,--port2   (default 1883)        Publish MQTT server port number
  -s,--topic1  (default test/1)      Subscribe topic
  -t,--topic2  (default test/2)      Publish topic
]]

local MQTT = require("mqtt_library")

mqtt_client1 = MQTT.client.create(args.host1, args.port1, callback)
mqtt_client2 = MQTT.client.create(args.host2, args.port2)

mqtt_client1:connect(args.id .. "a")
mqtt_client2:connect(args.id .. "b")

mqtt_client1:subscribe({ args.topic1 })

local error_message1 = nil
local error_message2 = nil

while (error_message1 == nil and error_message2 == nil) do
  error_message1 = mqtt_client1:handler()
  error_message2 = mqtt_client2:handler()
  socket.sleep(1.0)  -- seconds
end

if (error_message1 == nil) then
  mqtt_client1:unsubscribe({ args.topic1 })
  mqtt_client1:destroy()
else
  print(error_message1)
end

if (error_message2 == nil) then
  mqtt_client2:destroy()
else
  print(error_message2)
end

-- ------------------------------------------------------------------------- --
