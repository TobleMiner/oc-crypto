Cryptnet
========

Cryptnet is a simple cryptography layer for open computer modems. It uses AES-128 CBC for data encryption and HMAC-SHA1 for message authentication.

# Usage example

## Ping

### Client
```lua
local component = require('component')
local thread = require('thread')
local event = require('event')

local util = require('util')

local Cryptnet, KeyStore, Key = util.requireAll('cryptnet')

-- Create key storage
local keyStore = KeyStore.new()
-- Create new shared key
local key = Key.new('superSecretSharedKey')
-- Add key to key storage
keyStore:addKey(key)

-- Create new cryptnet instance, arguments: <modem side>, <key store>
local cryptnet = Cryptnet.new(component.modem, keyStore)

local pingtimes = {}

thread.waitForAll({
	-- Start cryptnet worker coroutine
	thread.create(function() util.try(function() cryptnet:run() end, function(err) print('Cryptnet thread failed: '..err) end) end),
	-- Send periodic ping
	thread.create(function() util.try(function() 
			local msgId = 0
			while true do
				print('sending ping ' .. tostring(msgId))
				pingtimes[msgId] = os.clock()
				cryptnet:send(msgId, '1cb440f9-c259-4aa7-bd49-b16f070e5cb6', key)
				msgId = msgId + 1
				os.sleep(0)
			end
		end,
		function(err) print('Tx thread failed: '..err) end) end),
	-- Use another thread to retrieve events for received messages
	thread.create(function() util.try(function()
		while true do
			local _, remoteAddress, msg = event.pull('cryptnet_message')
			print(string.format('got pong %d, rtt: %d ms', msg, (os.clock() - pingtimes[msg]) * 1000))
		end
	end, function(err) print('Message thread failed: '..err) end) end)
})
```

### Server
```lua
local component = require('component')
local thread = require('thread')

local util = require('util')

local Cryptnet, KeyStore, Key = util.requireAll('cryptnet')

-- Create key storage
local keyStore = KeyStore.new()
-- Create new shared key
local key = Key.new('superSecretSharedKey')
-- Add key to key storage
keyStore:addKey(key)

-- Create new cryptnet instance, arguments: <modem side>, <key store>
local cryptnet = Cryptnet.new(component.modem, keyStore)

-- Use the RX callback function for message events
cryptnet:setRxCallback(
	function(msg, senderId) 
		print('got ping ' .. tostring(msg) .. ' from ' .. tostring(senderId))
		print('sending pong ' .. tostring(msg) .. ' to ' .. tostring(senderId))
		cryptnet:send(msg, senderId, key)
	end)

-- Start cryptnet worker
cryptnet:run()

os.sleep(math.huge)
```