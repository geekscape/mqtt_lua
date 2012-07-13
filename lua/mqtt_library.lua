-- mqtt_library.lua
-- ~~~~~~~~~~~~~~~~
-- Please do not remove the following notices.
-- Copyright (c) 2011-2012 by Geekscape Pty. Ltd.
-- License: AGPLv3 http://geekscape.org/static/aiko_license.html
-- Version: 0.2 2012-06-01
--
-- Documentation
-- ~~~~~~~~~~~~~
-- MQTT Lua web-site
--   http://geekscape.github.com/mqtt_lua
--
-- MQTT Lua repository notes
--   https://github.com/geekscape/mqtt_lua/blob/master/readme.markdown
--
-- Aiko Platform web-site
--   https://sites.google.com/site/aikoplatform
--
-- References
-- ~~~~~~~~~~
-- MQTT web-site
--   http://mqtt.org

-- MQTT protocol specification 3.1
--   https://www.ibm.com/developerworks/webservices/library/ws-mqtt
--   http://mqtt.org/wiki/doku.php/mqtt_protocol   # Clarifications
--
-- Notes
-- ~~~~~
-- - Always assumes MQTT connection "clean session" enabled.
-- - Supports connection last will and testament message.
-- - Does not support connection username and password.
-- - Fixed message header byte 1, only implements the "message type".
-- - Only supports QOS level 0.
-- - Maximum payload length is 268,435,455 bytes (as per specification).
-- - Publish message doesn't support "message identifier".
-- - Subscribe acknowledgement messages don't check granted QOS level.
-- - Outstanding subscribe acknowledgement messages aren't escalated.
-- - Works on the Sony PlayStation Portable (aka Sony PSP) ...
--     See http://en.wikipedia.org/wiki/Lua_Player_HM
--
-- ToDo
-- ~~~~
-- * Consider when payload needs to be an array of bytes (not characters).
-- * Maintain both "last_activity_out" and "last_activity_in".
-- * - http://mqtt.org/wiki/doku.php/keepalive_for_the_client
-- * Update "last_activity_in" when messages are received.
-- * When a PINGREQ is sent, must check for a PINGRESP, within KEEP_ALIVE_TIME..
--   * Otherwise, fail the connection.
-- * When connecting, wait for CONACK, until KEEP_ALIVE_TIME, before failing.
-- * Should MQTT.client:connect() be asynchronous with a callback ?
-- * Review all public APIs for asynchronous callback behaviour.
-- * Implement parse PUBACK message.
-- * Handle failed subscriptions, i.e no subscription acknowledgement received.
-- * Fix problem when KEEP_ALIVE_TIME is short, e.g. mqtt_publish -k 1
--     MQTT.client:handler(): Message length mismatch
-- - On socket error, optionally try reconnection to MQTT server.
-- - Consider use of assert() and pcall() ?
-- - Only expose public API functions, don't expose internal API functions.
-- - Refactor "if self.connected()" to "self.checkConnected(error_message)".
-- - Maintain and publish messaging statistics.
-- - Memory heap/stack monitoring.
-- - When debugging, why isn't mosquitto sending back CONACK error code ?
-- - Subscription callbacks invoked by topic name (including wildcards).
-- - Implement asynchronous state machine, rather than single-thread waiting.
--   - After CONNECT, expect and wait for a CONACK.
-- - Implement complete MQTT broker (server).
-- - Consider using Copas http://keplerproject.github.com/copas/manual.html
-- ------------------------------------------------------------------------- --

function isPsp() return(Socket ~= nil) end

if (not isPsp()) then
  require("socket")
  require("io")
  require("ltn12")
--require("ssl")
end

local MQTT = {}

MQTT.Utility = require("utility")

MQTT.VERSION = 0x03

MQTT.ERROR_TERMINATE = false      -- Message handler errors terminate process ?

MQTT.DEFAULT_BROKER_HOSTNAME = "localhost"

MQTT.client = {}
MQTT.client.__index = MQTT.client

MQTT.client.DEFAULT_PORT       = 1883
MQTT.client.KEEP_ALIVE_TIME    = 60 -- seconds (maximum is 65535)
MQTT.client.MAX_PAYLOAD_LENGTH = 268435455 -- bytes

-- MQTT 3.1 Specification: Section 2.1: Fixed header, Message type

MQTT.message = {}
MQTT.message.TYPE_RESERVED    = 0x00
MQTT.message.TYPE_CONNECT     = 0x01
MQTT.message.TYPE_CONACK      = 0x02
MQTT.message.TYPE_PUBLISH     = 0x03
MQTT.message.TYPE_PUBACK      = 0x04
MQTT.message.TYPE_PUBREC      = 0x05
MQTT.message.TYPE_PUBREL      = 0x06
MQTT.message.TYPE_PUBCOMP     = 0x07
MQTT.message.TYPE_SUBSCRIBE   = 0x08
MQTT.message.TYPE_SUBACK      = 0x09
MQTT.message.TYPE_UNSUBSCRIBE = 0x0a
MQTT.message.TYPE_UNSUBACK    = 0x0b
MQTT.message.TYPE_PINGREQ     = 0x0c
MQTT.message.TYPE_PINGRESP    = 0x0d
MQTT.message.TYPE_DISCONNECT  = 0x0e
MQTT.message.TYPE_RESERVED    = 0x0f

-- MQTT 3.1 Specification: Section 3.2: CONACK acknowledge connection errors
-- http://mqtt.org/wiki/doku.php/extended_connack_codes

MQTT.CONACK = {}
MQTT.CONACK.error_message = {          -- CONACK return code used as the index
  "Unacceptable protocol version",
  "Identifer rejected",
  "Server unavailable",
  "Bad user name or password",
  "Not authorized"
--"Invalid will topic"                 -- Proposed
}

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Create an MQTT client instance
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function MQTT.client.create(                                      -- Public API
  hostname,  -- string:   Host name or address of the MQTT broker
  port,      -- integer:  Port number of the MQTT broker (default: 1883)
  callback)  -- function: Invoked when subscribed topic messages received
             -- return:   mqtt_client table

  local mqtt_client = {}

  setmetatable(mqtt_client, MQTT.client)

  mqtt_client.callback = callback  -- function(topic, payload)
  mqtt_client.hostname = hostname
  mqtt_client.port     = port or MQTT.client.DEFAULT_PORT

  mqtt_client.connected     = false
  mqtt_client.destroyed     = false
  mqtt_client.last_activity = 0
  mqtt_client.message_id    = 0
  mqtt_client.outstanding   = {}
  mqtt_client.socket_client = nil

  return(mqtt_client)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Client request a connection to an MQTT broker (server)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.1: CONNECT

function MQTT.client:connect(                                     -- Public API
  identifier,    -- string: MQTT client identifier (maximum 23 characters)
  will_topic,    -- string: Last will and testament topic
  will_qos,      -- byte:   Last will and testament Quality Of Service
  will_retain,   -- byte:   Last will and testament retention status
  will_message)  -- string: Last will and testament message
                 -- return: nil or error message

  if (self.connected) then
    return("MQTT.client:connect(): Already connected")
  end

  MQTT.Utility.debug("MQTT.client:connect(): " .. identifier)

  self.socket_client = socket.connect(self.hostname, self.port)

  if (self.socket_client == nil) then
    return("MQTT.client:connect(): Couldn't open MQTT broker connection")
  end

  MQTT.Utility.socket_wait_connected(self.socket_client)

  self.connected = true

-- Construct CONNECT variable header fields (bytes 1 through 9)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  local payload
  payload = MQTT.client.encode_utf8("MQIsdp")
  payload = payload .. string.char(MQTT.VERSION)

-- Connect flags (byte 10)
-- ~~~~~~~~~~~~~
-- bit    7: Username flag =  0  -- recommended no more than 12 characters
-- bit    6: Password flag =  0  -- ditto
-- bit    5: Will retain   =  0
-- bits 4,3: Will QOS      = 00
-- bit    2: Will flag     =  0
-- bit    1: Clean session =  1
-- bit    0: Unused        =  0

  if (will_topic == nil) then
    payload = payload .. string.char(0x02)       -- Clean session, no last will
  else
    local flags
    flags = MQTT.Utility.shift_left(will_retain, 5)
    flags = flags + MQTT.Utility.shift_left(will_qos, 3) + 0x06
    payload = payload .. string.char(flags)
  end

-- Keep alive timer (bytes 11 LSB and 12 MSB, unit is seconds)
-- ~~~~~~~~~~~~~~~~~
  payload = payload .. string.char(math.floor(MQTT.client.KEEP_ALIVE_TIME / 256))
  payload = payload .. string.char(MQTT.client.KEEP_ALIVE_TIME % 256)

-- Client identifier
-- ~~~~~~~~~~~~~~~~~
  payload = payload .. MQTT.client.encode_utf8(identifier)

-- Last will and testament
-- ~~~~~~~~~~~~~~~~~~~~~~~
  if (will_topic ~= nil) then
    payload = payload .. MQTT.client.encode_utf8(will_topic)
    payload = payload .. MQTT.client.encode_utf8(will_message)
  end

-- Send MQTT message
-- ~~~~~~~~~~~~~~~~~
  return(self:message_write(MQTT.message.TYPE_CONNECT, payload))
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Destroy an MQTT client instance
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function MQTT.client:destroy()                                    -- Public API
  MQTT.Utility.debug("MQTT.client:destroy()")

  if (self.destroyed == false) then
    self.destroyed = true         -- Avoid recursion when message_write() fails

    if (self.connected) then self:disconnect() end

    self.callback = nil
    self.outstanding = nil
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Disconnect message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.14: Disconnect notification
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()

function MQTT.client:disconnect()                                 -- Public API
  MQTT.Utility.debug("MQTT.client:disconnect()")

  if (self.connected) then
    self:message_write(MQTT.message.TYPE_DISCONNECT, nil)
    self.socket_client:close()
    self.connected = false
  else
    error("MQTT.client:disconnect(): Already disconnected")
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Encode a message string using UTF-8 (for variable header)
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.5: MQTT and UTF-8
--
-- byte  1:   String length MSB
-- byte  2:   String length LSB
-- bytes 3-n: String encoded as UTF-8

function MQTT.client.encode_utf8(                               -- Internal API
  input)  -- string

  local output
  output = string.char(math.floor(#input / 256))
  output = output .. string.char(#input % 256)
  output = output .. input

  return(output)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Handle received messages and maintain keep-alive PING messages
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- This function must be invoked periodically (more often than the
-- MQTT.client.KEEP_ALIVE_TIME) which maintains the connection and
-- services the incoming subscribed topic messages.

function MQTT.client:handler()                                    -- Public API
  if (self.connected == false) then
    error("MQTT.client:handler(): Not connected")
  end

  MQTT.Utility.debug("MQTT.client:handler()")

-- Transmit MQTT PING message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING request
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()

  local activity_timeout = self.last_activity + MQTT.client.KEEP_ALIVE_TIME

  if (MQTT.Utility.get_time() > activity_timeout) then
    MQTT.Utility.debug("MQTT.client:handler(): PINGREQ")

    self:message_write(MQTT.message.TYPE_PINGREQ, nil)
  end

-- Check for available client socket data
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  local ready = MQTT.Utility.socket_ready(self.socket_client)

  if (ready) then
    local error_message, buffer =
      MQTT.Utility.socket_receive(self.socket_client)

    if (error_message ~= nil) then
      self:destroy()
      error_message = "socket_client:receive(): " .. error_message
      MQTT.Utility.debug(error_message)
      return(error_message)
    end

    if (buffer ~= nil and #buffer > 0) then
      local index = 1

      -- Parse individual messages (each must be at least 2 bytes long)
      -- Decode "remaining length" (MQTT v3.1 specification pages 6 and 7)

      while (index < #buffer) do
        local message_type_flags = string.byte(buffer, index)
        local multiplier = 1
        local remaining_length = 0

        repeat
          index = index + 1
          local digit = string.byte(buffer, index)
          remaining_length = remaining_length + ((digit % 128) * multiplier)
          multiplier = multiplier * 128
        until digit < 128                              -- check continuation bit

        local message = string.sub(buffer, index + 1, index + remaining_length)

        if (#message == remaining_length) then
          self:parse_message(message_type_flags, remaining_length, message)
        else
          MQTT.Utility.debug(
            "MQTT.client:handler(): Incorrect remaining length: " ..
            remaining_length .. " ~= message length: " .. #message
          )
        end

        index = index + remaining_length + 1
      end

      -- Check for any left over bytes, i.e. partial message received

      if (index ~= (#buffer + 1)) then
        local error_message =
          "MQTT.client:handler(): Partial message received" ..
          index .. " ~= " .. (#buffer + 1)

        if (MQTT.ERROR_TERMINATE) then         -- TODO: Refactor duplicate code
          self:destroy()
          error(error_message)
        else
          MQTT.Utility.debug(error_message)
        end
      end
    end
  end

  return(nil)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit an MQTT message
-- ~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.1: Fixed header
--
-- byte  1:   Message type and flags (DUP, QOS level, and Retain) fields
-- bytes 2-5: Remaining length field (between one and four bytes long)
-- bytes m- : Optional variable header and payload

function MQTT.client:message_write(                             -- Internal API
  message_type,  -- enumeration
  payload)       -- string
                 -- return: nil or error message

-- TODO: Complete implementation of fixed header byte 1

  local message = string.char(MQTT.Utility.shift_left(message_type, 4))

  if (payload == nil) then
    message = message .. string.char(0)  -- Zero length, no payload
  else
    if (#payload > MQTT.client.MAX_PAYLOAD_LENGTH) then
      return(
        "MQTT.client:message_write(): Payload length = " .. #payload ..
        " exceeds maximum of " .. MQTT.client.MAX_PAYLOAD_LENGTH
      )
    end

    -- Encode "remaining length" (MQTT v3.1 specification pages 6 and 7)

    local remaining_length = #payload

    repeat
      local digit = remaining_length % 128
      remaining_length = math.floor(remaining_length / 128)
      if (remaining_length > 0) then digit = digit + 128 end -- continuation bit
      message = message .. string.char(digit)
    until remaining_length == 0

    message = message .. payload
  end

  local status, error_message = self.socket_client:send(message)

  if (status == nil) then
    self:destroy()
    return("MQTT.client:message_write(): " .. error_message)
  end

  self.last_activity = MQTT.Utility.get_time()
  return(nil)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT message
-- ~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 2.1: Fixed header
--
-- byte  1:   Message type and flags (DUP, QOS level, and Retain) fields
-- bytes 2-5: Remaining length field (between one and four bytes long)
-- bytes m- : Optional variable header and payload
--
-- The message type/flags and remaining length are already parsed and
-- removed from the message by the time this function is invoked.
-- Leaving just the optional variable header and payload.

function MQTT.client:parse_message(                             -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string: Optional variable header and payload

  local message_type = MQTT.Utility.shift_right(message_type_flags, 4)

-- TODO: MQTT.message.TYPE table should include "parser handler" function.
--       This would nicely collapse the if .. then .. elseif .. end.

  if (message_type == MQTT.message.TYPE_CONACK) then
    self:parse_message_conack(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PUBLISH) then
    self:parse_message_publish(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PUBACK) then
    print("MQTT.client:parse_message(): PUBACK -- UNIMPLEMENTED --")    -- TODO

  elseif (message_type == MQTT.message.TYPE_SUBACK) then
    self:parse_message_suback(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_UNSUBACK) then
    self:parse_message_unsuback(message_type_flags, remaining_length, message)

  elseif (message_type == MQTT.message.TYPE_PINGREQ) then
    self:ping_response()

  elseif (message_type == MQTT.message.TYPE_PINGRESP) then
    self:parse_message_pingresp(message_type_flags, remaining_length, message)

  else
    local error_message =
      "MQTT.client:parse_message(): Unknown message type: " .. message_type

    if (MQTT.ERROR_TERMINATE) then             -- TODO: Refactor duplicate code
      self:destroy()
      error(error_message)
    else
      MQTT.Utility.debug(error_message)
    end
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT CONACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.2: CONACK Acknowledge connection
--
-- byte 1: Reserved value
-- byte 2: Connect return code, see MQTT.CONACK.error_message[]

function MQTT.client:parse_message_conack(                      -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_conack()"
  MQTT.Utility.debug(me)

  if (remaining_length ~= 2) then
    error(me .. ": Invalid remaining length")
  end

  local return_code = string.byte(message, 2)

  if (return_code ~= 0) then
    local error_message = "Unknown return code"

    if (return_code <= table.getn(MQTT.CONACK.error_message)) then
      error_message = MQTT.CONACK.error_message[return_code]
    end

    error(me .. ": Connection refused: " .. error_message)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT PINGRESP message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING response

function MQTT.client:parse_message_pingresp(                    -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_pingresp()"
  MQTT.Utility.debug(me)

  if (remaining_length ~= 0) then
    error(me .. ": Invalid remaining length")
  end

-- ToDo: self.ping_response_outstanding = false
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT PUBLISH message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.3: Publish message
--
-- Variable header ..
-- bytes 1- : Topic name and optional Message Identifier (if QOS > 0)
-- bytes m- : Payload

function MQTT.client:parse_message_publish(                     -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_publish()"
  MQTT.Utility.debug(me)

  if (self.callback ~= nil) then
    if (remaining_length < 3) then
      error(me .. ": Invalid remaining length: " .. remaining_length)
    end

    local topic_length = string.byte(message, 1) * 256
    topic_length = topic_length + string.byte(message, 2)
    local topic  = string.sub(message, 3, topic_length + 2)
    local index  = topic_length + 3

-- Handle optional Message Identifier, for QOS levels 1 and 2
-- TODO: Enable Subscribe with QOS and deal with PUBACK, etc.

    local qos = MQTT.Utility.shift_left(message_type_flags, 1) % 3

    if (qos > 0) then
      local message_id = string.byte(message, index) * 256
      message_id = message_id + string.byte(message, index + 1)
      index = index + 2
    end

    local payload_length = remaining_length - index + 1
    local payload = string.sub(message, index, index + payload_length - 1)

    self.callback(topic, payload)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT SUBACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.9: SUBACK Subscription acknowledgement
--
-- bytes 1,2: Message Identifier
-- bytes 3- : List of granted QOS for each subscribed topic

function MQTT.client:parse_message_suback(                      -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_suback()"
  MQTT.Utility.debug(me)

  if (remaining_length < 3) then
    error(me .. ": Invalid remaining length: " .. remaining_length)
  end

  local message_id  = string.byte(message, 1) * 256 + string.byte(message, 2)
  local outstanding = self.outstanding[message_id]

  if (outstanding == nil) then
    error(me .. ": No outstanding message: " .. message_id)
  end

  self.outstanding[message_id] = nil

  if (outstanding[1] ~= "subscribe") then
    error(me .. ": Outstanding message wasn't SUBSCRIBE")
  end

  local topic_count = table.getn(outstanding[2])

  if (topic_count ~= remaining_length - 2) then
    error(me .. ": Didn't received expected number of topics: " .. topic_count)
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Parse MQTT UNSUBACK message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.11: UNSUBACK Unsubscription acknowledgement
--
-- bytes 1,2: Message Identifier

function MQTT.client:parse_message_unsuback(                    -- Internal API
  message_type_flags,  -- byte
  remaining_length,    -- integer
  message)             -- string

  local me = "MQTT.client:parse_message_unsuback()"
  MQTT.Utility.debug(me)

  if (remaining_length ~= 2) then
    error(me .. ": Invalid remaining length")
  end

  local message_id = string.byte(message, 1) * 256 + string.byte(message, 2)

  local outstanding = self.outstanding[message_id]

  if (outstanding == nil) then
    error(me .. ": No outstanding message: " .. message_id)
  end

  self.outstanding[message_id] = nil

  if (outstanding[1] ~= "unsubscribe") then
    error(me .. ": Outstanding message wasn't UNSUBSCRIBE")
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Ping response message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.13: PING response

function MQTT.client:ping_response()                            -- Internal API
  MQTT.Utility.debug("MQTT.client:ping_response()")

  if (self.connected == false) then
    error("MQTT.client:ping_response(): Not connected")
  end

  self:message_write(MQTT.message.TYPE_PINGRESP, nil)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Publish message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.3: Publish message
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()
-- Variable header ..
-- bytes 3- : Topic name and optional Message Identifier (if QOS > 0)
-- bytes m- : Payload

function MQTT.client:publish(                                     -- Public API
  topic,    -- string
  payload)  -- string

  if (self.connected == false) then
    error("MQTT.client:publish(): Not connected")
  end

  MQTT.Utility.debug("MQTT.client:publish(): " .. topic)

  local message = MQTT.client.encode_utf8(topic) .. payload

  self:message_write(MQTT.message.TYPE_PUBLISH, message)
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Subscribe message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.8: Subscribe to named topics
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()
-- Variable header ..
-- bytes 3,4: Message Identifier
-- bytes 5- : List of topic names and their QOS level

function MQTT.client:subscribe(                                   -- Public API
  topics)  -- table of strings

  if (self.connected == false) then
    error("MQTT.client:subscribe(): Not connected")
  end

  self.message_id = self.message_id + 1

  local message
  message = string.char(math.floor(self.message_id / 256))
  message = message .. string.char(self.message_id % 256)

  for index, topic in ipairs(topics) do
    MQTT.Utility.debug("MQTT.client:subscribe(): " .. topic)
    message = message .. MQTT.client.encode_utf8(topic)
    message = message .. string.char(0)  -- QOS level 0
  end

  self:message_write(MQTT.message.TYPE_SUBSCRIBE, message)

  self.outstanding[self.message_id] = { "subscribe", topics }
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - --
-- Transmit MQTT Unsubscribe message
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- MQTT 3.1 Specification: Section 3.10: Unsubscribe from named topics
--
-- bytes 1,2: Fixed message header, see MQTT.client:message_write()
-- Variable header ..
-- bytes 3,4: Message Identifier
-- bytes 5- : List of topic names


function MQTT.client:unsubscribe(                                 -- Public API
  topics)  -- table of strings

  if (self.connected == false) then
    error("MQTT.client:unsubscribe(): Not connected")
  end

  self.message_id = self.message_id + 1

  local message
  message = string.char(math.floor(self.message_id / 256))
  message = message .. string.char(self.message_id % 256)

  for index, topic in ipairs(topics) do
    MQTT.Utility.debug("MQTT.client:unsubscribe(): " .. topic)
    message = message .. MQTT.client.encode_utf8(topic)
  end

  self:message_write(MQTT.message.TYPE_UNSUBSCRIBE, message)

  self.outstanding[self.message_id] = { "unsubscribe", topics }
end

-- For ... MQTT = require("mqtt_library")

return(MQTT)
