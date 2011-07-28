#!/usr/bin/lua
-- ------------------------------------------------------------------------- --
-- example_00.lua
-- ~~~~~~~~~~~~~~
-- Please do not remove the following notices.
-- Copyright (c) 2011 by Geekscape Pty. Ltd.
-- Documentation: http://http://geekscape.github.com/mqtt_lua
-- License: AGPLv3 http://geekscape.org/static/aiko_license.html
-- Version: 0.0
--
-- Description
-- ~~~~~~~~~~~
-- Subscribe to a topic and publish all received messages on another topic.
--
-- ToDo
-- ~~~~
-- - On failure, automatically reconnect to MQTT server.
-- ------------------------------------------------------------------------- --

function callback(
  topic,    -- string
  message)  -- string

  print("Topic: " .. topic .. ", message: '" .. message .. "'")

  mqtt_client:publish(args.topic2, message)
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
  -h,--host    (default localhost)   MQTT server hostname
  -i,--id      (default example_00)  MQTT client identifier
  -p,--port    (default 1883)        MQTT server port number
  -s,--topic1  (default test/1)      Subscribe topic
  -t,--topic2  (default test/2)      Publish topic
]]

local MQTT = require("mqtt_library")

mqtt_client = MQTT.client.create(args.host, args.port, callback)

mqtt_client:connect(args.id)

mqtt_client:subscribe({ args.topic1 })

while (true) do
  mqtt_client:handler()
  socket.sleep(1.0)  -- seconds
end

mqtt_client:unsubscribe({ args.topic1 })

mqtt_client:destroy()

-- ------------------------------------------------------------------------- --
