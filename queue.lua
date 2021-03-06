local util = require('util')
local Logger = require('logger')

local event = require('event')

local Queue = util.class()
local Element = util.class()


function Queue:init(size)
	self.size = size

	local elem = Element.new()
	elem:setNext(elem)
	elem:setPrev(elem)
	self.head = elem
	self.len = 0

	self.logger = Logger.new('queue')
	
	self.event = 'queue_'..tostring(self)
end

function Queue:isEmpty()
	return self.head == self:getTail()
end

function Queue:isFull()
	return self:getSize() and self:length() >= self:getSize()
end

function Queue:length()
	return self.len
end

function Queue:enqueue(val)
	while self:isFull() do
		event.pull(self.event)
	end

	local elem = Element.new(val, self.head, self:getTail())
	self:getTail():setNext(elem)
	self.head:setPrev(elem)
	self.len = self.len + 1
end

function Queue:wakeUpWriters()
	event.push(self.event)
end

function Queue:remove(value)
	local cursor = self.head:getNext()
	while cursor ~= self.head do
		if cursor:getValue() == value then
			cursor:getNext():setPrev(cursor:getPrev())
			cursor:getPrev():setNext(cursor:getNext())
			-- Disconnect cursor
			cursor:setNext(cursor)
			cursor:setPrev(cursor)
			self.len = self.len - 1

			self:wakeUpWriters()

			return true
		end
		cursor = cursor:getNext()
	end
	return false
end

function Queue:dequeue()
	if self:isEmpty() then
		return nil
	end
	
	local valHead = self.head:getNext()
	-- Fix references to head
	valHead:getNext():setPrev(self.head)
	valHead:getPrev():setNext(valHead:getNext())
	-- Disconnect head
	valHead:setNext(valHead)
	valHead:setPrev(valHead)
	self.len = self.len - 1

	self:wakeUpWriters()

	return valHead:getValue()
end

function Queue:getTail()
	return self.head:getPrev()
end

function Queue:getSize()
	return self.size
end

function Element:init(val, next, prev)
	self.val = val
	self.next = next
	self.prev = prev
end

function Element:getValue()
	return self.val
end

function Element:getNext()
	return self.next
end

function Element:setNext(next)
	self.next = next
end

function Element:getPrev()
	return self.prev
end

function Element:setPrev(prev)
	self.prev = prev
end

return Queue
