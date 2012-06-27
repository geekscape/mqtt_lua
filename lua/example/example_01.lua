#!/usr/bin/lua
--
-- example_01.lua
-- ~~~~~~~~~~~~~~
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

  mqtt_client2:publish(args.topic_p, message)
end

-- ------------------------------------------------------------------------- --

function is_openwrt()
  return(os.getenv("USER") == "root")  -- Assume logged in as "root" on OpenWRT
end

-- ------------------------------------------------------------------------- --

if (not is_openwrt()) then require("luarocks.require") end
local lapp = require("pl.lapp")

args = lapp [[
  Subscribe to topic_s and publish all messages on topic_p
  -g,--host_s   (default localhost)   Subscribe MQTT server hostname
  -H,--host_p   (default localhost)   Publish MQTT server hostname
  -i,--id       (default example_01)  MQTT client identifier
  -p,--port_s   (default 1883)        Subscribe MQTT server port number
  -q,--port_p   (default 1883)        Publish MQTT server port number
  -s,--topic_s  (default test/1)      Subscribe topic
  -t,--topic_p  (default test/2)      Publish topic
]]

local MQTT = require("mqtt_library")

mqtt_client1 = MQTT.client.create(args.host_s, args.port_s, callback)
mqtt_client2 = MQTT.client.create(args.host_p, args.port_p)

mqtt_client1:connect(args.id .. "a")
mqtt_client2:connect(args.id .. "b")

mqtt_client1:subscribe({ args.topic_s })

local error_message1 = nil
local error_message2 = nil

while (error_message1 == nil and error_message2 == nil) do
  error_message1 = mqtt_client1:handler()
  error_message2 = mqtt_client2:handler()
  socket.sleep(1.0)  -- seconds
end

if (error_message1 == nil) then
  mqtt_client1:unsubscribe({ args.topic_s })
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
