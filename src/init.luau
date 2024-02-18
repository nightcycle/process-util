--!strict
local _Package = script
local _Packages = _Package.Parent
-- Services
local RunService = game:GetService("RunService")
-- Packages
local Signal = require(_Packages:WaitForChild("Signal"))
-- Modules
-- Types
-- Constants
-- Variables
-- References
-- Private Functions

function getStepSignal(): RBXScriptSignal
	return if RunService:IsServer() then RunService.Heartbeat else RunService.RenderStepped
end

function getIfParallel(override: boolean?): boolean
	return if override == nil then script:GetActor() ~= nil else override
end

function iterate(i: number, iLimit: number): (number, boolean)
	i += 1
	if i > iLimit then
		return 1, true
	else
		return i, false
	end
end


-- Class
local Util = {}

function Util.runProcess3D(
	processor: (x: number, y: number, z: number) -> boolean, 
	runLimit: number, 
	xLimit: number, yLimit: number, zLimit: number,
	getIfDead: (() -> boolean)?,
	isParallel: boolean?
): boolean

	local isDone = false
	local x,y,z = 1,1,1

	local connection: RBXScriptConnection
	local yieldSignal = Signal.new()

	local function cleanUp()
		connection:Disconnect()
		yieldSignal:Fire()
		yieldSignal:Destroy()
	end

	local function onStep()
		local success, msg = pcall(function()
			local start = tick()
			local isDead = if getIfDead then getIfDead() else false
			if not isDead then
				repeat
					isDead = if getIfDead then getIfDead() else false
					if not isDead then
						isDone = processor(x,y,z)
					end

					if isDone then break end

					local isZReset = false
					z, isZReset = iterate(z, zLimit)

					if isZReset then
						local isYReset = false
						y, isYReset = iterate(y, yLimit)

						if isYReset then
							local _isXReset = false
							x, _isXReset = iterate(x, xLimit)
						end
					end
				until tick()-start > runLimit or isDone or isDead
			end
		end)
		if not success then
			cleanUp()
			error(msg)
		end
		if isDone then
			cleanUp()
		elseif getIfDead and getIfDead() then
			cleanUp()
		end
	end
	
	if getIfParallel() then
		connection = getStepSignal():ConnectParallel(onStep)
	else
		connection = getStepSignal():Connect(onStep)
	end

	yieldSignal:Wait()
	return isDone
end

function Util.runProcess(
	processor: (i: number) -> boolean, 
	runLimit: number, 
	iLimit: number,
	getIfDead: (() -> boolean)?,
	isParallel: boolean?
): boolean

	local isDone = false
	local i = 1

	local connection: RBXScriptConnection
	local yieldSignal = Signal.new()

	local function cleanUp()
		connection:Disconnect()
		yieldSignal:Fire()
		yieldSignal:Destroy()
	end

	local function onStep()
		local success, msg = pcall(function()
			local start = tick()
			local isDead = if getIfDead then getIfDead() else false
			if not isDead then
				repeat
					isDead = if getIfDead then getIfDead() else false
					if not isDead then
						isDone = processor(i)
					end

					local _isIReset = false
					i, _isIReset = iterate(i, iLimit)
				until tick()-start > runLimit or isDone or isDead
			end
		end)
		if not success then
			cleanUp()
			error(msg)
		end
		if isDone then
			cleanUp()
			elseif getIfDead and getIfDead() then
			cleanUp()
		end
	end
		
	if getIfParallel(isParallel) then
		connection = getStepSignal():ConnectParallel(onStep)
	else
		connection = getStepSignal():Connect(onStep)
	end

	yieldSignal:Wait()
	return isDone
end


function Util.runItemProcess<V>(
	initial: V,
	processor: (v: V) -> V?, 
	runLimit: number,
	getIfDead: (() -> boolean)?,
	isParallel: boolean?
): ()

	local nextValue: V? = initial

	local connection: RBXScriptConnection
	local yieldSignal = Signal.new()

	local function cleanUp()
		connection:Disconnect()
		yieldSignal:Fire()
		yieldSignal:Destroy()
	end

	local function onStep()
		local success, msg = pcall(function()
			local start = tick()
			local isDead = if getIfDead then getIfDead() else false
			if not isDead then
				repeat
					isDead = if getIfDead then getIfDead() else false
					if not isDead then
						if nextValue ~= nil then
							nextValue = processor(nextValue)
						end
					end
				until tick()-start > runLimit or nextValue==nil or isDead
			end
		end)
		if not success then
			cleanUp()
			error(msg)
		end
		if nextValue == nil then
			cleanUp()
			elseif getIfDead and getIfDead() then
			cleanUp()
		end
	end

	if getIfParallel(isParallel) then
		connection = getStepSignal():ConnectParallel(onStep)
	else
		connection = getStepSignal():Connect(onStep)
	end

	yieldSignal:Wait()
end


return Util