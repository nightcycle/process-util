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
	end

	local budget = budgetMs/1000
	local function onStep()
		local success, msg = pcall(function()
			local start = tick()
			local step = 0
			repeat
				if nextValue ~= nil then
					nextValue = processor(nextValue)
					step += 1
				end
			until tick()-start > budget or nextValue==nil
			if step == 1 and nextValue then
				warn(`runProcessAsync: a single process run took longer than ms budget, budget={budgetMs}ms, actual={math.round((tick()-start)*1000*100)/100}ms`)
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
