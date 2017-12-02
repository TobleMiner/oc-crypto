local util = require('util')
local Logger = require('logger')

local event = require('event')
local computer = require('computer')

local TimerCallback = util.class()
local TimerManager = util.class()

function TimerCallback:init(callback, ...)
	self.callback = callback
	self.args = table.pack(...)
end

function TimerCallback:call(...)
	self.callback(table.unpack(self.args), ...)
end


function TimerManager:init(errorCallback, ...)
	self.timers = {}
	self:setErrorCallback(errorCallback, ...)
	self.logger = Logger.new('Timer', Logger.WARNING)
end

function TimerManager.run()

end

function TimerManager:setTimeout(callback, timeout, ...)
	local cb = TimerCallback.new(callback, ...)
	local id = event.timer(timeout / 1000, function()
			self.logger:debug(string.format('Timer fired, now: %.2f', computer.uptime()))
			local success, err = pcall(callback.call, callback)
			if not success and self.errorCallback then
				self.errorCallback:call(id, err)
			end			
		end, 1)
	self.logger:debug(string.format('Set up new timer, firing in %d ms, id: %d, now: %.2f', timeout, id, computer.uptime()))
	return id
end

function TimerManager:clearTimeout(id)
	local success = event.cancel(id)
	self.logger:debug(string.format('Canceled timer %d, success: %s', id, tostring(success)))
end

function TimerManager:setErrorCallback(cb, ...)
	if cb then
		self.errorCallback = TimerCallback.new(cb, ...)
	else
		self.errorCallback = nil
	end
end

return TimerManager