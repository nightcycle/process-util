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

	local connection: RBXScriptConnection
	local yieldSignal = Signal.new()

	local function cleanUp()
		connection:Disconnect()
		yieldSignal:Fire()
		yieldSignal:Destroy()
	end

	local budget = budgetMs/1000
	local function onStep()
		local success, msg = pcall(function()
			local start = tick()
			repeat
				if nextValue ~= nil then
					nextValue = processor(nextValue)
				end
			until tick()-start > budget or nextValue==nil
		end)
		if not success then
			cleanUp()
			error(msg)
		end
		if nextValue == nil then
			cleanUp()
		end
	end

	if isParallel then
		connection = getStepSignal(stepSignal):ConnectParallel(onStep)
	else
		connection = getStepSignal(stepSignal):Connect(onStep)
	end

	yieldSignal:Wait()
end


return Util
