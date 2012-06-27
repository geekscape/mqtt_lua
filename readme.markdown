Lua MQTT client library (version 0.2 2012-06-01)
=======================

This project is part of the
[Eclipse Paho project](http://eclipse.org/paho)

Contents
--------
- [Introduction](#introduction)
- [Protocol implementation and restrictions](#restrictions)
- [Download](#download)
- [Feedback and issues](#feedback)
- [Installation](#installation)
- [Usage](#usage)
- [Example code](#example)
- [Library API](#api)
- [Known problems](#problems)

<a name="introduction" />
Introduction
------------
This project provides a client-side (only) implementation of the
[MQTT protocol](http://mqtt.org),
plus command-line utilities for publishing and subscribing to MQTT topics.
Typically, one or more MQTT servers, such as
[mosquitto](http://mosquitto.org) or
[rsmb](http://www.alphaworks.ibm.com/tech/rsmb)
will be running on host systems, with which the Lua MQTT client can interact.

MQTT stands for "Message Queue Telemetry Transport", a protocol authored by
[Dr. Andy Stanford-Clark](http://wikipedia.org/wiki/Andy_Stanford-Clark)
and Arlen Nipper.
The protocol is a message-based, publish/subscribe transport layer,
which is optimized for simple telemetry applications running on small
micro-controllers, such as an [Arduino](http://arduino.cc),
over low-bandwidth connections.
[MQTT libraries exist](http://mqtt.org/software)
for most popular programming languages, so you can utilize MQTT
on whatever server or device that you require.

The Lua MQTT client library implements the client-side subset of the
[MQTT protocol specification 3.1](https://www.ibm.com/developerworks/webservices/library/ws-mqtt).

![Lua MQTT overview](https://github.com/geekscape/mqtt_lua/raw/master/images/lua_mqtt_overview.jpg)

A good use-case for this library is running on constrained systems, such as
[OpenWRT](http://openwrt.org),
and acting as a gateway between non-MQTT clients and MQTT servers.
An advantage of using Lua is that only a text editor is required for rapid
development of simple MQTT client applications on platforms such as OpenWRT.
In constrast, working with the C programming language would comparatively
require more effort, due to requiring a cross-platform development environment.

The Lua MQTT client library also runs (unmodified) on a Sony PlayStation
Portable using the
[Lua Player HM](http://en.wikipedia.org/wiki/Lua_Player_HM)
_(which requires your PSP to be able to run unsigned executables)._

![PlayStation Portable](https://github.com/geekscape/mqtt_lua/raw/master/images/playstation_portable.jpg)

<a name="restrictions" />
Protocol implementation and restrictions
----------------------------------------
- Always assumes MQTT connection "clean session" enabled.
- Supports connection last will and testament message.
- Does not support connection username and password.
- Fixed message header byte 1, only implements the "message type".
- Only supports QOS (Quality Of Service) level 0.
- Maximum payload length is 127 bytes (easily increased).
- Publish message doesn't support "message identifier".
- Subscribe acknowledgement messages don't check granted QOS level.
- Outstanding subscribe acknowledgement messages aren't escalated.
- Works on the Sony PlayStation Portable, using
  [Lua Player HM](http://en.wikipedia.org/wiki/Lua_Player_HM).

<a name="download" />
Download
--------
The Lua MQTT client library is cross-platform and should work on any
platform that supports the Lua programming language and network sockets.

- [Download Lua MQTT client library](https://github.com/geekscape/mqtt_lua/archives/master)

<a name="feedback" />
Feedback and issues
-------------------
Tracking is managed via GitHub ...

- [Enhancements requests and issue tracking](https://github.com/geekscape/mqtt_lua/issues)

<a name="installation" />
Installation
------------
You may choose to install an MQTT server either on the same or a different
system from the Lua MQTT client library, depending upon your deployment
scenario.

Prerequisites ...

- Install [Mosquitto MQTT server](http://mosquitto.org/download)
or any other MQTT server
- Install [Lua programming language](http://www.lua.org/download.html)
- Install [LuaRocks package manager](http://luarocks.org/en/Download)
- Install [LuaSocket](http://w3.impa.br/~diego/software/luasocket)
- Install [PenLight](https://github.com/stevedonovan/Penlight)

On Linux, Lua and LuaRocks can be installed via your Linux distribution
package manager.
On Mac OS X, Lua and LuaRocks can be installed viarDarwin ports.
After that, LuaSocket and PenLight can be installed via LuaRocks.

Lua MQTT client library (source code) from GitHub ...

* TODO

<a name="usage" />
Usage
-----
The Lua MQTT client library comes with three command line utilites,
which are useful for testing the library and acting as example code.
These utilities require that Lua Penlight has been installed.

#### mqtt\_test: Test publish and receive messages on different topics

This command periodically publishes a message on topic "test/1" and
subscribes to the topic "test/2".  The command exits when the message
"quit" is published on topic "test/2".

      cd $(LUA_MQTT_LIB)              // where Lua MQTT library is installed
      example/mqtt_test -d localhost  // Assume MQTT server is on "localhost"

      -d,--debug                       Verbose console logging
      -i,--id     (default MQTT test)  MQTT client identifier
      -p,--port   (default 1883)       MQTT server port number
      <host>      (default localhost)  MQTT server hostname

#### mqtt\_publish: Publish a single message to a specified topic

This command publishes a single message and then exits.

      example/mqtt_publish -d -t test/1 -m "Test message"

Only the _--topic_ and _--message_ parameters are required.

      -d,--debug                               Verbose console logging
      -H,--host         (default localhost)    MQTT server hostname
      -i,--id           (default MQTT client)  MQTT client identifier
      -m,--message      (string)               Message to be published
      -p,--port         (default 1883)         MQTT server port number
      -t,--topic        (string)               Topic on which to publish
      -w,--will_message                        Last will and testament message
      -w,--will_qos     (default 0)            Last will and testament QOS
      -w,--will_retain  (default 0)            Last will and testament retention
      -w,--will_topic                          Last will and testament topic

#### mqtt\_subscribe: Subscribe to a topic

This command subscribes to a topic and listens indefinitely for messages.
Use ^C (or similar) to stop execution.

      example/mqtt_subscribe -d -t test/1

Only the _--topic_ parameter is required.

      -d,--debug                               Verbose console logging
      -H,--host         (default localhost)    MQTT server hostname
      -i,--id           (default MQTT client)  MQTT client identifier
      -k,--keepalive    (default 60)           Send MQTT PING period (seconds)
      -p,--port         (default 1883)         MQTT server port number
      -t,--topic        (string)               Subscription topic
      -w,--will_message                        Last will and testament message
      -w,--will_qos     (default 0)            Last will and testament QOS
      -w,--will_retain  (default 0)            Last will and testament retention
      -w,--will_topic                          Last will and testament topic

<a name="example" />
Example code
------------
The complete functioning code can be viewed here ...
[mqtt_lua/lua/example/mqtt\_test.lua](https://github.com/geekscape/mqtt_lua/blob/master/lua/example/mqtt_test.lua)

    -- Define a function which is called by mqtt_client:handler(),
    -- whenever messages are received on the subscribed topics

      function callback(topic, message)
        print("Received: " .. topic .. ": " .. message)
        if (message == "quit") then running = false end
      end

    -- Create an MQTT client instance, connect to the MQTT server and
    -- subscribe to the topic called "test/2"

      MQTT = require("mqtt_library")
      MQTT.Utility.set_debug(true)
      mqtt_client = MQTT.client.create("localhost", nil, callback)
      mqtt_client:connect("lua mqtt client"))
      mqtt_client:subscribe({"test/2"})

    -- Continously invoke mqtt_client:handler() to process the MQTT protocol and
    -- handle any received messages.  Also, publish a message on topic "test/1"

      running = true

      while (running) do
        mqtt_client:handler()
        mqtt_client:publish("test/1", "test message")
        socket.sleep(1.0)  -- seconds
      end

    -- Clean-up by unsubscribing from the topic and closing the MQTT connection

      mqtt_client:unsubscribe({"test/2"})
      mqtt_client:destroy()

There are also a number of Lua MQTT client examples in the _example/_ directory.
They can be run from the _lua/_ parent directory, as follow ...

      cd mqtt_client/lua
      example/example_00.lua

<a name="api" />
MQTT client Library API
-----------------------
Once the MQTT client library has been included (via _require_), one or more
MQTT server connections can be created.  Using a server connection, the client
may then publish messages directly on a specified topic.  Or, subscribe to one
or more topics, where received messages are passed to a callback function
(defined when creating an MQTT client instance).  Finally, the client can
unsubscribe from one or more topics and disconnect from the MQTT server.

Use the Lua _require_ statement to load the MQTT client library ...

      MQTT = require("mqtt_library")

#### MQTT.Utility.set_debug(): Library debug console logging

The following statement enables debug console logging for diagnosis.

      MQTT.Utility.set_debug(true)

#### MQTT.client.create(): Create an MQTT client instance

Create an MQTT client that will be connected to the specified host.

      mqtt_client = MQTT.client.create(hostname, port, callback)

The _hostname_ must be provided, but both the _port_ and _callback function_
parameters are optional.  This function returns an MQTT client instance
that must be used for all subsequent MQTT operations for that server connection.

      hostname string:   Host name or address of the MQTT broker
      port     integer:  Port number of the MQTT broker (default: 1883)
      callback function: Invoked when subscribed topic messages received

The _callback function_ is defined as follows ...

      function callback(topic, payload)
      -- application specific code
      end

      topic   -- string: Topic for the received message
      payload -- string: Message data

#### MQTT.client:destroy(): Destroy an MQTT client instance

When finished with a server connection, this statement cleans-up all resources
allocated by the client.

      mqtt_client:destroy()

#### MQTT.client:connect(): Make a connection to an MQTT server

Before messages can be transmitted, the MQTT client must connect to the server.

      mqtt_client:connect(identifier)

Each individual client connection must use a unique identifier.
Only the _identifier_ parameter is required, the remaining parameters
are optional.

      mqtt_client:connect(identifier, will_topic, will_qos, will_retain, will_message)

MQTT also provides a "last will and testament" for clients, which is a message
automatically sent by the server on behalf of the client, should the connection
fail.

      identifier   -- string: MQTT client identifier (maximum 23 characters)
      will_topic   -- string: Last will and testament topic
      will_qos     -- byte:   Last will and testament Quality Of Service
      will_retain  -- byte:   Last will and testament retention status
      will_message -- string: Last will and testament message

#### MQTT.client:disconnect(): Transmit MQTT Disconnect message

Transmit an MQTT disconnect message to the server.

      mqtt_client:disconnect()

#### MQTT.client:publish(): Transmit MQTT publish message

Transmit a message on a specified topic.

      mqtt_client:publish(topic, payload)

      topic   -- string: Topic for the published message
      payload -- string: Message data

#### MQTT.client:subscribe(): Transmit MQTT Subscribe message

Subscribe to one or more topics.  Whenever a message is published to one of
those topics, the callback function (defined above) will be invoked.

      mqtt_client:subscribe(topics)

      topics -- table of strings, e.g. { "topic1", "topic2" }

#### MQTT.client:handler(): Handle received messages, maintain keep-alive messages

The _handler()_ function must be called periodically to service incoming
messages and to ensure that keep-alive messages (PING) are being sent
when required.

The default _KEEP\_ALIVE\_TIME_ is 60 seconds, therefore _handler()_ must be
invoked more often than once per minute.

Should any messages be received on the subscribed topics, then _handler()_
will invoke the callback function (defined above).

      mqtt_client:handler()

#### MQTT.client:unsubscribe(): Transmit MQTT Unsubscribe message

Unsubscribe from one or more topics, so that messages published to those
topics are no longer received.

      topics -- table of strings, e.g. { "topic1", "topic2" }

<a name="problems" />
Known problems
--------------
- Occasional "MQTT.client:handler(): Message length mismatch" errors,
  particularly when subscribed topics are transmitting many messages.

- Not really a problem, but if you find that the MQTT socket connection is
  being closed for no apparent reason, particularly for subscribers ...
  then check that all MQTT clients are using a unique client identifier.
