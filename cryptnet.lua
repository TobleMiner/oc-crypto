sha1 = require('sha1')
aeslua = require("aeslua")

local util = require('util')
local Logger = require('logger')
local Semaphore = require('semaphore')

local SessionManger = require('cryptnet/session')
local Message = util.requireAll('cryptnet/message')
local KeyStore, Key = util.requireAll('cryptnet/key')

local thread = require('thread')
local event = require('event')
local serialization = require('serialization')

local MODEM_PORT = 42
local QUEUE_SIZE = 10
local DEBUG_LEVEL = Logger.INFO

local Callback = util.class()

function Callback:init(callback, ...)
	self.callback = callback
	self.args = table.pack(...)
end

function Callback:call(...)
	local args = table.pack(...)
	return pcall(function()
		if #self.args > 0 then
			self.callback(table.unpack(self.args), table.unpack(args))
		else
			self.callback(table.unpack(args))
		end
	end)
end

local Cryptnet = util.class()

--[[
	This is a rough explanation of the message format. It should be reasonably(TM) secure

	Messages:
		ASSOC:
			Initial message for session setup. Sets up session and challenge on remote side. Sent A -> B
			(cleartext)
				type: "associate"
				id_a: local session id of requesting station
				id: id of sender (computer id)
				id_recipient: id of recipient
				keyid: id of key to use
				challenge: Random blob of data
			
			
		ASSOC_RESP:
			Association response, proves knowledge of secret key and sets up challenge on A. Sent B -> A
			(cleartext)
				type: "associate_response"
				id_a: local session id of requesting station
				id_b: local session id of responding station
				id: id of sender (computer id)
				id_recipient: id of recipient
				challenge: Random blob of data (my own challenge)
				hmac: hmac of all other paramters + challenge from ASSOC
				
				
		DATA:
			Messages sent after session setup. Sent A <-> B
			(cleartext)
				type: "data"
				id_a: local session id of sending station
				id_b: local session id of receiving station
				id: id of sender (computer id)
				id_recipient: id of recipient
				hmac: hmac of all other paramters + (ciphertext) + current challenge
			(ciphertext)
				data: payload
				
				
		DATA_RESP:
			This packet is not really authenticated too well but adding authentication would result in problems with lost response messages, too.
			Also current_challenge changes with each msg received thus it should be a rather small-ish problem. It might be possible however to use this message
			to force a reset of te challenge to a known value resulting in a replay attack scenario
			(cleartext)
				type: "data_response"
				id_a: local session id of sending station
				id_b: local session id of receiving station
				id: id of sender (computer id)
				id_recipient: id of recipient
				success: [boolean] received msg was ok
				current_challenge: challenge expected by sender
				hmac: hmac of all other paramters
				
				
		DEASSOC:
			Deassociation message. Typically sent by A but can also be transmitted by B. Properly authenticated to prevent WLAN deauth-type fuckups
			(cleartexr)
				type: "deassociate"
				id_a: local session id of sending station
				id_b: local session id of receiving station
				id: id of sender (computer id)
				id_recipient: id of recipient
				hmac: hmac of all other paramters + current challenge
]]

function Cryptnet:init(modem, keyStore, rxCallback, ...)	
	self.modem = modem
	self.keyStore = keyStore
	self.sessionManger = SessionManger.new(self)
	self.logger = Logger.new('cryptnet', DEBUG_LEVEL)
	self.txSema = Semaphore.new(QUEUE_SIZE)
	self:setRxCallback(rxCallback, ...)
end

function Cryptnet:sendMessage(msg, remoteAddress)
	self.logger:debug('Sending message to ' .. tostring(remoteAddress)	)
	self.modem.send(remoteAddress, MODEM_PORT, serialization.serialize(msg))
end

function Cryptnet:run()
	self.logger:debug('Starting threads')
	thread.waitForAll({
		thread.create(function() util.try(function() self:listen() end, function(err) self.logger:warn('RX thread failed: ' .. err) end) end),
		thread.create(function() util.try(function() self.sessionManger:run() end, function(err) self.logger:warn('Session thread failed: ' .. err) end) end)
	})
end

function Cryptnet:listen()
	self.modem.open(MODEM_PORT)

	self.logger:debug('Listening...')
	while true do
		local _, localAddress, remoteAddress, port, dist, msg = event.pull('modem_message')
		if localAddress == self:getLocalAddress() then
			self.logger:debug('Got message')
			local success, err = pcall(function()
				local message = Message.parse(self, serialization.unserialize(msg))
				if message then
					self.sessionManger:enqueueMessageRx(message)
					event.push('cryptnet_rx')
				end
			end)
			if not success then
				self.logger:warn('Message handling failed: ' .. err)
			end
		end
	end
end

function Cryptnet:send(msg, recipient, key)
	self.txSema:down()
	self.sessionManger:enqueueMessageTx(msg, recipient, key)
	event.push('cryptnet_tx')
end

function Cryptnet:onMessageHandled()
	self.txSema:up()
end

function Cryptnet:onRx(msg, remoteId)
	if self.rxCallback then
		local success, err = self.rxCallback:call(msg, remoteId)
		if not success then
			self.logger:warn('Callback failed: ' .. err)
		end
	else
		event.push('cryptnet_message', remoteId, msg)
	end
end

function Cryptnet:setRxCallback(rxCallback, ...)
	if rxCallback then
		self.rxCallback = Callback.new(rxCallback, ...)
	else
		self.rxCallback = nil
	end
end

function Cryptnet:getLocalAddress()
	return self.modem.address
end

function Cryptnet:getKeyStore()
	return self.keyStore
end

function Cryptnet:getLogger()
	return self.logger
end

return { Cryptnet, KeyStore, Key }