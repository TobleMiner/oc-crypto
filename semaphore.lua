local thread = require('thread')
local event = require('event')

local util = require('util')
local Queue = require('queue')
local Logger = require('logger')

local Semaphore = util.class()

function Semaphore:init(limit, value)
	self.limit = limit or 1
	self.value = value or self.limit
	self.logger = Logger.new('Semaphore', Logger.INFO)
end

function Semaphore:up()
	self.logger:debug('up')
	if self.value >= self.limit then
		return false
	end
	self.value = self.value + 1
	event.push('semaphore')
	return true
end

function Semaphore:down()
	self.logger:debug('down')
	while not self:tryDown() do
		event.pull('semaphore')
	end
end

function Semaphore:tryDown()
	if self.value <= 0 then
		return false
	end
	self.value = self.value - 1
	return true
end

return Semaphore