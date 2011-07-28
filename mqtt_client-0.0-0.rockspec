package = "mqtt_client"
version = "0.0-0"

source = {
  url = "http://github.com/downloads/geekscape/lua_mqtt_client/lua_mqtt_client-0.0.tar.gz"
}

description = {
  summary = "Lua MQTT client",
  detailed = [[
    MQTT (Message Queue Telemetry Transport) client-side implementation ...
      http://mqtt.org
    Based on the "MQTT protocol specification 3.1" ...
      https://www.ibm.com/developerworks/webservices/library/ws-mqtt
  ]],

  homepage = "https://geekscape.github.com/lua_mqtt_client",
  license = "GPLv3 or commercial",
  maintainer = "Andy Gelme (@geekscape)"
}

dependencies = {
  "lua >= 5.1",
  "luasocket >= 2.0.2"
}

build = {
  type = "builtin",

  modules = {
    lapp           = "lua/lapp.lua",
    mqtt_library   = "lua/mqtt_library.lua",
    mqtt_publish   = "lua/mqtt_publish.lua",
    mqtt_subscribe = "lua/mqtt_subscribe.lua",
    mqtt_test      = "lua/mqtt_test.lua",
    utility        = "lua/utility.lua"
  }
}
