--!strict
--!native
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
function getStepSignal(stepSignal: RBXScriptSignal?): RBXScriptSignal
	return if stepSignal then stepSignal elseif RunService:IsServer() then RunService.Heartbeat else RunService.RenderStepped
end

-- Class
local Util = {}

function Util.runIteratorAsync<V>(
	list: {V},
	processor: (i: number, v: V) -> (),
	budgetMs: number,
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	isParallel: boolean?,
	stepSignal: RBXScriptSignal?
): ()
	if #list == 0 then
		if onFinishInvoke then
			onFinishInvoke(true)
		end
		return
	end
	list = table.clone(list)
	Util.runProcessAsync(
		1,
		function(i: number): number?
			processor(i, list[i])
			if i == #list then
				return nil
			end
			return i+1
		end,
		budgetMs,
		onFinishInvoke,
		isParallel,
		stepSignal
	)
end

function Util.runProcessAsync<V>(
	initial: V,
	processor: (v: V) -> V?,
	budgetMs: number,
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	isParallel: boolean?,
	stepSignal: RBXScriptSignal?
): ()

	local nextValue: V? = initial
	stepSignal = stepSignal or (if RunService:IsServer() then RunService.Heartbeat else RunService.RenderStepped)
	local connection: RBXScriptConnection?
	local yieldSignal: Signal.Signal?
	local isFired = false
	local function cleanUp()
		if connection then
			connection:Disconnect()
		end
		if yieldSignal then
			if not isFired then
				yieldSignal:Fire()
			end
			yieldSignal:Destroy()
		end
		if onFinishInvoke then
			onFinishInvoke(nextValue == nil)
		end
	end

	local budget = budgetMs / 1000
	local source = debug.traceback("process source", 2)
	local function onStep()
		local success, msg = pcall(function()
			local step = 0
			local start = tick()
			local duration = (tick() - start)
			repeat
				if nextValue ~= nil then
					nextValue = processor(nextValue)
					step += 1
				end
				duration = (tick() - start)
			until (step+1)*(duration/(step)) > budget or nextValue==nil
			if step == 1 and duration > budget and nextValue then
				warn(`runProcessAsync: a single process run took longer than ms budget, budget={budgetMs}ms, actual={math.round((tick() - start) * 1000 * 100) / 100}ms`)
				print(source)
			end
		end)
		if not success then
			cleanUp()
			error(msg)
		end
		if nextValue == nil then
			cleanUp()
		end
	end
	onStep()
	if not initial then
		cleanUp()
		return
	end

	if isParallel then
		connection = getStepSignal(stepSignal):ConnectParallel(onStep)
	else
		connection = getStepSignal(stepSignal):Connect(onStep)
	end

	yieldSignal = Signal.new()
	assert(yieldSignal)

	yieldSignal:Wait()
	isFired = true
	cleanUp()
end

return Util
