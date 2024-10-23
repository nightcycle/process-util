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
function getEvent(event: RBXScriptSignal?): RBXScriptSignal
	return if event
		then event
		elseif RunService:IsClient() then RunService.RenderStepped
		else RunService.Heartbeat
end

-- Class
local Util = {}

Util.IS_DEBUG_WARN_ENABLED = true

function Util.newIteratorRunner<K, V>(
	dict: { [K]: V },
	processor: (k: K, v: V) -> boolean?,
	budgetMs: number
): () -> (boolean, boolean)
	local keys: { K } = {}
	for k in pairs(dict) do
		table.insert(keys, k)
	end

	if #keys == 0 then
		if Util.IS_DEBUG_WARN_ENABLED then
			warn(`iterator-runner: empty dictionary`)
		end
		return function(): (boolean, boolean)
			return true, false
		end
	end

	return Util.newRecursiveRunner(1, function(i: number): number?
		local k = keys[i]
		local result = processor(k, dict[k])
		if i >= #keys or result == true then
			return nil
		end
		return i + 1
	end, budgetMs)
end

function Util.newRecursiveRunner<V>(
	initial: V,
	processor: (v: V) -> V?,
	budgetMs: number
): () -> (boolean, boolean)
	local nextValue: V? = initial
	local budget = budgetMs / 1000

	local source = debug.traceback("process source", 2)

	local isError = false
	local function onStep(): boolean
		if isError then
			return true
		end
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
		return nextValue ~= nil
	end

	local isComplete = false
	return function(): (boolean, boolean)
		if isComplete then
			return true, isError
		end
		isComplete = onStep() == nil
		return isComplete, isError
	end
end

function Util.run<V>(
	runner: () -> (boolean, boolean),
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	event: RBXScriptSignal?,
	useConnectParallel: boolean?
): () -> ()
	event = getEvent(event)
	assert(event)
	local connection: RBXScriptConnection?

	local isComplete = false
	local isError = false
	local isAlive = true

	local function cleanUp()
		if connection then
			connection:Disconnect()
		end
		if onFinishInvoke then
			onFinishInvoke(isComplete)
		end
	end
	local function onStep()
		isComplete, isError = runner()
		if isComplete or isError then
			cleanUp()
		end
	end

	onStep()
	if isComplete then
		return cleanUp
	end

	if useConnectParallel then
		connection = event:ConnectParallel(onStep)
	else
		connection = event:Connect(onStep)
	end

	return cleanUp
end

function Util.runAsync(
	runner: () -> (boolean, boolean),
	onFinishInvoke: ((isComplete: boolean) -> ())?,
	event: RBXScriptSignal?,
	useConnectParallel: boolean?
)
	local yieldSignal: Signal.Signal?
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

	if not isFired then
		yieldSignal:Wait()
	end
	cleanUp()
	yieldSignal:Destroy()
end

return Util
