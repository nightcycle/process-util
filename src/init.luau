--!strict
--!native
-- Services
local RunService = game:GetService("RunService")
-- Packages
local Signal = require("@wally/Signal")
-- Modules
-- Types
-- Constants
-- Variables
-- References
-- Private Functions
function getDefaultEvent(event: RBXScriptSignal?): RBXScriptSignal
	return if event then event elseif RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
end

-- Class
local Util = {}

Util.IS_DEBUG_WARN_ENABLED = true -- set to false to disable debug warnings, such as when a single process run takes longer than the budget

-- creates a runner that iterates over a table, to break early return "true" otherwise return nil
function Util.newIteratorRunner<K, V>(
	dict: { [K]: V },
	processor: (k: K, v: V) -> true?,
	budgetMs: number
): () -> (boolean, boolean)
	local keys: { K } = {}
	for k in pairs(dict) do
		table.insert(keys, k)
	end

	return Util.newRecursiveRunner(1, function(i: number): number?
		if i > #keys then
			return nil
		end
		local k = keys[i]
		local result = processor(k, dict[k])
		if i >= #keys or result == true then
			return nil
		end
		return i + 1
	end, budgetMs)
end

-- creates a runner that runs recursively, to break early return nil otherwise return the next value
function Util.newRecursiveRunner<V>(initial: V, processor: (v: V) -> V?, budgetMs: number): () -> (boolean, boolean)
	local nextValue: V? = initial
	local budget = budgetMs / 1000

	local source = debug.traceback("process source", 2)

	local isError = false
	local function onStep()
		if isError then
			return
		end
		local success, msg = pcall(function()
			local step = 0
			local start = tick()
			local duration = (tick() - start)
			repeat
				if nextValue ~= nil then
					local thr = task.spawn(function()
						nextValue = processor(nextValue)
					end)
					if coroutine.status(thr) ~= "dead" then
						error(`process yielded instead of finishing: {source}`)
					end
					-- nextValue = processor(nextValue)
					step += 1
				end
				duration = (tick() - start)
			until nextValue == nil or (step + 1) * (duration / step) > budget
			if Util.IS_DEBUG_WARN_ENABLED then
				if step == 1 and duration > budget and nextValue then
					warn(
						`runProcessAsync: a single process run took longer than ms budget, budget={budgetMs}ms, actual={math.round(
							(tick() - start) * 1000 * 100
						) / 100}ms`
					)
					warn(source)
				end
			end
		end)
		if not success then
			isError = true
			error(`{msg}: {source}`)
		end
	end

	return function(): (boolean, boolean)
		if nextValue ~= nil then
			onStep()
		end
		local isWorking = nextValue ~= nil
		return isWorking, isError
	end
end

-- runs a runner via an event, the calling thread will not yield
function Util.run<V>(
	runner: () -> (boolean, boolean),
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	event: RBXScriptSignal?,
	useConnectParallel: boolean?
): () -> ()
	event = getDefaultEvent(event)
	assert(event)
	local connection: RBXScriptConnection?

	local isComplete = false
	local isAlive = true

	local function cleanUp()
		if not isAlive then
			return
		end
		isAlive = false
		if connection then
			connection:Disconnect()
		end
		if onFinishInvoke then
			onFinishInvoke(isComplete)
		end
	end
	local function onStep()
		local isWorking, isError = runner()
		isComplete = not isWorking
		if isComplete or isError then
			cleanUp()
		end
	end

	onStep()
	if isComplete or not isAlive then
		return cleanUp
	end

	if useConnectParallel then
		connection = event:ConnectParallel(onStep)
	else
		connection = event:Connect(onStep)
	end

	return cleanUp
end

-- runs a runner, yielding the thread until it's complete. Returns whether the runner completed successfully
function Util.runAsync(
	runner: () -> (boolean, boolean),
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	event: RBXScriptSignal?,
	useConnectParallel: boolean?
): boolean
	local yieldSignal: Signal.Signal<boolean>?
	local isFired = false

	yieldSignal = Signal.new()
	assert(yieldSignal)

	local cleanUp = Util.run(runner, function(isComplete: boolean)
		if isFired then
			return
		end
		isFired = true
		yieldSignal:Fire(isComplete)
		if onFinishInvoke then
			onFinishInvoke(isComplete)
		end
	end, event, useConnectParallel)

	local isComplete: boolean?
	if not isFired then
		isComplete = yieldSignal:Wait()
	end
	cleanUp()
	yieldSignal:Destroy()
	assert(isComplete ~= nil)
	return isComplete
end

return Util
